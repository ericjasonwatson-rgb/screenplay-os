#!/usr/bin/env python3
"""Reject known private-source markers in current tracked source/test material.

This is a narrow regression guard, not a confidentiality classifier. It does not
read history, tags, historical documentation, binary image contents or remote data.
New fixtures still require review and must be independently authored synthetic data.
"""
from __future__ import annotations

from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {".swift", ".json", ".fdx", ".xml", ".fountain", ".txt", ".md", ".py"}
# Distinctive source identifiers only. Generic VFX terms such as "beam" are not
# prohibited; the names below are a denylist, not screenplay content.
RESTRICTED = re.compile(
    r"cat[\W_]*island|stargazer|mewseum|savannah[\W_]*rubies", re.IGNORECASE
)


def violation(path: str, data: bytes | None) -> str | None:
    if RESTRICTED.search(path):
        return "restricted fixture/source filename"
    if data is not None and Path(path).suffix.lower() in TEXT_SUFFIXES:
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            return "source/test text is not UTF-8; review required"
        if RESTRICTED.search(text):
            return "known private-source marker in current text"
    return None


def main() -> int:
    listed = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z", "--", "Sources", "Tests"],
                            check=True, capture_output=True).stdout
    paths = [name.decode("utf-8") for name in listed.split(b"\0") if name]
    failures = []
    for name in paths:
        path = ROOT / name
        if path.is_symlink():
            failures.append((name, "symbolic source/test path requires review"))
            continue
        # A staged deletion or absent checkout path is not reintroduced content.
        if not path.exists():
            continue
        data = path.read_bytes() if path.suffix.lower() in TEXT_SUFFIXES else None
        issue = violation(name, data)
        if issue:
            failures.append((name, issue))
    if failures:
        # Never print the matched source text or a copied excerpt.
        for name, issue in failures:
            print(f"Fixture hygiene failed: {name}: {issue}", file=sys.stderr)
        return 1
    print(f"Current tracked fixture/source hygiene passed ({len(paths)} paths). History and documentation were not scanned.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
