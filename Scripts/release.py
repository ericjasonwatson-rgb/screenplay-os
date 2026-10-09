#!/usr/bin/env python3
"""Build a local review package or a signed, notarized direct-download release."""
import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
CONFIG = ROOT / "Website/release.json"


def run(*args, **kwargs):
    print("+", " ".join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), check=True, **kwargs)


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def verify_app(app, version, build, arch):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    expected = {"CFBundleIdentifier": "com.screenplayos.app", "CFBundleName": "ScreenplayOS",
                "CFBundleShortVersionString": version, "CFBundleVersion": str(build),
                "CFBundleIconFile": "ScreenplayOS.icns"}
    for key, value in expected.items():
        if info.get(key) != value:
            raise RuntimeError(f"{key}: expected {value!r}, found {info.get(key)!r}")
    for resource in ("ScreenplayOS.icns", "ScreenplayOSLogo.png"):
        if not (app / "Contents/Resources" / resource).is_file():
            raise RuntimeError(f"Missing app resource: {resource}")
    binary = app / "Contents/MacOS/ScreenplayOS"
    found = subprocess.check_output(["lipo", "-archs", str(binary)], text=True).split()
    wanted = ["arm64", "x86_64"] if arch == "universal" else [arch]
    if sorted(found) != sorted(wanted):
        raise RuntimeError(f"Expected architectures {wanted}, found {found}")
    run("codesign", "--verify", "--deep", "--strict", app)
    return info


