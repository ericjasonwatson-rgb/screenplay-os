#!/usr/bin/env python3
"""Validation-only macOS reviewer packaging; Developer ID is a separate gate."""
import argparse
import os
import pathlib
import plistlib
import re
import shutil
import stat
import subprocess
import sys

EXECUTABLES = {"demo": "ShieldReviewerDemoApp",
               "candidate": "ShieldReviewerCandidateApp"}
TEAM_ID = re.compile(r"[A-Z0-9]{10}\Z")
LABEL = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\Z")
DEVELOPER_ID_CA = "1.2.840.113635.100.6.2.6"
DEVELOPER_ID_APP = "1.2.840.113635.100.6.1.13"


class BundleError(Exception):
    pass


def check_id(value):
    parts = value.split(".")
    if not (len(parts) >= 2 and len(value.encode()) <= 200 and all(
            part and len(part) <= 63 and LABEL.fullmatch(part) for part in parts)):
        raise BundleError("Invalid macOS bundle or Mach service identifier")


def check_team(value):
    if not TEAM_ID.fullmatch(value):
        raise BundleError("Invalid Apple Developer Team ID")


def reviewer_config(team_id, bundle_id, agent, helper, agent_service, reviewer_service):
    check_team(team_id)
    for value in (bundle_id, agent, helper, agent_service, reviewer_service):
        check_id(value)
    if len({bundle_id, agent, helper}) != 3 or agent_service == reviewer_service:
        raise BundleError("Overlapping reviewer/agent/helper identities or Mach services")
    return {
        "CIPSTeamID": team_id,
        "CIPSReviewerBundleID": bundle_id,
        "CIPSAgentBundleID": agent,
        "CIPSHelperBundleID": helper,
        "CIPSAgentMachService": agent_service,
        "CIPSReviewerMachService": reviewer_service,
        "CIPSReviewerCandidate": True,
    }


def inspect(app, bundle_id):
    check_id(bundle_id)
    if not app.is_dir() or app.is_symlink() or app.suffix != ".app":
        raise BundleError("Reviewer app missing or symlinked")
    plist_path = app / "Contents" / "Info.plist"
    if plist_path.is_symlink():
        raise BundleError("Reviewer plist cannot be symlinked")
    try:
        with plist_path.open("rb") as handle:
            info = plistlib.load(handle)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise BundleError("Invalid reviewer bundle Info.plist") from error
    kind = "candidate" if info.get("CIPSReviewerCandidate") is True else "demo"
    executable_name = EXECUTABLES[kind]
    binary = app / "Contents" / "MacOS" / executable_name
    if binary.is_symlink():
        raise BundleError("Reviewer executable cannot be symlinked")
    try:
        mode = binary.stat().st_mode
    except OSError as error:
        raise BundleError("Reviewer binary unavailable") from error
    required = {
        "CFBundleIdentifier": bundle_id,
        "CFBundleExecutable": executable_name,
        "CFBundlePackageType": "APPL",
        "LSMinimumSystemVersion": "13.0",
        "CIPSValidationOnly": True,
        "CIPSNoRealApprovalOrEgress": True,
    }
    if any(info.get(key) != value for key, value in required.items()):
        raise BundleError("Reviewer metadata does not match configured bundle")
    if not stat.S_ISREG(mode) or not os.access(binary, os.X_OK):
        raise BundleError("Reviewer executable is not a runnable regular file")
    if kind == "candidate":
        reviewer_config(
            info.get("CIPSTeamID", ""),
            bundle_id,
            info.get("CIPSAgentBundleID", ""),
            info.get("CIPSHelperBundleID", ""),
            info.get("CIPSAgentMachService", ""),
            info.get("CIPSReviewerMachService", ""),
        )
        if info.get("CIPSReviewerBundleID") != bundle_id:
            raise BundleError("Signed reviewer configuration bundle mismatch")
    return kind, info, binary


def assemble(binary, app, bundle_id, kind="demo", configuration=None):
    check_id(bundle_id)
    if kind not in EXECUTABLES:
        raise BundleError("Unknown reviewer app kind")
    executable_name = EXECUTABLES[kind]
    if (binary.name != executable_name or binary.is_symlink()
            or not binary.is_file() or not os.access(binary, os.X_OK)):
        raise BundleError("Expected a regular compiled reviewer executable")
    if app.suffix != ".app" or app.exists() or app.is_symlink():
        raise BundleError("Bundle name invalid or existing bundle would be overwritten")
    if not app.parent.is_dir():
        raise BundleError("Output parent directory must already exist")
    if kind == "candidate" and not configuration:
        raise BundleError("Candidate requires explicit signed identities")
    app.mkdir(mode=0o700)
    try:
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        info = {
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": "Creative IP Shield - Validation Reviewer",
            "CFBundleExecutable": executable_name,
            "CFBundleIdentifier": bundle_id,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "Creative IP Shield Reviewer",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "13.0",
            "NSHighResolutionCapable": True,
            "NSPrincipalClass": "NSApplication",
            "CIPSValidationOnly": True,
            "CIPSNoRealApprovalOrEgress": True,
        }
        if kind == "candidate":
            info.update(configuration)
        with (contents / "Info.plist").open("wb") as handle:
            plistlib.dump(info, handle, fmt=plistlib.FMT_XML, sort_keys=True)
        destination = contents / "MacOS" / executable_name
        shutil.copy2(binary, destination)
        destination.chmod(0o755)
        actual_kind, _, _ = inspect(app, bundle_id)
        if actual_kind != kind:
            raise BundleError("Assembled reviewer kind is inconsistent")
    except Exception:
        shutil.rmtree(app)
        raise


