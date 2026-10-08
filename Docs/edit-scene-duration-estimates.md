# Scene duration in the Edit timeline

Use **Edit → Estimates** in the existing spine header. There is one timing lane; the separate scene-planning box has been removed.

With Estimates on, a scene without timed boards/media occupies its script estimate's midpoint duration directly in the existing timeline. Widths, cumulative start positions, the playback slider, scene selection and total duration use the same derived timing. Estimated blocks and the playback total are labelled “Est.” The midpoint is a planning choice, not measured runtime.

Existing board/media clips retain their timing. A scene containing only shot placeholders uses its whole-scene estimate when one is available. Turning Estimates off returns to eligible board/media timing (shot placeholders contribute no duration) and resets/pauses the playhead. The preference is initially on for new preferences and preserves prior user choices. It lives outside the document.

Script edits, Undo/Redo, reopening and editorial reordering invalidate the derived timeline. Untimed scenes remain in the scene strip, are counted beside the playback total, and contribute no invented duration; time coordinates then describe only timed content. Estimates never become persisted clips or appear as authored clip timing in exports. Screenplay text, existing clip durations and stored editorial order are not changed merely by displaying or playing estimates.

The script range uses dialogue at 120–180 words/minute and action at 45–75 seconds per planning page (60 columns, 54 lines including one spacing line per nonempty paragraph), rounded outward to five seconds, with a minimum 5–10-second range. Headings, character cues, transitions and parentheticals add no spoken words. Empty/heading-only scenes have no estimate. Action prose is a weak timing predictor: staging, pauses, montage and performance can fall outside the range.

The full production-media import/conform workflow and manual measured-scene overrides remain unimplemented. Boardomatic and current clip playback continue to work independently of whether estimated scenes are present. Current persisted/exported edit guides remain clip-based.

October 8 timing correction: omitted clips, placeholder clips, and media without an
assembled/locked/replaced status are excluded from the derived playback lane,
its EDL/FCPXML guides, clip-only CSV, and timing summary. Stored source clips are
not deleted or rewritten. If a scene already has board/media records but all are
excluded, no script estimate silently fills their place. Untimed scenes remain
visible. CSV includes only eligible clips; when estimates precede them, their
start positions match the displayed timeline, leaving those estimated spans out
of the clip-only rows.

The action planning page is an explicit fixed heuristic, not the current printed
page count. Zoom, font changes and pending line-pitch decisions do not alter it.
See `phase-a-timing-calibration.md` for assumptions and validation limits.
