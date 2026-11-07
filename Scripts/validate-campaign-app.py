#!/usr/bin/env python3
"""Validate a disposable local-review Release .app, never a distribution artifact.

macOS/Xcode and a clean checkout are required. --output must name an absent
folder outside the checkout. Only evidence.json survives; app/build/probe files
are temporary. No installation, publication, network/provider calls, permission
prompts, Gatekeeper bypass, or signing credentials are involved.

GUI startup may write preferences/application support. It is OFF by default and
--launch-on-disposable-runner is allowed only when GITHUB_ACTIONS=true and
RUNNER_ENVIRONMENT=github-hosted. Never use it on a user's workstation. The gate
requires a visible window owned by the exact child PID, not merely a live process.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid

REPO = Path(__file__).resolve().parents[1]
RESOURCE_SOURCES = {
    "pricing.json": "Sources/ScreenplayDomain/Resources/pricing.json",
    "ScreenplayOS.icns": "Sources/ScreenplayOSApp/Resources/ScreenplayOS.icns",
    "ScreenplayOSAppIcon.png": "Sources/ScreenplayOSApp/Resources/ScreenplayOSAppIcon.png",
    **{f"LegacyConverter/Scripts/{name}": f"Scripts/{name}" for name in (
        "convert-legacy-copy.py", "legacy_copy.py", "legacy_destination.py",
        "legacy_media.py", "inspect-legacy.py")},
    **{f"LegacyConverter/Specs/{name}": f"Specs/{name}" for name in (
        "screenplayos-1.0.schema.json", "legacy/open-screenplay-1.0.schema.json",
        "drafts/legacy-destination-0.1.schema.json")},
}
LIMITATIONS = [
    "Local ad-hoc signature only; not Developer ID signed, notarized, or approved for downloaded distribution.",
    "No installation, publication, accounts, live providers, or user documents are supplied or modified. Normal GUI startup may create blank documents/preferences on the disposable runner.",
    "Resource probe compiles unchanged production Commerce.swift plus the actual generated SwiftPM accessor; it is not a shipping app command.",
    "A window smoke test is startup evidence only, not interactive Campaign workflow or visual-quality acceptance.",
    "Native-open evidence uses OS document events, exact process/window metadata, and the existing post-decode recent-document preference. It does not inspect rendered content or prove keyboard, selection, Undo, or physical-user acceptance.",
    "Native-open negative controls observe a bounded interval; synthetic source bytes are checked unchanged. Disposable-runner preferences may retain temporary paths after cleanup.",
    "No Accessibility/Screen Recording permission, screenshot, Gatekeeper bypass, or existing-app termination is used.",
    "Missing/malformed pricing probes intentionally fail with production fatal errors; macOS may create diagnostic reports for these disposable probes.",
]


class ValidationError(RuntimeError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def sha256(path: Path) -> str:
    with path.open("rb") as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
        return digest.hexdigest()


def inside(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def prepare_output(output: Path, repo: Path) -> Path:
    # Reject existing files, directories and broken symlinks; never replace evidence.
    require(not output.exists() and not output.is_symlink(), "Output already exists; choose a new evidence directory.")
    output = output.resolve()
    require(not inside(output, repo), "Evidence output must be outside the checkout.")
    require(output.parent.is_dir(), "Evidence parent directory must already exist.")
    output.mkdir(mode=0o700)
    return output


def check_launch_permission(enabled: bool, env: dict[str, str]) -> None:
    if enabled:
        require(env.get("GITHUB_ACTIONS") == "true" and env.get("RUNNER_ENVIRONMENT") == "github-hosted",
                "GUI launch requires GITHUB_ACTIONS=true and RUNNER_ENVIRONMENT=github-hosted on a disposable hosted runner.")


def stop_command_tree(process: subprocess.Popen, *, grace=5) -> None:
    """Terminate only a new session created for this command and its children."""
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=grace)
    except subprocess.TimeoutExpired:
        pass
    # The leader may exit before a compiler descendant. Reap the entire owned
    # group before removing its scratch files, not just the shell process.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait(timeout=5)


class Runner:
    """Record bounded diagnostics; large build logs exist only in temporary storage."""
    def __init__(self, evidence: dict):
        self.evidence = evidence
        self.last_returncode = None

    def run(self, args, *, cwd=None, env=None, timeout=120, allowed=(0,), include_output=False,
            termination_grace=5):
        args = [str(arg) for arg in args]
        started = time.monotonic()
        print("Checking: " + " ".join(args), flush=True)
        timed_out = False
        interrupted = False
        # File-backed capture prevents build output from consuming unbounded RAM.
        with tempfile.TemporaryFile() as log:
            process = subprocess.Popen(args, cwd=cwd, env=env, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                stop_command_tree(process, grace=termination_grace)
            except KeyboardInterrupt:
                interrupted = True
                stop_command_tree(process, grace=termination_grace)
            self.last_returncode = process.returncode
            log.seek(0)
            digest = hashlib.sha256()
            tail = b""
            for block in iter(lambda: log.read(64 * 1024), b""):
                digest.update(block)
                tail = (tail + block)[-16000:]
        output = tail.decode("utf-8", errors="replace")
        record = {"command": args, "returncode": process.returncode,
                  "elapsedSeconds": round(time.monotonic() - started, 3),
                  "outputSHA256": digest.hexdigest()}
        if timed_out:
            record["timedOut"] = True
        if interrupted:
            record["interrupted"] = True
        if include_output or (allowed is not None and process.returncode not in allowed):
            record["outputTail"] = output
        self.evidence.setdefault("commands", []).append(record)
        if interrupted:
            raise KeyboardInterrupt("validation command interrupted")
        require(not timed_out, f"Command timed out after {timeout}s: {args[0]}")
        require(allowed is None or process.returncode in allowed,
                f"Command failed ({process.returncode}): {args[0]}\n{output[-4000:]}")
        return output


def git_state(repo: Path, runner: Runner) -> dict:
    head = runner.run(["git", "rev-parse", "HEAD"], cwd=repo).strip()
    require(re.fullmatch(r"[0-9a-f]{40}", head) is not None, "Git did not return a full source SHA.")
    status = runner.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=repo).strip()
    runner.evidence.setdefault("source", {"head": head, "clean": not status})
    require(not status, "Source checkout is dirty; commit the reviewed source before validating a package.")
    return {"head": head, "clean": True}


def regular_file(path: Path, root: Path) -> None:
    require(path.is_file() and not path.is_symlink() and inside(path, root), f"Missing or unsafe regular file: {path}")
    for parent in path.parents:
        if parent == root:
            break
        require(not parent.is_symlink(), f"Symlinked resource parent: {parent}")


def verify_bundle(app: Path, repo: Path, head: str, *, version="0.1", build="1") -> dict:
    """Independent static contract; usable in portable unit tests without macOS."""
    require(app.is_dir() and not app.is_symlink(), "App must be a real directory.")
    plist_path = app / "Contents/Info.plist"
    regular_file(plist_path, app)
    try:
        info = plistlib.loads(plist_path.read_bytes())
    except (ValueError, plistlib.InvalidFileException) as error:
        raise ValidationError("App Info.plist is invalid.") from error
    require(isinstance(info, dict), "App Info.plist must be a dictionary.")
    expected = {
        "CFBundleExecutable": "ScreenplayOS", "CFBundleIdentifier": "com.screenplayos.app",
        "CFBundleName": "ScreenplayOS", "CFBundleIconFile": "ScreenplayOS.icns",
        "CFBundlePackageType": "APPL", "CFBundleShortVersionString": version,
        "CFBundleVersion": build, "LSMinimumSystemVersion": "13.0",
        "NSHighResolutionCapable": True, "ScreenplayOSBuildConfiguration": "release",
        "ScreenplayOSSourceRevision": head, "ScreenplayOSSourceDirty": False,
        "CFBundleDocumentTypes": [{"CFBundleTypeName": "ScreenplayOS document",
            "CFBundleTypeRole": "Editor", "LSItemContentTypes": ["com.screenplayos.document"]}],
        "UTExportedTypeDeclarations": [{"UTTypeIdentifier": "com.screenplayos.document",
            "UTTypeDescription": "ScreenplayOS document", "UTTypeConformsTo": ["public.json"],
            "UTTypeTagSpecification": {"public.filename-extension": ["screenplayos.json"],
                "public.mime-type": "application/vnd.screenplayos+json"}}],
    }
    for key, value in expected.items():
        require(info.get(key) == value and type(info.get(key)) is type(value), f"Incorrect plist field: {key}")
    revision = info.get("ScreenplayOSRevision", "")
    require(isinstance(revision, str) and len(revision) >= 7 and head.startswith(revision),
            "Display revision must be a clean prefix of the full source SHA.")
    executable = app / "Contents/MacOS/ScreenplayOS"
    regular_file(executable, app)
    require(os.access(executable, os.X_OK), "Packaged executable is not executable.")
    resources = app / "Contents/Resources"
    manifest_path = resources / "BuildManifest.json"
    regular_file(manifest_path, app)
    try:
        manifest = json.loads(manifest_path.read_text())
    except (ValueError, UnicodeError) as error:
        raise ValidationError("Build manifest is invalid JSON.") from error
    require(isinstance(manifest, dict), "Build manifest must be an object.")
    require(type(manifest.get("schemaVersion")) is int and manifest["schemaVersion"] == 1,
            "Build manifest schema is unsupported.")
    require(manifest.get("sourceRevision") == head and manifest.get("sourceDirty") is False
            and manifest.get("buildConfiguration") == "release", "Build manifest source/configuration is incorrect.")
    entries = manifest.get("resources")
    require(isinstance(entries, dict) and set(entries) == set(RESOURCE_SOURCES), "Build manifest resource inventory is incorrect.")
    hashes = {}
    for name, source in RESOURCE_SOURCES.items():
        packaged, original = resources / name, repo / source
        regular_file(packaged, app)
        regular_file(original, repo)
        digest = sha256(packaged)
        require(digest == sha256(original), f"Packaged resource differs from source: {name}")
        require(entries[name] == {"source": source, "sha256": digest}, f"Build manifest hash/source is incorrect: {name}")
        hashes[name] = digest
    actual_resources = {str(path.relative_to(resources)) for path in resources.rglob("*") if path.is_file() or path.is_symlink()}
    require(actual_resources == set(RESOURCE_SOURCES) | {"BuildManifest.json"}, "App contains unexpected or missing resources.")
    try:
        pricing = json.loads((resources / "pricing.json").read_text())
    except (ValueError, UnicodeError) as error:
        raise ValidationError("Packaged pricing is invalid JSON.") from error
    require(isinstance(pricing, dict), "Packaged pricing must be an object.")
    # A deterministic tree digest identifies the signed app without retaining or
    # uploading the binary. Include the code seal as well as executable/resources.
    tree = {}
    for path in sorted(app.rglob("*")):
        if path.is_file() or path.is_symlink():
            regular_file(path, app)
            tree[str(path.relative_to(app))] = sha256(path)
    tree_digest = hashlib.sha256(json.dumps(tree, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
    return {"status": "passed", "bundleTreeSHA256": tree_digest, "plistSHA256": sha256(plist_path),
            "executableSHA256": sha256(executable), "manifestSHA256": sha256(manifest_path),
            "resourceSHA256": hashes, "pricing": pricing}


def expected_architectures(architecture: str) -> set[str]:
    require(architecture in ("arm64", "x86_64", "universal"), "Unsupported architecture.")
    return {"arm64", "x86_64"} if architecture == "universal" else {architecture}


def verify_native(app: Path, architecture: str, runner: Runner) -> dict:
    executable = app / "Contents/MacOS/ScreenplayOS"
    arches = runner.run(["lipo", "-archs", executable], include_output=True).split()
    require(set(arches) == expected_architectures(architecture), "Packaged executable architecture differs from the requested architecture.")
    runner.run(["plutil", "-lint", app / "Contents/Info.plist"], include_output=True)
    runner.run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", app], include_output=True)
    details = runner.run(["codesign", "--display", "--verbose=4", app], include_output=True)
    require("Signature=adhoc" in details, "Validator requires an ad-hoc local-review signature.")
    require("TeamIdentifier=not set" in details, "Unexpected distribution signing identity.")
    return {"status": "passed", "architectures": sorted(arches), "signing": "ad-hoc", "notarized": False}


def find_accessor(scratch: Path) -> Path:
    candidates = list(scratch.glob("**/ScreenplayDomain.build/DerivedSources/resource_bundle_accessor.swift"))
    require(bool(candidates), "Actual generated ScreenplayDomain resource accessor was not found.")
    # Universal builds have one accessor per architecture with the same contract.
    candidates.sort()
    for candidate in candidates:
        source = candidate.read_text()
        paths = re.findall(r'let buildPath\s*=\s*"([^"\n]+)"', source)
        require(len(paths) == 1 and inside(Path(paths[0]), scratch),
                "Generated resource fallback is not entirely inside the owned scratch tree.")
        require("Bundle.main.bundleURL" in source, "Unexpected generated resource accessor; review the isolation contract.")
    return candidates[0]


@contextmanager
def hidden_scratch(scratch: Path):
    """Hide only this run's owned tree, never the checkout or another user's build."""
    hidden = scratch.with_name(scratch.name + ".hidden")
    require(scratch.is_dir() and not scratch.is_symlink() and not hidden.exists() and not hidden.is_symlink(),
            "Cannot safely hide the owned scratch tree.")
    try:
        scratch.rename(hidden)
        yield
    finally:
        # Nothing runs SwiftPM while hidden. Do not overwrite an unexpected path.
        require(not scratch.exists() and not scratch.is_symlink(), "Scratch path reappeared; refusing to overwrite it during restoration.")
        hidden.rename(scratch)


def build_probe(repo: Path, app: Path, scratch: Path, root: Path, runner: Runner) -> tuple[Path, dict]:
    accessor = find_accessor(scratch)
    probe = root / "ResourceProbe.app"
    executable = probe / "Contents/MacOS/ResourceProbe"
    executable.parent.mkdir(parents=True)
    shutil.copytree(app / "Contents/Resources", probe / "Contents/Resources")
    (probe / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleExecutable": "ResourceProbe", "CFBundleIdentifier": "com.screenplayos.packaging-resource-probe",
        "CFBundleName": "ResourceProbe", "CFBundlePackageType": "APPL"}))
    commerce = repo / "Sources/ScreenplayDomain/Commerce.swift"
    main = repo / "Scripts/Packaging/ResourceProbe.swift"
    target = ("arm64" if platform.machine() == "arm64" else "x86_64") + "-apple-macosx13.0"
    runner.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-target", target, commerce, accessor, main,
                "-o", executable], cwd=root, timeout=180)
    runner.run(["codesign", "--force", "--sign", "-", probe])
    prefixes = re.findall(r'fatalError\("([^"\\\n]{10,})', accessor.read_text())
    require(len(prefixes) == 1, "Cannot identify generated accessor fatal error for the missing-resource control.")
    return executable, {"productionCommerceSHA256": sha256(commerce),
                        "generatedAccessorSHA256": sha256(accessor), "probeMainSHA256": sha256(main),
                        "missingBundleFatalPrefix": prefixes[0]}


def run_probe(executable: Path, expected_path: Path, expected: dict, runner: Runner, *, cwd: Path) -> dict:
    output = runner.run([executable, expected_path], cwd=cwd)
    try:
        actual = json.loads(output)
    except ValueError as error:
        raise ValidationError("Resource probe did not return decoded pricing JSON.") from error
    # JSONEncoder omits nil optionals; equality against the full decoded source is
    # also checked inside Swift using PricingConfiguration's synthesized equality.
    normalized = {key: value for key, value in expected.items() if value is not None}
    require(actual == normalized, "Decoded runtime pricing differs from the full source configuration.")
    return {"status": "passed", "decodedPricing": actual, "entireDecodedConfigurationCompared": True,
            "swiftPMBuildFallbackHidden": True, "resourcesCopiedFromActualApp": True}


def negative_resource_checks(app: Path, repo: Path, head: str, root: Path) -> dict:
    """Tamper disposable copies, proving pre-publication checks fail closed."""
    candidate = root / "Tampered.app"
    shutil.copytree(app, candidate)
    pricing = candidate / "Contents/Resources/pricing.json"
    original = pricing.read_bytes()
    cases = {}
    try:
        for case in ("missingPricing", "alteredPricing", "missingConverter", "alteredIcon"):
            target = pricing
            if case == "missingPricing":
                pricing.unlink()
            elif case == "alteredPricing":
                changed = json.loads(original)
                changed["proMonthlyCents"] += 1
                pricing.write_text(json.dumps(changed))
            elif case == "missingConverter":
                target = candidate / "Contents/Resources/LegacyConverter/Scripts/legacy_copy.py"
                target.unlink()
            else:
                target = candidate / "Contents/Resources/ScreenplayOS.icns"
                target.write_bytes(b"not-an-icon")
            try:
                verify_bundle(candidate, repo, head)
            except ValidationError:
                cases[case] = "rejected"
            else:
                raise ValidationError(f"Negative resource control was incorrectly accepted: {case}")
            # Restore from the validated actual app, not a synthesized test resource.
            shutil.copyfile(app / target.relative_to(candidate), target)
    finally:
        shutil.rmtree(candidate)
    return {"status": "passed", "cases": cases}


def negative_runtime_checks(probe: Path, expected: Path, root: Path, missing_prefix: str, runner: Runner) -> dict:
    """Run unchanged production code against damaged, re-signed probe copies."""
    results = {}
    for case, contents, expected_error in (
        ("missingPricing", None, missing_prefix),
        ("malformedPricing", b"{invalid json", "The bundled pricing configuration is missing or invalid."),
    ):
        app = root / (case + ".app")
        shutil.copytree(probe.parents[2], app)
        pricing = app / "Contents/Resources/pricing.json"
        if contents is None:
            pricing.unlink()
        else:
            pricing.write_bytes(contents)
        # Tampering invalidates the previous signature. Re-sign and verify so an
        # OS signature refusal cannot be mistaken for a production lookup failure.
        runner.run(["codesign", "--force", "--sign", "-", app])
        runner.run(["codesign", "--verify", "--deep", "--strict", app])
        env = dict(os.environ)
        env["SWIFT_BACKTRACE"] = "enable=no"
        output = runner.run([app / "Contents/MacOS/ResourceProbe", expected], cwd=root,
                            env=env, timeout=15, allowed=None)
        require(runner.last_returncode != 0, f"Runtime negative control was accepted: {case}")
        require("Fatal error:" in output and expected_error in output,
                f"Runtime negative control failed for an unexpected reason: {case}")
        results[case] = {"status": "rejected", "returncode": runner.last_returncode,
                         "matchedProductionError": expected_error, "signatureReverified": True}
    return {"status": "passed", "swiftPMBuildFallbackHidden": True, "cases": results}


def stop_child(process: subprocess.Popen) -> None:
    # Popen owns this exact child; never use killall, process names or bundle IDs.
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def launch_smoke(app: Path, window_probe: Path, runner: Runner, *, timeout=30) -> dict:
    executable = app / "Contents/MacOS/ScreenplayOS"
    # Do not record app stdout/stderr, window titles, or restored content.
    process = subprocess.Popen([str(executable)], cwd=app.parent,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    result = {"status": "failed", "pid": process.pid, "visibleWindowCount": 0}
    try:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            require(process.poll() is None, "Packaged app exited before showing its window.")
            output = runner.run([window_probe, str(process.pid), executable], timeout=5)
            try:
                window = json.loads(output)
            except ValueError as error:
                raise ValidationError("Window probe returned invalid metadata.") from error
            require(window.get("pid") == process.pid, "Window probe reported a different process.")
            if (type(window.get("visibleWindowCount")) is int and window["visibleWindowCount"] > 0
                    and window.get("finishedLaunching") is True and window.get("executableMatches") is True):
                # Catch immediate startup crashes even if a window briefly appeared.
                time.sleep(2)
                require(process.poll() is None, "Packaged app exited just after showing its window.")
                result.update(status="passed", visibleWindowCount=window["visibleWindowCount"],
                              finishedLaunching=True, executableMatches=True,
                              minimumWindowSize={"width": 900, "height": 560})
                break
            time.sleep(0.5)
        require(result["status"] == "passed", "Packaged app showed no visible normal window before timeout.")
    finally:
        stop_child(process)
        result["ownedChildReaped"] = process.poll() is not None
    return result


NATIVE_OPEN_INPUTS = (
    "cold.screenplayos.json", "warm.screenplayos.json", "multi-a.screenplayos.json",
    "multi-b.screenplayos.json", "unsupported.txt", "malformed.screenplayos.json",
)
NATIVE_OPEN_CASES = {
    "coldOpen": (1, 1), "warmOpen": (1, 1), "repeatSameFile": (1, 1),
    "multipleURLsRejected": (2, 0), "unsupportedRejected": (1, 0), "malformedRejected": (1, 0),
}


def make_native_open_inputs(root: Path) -> dict[str, str]:
    """Fresh minimal native documents, independent of private/pilot fixtures."""
    root.mkdir(mode=0o700)  # Never reuse inputs or their recent-document paths.
    for name in NATIVE_OPEN_INPUTS:
        path = root / name
        if name == "malformed.screenplayos.json":
            data = b'{"format": "screenplayos", invalid JSON\n'
        else:
            screenplay_id = str(uuid.uuid4()).upper()
            document = {
                "format": "screenplayos", "format_version": "1.0",
                "project": {"id": str(uuid.uuid4()).upper(), "screenplay_id": screenplay_id,
                    "metadata": {"title": "Synthetic native-open check", "author": "",
                        "created_at": "2026-01-01T00:00:00Z", "modified_at": "2026-01-01T00:00:00Z"}},
                "screenplay": {"id": screenplay_id, "metadata": {"title": "Synthetic native-open check"},
                    "elements": [{"id": str(uuid.uuid4()).upper(), "type": "action",
                        "text": "A blank ticket rests beside a fictional receipt printer.", "external_ids": {}}],
                    "revision": 0, "revision_settings": {"mode_enabled": False,
                        "label": "Blue Revision", "color": "blue"}},
            }
            data = (json.dumps(document, sort_keys=True, indent=2) + "\n").encode()
        with path.open("xb") as stream:
            stream.write(data)
        path.chmod(0o600)
    return {name: sha256(root / name) for name in NATIVE_OPEN_INPUTS}


def verify_native_open_output(output: str, app: Path) -> dict:
    """Fail closed: a workspace completion callback alone is never a load pass."""
    try:
        result = json.loads(output)
    except (ValueError, TypeError) as error:
        raise ValidationError("Native-open probe returned invalid JSON evidence.") from error
    fields = {"schemaVersion", "status", "appPath", "executablePath", "pid",
              "initialRecentInputsAbsent", "scenarios", "cleanup"}
    require(isinstance(result, dict) and set(result) == fields, "Native-open evidence fields are not allowlisted.")
    require(type(result["schemaVersion"]) is int and result["schemaVersion"] == 1
            and result["status"] == "passed", "Native-open probe did not pass.")
    require(result["appPath"] == str(app.resolve())
            and result["executablePath"] == str((app / "Contents/MacOS/ScreenplayOS").resolve()),
            "Native-open probe used a different app or executable.")
    pid = result["pid"]
    require(type(pid) is int and pid > 0, "Native-open process identity is invalid.")
    require(result["initialRecentInputsAbsent"] is True, "Native-open inputs were not proven absent from recents.")
    cases = result["scenarios"]
    require(isinstance(cases, dict) and set(cases) == set(NATIVE_OPEN_CASES), "Native-open scenarios are incomplete.")
    case_fields = {"status", "pid", "requestedURLCount", "workspaceCompletionReceived",
                   "executableMatches", "finishedLaunching", "mainWindowIDs", "recentFirstMatches",
                   "matchingRecentURLCount", "rejectedURLsAbsent", "stableObservationSeconds"}
    main_windows = None
    for name, (request_count, recent_count) in NATIVE_OPEN_CASES.items():
        case = cases[name]
        require(isinstance(case, dict) and set(case) == case_fields, f"Native-open scenario fields are not allowlisted: {name}")
        require(case["status"] == "passed" and type(case["pid"]) is int and case["pid"] == pid,
                f"Native-open scenario changed process: {name}")
        for key in ("workspaceCompletionReceived", "executableMatches", "finishedLaunching",
                    "recentFirstMatches", "rejectedURLsAbsent"):
            require(case[key] is True, f"Native-open scenario lacks {key}: {name}")
        require(type(case["requestedURLCount"]) is int and case["requestedURLCount"] == request_count
                and type(case["matchingRecentURLCount"]) is int and case["matchingRecentURLCount"] == recent_count,
                f"Native-open scenario did not prove its requested/rejected URL state: {name}")
        windows = case["mainWindowIDs"]
        require(isinstance(windows, list) and len(windows) == 1 and type(windows[0]) is int and windows[0] > 0,
                f"Native-open scenario lacks one visible main window: {name}")
        if main_windows is None:
            main_windows = windows
        require(windows == main_windows, f"Native-open scenario replaced the main window: {name}")
        duration = case["stableObservationSeconds"]
        require(type(duration) in (int, float) and 2 <= duration <= 35,
                f"Native-open scenario lacks bounded stable observation: {name}")
    cleanup = result["cleanup"]
    require(isinstance(cleanup, dict) and set(cleanup) == {"status", "pid", "executableMatches", "terminated", "forceTerminationUsed"},
            "Native-open cleanup evidence is not allowlisted.")
    require(cleanup["status"] == "passed" and type(cleanup["pid"]) is int and cleanup["pid"] == pid
            and cleanup["executableMatches"] is True and cleanup["terminated"] is True
            and type(cleanup["forceTerminationUsed"]) is bool, "Native-open owned app was not safely terminated.")
    return result


def native_open_smoke(app: Path, probe: Path, root: Path, runner: Runner, result: dict) -> None:
    check_launch_permission(True, dict(os.environ))
    inputs = root / "native-open-inputs"
    before = make_native_open_inputs(inputs)
    result.update(status="failed", inputSHA256=before, sourceBytesUnchanged=False,
                  evidenceScope="OS-native-open-loaded-model-route; not rendered-content or physical-user acceptance")
    try:
        # This helper owns the NSWorkspace-launched instance, not the Python
        # process group. Give its signal handler time to verify/stop that exact
        # instance before Runner can escalate termination of the helper itself.
        output = runner.run([probe, app, inputs], cwd=root, timeout=240, termination_grace=10)
        result["probe"] = verify_native_open_output(output, app)
    finally:
        unchanged = all((inputs / name).is_file() and not (inputs / name).is_symlink()
                        and sha256(inputs / name) == digest for name, digest in before.items())
        result["sourceBytesUnchanged"] = unchanged
        require(unchanged, "Native-open changed or removed a synthetic source file.")
    result["status"] = "passed"


def validate(repo: Path, architecture: str, launch: bool, evidence: dict) -> None:
    check_launch_permission(launch, dict(os.environ))
    require(platform.system() == "Darwin", "Real .app validation requires macOS and Xcode; portable tests do not substitute for this gate.")
    runner = Runner(evidence)
    initial = git_state(repo, runner)
    evidence["source"] = initial
    evidence["host"] = {"system": platform.system(), "release": platform.release(), "machine": platform.machine()}
    evidence["toolchain"] = {"swift": runner.run(["xcrun", "swift", "--version"], include_output=True).strip(),
                             "xcode": runner.run(["xcodebuild", "-version"], include_output=True).strip()}
    native = "arm64" if platform.machine() == "arm64" else "x86_64"
    require(native in expected_architectures(architecture), "Requested architecture cannot run natively on this runner; no Rosetta installation is attempted.")
    with tempfile.TemporaryDirectory(prefix="campaign-app-validation-") as temporary:
        root = Path(temporary).resolve()
        require(not inside(root, repo), "Temporary validation directory must be outside the checkout.")
        scratch = root / "build"
        built = root / "staging/ScreenplayOS.app"
        built.parent.mkdir()
        require(not built.exists(), "Package destination must be absent.")
        env = dict(os.environ)
        env.update(SCREENPLAYOS_SCRATCH_PATH=str(scratch), SCREENPLAYOS_BUILD_CONFIGURATION="release",
                   SCREENPLAYOS_BUILD_ARCH=architecture, SCREENPLAYOS_SIGNING_IDENTITY="-",
                   SCREENPLAYOS_NOTARY_PROFILE="", SCREENPLAYOS_ALLOW_DIRTY="0",
                   SCREENPLAYOS_APP_VERSION="0.1", SCREENPLAYOS_BUILD_NUMBER="1",
                   SCREENPLAYOS_SKIP_REVIEW_CLEANUP="1")
        runner.run(["bash", repo / "Scripts/package-app.sh", built], cwd=repo, env=env, timeout=1800)
        require(git_state(repo, runner) == initial, "Source changed during packaging.")
        evidence["bundle"] = verify_bundle(built, repo, initial["head"])
        evidence["nativeBundle"] = verify_native(built, architecture, runner)
        evidence["negativeResourceControls"] = negative_resource_checks(built, repo, initial["head"], root)
        relocated = root / "relocated/ScreenplayOS.app"
        relocated.parent.mkdir()
        shutil.move(str(built), relocated)
        require(not built.exists(), "Original app destination still exists after relocation.")
        evidence["relocatedBundle"] = verify_native(relocated, architecture, runner)
        require(verify_bundle(relocated, repo, initial["head"]) == evidence["bundle"], "Relocation changed the packaged bundle.")
        probe, probe_details = build_probe(repo, relocated, scratch, root, runner)
        expected = root / "expected-pricing.json"
        shutil.copyfile(repo / RESOURCE_SOURCES["pricing.json"], expected)
        window_probe = root / "window-probe"
        native_open_probe = root / "native-open-probe"
        if launch:
            runner.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-target", native + "-apple-macosx13.0",
                        repo / "Scripts/Packaging/WindowProbe.swift",
                        "-o", window_probe], cwd=root, timeout=120)
            runner.run(["xcrun", "swiftc", "-O", "-parse-as-library", "-target", native + "-apple-macosx13.0",
                        repo / "Scripts/Packaging/NativeOpenProbe.swift",
                        "-o", native_open_probe], cwd=root, timeout=120)
        with hidden_scratch(scratch):
            evidence["runtimePricing"] = {**probe_details,
                **run_probe(probe, expected, evidence["bundle"]["pricing"], runner, cwd=relocated.parent)}
            evidence["negativeRuntimeControls"] = negative_runtime_checks(
                probe, expected, root, probe_details["missingBundleFatalPrefix"], runner)
            if launch:
                evidence["launch"] = launch_smoke(relocated, window_probe, runner)
                evidence["nativeOpen"] = {"status": "failed"}
                native_open_smoke(relocated, native_open_probe, root, runner, evidence["nativeOpen"])
            else:
                evidence["launch"] = {"status": "not_run", "reason": "GUI launch was not opted into on a disposable hosted runner."}
                evidence["nativeOpen"] = dict(evidence["launch"])
        evidence["scratchRestored"] = scratch.is_dir()
        require(evidence["scratchRestored"], "Owned build tree was not restored.")
        require(git_state(repo, runner) == initial, "Source changed during validation.")
    evidence["temporaryArtifactsRemoved"] = not root.exists()
    require(evidence["temporaryArtifactsRemoved"], "Temporary app/build artifacts were not removed.")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="new evidence directory outside the checkout; parent must exist")
    parser.add_argument("--architecture", choices=("arm64", "x86_64", "universal"),
                        default="arm64" if platform.machine() == "arm64" else "x86_64")
    parser.add_argument("--launch-on-disposable-runner", action="store_true", help="require window and OS-native-open gates; GitHub-hosted disposable CI only")
    args = parser.parse_args(argv)
    evidence = {"schemaVersion": 1, "status": "failed", "purpose": "local-review-app-validation",
                "startedAt": datetime.now(timezone.utc).isoformat(), "requestedArchitecture": args.architecture,
                "launchRequested": args.launch_on_disposable_runner, "limitations": list(LIMITATIONS)}
    try:
        output = prepare_output(args.output, REPO)
    except (OSError, ValidationError) as error:
        print(f"Validation refused: {error}", file=sys.stderr)
        return 1
    # A normal interruption must unwind scratch hiding and owned-child cleanup.
    def interrupt(signum, frame):
        raise KeyboardInterrupt(f"signal {signum}")
    old_term = signal.signal(signal.SIGTERM, interrupt)
    try:
        validate(REPO, args.architecture, args.launch_on_disposable_runner, evidence)
        evidence["status"] = "passed"
    except (ValidationError, OSError, ValueError, KeyboardInterrupt) as error:
        evidence["error"] = str(error) or type(error).__name__
        print(f"Validation failed: {evidence['error']}", file=sys.stderr)
    finally:
        signal.signal(signal.SIGTERM, old_term)
        evidence["completedAt"] = datetime.now(timezone.utc).isoformat()
        (output / "evidence.json").write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    print(f"{evidence['status']}: {output / 'evidence.json'}")
    return 0 if evidence["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
