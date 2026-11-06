#!/usr/bin/env python3
"""Assemble synthetic reviewer .app; verify real Developer ID signatures."""
import argparse
import os
import pathlib
import plistlib
import re
import shutil
import stat
import subprocess
import sys

EXECUTABLE = "ShieldReviewerDemoApp"
TEAM_ID = re.compile(r"[A-Z0-9]{10}\Z")
LABEL = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\Z")


class BundleError(Exception):
    pass


def check_id(value):
    parts = value.split(".")
    if not (len(parts) >= 2 and len(value.encode()) <= 200 and all(
            part and len(part) <= 63 and LABEL.fullmatch(part) for part in parts)):
        raise BundleError("Invalid reviewer bundle identifier")


def check_team(value):
    if not TEAM_ID.fullmatch(value):
        raise BundleError("Invalid Apple Developer Team ID")


def inspect(app, bundle_id):
    check_id(bundle_id)
    if not app.is_dir() or app.is_symlink() or app.suffix != ".app":
        raise BundleError("Reviewer app missing or symlinked")
    info_file = app / "Contents" / "Info.plist"
    executable = app / "Contents" / "MacOS" / EXECUTABLE
    if info_file.is_symlink() or executable.is_symlink():
        raise BundleError("App contains unexpected symlink")
    try:
        with info_file.open("rb") as stream:
            info = plistlib.load(stream)
        mode = executable.stat().st_mode
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise BundleError("Invalid reviewer bundle structure") from error
    required = {
        "CFBundleIdentifier": bundle_id,
        "CFBundleExecutable": EXECUTABLE,
        "CFBundlePackageType": "APPL",
        "LSMinimumSystemVersion": "13.0",
        "CIPSValidationOnly": True,
        "CIPSNoRealApprovalOrEgress": True,
    }
    if any(info.get(key) != value for key, value in required.items()):
        raise BundleError("Reviewer app metadata is inconsistent")
    if not stat.S_ISREG(mode) or not os.access(executable, os.X_OK):
        raise BundleError("Reviewer executable is missing or not executable")


def assemble(binary, app, bundle_id):
    check_id(bundle_id)
    if binary.name != EXECUTABLE or binary.is_symlink() or not binary.is_file():
        raise BundleError("Expected a regular reviewer Swift executable")
    if not os.access(binary, os.X_OK):
        raise BundleError("Reviewer Swift executable is not runnable")
    if app.suffix != ".app" or app.exists() or app.is_symlink():
        raise BundleError("Bundle name invalid or bundle already exists")
    if not app.parent.is_dir():
        raise BundleError("Destination parent must already exist")
    app.mkdir(mode=0o700)
    try:
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        info = {
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": "Creative IP Shield - Synthetic Reviewer Preview",
            "CFBundleExecutable": EXECUTABLE,
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
        with (contents / "Info.plist").open("wb") as stream:
            plistlib.dump(info, stream, fmt=plistlib.FMT_XML)
        target = contents / "MacOS" / EXECUTABLE
        shutil.copy2(binary, target)
        target.chmod(0o755)
        inspect(app, bundle_id)
    except Exception:
        shutil.rmtree(app)
        raise


def verify_release(app, bundle_id, team_id):
    check_team(team_id)
    inspect(app, bundle_id)
    requirement = (
        f'identifier "{bundle_id}" and anchor apple generic '
        f'and certificate leaf[subject.OU] = "{team_id}"'
    )
    check = subprocess.run(
        ["codesign", "--verify", "--strict", "--verbose=2",
         f"--test-requirement={requirement}", str(app)],
        capture_output=True, text=True,
    )
    if check.returncode:
        raise BundleError("Expected Developer ID signature/Team requirement not met")


def sign_release(app, bundle_id, team_id, identity):
    check_team(team_id)
    inspect(app, bundle_id)
    if not identity.startswith("Developer ID Application: "):
        raise BundleError("Ad-hoc and development-only signatures cannot be released")
    if bundle_id.startswith("com.example.") or bundle_id.startswith("org.example."):
        raise BundleError("Example bundle IDs may not be release signed")
    # Only an authorized operator on their own certificate-equipped Mac runs this.
    code = subprocess.run(
        ["codesign", "--force", "--options", "runtime", "--timestamp",
         "--sign", identity, str(app)],
        capture_output=True, text=True,
    )
    if code.returncode:
        raise BundleError("Developer ID signing failed")
    verify_release(app, bundle_id, team_id)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="cmd", required=True)
    p = subs.add_parser("assemble")
    p.add_argument("--binary", required=True, type=pathlib.Path)
    p.add_argument("--app", required=True, type=pathlib.Path)
    p.add_argument("--bundle-id", required=True)
    for cmd in ("verify-release", "sign-release"):
        p = subs.add_parser(cmd)
        p.add_argument("--app", required=True, type=pathlib.Path)
        p.add_argument("--bundle-id", required=True)
        p.add_argument("--team-id", required=True)
        if cmd == "sign-release":
            p.add_argument("--identity", required=True)
    args = parser.parse_args()
    try:
        if args.cmd == "assemble":
            assemble(args.binary, args.app, args.bundle_id)
            print("ASSEMBLED_UNSIGNED_SYNTHETIC_REVIEWER_APP")
        elif args.cmd == "verify-release":
            verify_release(args.app, args.bundle_id, args.team_id)
            print("VERIFIED_DEVELOPER_ID_SIGNATURE_NOT_NOTARIZED")
        else:
            sign_release(args.app, args.bundle_id, args.team_id, args.identity)
            print("DEVELOPER_ID_SIGNED_NOT_NOTARIZED")
    except (BundleError, OSError) as error:
        print(f"DENIED: {error}", file=sys.stderr)
        return 78
    return 0


if __name__ == "__main__":
    sys.exit(main())
