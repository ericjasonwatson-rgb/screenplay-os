#!/usr/bin/env python3
"""Reject a Swift Testing process that exits before reporting its full result."""
from pathlib import Path
import re
import sys


def verify(text: str) -> int:
    # XCTest's separate "Executed 0 tests" summary is not Swift Testing proof.
    # Native dialogs can end a test process with status zero before Swift Testing
    # reports failure, so the shell exit code alone is insufficient.
    text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", text)
    summaries = re.findall(r"^✔ Test run with ([0-9]+) tests? passed after [0-9.]+ seconds?\.$",
                           text, flags=re.MULTILINE)
    if len(summaries) != 1 or int(summaries[0]) < 1:
        raise ValueError("Native test run has no unique, nonempty Swift Testing success summary; it may have exited early.")
    if "✘" in text or "recorded an issue" in text:
        raise ValueError("Native test output contains a reported failure despite its exit status or summary.")
    return int(summaries[0])


def main(argv=None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1:
        print("usage: check-native-test-completion.py OUTPUT", file=sys.stderr)
        return 2
    try:
        count = verify(Path(args[0]).read_text(encoding="utf-8"))
    except (OSError, UnicodeError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 1
    print(f"Verified complete Swift Testing result: {count} tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
