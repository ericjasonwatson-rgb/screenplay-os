#!/usr/bin/env python3
"""Fail-closed comparison of ScreenplayOS OTIO against external NLE OTIO.

Input files are public-safe synthetic fixtures unless a user explicitly supplies
their own export. No files are modified, no provider connection is made, and no
external edit is ever imported into a ScreenplayOS document.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import opentimelineio as otio

TRACKED = (
    "occurrence_id", "scene_id", "shot_id", "board_id", "take_id",
    "generation_job_id", "media_sha256", "prompt_sha256",
)

def safe_relative_media_path(value):
    if not isinstance(value, str) or not value or value.startswith("/"):
        return False
    # All Windows paths and separators are rejected, including a single
    # leading backslash. Use the ASCII code to avoid escaping ambiguity.
    if chr(92) in value or "://" in value or ":" in value:
        return False
    if any(ord(character) < 32 or ord(character) == 127 for character in value):
        return False
    return all(part not in ("", ".", "..") for part in value.split("/"))

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
        if namespace is None or not hasattr(namespace, "get"):
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
        if not safe_relative_media_path(reference.target_url):
            raise ValueError(f"Clip {index} returned unsafe/absolute media path")
        entries.append({
            "ids": {field: namespace[field] for field in TRACKED},
            "index": index,
            "source_start": [time.start_time.value, time.start_time.rate],
            "duration": [time.duration.value, time.duration.rate],
            "media": reference.target_url,
            "note": namespace.get("note", ""),
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
        for key in ("index", "source_start", "duration", "media", "note"):
            if baseline[key] != entry[key]:
                proposed.append({
                    "occurrence_id": occurrence_id, "field": key,
                    "before": baseline[key], "after": entry[key],
                })
    if set(by_occurrence) != observed:
        raise ValueError("Returned timeline omitted original occurrences")
    return proposed

def identity_loss_report(original_path, returned_path):
    """Summarize lost identities without aligning clips by index or media name.

    Positional matching is unsafe when an editor can split, trim, reorder or
    duplicate clips. This is diagnostic evidence only, never an import plan.
    """
    baseline = snapshot(original_path)
    returned = otio.adapters.read_from_file(str(returned_path))
    if not isinstance(returned, otio.schema.Timeline):
        raise ValueError("External output is not an OTIO Timeline")
    clips = list(returned.find_clips())
    losses = []
    for index, clip in enumerate(clips):
        namespace = clip.metadata.get("screenplayos")
        fields = namespace if namespace is not None and hasattr(namespace, "get") else {}
        missing = [key for key in TRACKED if not fields.get(key)]
        reference = clip.media_reference
        safe_path = (
            isinstance(reference, otio.schema.ExternalReference) and
            safe_relative_media_path(reference.target_url)
        )
        losses.append({
            "returned_clip_index": index,
            "lost_fields": missing,
            "media_reference_safe": safe_path,
            "has_screenplayos_namespace": bool(fields),
        })
    return {
        "status": "blocked_identity_loss",
        "adopted": False,
        "matching_performed": False,
        "baseline_occurrences": len(baseline),
        "returned_clips": len(clips),
        "baseline_sha256": hashlib.sha256(original_path.read_bytes()).hexdigest(),
        "returned_sha256": hashlib.sha256(returned_path.read_bytes()).hexdigest(),
        "returned_clip_diagnostics": losses,
        "reason": "External editorial output cannot be trusted without original occurrence and Take provenance.",
    }


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
