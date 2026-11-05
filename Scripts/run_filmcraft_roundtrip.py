#!/usr/bin/env python3
"""Run a pinned, local FilmCraft CLI import/export in one isolated headless session.

The caller supplies the executable path. This script does not download binaries,
install software, open a GUI or alter the original ScreenplayOS source files.
It fails when FilmCraft omits identity/provenance, instead of silently adopting.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from compare_filmcraft_otio import snapshot, compare

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--filmcraft-cli", type=Path, required=True)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    executable = args.filmcraft_cli.resolve(strict=True)
    source = args.input.resolve(strict=True)
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise SystemExit("FilmCraft CLI executable is not runnable")
    baseline = snapshot(source)  # Verify the original before invoking external code.
    with tempfile.TemporaryDirectory(prefix="screenplayos-filmcraft-test-") as work:
        root = Path(work)
        export = root / "filmcraft-return.otio"
        sequence = [
            {"id": "file.import", "params": {"paths": [str(source)], "replace": True}},
            {"id": "file.exportOtio", "params": {"path": str(export)}},
        ]
        commands = root / "commands.jsonl"
        commands.write_text(
            "".join(json.dumps(item) + "\n" for item in sequence),
            encoding="utf-8",
        )
        result = subprocess.run(
            [str(executable), "--data-dir", str(root / "filmcraft-data"),
             "run", str(commands)],
            cwd=root, text=True, capture_output=True, timeout=180,
            check=False, env={**os.environ, "HOME": str(root)},
        )
        # Do not log untrusted provider project data or media from stdout.
        if result.returncode != 0 or not export.is_file():
            print(f"FilmCraft import/export did not complete (exit {result.returncode}); "
                  "no project was changed.", file=sys.stderr)
            return 1
        try:
            proposed = compare(baseline, snapshot(export))
        except (ValueError, KeyError, TypeError) as exc:
            print(f"FilmCraft interoperability gate failed closed: {exc}", file=sys.stderr)
            return 1
        report = {
            "status": "review_required" if proposed else "identical",
            "provider": "FilmCraft CLI", "original_occurences": len(baseline),
            "proposed_changes": proposed, "adopted": False,
        }
        payload = json.dumps(report, sort_keys=True, indent=2)
        if args.report:
            args.report.write_text(payload + "\n", encoding="utf-8")
        print(payload)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
