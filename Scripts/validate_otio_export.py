#!/usr/bin/env python3
"""Validate ScreenplayOS's synthetic OTIO export with the official library.

No user screenplay, actual media, provider access, or application mutation.
A passing gate verifies OTIO JSON parser compatibility and namespaced metadata
for this fixture, not compatibility with FilmCraft or another editor.
"""
import json
import sys
from pathlib import Path

import opentimelineio as otio

source = Path(sys.argv[1])
if not source.is_file():
    raise SystemExit(f"Missing synthetic ScreenplayOS OTIO export: {source}")
data = json.loads(source.read_text(encoding="utf-8"))
if data.get("OTIO_SCHEMA") != "Timeline.1":
    raise AssertionError("Expected a native OTIO Timeline.1 document")

timeline = otio.adapters.read_from_file(str(source))
if not isinstance(timeline, otio.schema.Timeline):
    raise AssertionError("Official OTIO parser did not return a Timeline")

clips = list(timeline.find_clips())
if len(clips) != 2:
    raise AssertionError(f"Expected two clip occurrences, got {len(clips)}")

metadata = [clip.metadata["screenplayos"] for clip in clips]
occurrences = {entry["occurrence_id"] for entry in metadata}
if len(occurrences) != 2:
    raise AssertionError("Two occurrences must retain independent IDs")
for key in ("shot_id", "board_id", "take_id", "generation_job_id", "media_sha256", "prompt_sha256"):
    values = {entry[key] for entry in metadata}
    if len(values) != 1 or None in values:
        raise AssertionError(f"Shared Take metadata changed: {key}")
if [round(clip.source_range.duration.value) for clip in clips] != [48, 48]:
    raise AssertionError("OTIO source durations did not survive parsing")
for clip in clips:
    if clip.source_range.duration.rate != 24:
        raise AssertionError("Frame rate changed during parsing")
    if not isinstance(clip.media_reference, otio.schema.ExternalReference):
        raise AssertionError("Missing expected external media reference")
    if clip.media_reference.target_url != "Board Images/generated.png":
        raise AssertionError("External media path changed during parsing")
if any("/tmp/candidate.png" in repr(clip) for clip in clips):
    raise AssertionError("Private absolute source path escaped")

# The OTIO-native adapter should retain the same canonical identities on a
# native encode/decode cycle. This does not represent an NLE import/export.
roundtrip = otio.adapters.read_from_string(
    otio.adapters.write_to_string(timeline, adapter_name="otio_json"),
    adapter_name="otio_json",
)
roundtrip_metadata = [clip.metadata["screenplayos"] for clip in roundtrip.find_clips()]
if roundtrip_metadata != metadata:
    raise AssertionError("Namespaced metadata changed in native OTIO roundtrip")
print("Official OpenTimelineIO validated two distinct edit occurrences and one shared generated Take.")
