# Build 24 audit — 2026-10-05

Scope: current macOS app, with emphasis on recent compact Script UI, dialog observation, board generation, and portable image copies. This is a bounded code review plus automated and live checks, not proof that every possible workflow is defect-free.

## Fixed

- Relative board-image URLs now encode filenames safely. Characters such as `#`, `?`, spaces, and `%` round-trip without becoming URL fragments or queries.
- Managed image storage rejects a symlink at the final immutable PNG path, as well as a symlinked media directory.
- Portable export copies and validates images off the interface thread. It captures the selected project state before export, prevents a second concurrent export, and shows progress and the result in every workflow mode. Previously results appeared only in Script mode and large exports blocked UI work.

## Validation

- Full suite: 236 Swift tests, 37 Python inspector tests, and 14 self-tests passed (287 total).
- Storage regression coverage: relocation after deleting the original image, unchanged IDs and selected version, missing-image rejection without publishing a partial folder, existing-destination refusal, unsafe-path rejection, special-character filenames, and symlink rejection.
- Observation checks cover provider/title dialog presentation and dismissal plus portable-export progress and message changes.
- Live installed-build checks: Outline, Script, Shot, Boards, and Edit respond; scene estimates appear in Edit; Scene Script panel toggles both ways; page navigation reaches page 2 and returns to page 1. Earlier dialog checks in this session verified provider, board, title-page, and print-preview dismissal.
- Release typing measurements used disposable copies. The 18-page/352-element fixture and synthetic 106-page/2,112-element fixture ran 20 middle-of-script insertions with navigator and context panels visible. Text projection consistency passed throughout.

## Remaining limitations

- Long-script responsiveness needs more work: the 106-page run measured roughly 81–94 ms per warm insertion and 228 ms for its first insertion. This includes native insertion, layout, deferred observations, and display, not merely model mutation. Timing depends on hardware and UI state; no performance-parity claim is made.
- Live paid image generation remains unverified; the last provider response reported no API credits. No chargeable request or creative-content upload was made during this audit.
- Portable export includes current project data and every current board-image version. It does not gather other external media or named snapshot history. Share the entire exported folder. Save As alone is not a media-gather operation.
- Legacy JSON is not the draft `.screenplay` package. Unknown-field preservation and complete project-format migration are separate work.
- Build is locally ad-hoc signed. This audit does not verify Developer ID signing, notarization, or another Mac's launch behavior.

Build 24 installation and visual verification of its new export progress banner are pending app closure. Full-suite results cover the source used to package this build.
