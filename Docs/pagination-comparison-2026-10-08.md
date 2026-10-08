# Final Draft pagination comparison — 2026-10-08

## Observed page counts

| Sample | ScreenplayOS | Final Draft 13 | Difference |
| --- | ---: | ---: | ---: |
| Defenders export (previous recorded baseline) | 18 | 15 | +20% |
| Synthetic action-heavy | 24 | 18 | +33% |
| Synthetic dialogue-heavy | 30 | 20 | +50% |

The two synthetic comparisons were read from the live apps. ScreenplayOS used the Release timing-audit build from source 53fa30a. The Defenders result is the earlier evidence in phase-a-fdx-export.md, not a newly repeated comparison. These are diagnostic samples, not a claim of universal pagination accuracy.

## Reproduction and integrity

The fixtures in AuditEvidence/pagination-2026-10-08 contain twelve scenes each. Action-heavy has eight long action paragraphs per scene (120 total elements). Dialogue-heavy has eight alternating speakers per scene, including parentheticals (252 total elements). Neither input had title pages, explicit page breaks, production locks, or custom layout settings. ScreenplayOS opened JSON imported by screenplay-inspect; Final Draft opened the corresponding FDX. The committed FDX files were saved by Final Draft to expose its default formatting. Every paragraph type and exact text was compared against the imported ScreenplayOS JSON after that save: both comparisons passed.

Final Draft settings: US Letter, 72-point top/bottom margins, Courier Final Draft 12, normal document leading, regular font leading. Action and scene-heading indents are 1.5–7.5 inches; dialogue is 2.5–6 inches. Space before is 24 points for headings, 12 for action/character, and zero for dialogue/parentheticals.

ScreenplayOS ScreenplayBodyLayout uses corresponding action/dialogue widths and paragraph spacing, but also sets lineSpacing to 2 points. PackageTypography resolves the document font through NSFont, with Courier fallback. Font metrics, line pitch, sentence splitting, and continuation handling require separate measurement; the extra spacing alone has not been established as the cause of the entire difference.

## Proposed next implementation

1. Measure baseline-to-baseline line pitch, wrapping, and usable page height using the same available font in both apps. Check action and dialogue separately, including split paragraphs and continuation lines.
2. Prototype explicit line pitch in a separate compatibility layout profile. Compare all three samples and screen/PDF output before selecting defaults. Do not apply a global percentage shrink to force these totals.
3. Preserve existing document layout and production locks. Require an explicit layout conversion with a page-change preview before applying a new profile to existing documents.
4. Add regression coverage for page boundaries, orphan headings, dialogue continuation, and renderer agreement once expected behavior has been measured.

No spacing, font defaults, or production-lock behavior changed in this audit.