def make_dmg(app, destination, temp, dmg_python):
    try:
        run(dmg_python, "-c", "import dmgbuild")
    except subprocess.CalledProcessError as error:
        raise RuntimeError("Install the pinned release dependency in a venv; see Docs/direct-distribution.md") from error
    run(dmg_python, "-m", "dmgbuild", "-s", ROOT / "Scripts/dmg-settings.py",
        "-D", f"app={app}", "ScreenplayOS", destination)
    run("hdiutil", "verify", destination)
    check = temp / "verify-mount"
    check.mkdir()
    run("hdiutil", "attach", destination, "-mountpoint", check, "-nobrowse", "-readonly")
    try:
        if not (check / "ScreenplayOS.app").is_dir() or not (check / "Applications").is_symlink():
            raise RuntimeError("DMG contents are incomplete")
        if (check / "Applications").resolve() != Path("/Applications"):
            raise RuntimeError("Applications shortcut target is wrong")
        layout = check / ".DS_Store"
        if not layout.is_file() or layout.stat().st_size < 100:
            raise RuntimeError("DMG Finder layout metadata is missing")
        run("codesign", "--verify", "--deep", "--strict", check / "ScreenplayOS.app")
    finally:
        run("hdiutil", "detach", check)
    return True

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--unsigned", action="store_true", help="local review build; allows dirty source")
    parser.add_argument("--dry-run", action="store_true", help="show requirements without building")
    parser.add_argument("--arch", choices=["arm64", "x86_64", "universal"], default="universal")
    parser.add_argument("--output", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    config = json.loads(CONFIG.read_text())
    version, build = config["version"], config["build"]
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", version) or not isinstance(build, int) or build < 1:
        parser.error("Website/release.json needs a numeric version and positive build")
    if config["downloadUrl"] != f"https://screenplayos.com/downloads/ScreenplayOS-{version}.dmg":
        parser.error("downloadUrl must match the configured version and domain")
    dirty = bool(git("status", "--porcelain", "--untracked-files=all"))
    revision = git("rev-parse", "HEAD")
    identity = os.environ.get("SCREENPLAYOS_SIGNING_IDENTITY", "")
    profile = os.environ.get("SCREENPLAYOS_NOTARY_PROFILE", "")
    dmg_python = os.environ.get("SCREENPLAYOS_DMG_PYTHON", sys.executable)
    if args.dry_run:
        builder_available = subprocess.run([dmg_python, "-c", "import dmgbuild"],
                                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        print(json.dumps({"version": version, "build": build, "architecture": args.arch,
                          "mode": "unsigned review" if args.unsigned else "signed public",
                          "source_clean": not dirty, "identity_configured": bool(identity),
                          "notary_profile_configured": bool(profile),
                          "dmg_builder_available": builder_available,
                          "output": str(args.output.resolve())}, indent=2))
        return
    if not args.unsigned:
        if dirty:
            parser.error("signed release requires a clean committed checkout")
        if not identity.startswith("Developer ID Application:") or not profile:
            parser.error("set SCREENPLAYOS_SIGNING_IDENTITY to a Developer ID Application identity and SCREENPLAYOS_NOTARY_PROFILE to a stored notarytool profile")
    output = args.output.resolve()
    if output.exists() and any(output.iterdir()):
        parser.error(f"output directory is not empty: {output}")
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="screenplayos-release-") as directory:
        temp = Path(directory)
        app = temp / "ScreenplayOS.app"
        env = os.environ.copy()
        env.update(SCREENPLAYOS_BUILD_CONFIGURATION="release", SCREENPLAYOS_BUILD_ARCH=args.arch,
                   SCREENPLAYOS_APP_VERSION=version, SCREENPLAYOS_BUILD_NUMBER=str(build),
                   SCREENPLAYOS_SIGNING_IDENTITY="-" if args.unsigned else identity,
                   SCREENPLAYOS_NOTARY_PROFILE="" if args.unsigned else profile,
                   SCREENPLAYOS_ALLOW_DIRTY="1" if args.unsigned else "0",
                   SCREENPLAYOS_SCRATCH_PATH=str(ROOT / ".build/direct-release"),
                   SCREENPLAYOS_SKIP_REVIEW_CLEANUP="1")
        run(ROOT / "Scripts/package-app.sh", app, cwd=ROOT, env=env)
        if not args.unsigned and (git("rev-parse", "HEAD") != revision or
                                  git("status", "--porcelain", "--untracked-files=all")):
            raise RuntimeError("source changed during signed build; release aborted")
        info = verify_app(app, version, build, args.arch)
        dmg = output / f"ScreenplayOS-{version}.dmg"
        layout_configured = make_dmg(app, dmg, temp, dmg_python)
        if not args.unsigned:
            run("codesign", "--force", "--sign", identity, "--timestamp", dmg)
            run("codesign", "--verify", dmg)
            run("xcrun", "notarytool", "submit", dmg, "--keychain-profile", profile, "--wait")
            run("xcrun", "stapler", "staple", dmg)
            run("xcrun", "stapler", "validate", dmg)
            run("spctl", "--assess", "--type", "open", "--context", "context:primary-signature", "--verbose=2", dmg)
        archive = output / f"ScreenplayOS-{version}.zip"
        run("ditto", "-c", "-k", "--keepParent", app, archive)
        notes = output / "RELEASE_NOTES.md"
        status = "Public release" if not args.unsigned else "Unpublished local review candidate"
        notes.write_text(f"# ScreenplayOS {version} ({build})\n\n{status}. Built from `{git('rev-parse', 'HEAD')}`"
                         f"{' with uncommitted changes' if dirty else ''}.\n\n"
                         "ScreenplayOS is a local macOS writing and filmmaking workspace with Outline, Script, Shot, Boards, and Edit views. "
                         "This candidate adds the permanent app identity and a direct-download release package. "
                         "Existing screenplay files stay in their current locations.\n\n"
                         "Requires macOS 13 or later. Check the manifest for included processor architectures. "
                         "Back up active work before testing a new build.\n")
        artifacts = {p.name: {"sha256": digest(p), "bytes": p.stat().st_size} for p in (dmg, archive, notes)}
        manifest = {"schemaVersion": 1, "name": "ScreenplayOS", "version": version, "build": build,
                    "bundleIdentifier": info["CFBundleIdentifier"], "minimumMacOS": info["LSMinimumSystemVersion"],
                    "architectures": ["arm64", "x86_64"] if args.arch == "universal" else [args.arch],
                    "sourceRevision": git("rev-parse", "HEAD"), "sourceDirty": dirty,
                    "developerIDSigned": not args.unsigned, "notarized": not args.unsigned,
                    "finderLayoutConfigured": layout_configured,
                    "createdAtUTC": dt.datetime.now(dt.timezone.utc).isoformat(),
                    "downloadUrl": config["downloadUrl"], "artifacts": artifacts}
        manifest_path = output / "release-manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        checksums = output / "SHA256SUMS.txt"
        checksums.write_text("".join(f"{digest(p)}  {p.name}\n" for p in (dmg, archive, notes, manifest_path)))
        if not args.unsigned and (git("rev-parse", "HEAD") != revision or
                                  git("status", "--porcelain", "--untracked-files=all")):
            raise RuntimeError("source changed during signed packaging; do not publish these artifacts")
        print(f"Release package ready: {output}")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
