# Scene duration in the Edit spine

Use **Edit → Estimates** in the spine header to show or hide script-derived timing ranges. This is a persistent application display preference, initially on for new preferences; existing on/off choices are retained. It does not change clip durations, playback, screenplay text, or the document format.

With Estimates enabled, a new scene-planning lane places scenes left to right in editorial order. Timed widths use the midpoint of each script range at a common scale; confirmed current-media-cut durations take precedence scene by scene. Approximate cumulative midpoint start times and an estimated total range are displayed. Scene selection follows across the lane, readable detail cards and script context. The ordinary clip playback lane remains separate.

Heading-only scenes have an explicitly untimed block of fixed visual width, not an invented duration. Subsequent start times are unknown. When any scene is untimed, the aggregate is labelled a timed subtotal rather than a complete-film runtime. Range totals are planning sums, not statistical confidence intervals.

The range is recalculated from each scene's current action and dialogue, keyed by the scene's stable spine ID. Editorial rearrangement does not change which script scene supplies the estimate. Heading-only or empty scenes show “Est. unavailable.” Character cues, headings, transitions, and parentheticals do not add spoken words.

These are deliberately rough planning assumptions, not measured timing or statistical confidence intervals:

- Dialogue: 120–180 words per minute.
- Action prose: 60–120 words per minute.
- Display bounds round outward to five seconds, with a minimum displayed range of 5–10 seconds.

Action description is a particularly weak predictor: “They fight” could cover seconds or minutes. Pauses, performance, montage and staging can fall outside the range. The assumptions are available from the toggle and estimate help text.

Board and placeholder timings remain separately labelled. Changing a board's duration updates its existing edit timing; it does not calibrate the prose heuristic. The display resolver gives assembled/locked/replaced media clips precedence over the estimate and describes their current cut, not scene completeness. Mixed or planned clips do not masquerade as measured scene runtime. Omitted clips remain included in the existing timeline's duration and are explicitly flagged in the card label.

Current limitation: the editor still derives its persisted edit guide from shots and boards. A complete production-media ingest/conform workflow and manual measured-scene overrides are not implemented here. The resolver's media precedence is tested preparation for that workflow, not a claim that real-media conform already works. Estimate settings/ranges are never saved into the screenplay as actual timing.
