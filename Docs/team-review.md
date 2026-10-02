# ScreenplayOS team review

Review baseline: application commit `95b7d5c` (2026-10-02). Documentation-only commits may follow this baseline.

## Run the review app

Download the zipped ScreenplayOS app from this private repository's Releases page when a release is available. Extract it and open ScreenplayOS.app. The supplied build is for Apple silicon Macs; it is a development build, not a signed/notarized public distribution. It has not been validated on every supported macOS version. If macOS blocks it, report the exact message; developers can build from source instead.

Use a duplicate screenplay for review. Legacy imports and new drafts can automatically save into Downloads; editing a previously saved document updates that file. Keep your originals separate. Do not replace production work with this prototype.

## Build and test

Clone this repository on a Mac with an Apple Swift toolchain that includes Swift Testing. The review baseline was verified using Apple Swift 6.3 on an Apple silicon Mac. The package declares macOS 13 as its minimum; that declaration is not a test result for every OS version.

From the repository root:

```sh
./Scripts/test.sh
./Scripts/package-app.sh
open ../ScreenplayOS.app
```

For optimized test coverage:

```sh
SCREENPLAYOS_BUILD_CONFIGURATION=release ./Scripts/test.sh
```

The test script keeps compiler caches in `.build`, handles Command Line Tools Swift Testing search paths, and runs the Python inspector checks and Swift self-tests. Python 3 is required for those checks and app packaging. The baseline passed 198 Swift tests, 37 Python checks, and 14 self-tests in each of Debug and Release.

The owner has approved including the Defenders of Cat Island pilot fixture in this private repository for team review. Its presence is not permission to redistribute the screenplay outside the team. No new open-source license is granted by this review setup.

## Review priorities

1. Writing responsiveness: type, select, delete, paste, and undo in short and feature-length scripts. Include page count and Mac model in your report.
2. Formatting and pagination: character cues, scene headings, parentheticals, emphasis, page zoom, white/dark paper, print preview, and title page separation.
3. Imports: FDX, text, DOCX, and selectable-text PDF. Compare against the original and identify concrete losses or ordering errors.
4. Save/reopen: preserve a separate original, edit the duplicate, save, close, reopen, and compare text and formatting.
5. Connected views: preserve scene context through Outline, Script, Shot, Boards, and Edit. In Edit, test the Estimates toggle and distinguish estimates from board timing.

## Known limitations

- Long-script responsiveness remains the top priority. The 132-page benchmark improved from about 608 ms to 259 ms per synchronous insert/layout/display cycle; that is not physical key-to-screen latency or a claim that lag is solved.
- Scene estimates are rough, optional prose-based ranges. Board timing is separate. Real-media conform and manual measured-scene overrides are not complete.
- PDF import requires selectable text and review of reading order. DOCX import is text extraction; rich layout, images, and comments are not preserved.
- Reviewed FDX dual dialogue is sequential rather than side-by-side.
- Native-package and legacy-document editors do not have complete parity. Mobile, cloud collaboration, and production-media editing remain future work.

See [the audit](full-audit-2026-10-02.md) and [estimate assumptions](edit-scene-duration-estimates.md) for evidence and boundaries.

## Report findings

Create a GitHub Issue with the build revision, macOS version, Mac/chip, document format/page count, steps to reproduce, expected result, and actual result. Include a screenshot when helpful, but avoid attaching another writer's private screenplay without permission. Separate reproducible bugs from design suggestions. Use a branch and pull request for proposed code changes.
