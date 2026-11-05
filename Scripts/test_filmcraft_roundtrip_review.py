#!/usr/bin/env python3
"""Adversarial tests for the FilmCraft editorial review comparator.

The input is the public-safe synthetic OTIO created by the ScreenplayOS Swift
export fixture. All mutations happen only in a temporary directory.
"""
import copy
import json
from pathlib import Path
import sys
import tempfile
import opentimelineio as otio
from compare_filmcraft_otio import snapshot, compare

def check_fail(baseline, data, path, expected):
    path.write_text(json.dumps(data), encoding="utf-8")
    try:
        compare(baseline, snapshot(path))
    except ValueError as exc:
        if expected not in str(exc):
            raise AssertionError(f"Unexpected refusal: {exc}") from exc
    else:
        raise AssertionError(f"Unsafe external change was accepted: {expected}")

def main():
    source = Path(sys.argv[1])
    original_json = json.loads(source.read_text(encoding="utf-8"))
    baseline = snapshot(source)
    assert len(baseline) == 2
    with tempfile.TemporaryDirectory(prefix="screenplayos-otio-adversarial-") as temp:
        path = Path(temp) / "returned.otio"
        assert compare(baseline, snapshot(source)) == []
        forged = copy.deepcopy(original_json)
        clips = forged["tracks"]["children"][0]["children"]
        clips[0]["metadata"]["screenplayos"]["take_id"] = "00000000-0000-0000-0000-000000000000"
        check_fail(baseline, forged, path, "Identity/provenance drift")

        removed = copy.deepcopy(original_json)
        removed["tracks"]["children"][0]["children"].pop()
        check_fail(baseline, removed, path, "Clip count changed")

        lost = copy.deepcopy(original_json)
        del lost["tracks"]["children"][0]["children"][0]["metadata"]["screenplayos"]["prompt_sha256"]
        check_fail(baseline, lost, path, "lost required metadata")

        changed = copy.deepcopy(original_json)
        changed["tracks"]["children"][0]["children"][0]["media_references"]["DEFAULT_MEDIA"]["target_url"] = "Board Images/alternate.mov"
        path.write_text(json.dumps(changed), encoding="utf-8")
        proposals = compare(baseline, snapshot(path))
        assert len(proposals) == 1 and proposals[0]["field"] == "media"
        assert proposals[0]["after"] == "Board Images/alternate.mov"

        changed_note = copy.deepcopy(original_json)
        changed_note["tracks"]["children"][0]["children"][0]["metadata"]["screenplayos"]["note"] = "Outside editor note"
        path.write_text(json.dumps(changed_note), encoding="utf-8")
        proposed = compare(baseline, snapshot(path))
        assert len(proposed) == 1 and proposed[0]["field"] == "note"
        assert proposed[0]["after"] == "Outside editor note"

        # The standalone wrapper prints 'adopted: false' for any reviewable
        # external change; never silently mutate the project.
        import subprocess
        result = subprocess.run(
            [sys.executable, str(Path(__file__).with_name("compare_filmcraft_otio.py")),
             str(source), str(path)], check=True, capture_output=True, text=True,
        )
        report = json.loads(result.stdout)
        assert report["status"] == "review_required"
        assert report["adopted"] is False
    print("External OTIO changes fail closed or remain explicit, non-adopted proposals.")

if __name__ == "__main__":
    main()
