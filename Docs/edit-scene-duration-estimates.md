# Scene duration in the Edit spine

Use **Edit → Estimates** in the spine header to show or hide script-derived timing ranges. This is a persistent application display preference, initially off. It does not change clip durations, playback, screenplay text, or the document format.

The range is recalculated from each scene's current action and dialogue, keyed by the scene's stable spine ID. Editorial rearrangement does not change which script scene supplies the estimate. Heading-only or empty scenes show “Est. unavailable.” Character cues, headings, transitions, and parentheticals do not add spoken words.

These are deliberately rough planning assumptions, not measured timing or statistical confidence intervals:

- Dialogue: 120–180 words per minute.
- Action prose: 60–120 words per minute.
- Display bounds round outward to five seconds, with a minimum displayed range of 5–10 seconds.

Action description is a particularly weak predictor: “They fight” could cover seconds or minutes. Pauses, performance, montage and staging can fall outside the range. The assumptions are available from the toggle and estimate help text.

Board and placeholder timings remain separately labelled. Changing a board's duration updates its existing edit timing; it does not calibrate the prose heuristic. The display resolver gives assembled/locked/replaced media clips precedence over the estimate and describes their current cut, not scene completeness. Mixed or planned clips do not masquerade as measured scene runtime. Omitted clips remain included in the existing timeline's duration and are explicitly flagged in the card label.

Current limitation: the editor still derives its persisted edit guide from shots and boards. A complete production-media ingest/conform workflow and manual measured-scene overrides are not implemented here. The resolver's media precedence is tested preparation for that workflow, not a claim that real-media conform already works. Estimate settings/ranges are never saved into the screenplay as actual timing.