def developer_id_requirement(bundle_id, team_id):
    check_id(bundle_id)
    check_team(team_id)
    # Apple TN3127: Developer ID Application leaf and intermediate extensions.
    # Team+Apple anchor alone also admits Apple Development identities.
    return (
        f'identifier "{bundle_id}" and anchor apple generic '
        f'and certificate 1[field.{DEVELOPER_ID_CA}] exists '
        f'and certificate leaf[field.{DEVELOPER_ID_APP}] exists '
        f'and certificate leaf[subject.OU] = "{team_id}"'
    )


def verify_release(app, bundle_id, team_id):
    kind, info, _ = inspect(app, bundle_id)
    if kind != "candidate" or info.get("CIPSTeamID") != team_id:
        raise BundleError("Synthetic demo or Team mismatch: not release-eligible")
    requirement = developer_id_requirement(bundle_id, team_id)
    result = subprocess.run(
        ["codesign", "--verify", "--strict", "--verbose=2",
         f"--test-requirement={requirement}", str(app)],
        capture_output=True, text=True, timeout=60
    )
    if result.returncode != 0:
        raise BundleError("Signed reviewer fails Developer ID Application certificate requirement")
    display = subprocess.run(
        ["codesign", "--display", "--verbose=4", str(app)],
        capture_output=True, text=True, timeout=30
    )
    detail = display.stdout + display.stderr
    if display.returncode != 0:
        raise BundleError("Unable to inspect code signature")
    # This is additional metadata validation, NOT notarization or Gatekeeper.
    if not re.search(r"(?m)^CodeDirectory .*flags=.*\bruntime\b", detail):
        raise BundleError("Signed reviewer lacks hardened runtime")
    if not re.search(r"(?m)^Timestamp=(?!none\b).+", detail):
        raise BundleError("Signed reviewer lacks secure timestamp")


def sign_release(app, bundle_id, team_id, identity):
    kind, info, _ = inspect(app, bundle_id)
    if kind != "candidate" or info.get("CIPSTeamID") != team_id:
        raise BundleError("Only exact Team-matched reviewer candidate can be signed")
    if not identity.startswith("Developer ID Application: ") or not identity.endswith(
            f"({team_id})"):
        raise BundleError("Signing identity is not a matching Developer ID Application")
    if bundle_id.startswith(("com.example.", "org.example.")):
        raise BundleError("Example identifiers cannot be release-signed")
    # Run ONLY on the owner's credential-equipped Mac, never with CI secrets.
    signed = subprocess.run(
        ["codesign", "--force", "--options", "runtime", "--timestamp",
         "--sign", identity, str(app)], capture_output=True, text=True, timeout=120
    )
    if signed.returncode:
        raise BundleError("Developer ID signing failed")
    verify_release(app, bundle_id, team_id)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="command", required=True)
    p = subs.add_parser("assemble")
    p.add_argument("--binary", type=pathlib.Path, required=True)
    p.add_argument("--app", type=pathlib.Path, required=True)
    p.add_argument("--bundle-id", required=True)
    p = subs.add_parser("assemble-candidate")
    p.add_argument("--binary", type=pathlib.Path, required=True)
    p.add_argument("--app", type=pathlib.Path, required=True)
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--team-id", required=True)
    p.add_argument("--agent-bundle-id", required=True)
    p.add_argument("--helper-bundle-id", required=True)
    p.add_argument("--agent-mach-service", required=True)
    p.add_argument("--reviewer-mach-service", required=True)
    for command in ("verify-release", "sign-release"):
        p = subs.add_parser(command)
        p.add_argument("--app", type=pathlib.Path, required=True)
        p.add_argument("--bundle-id", required=True)
        p.add_argument("--team-id", required=True)
        if command == "sign-release":
            p.add_argument("--identity", required=True)
    args = parser.parse_args()
    try:
        if args.command == "assemble":
            assemble(args.binary, args.app, args.bundle_id)
            print("ASSEMBLED_UNSIGNED_SYNTHETIC_REVIEWER_APP")
        elif args.command == "assemble-candidate":
            cfg = reviewer_config(
                args.team_id, args.bundle_id, args.agent_bundle_id,
                args.helper_bundle_id, args.agent_mach_service,
                args.reviewer_mach_service,
            )
            assemble(args.binary, args.app, args.bundle_id, "candidate", cfg)
            print("ASSEMBLED_UNSIGNED_FAIL_CLOSED_REVIEWER_CANDIDATE")
        elif args.command == "verify-release":
            verify_release(args.app, args.bundle_id, args.team_id)
            print("VERIFIED_DEVELOPER_ID_APP_CHAIN_RUNTIME_TIMESTAMP_NOT_NOTARIZED")
        else:
            sign_release(args.app, args.bundle_id, args.team_id, args.identity)
            print("DEVELOPER_ID_SIGNED_NOT_NOTARIZED")
    except (BundleError, OSError, subprocess.TimeoutExpired) as error:
        print(f"DENIED: {error}", file=sys.stderr)
        return 78
    return 0


if __name__ == "__main__":
    sys.exit(main())
