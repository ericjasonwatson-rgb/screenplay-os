#!/usr/bin/env python3
"""Fail-closed comparison of ScreenplayOS OTIO against external NLE OTIO.

Input files are public-safe synthetic fixtures unless a user explicitly supplies
their own export. No files are modified, no provider connection is made, and no
external edit is ever imported into a ScreenplayOS document.
"""
import argparse
import json
from pathlib import Path
import sys

import opentimelineio as otio

TRACKED = (
    "occurrence_id", "scene_id", "shot_id", "board_id", "take_id",
    "generation_job_id", "media_sha256", "prompt_sha256",
)

def snapshot(path):
    timeline = otio.adapters.read_from_file(str(path))
    if not isinstance(timeline, otio.schema.Timeline):
        raise ValueError("File does not decode as an OTIO Timeline")
    clips = list(timeline.find_clips())
    if not clips:
        raise ValueError("Empty external timeline; cannot claim interoperability")
    entries = []
    for index, clip in enumerate(clips):
        namespace = clip.metadata.get("screenplayos")
        if not isinstance(namespace, dict):
            raise ValueError(f"Clip {index} has no ScreenplayOS provenance namespace")
        missing = [field for field in TRACKED if not namespace.get(field)]
        if missing:
            raise ValueError(f"Clip {index} lost required metadata: {', '.join(missing)}")
        time = clip.source_range
        if time is None:
            raise ValueError(f"Clip {index} has no source range")
        reference = clip.media_reference
        if not isinstance(reference, otio.schema.ExternalReference):
            raise ValueError(f"Clip {index} lost its ExternalReference")
        entries.append({
            "ids": {field: namespace[field] for field in TRACKED},
            "index": index,
            "source_start": [time.start_time.value, time.start_time.rate],
            "duration": [time.duration.value, time.duration.rate],
            "media": reference.target_url,
        })
    return entries

def compare(original, returned):
    if len(original) != len(returned):
        raise ValueError(f"Clip count changed: {len(original)} -> {len(returned)}")
    by_occurrence = {entry["ids"]["occurrence_id"]: entry for entry in original}
    if len(by_occurrence) != len(original):
        raise ValueError("Duplicate original occurrence identifiers")
    observed = set()
    proposed = []
    for entry in returned:
        occurrence_id = entry["ids"]["occurrence_id"]
        if occurrence_id in observed:
            raise ValueError(f"Duplicate returned occurrence: {occurrence_id}")
        observed.add(occurrence_id)
        baseline = by_occurrence.get(occurrence_id)
        if baseline is None:
            raise ValueError(f"Unmapped external occurrence: {occurrence_id}")
        if baseline["ids"] != entry["ids"]:
            changed = [k for k in TRACKED if baseline["ids"][k] != entry["ids"][k]]
            raise ValueError(f"Identity/provenance drift in {occurrence_id}: {changed}")
        for key in ("index", "source_start", "duration", "media"):
            if baseline[key] != entry[key]:
                proposed.append({
                    "occurrence_id": occurrence_id, "field": key,
                    "before": baseline[key], "after": entry[key],
                })
    if set(by_occurrence) != observed:
        raise ValueError("Returned timeline omitted original occurrences")
    return proposed

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("returned", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        original = snapshot(args.baseline)
        returned = snapshot(args.returned)
        proposals = compare(original, returned)
    except (ValueError, KeyError, TypeError, RuntimeError) as exc:
        print(f"FAIL CLOSED: {exc}", file=sys.stderr)
        return 1
    report = {
        "status": "review_required" if proposals else "identical",
        "occurrences": len(original),
        "proposed_changes": proposals,
        "adopted": False,
    }
    payload = json.dumps(report, indent=2, sort_keys=True)
    if args.report:
        args.report.write_text(payload + "\n", encoding="utf-8")
    print(payload)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
