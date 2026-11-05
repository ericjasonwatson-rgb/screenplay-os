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
from compare_filmcraft_otio import snapshot, compare, identity_loss_report
from filmcraft_manual_relink_candidates import manual_candidates

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

        # FilmCraft v0.17.1 drops the ScreenplayOS namespace. Diagnose
        # precisely, but never reconstruct identities by sequence or timing.
        metadata_stripped = copy.deepcopy(original_json)
        for exported_clip in metadata_stripped["tracks"]["children"][0]["children"]:
            exported_clip["metadata"] = {}
        check_fail(baseline, metadata_stripped, path, "no ScreenplayOS provenance")
        hints = manual_candidates(source, path)
        assert hints["status"] == "manual_identity_review_required"
        assert hints["adopted"] is False
        assert hints["safe_to_auto_import"] is False
        assert all(not candidate["verified"] and not candidate["approved"]
                   for candidate in hints["candidates"])
        loss = identity_loss_report(source, path)
        assert loss["status"] == "blocked_identity_loss"
        assert loss["adopted"] is False and loss["matching_performed"] is False
        assert loss["unique_occurrence_names_preserved"] is True
        # Names surviving does NOT reinstate missing original Take provenance.
        name_drift = copy.deepcopy(metadata_stripped)
        name_drift["tracks"]["children"][0]["children"][0]["name"] = "Renamed by editor"
        path.write_text(json.dumps(name_drift), encoding="utf-8")
        changed_names = identity_loss_report(source, path)
        assert changed_names["unique_occurrence_names_preserved"] is False
        try:
            manual_candidates(source, path)
        except ValueError as error:
            assert "changed clip names" in str(error)
        else:
            raise AssertionError("Renamed clip must not produce identity hints")
        assert changed_names["adopted"] is False and changed_names["matching_performed"] is False
        assert loss["baseline_occurrences"] == 2 and loss["returned_clips"] == 2
        assert len(loss["baseline_sha256"]) == 64
        assert all(len(item["lost_fields"]) == 8 for item in loss["returned_clip_diagnostics"])
        assert all(not item["has_screenplayos_namespace"]
                   for item in loss["returned_clip_diagnostics"])
        assert all(item["returned_name_matches_any_original_occurrence"]
                   for item in loss["returned_clip_diagnostics"])
        assert all(not item["has_filmcraft_namespace"]
                   for item in loss["returned_clip_diagnostics"])
        # A FilmCraft export creates its own metadata while losing ours.
        filmcraft_only = copy.deepcopy(metadata_stripped)
        for returned_clip in filmcraft_only["tracks"]["children"][0]["children"]:
            returned_clip["metadata"] = {"filmcraft": {"source_in_ticks": 0}}
        path.write_text(json.dumps(filmcraft_only), encoding="utf-8")
        filmcraft_loss = identity_loss_report(source, path)
        assert all(item["has_filmcraft_namespace"]
                   and not item["has_screenplayos_namespace"]
                   for item in filmcraft_loss["returned_clip_diagnostics"])
        assert filmcraft_loss["adopted"] is False

        changed = copy.deepcopy(original_json)
        changed["tracks"]["children"][0]["children"][0]["media_references"]["DEFAULT_MEDIA"]["target_url"] = "Board Images/alternate.mov"
        path.write_text(json.dumps(changed), encoding="utf-8")
        proposals = compare(baseline, snapshot(path))
        assert len(proposals) == 1 and proposals[0]["field"] == "media"
        assert proposals[0]["after"] == "Board Images/alternate.mov"

        unsafe = copy.deepcopy(original_json)
        unsafe["tracks"]["children"][0]["children"][0]["media_references"]["DEFAULT_MEDIA"]["target_url"] = "../private/generated.png"
        check_fail(baseline, unsafe, path, "unsafe/absolute media path")

        windows = copy.deepcopy(original_json)
        windows["tracks"]["children"][0]["children"][0]["media_references"]["DEFAULT_MEDIA"]["target_url"] = chr(92) + "private" + chr(92) + "generated.png"
        check_fail(baseline, windows, path, "unsafe/absolute media path")

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
