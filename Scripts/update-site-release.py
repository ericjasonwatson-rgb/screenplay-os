#!/usr/bin/env python3
"""Refresh the website release line and DMG checksum from a packaged release."""

import argparse
import datetime as dt
import hashlib
import html
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def replace_one(source: str, pattern: str, replacement: str) -> str:
    updated, count = re.subn(pattern, lambda _: replacement, source, count=1, flags=re.S)
    if count != 1:
        raise ValueError(f"Expected one website marker for {pattern}")
    return updated


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release_dir", type=Path, help="Directory containing release-manifest.json and SHA256SUMS.txt")
    args = parser.parse_args()
    folder = args.release_dir.resolve()
    manifest = json.loads((folder / "release-manifest.json").read_text())
    version = str(manifest["version"])
    filename = f"ScreenplayOS-{version}.dmg"
    expected = manifest["artifacts"][filename]["sha256"]
    checksums = dict((name, digest) for digest, name in (
        line.split(maxsplit=1) for line in (folder / "SHA256SUMS.txt").read_text().splitlines()
    ))
    if checksums.get(filename) != expected:
        raise ValueError("DMG hash disagrees between manifest and SHA256SUMS.txt")
    actual = hashlib.sha256((folder / filename).read_bytes()).hexdigest()
    if actual != expected:
        raise ValueError("DMG bytes do not match the recorded SHA-256")
    if sorted(manifest["architectures"]) != ["arm64", "x86_64"]:
        raise ValueError("Website compatibility copy requires a Universal release")
    if str(manifest["minimumMacOS"]).split(".")[0] != "13":
        raise ValueError("Website minimum macOS copy requires macOS 13")
    release_month = dt.datetime.fromisoformat(manifest["createdAtUTC"].replace("Z", "+00:00")).strftime("%B %Y")
    details = f"Version {version} ({manifest['build']}) · {release_month} · Universal (Apple Silicon and Intel) · macOS 13 or later"
    site = ROOT / "Website" / "index.html"
    source = site.read_text()
    source = replace_one(source, r'<p class="release-line" id="release-details" data-site-release="details">.*?</p>',
                         f'<p class="release-line" id="release-details" data-site-release="details">{html.escape(details)}</p>')
    source = replace_one(source, r'<code id="dmg-checksum" data-site-release="checksum">.*?</code>',
                         f'<code id="dmg-checksum" data-site-release="checksum">{expected}</code>')
    source = replace_one(source, r'<code>shasum -a 256 ScreenplayOS-[^<]+</code>',
                         f'<code>shasum -a 256 {html.escape(filename)}</code>')
    site.write_text(source)
    print(f"Updated {site} from {folder.name}: {details}; DMG SHA-256 {expected}")


if __name__ == "__main__":
    main()
