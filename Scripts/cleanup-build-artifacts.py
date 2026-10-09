#!/usr/bin/env python3
"""Remove superseded review archives after a verified local app build."""
import argparse
import pathlib
import plistlib
import re
import subprocess

PATTERN = re.compile(r"ScreenplayOS-[0-9.]+-build-([0-9]+)-(local-review\.zip|review-checklist\.md)")


def candidates(directory, current_build):
    entries = []
    for path in directory.iterdir():
        match = PATTERN.fullmatch(path.name)
        if match and path.is_file() and not path.is_symlink():
            entries.append((path, int(match[1]), match[2]))
    archives = [build for _, build, kind in entries
                if kind == "local-review.zip" and build <= current_build]
    # Keep the newest review archive even if the new build has no ZIP yet.
    if not archives:
        return []
    cutoff = min(current_build, max(archives))
    return sorted(path for path, build, _ in entries if build < cutoff)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path)
    parser.add_argument("--apply", action="store_true", help="Delete; otherwise list only")
    args = parser.parse_args()
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(args.app)], check=True)
    with (args.app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != "com.screenplayos.app":
        parser.error("Not a ScreenplayOS app")
    build = int(info["CFBundleVersion"])
    directory = pathlib.Path(__file__).resolve().parents[2]
    for path in candidates(directory, build):
        print(f"{'Removing' if args.apply else 'Would remove'} {path.name}")
        if args.apply:
            path.unlink()


if __name__ == "__main__":
    main()
