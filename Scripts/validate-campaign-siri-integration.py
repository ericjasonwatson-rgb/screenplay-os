#!/usr/bin/env python3
"""Compose and test the reviewed Campaign + Siri tree without moving any branch.

The checkout must already contain the pinned Siri commit. No fetch, merge commit,
push, or real branch update occurs. Native tests need macOS/Xcode; --prepare-only
performs the deterministic tree/patch checks on other hosts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

SIRI_HEAD = "c20b136622cc752cc350335824bcd0de33a846a0"
CAMPAIGN_BASE = "d8ad69259d7ca04011fb683f189d0cc29b983c0a"
MERGE_BASE = "f995ee1d2fe383b1159e0fa9dddd9b76f777696b"
APP = "Sources/ScreenplayOSApp/ScreenplayOSApp.swift"
SIRI_SOURCE = "Sources/ScreenplayOSApp/SiriWorkspaceIntents.swift"
SIRI_TESTS = "Tests/ScreenplayEditorTests/SiriWorkspaceIntentsTests.swift"
INTEGRATION_TEST = "CampaignSiriWorkspaceIntegrationTests.swift"
# The sanitized Siri head retains the original five implementation/test changes
# and deletes two private fixtures. Match statuses too: a deletion is not an
# allowance to reintroduce a similarly named file.
SIRI_INVENTORY = {
    APP: "M", SIRI_SOURCE: "A", SIRI_TESTS: "A",
    "Sources/ScreenplayOSApp/ScreenplayChromeState.swift": "M",
    ".github/workflows/siri-intents-macos.yml": "A",
    "Tests/Fixtures/Defenders_of_Cat_Island.open-screenplay.json": "D",
    "Tests/Fixtures/Defenders_of_Cat_Island_Pilot_Final_Draft.fdx": "D",
}
SIRI_FILES = set(SIRI_INVENTORY)
HYGIENE_PATH = "Scripts/check-fixture-hygiene.py"
PATCH_PATH = "Scripts/Integration/campaign-siri-modal-boundary.patch"
TEST_PATH = "Tests/Integration/" + INTEGRATION_TEST


class IntegrationError(RuntimeError):
    pass


def git(repo: Path, *args: str, allowed: tuple[int, ...] = (0,)) -> subprocess.CompletedProcess:
    result = subprocess.run(["git", "-C", str(repo), *args], capture_output=True)
    if result.returncode not in allowed:
        raise IntegrationError(result.stderr.decode().strip() or result.stdout.decode().strip()
                               or f"git {args[0]} failed ({result.returncode})")
    return result


def resolve(repo: Path, ref: str) -> str:
    return git(repo, "rev-parse", "--verify", ref + "^{commit}").stdout.decode().strip()


def reviewed_inputs(repo: Path, campaign_ref: str, siri_ref: str) -> tuple[str, str, str]:
    campaign = resolve(repo, campaign_ref)
    siri = resolve(repo, siri_ref)
    if siri != SIRI_HEAD:
        raise IntegrationError(f"Siri head changed: expected {SIRI_HEAD}, got {siri}. Review and refresh the integration artifacts; do not silently repin.")
    if git(repo, "merge-base", "--is-ancestor", CAMPAIGN_BASE, campaign, allowed=(0, 1)).returncode:
        raise IntegrationError("Campaign ref is not a descendant of the reviewed Campaign head.")
    if git(repo, "merge-base", "--is-ancestor", siri, campaign, allowed=(0, 1)).returncode == 0:
        raise IntegrationError("Siri is already in Campaign history. Retire this temporary integration check instead of replaying it.")
    base = git(repo, "merge-base", campaign, siri).stdout.decode().strip()
    if base != MERGE_BASE:
        raise IntegrationError("Siri merge base changed. Review ancestry before composing sources.")
    fields = git(repo, "diff", "--name-status", "--no-renames", "-z", base, siri).stdout.decode().split("\0")
    fields = fields[:-1] if fields[-1] == "" else fields
    if len(fields) % 2:
        raise IntegrationError("Malformed Siri source inventory; no composition is allowed.")
    inventory = dict(zip(fields[1::2], fields[::2]))
    if inventory != SIRI_INVENTORY:
        raise IntegrationError("Siri change inventory no longer matches the reviewed five source changes and two fixture deletions.")
    return campaign, siri, base


def check_fixture_hygiene(destination: Path) -> dict:
    """Check the materialized current tree, including prepare-only validation."""
    checker = destination / HYGIENE_PATH
    if not checker.is_file() or checker.is_symlink():
        raise IntegrationError("Composed source is missing the regular fixture-hygiene checker. Propagate the synthetic baseline before validation.")
    result = subprocess.run([sys.executable, str(checker)], cwd=destination,
                            capture_output=True, text=True)
    if result.returncode:
        # The checker reports paths/reasons, never matched private source text.
        details = (result.stderr or result.stdout).strip()
        raise IntegrationError(f"Composed source fixture hygiene failed (exit {result.returncode}). {details}")
    return {"status": "passed", "checker_sha256": hashlib.sha256(checker.read_bytes()).hexdigest(),
            "summary": result.stdout.strip()}


def compose(repo: Path, destination: Path, campaign_ref: str, siri_ref: str) -> dict:
    campaign, siri, base = reviewed_inputs(repo, campaign_ref, siri_ref)
    # Plumbing writes only Git objects, not a branch, index, or working file.
    result = git(repo, "merge-tree", "--write-tree", "--name-only", "--no-messages", "-z",
                 campaign, siri, allowed=(0, 1))
    fields = result.stdout.decode().split("\0")
    tree, conflicts = fields[0], set(filter(None, fields[1:]))
    if result.returncode != 1 or conflicts != {APP}:
        raise IntegrationError(f"Expected only the reviewed app-lifecycle conflict; found {sorted(conflicts)} (exit {result.returncode}). Review before updating the resolution.")
    if destination.exists():
        raise IntegrationError("Integration worktree destination already exists; refusing to overwrite it.")
    patch = repo / PATCH_PATH
    test = repo / TEST_PATH
    if not patch.is_file() or not test.is_file():
        raise IntegrationError("Reviewed integration patch or test fixture is missing.")
    git(repo, "worktree", "add", "--detach", str(destination), campaign)
    # Materialize the composed tree in the NEW detached worktree only. Keep all
    # Campaign changes to the app and resolve its conflict with the reviewed patch.
    git(destination, "read-tree", "--reset", "-u", tree)
    (destination / APP).write_bytes(git(repo, "show", f"{campaign}:{APP}").stdout)
    git(destination, "apply", "--check", str(patch))
    git(destination, "apply", str(patch))
    shutil.copyfile(test, destination / "Tests/ScreenplayEditorTests" / INTEGRATION_TEST)
    git(destination, "add", "--", APP, SIRI_SOURCE, "Tests/ScreenplayEditorTests/" + INTEGRATION_TEST)
    git(destination, "diff", "--cached", "--check")
    combined = git(destination, "write-tree").stdout.decode().strip()
    app = (destination / APP).read_text()
    if app.count(".sheet(isPresented: $model.campaignPresented)") != 1 or app.count("SiriWorkspaceNavigation.consume(model: model)") != 2:
        raise IntegrationError("Composed app no longer has exactly one Campaign sheet and both reviewed Siri lifecycle hooks.")
    if git(destination, "show", f"{combined}:{SIRI_TESTS}").stdout != git(repo, "show", f"{siri}:{SIRI_TESTS}").stdout:
        raise IntegrationError("Original Siri tests must remain byte-for-byte unchanged.")
    hygiene = check_fixture_hygiene(destination)
    manifest = {
        "campaign_head": campaign, "siri_head": siri, "merge_base": base,
        "combined_tree": combined,
        "fixture_hygiene": hygiene,
        "patch_sha256": hashlib.sha256(patch.read_bytes()).hexdigest(),
        "integration_tests_sha256": hashlib.sha256(test.read_bytes()).hexdigest(),
        "native_tests": "not run", "worktree": str(destination),
    }
    (destination / ".build").mkdir(exist_ok=True)
    (destination / ".build/campaign-siri-integration.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--campaign-ref", default="HEAD", help="Exact campaign source commit/ref (default HEAD).")
    parser.add_argument("--siri-ref", default=SIRI_HEAD, help="Fetched PR3 head/ref; must equal the reviewed pin.")
    parser.add_argument("--configuration", choices=("debug", "release"), default="debug")
    parser.add_argument("--worktree", type=Path, help="New destination; must not already exist.")
    parser.add_argument("--prepare-only", action="store_true", help="Compose and verify sources; do not claim native tests ran.")
    parser.add_argument("--keep-worktree", action="store_true", help="Retain the detached test tree for inspection.")
    args = parser.parse_args(argv)
    repo = Path(__file__).resolve().parent.parent
    temporary = None
    if args.worktree is None:
        temporary = tempfile.TemporaryDirectory(prefix="campaign-siri-")
        destination = Path(temporary.name) / "combined"
    else:
        destination = args.worktree.resolve()
    if destination == repo or repo in destination.parents:
        parser.error("Use a temporary worktree outside the source checkout.")
    if args.keep_worktree and args.worktree is None:
        parser.error("--keep-worktree requires an explicit --worktree destination.")
    existed = destination.exists()
    try:
        manifest = compose(repo, destination, args.campaign_ref, args.siri_ref)
        print(json.dumps(manifest, indent=2), flush=True)
        if args.prepare_only:
            print("Prepared and checked the combined source tree. Native tests NOT RUN.", flush=True)
            return 0
        if sys.platform != "darwin" or shutil.which("swift") is None or shutil.which("xcode-select") is None:
            raise IntegrationError("Native integration tests require macOS, Swift, and Xcode. Source composition passed; native tests did not run.")
        environment = os.environ.copy()
        environment["SCREENPLAYOS_BUILD_CONFIGURATION"] = args.configuration
        result = subprocess.run(["./Scripts/test.sh", "--no-parallel"], cwd=destination, env=environment)
        manifest["native_tests"] = "passed" if result.returncode == 0 else "failed"
        manifest["configuration"] = args.configuration
        (destination / ".build/campaign-siri-integration.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(json.dumps(manifest, indent=2), flush=True)
        return result.returncode
    except (IntegrationError, OSError) as error:
        print(f"Campaign/Siri integration stopped: {error}", file=sys.stderr)
        return 1
    finally:
        # Never remove a pre-existing directory, even after a failed preflight.
        if not existed and destination.exists() and not args.keep_worktree:
            git(repo, "worktree", "remove", "--force", str(destination))
        if temporary is not None:
            temporary.cleanup()


if __name__ == "__main__":
    raise SystemExit(main())
