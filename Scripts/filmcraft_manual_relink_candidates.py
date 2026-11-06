#!/usr/bin/env python3
"""Create non-authoritative manual relink candidates when FilmCraft drops metadata.

Never reassigns identity, edits a project, or declares a verified round trip.
Clip names are untrusted editable hints and are NOT equivalent to OTIO
provenance. Both the baseline and returned OTIO are local inputs.
"""
import argparse
import json
from pathlib import Path
import sys

import opentimelineio as otio
from compare_filmcraft_otio import snapshot, safe_relative_media_path


def manual_candidates(original, returned):
    baseline = snapshot(original)
    timeline = otio.adapters.read_from_file(str(returned))
    if not isinstance(timeline, otio.schema.Timeline):
        raise ValueError("Returned file is not an OTIO timeline")
    clips = list(timeline.find_clips())
    if len(clips) != len(baseline):
        raise ValueError("Clip count changed; no candidate relinking")
    originals = {record["ids"]["occurrence_id"]: record for record in baseline}
    if len(originals) != len(baseline):
        raise ValueError("Duplicate baseline occurrence IDs")

    returned_names = [str(clip.name or "") for clip in clips]
    # A duplicate, missing, renamed, or unknown name is ambiguous. No mapping.
    if len(set(returned_names)) != len(clips) or set(returned_names) != set(originals):
        raise ValueError("Missing, duplicate, or changed clip names; no candidate relinking")

    result = []
    for index, clip in enumerate(clips):
        name = returned_names[index]
        source = originals[name]
        if clip.source_range is None:
            raise ValueError("Returned clip has no source range")
        media_ref = clip.media_reference
        if not isinstance(media_ref, otio.schema.ExternalReference):
            raise ValueError("Returned clip has no external media reference")
        if not safe_relative_media_path(media_ref.target_url):
            raise ValueError("Unsafe returned media path")
        result.append({
            "candidate_from_untrusted_clip_name": name,
            "original_occurrence_id": source["ids"]["occurrence_id"],
            "original_take_id": source["ids"]["take_id"],
            "original_generation_job_id": source["ids"]["generation_job_id"],
            "returned_index": index,
            "original_index": source["index"],
            "returned_duration": [clip.source_range.duration.value,
                                  clip.source_range.duration.rate],
            "returned_source_start": [clip.source_range.start_time.value,
                                      clip.source_range.start_time.rate],
            "returned_relative_media": media_ref.target_url,
            "matching_evidence": "untrusted editable clip name only",
            "verified": False,
            "approved": False,
        })
    return {
        "status": "manual_identity_review_required",
        "safe_to_auto_import": False,
        "adopted": False,
        "authoritative": False,
        "candidates": result,
        "warning": "These are untrusted name-based hints. A filmmaker must verify identity against original media and edits; never reconstruct project provenance automatically.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("returned", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        report = manual_candidates(args.original, args.returned)
    except (ValueError, KeyError, TypeError, RuntimeError) as error:
        print(f"No manual candidate mapping: {error}", file=sys.stderr)
        return 1
    payload = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.report:
        args.report.write_text(payload, encoding="utf-8")
    print(payload, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
