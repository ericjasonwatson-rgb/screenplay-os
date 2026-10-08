# Build 26 handoff validation — 2026-10-07

The notarized build 26 and installed app were not replaced. Validation uses a separate
ad-hoc audit app with its own bundle identifier and disposable files under
`/private/tmp/screenplay-handoff-audit`. No AI requests or release publication occurred.

## Repairs to the handoff

- Combined duplicate `WritingTextView.viewDidMoveToWindow` overrides; the original
  handoff did not compile.
- Live title-page testing found Cmd+1–7 changed the selected screenplay element
  while editing the author field. Menu commands now validate the native responder
  at invocation and are disabled during title-page/AI sheets. The key monitor also
  rejects an attached sheet. Added a regression for fields and sheet ownership.

## Automated checks

Initial compile repair: Debug and Release each passed 247 Swift tests, 37 Python
checks, and 14 executable self-checks (298 total per configuration).
After the focus repair: Debug and Release each passed 248 Swift tests, 37 Python
checks, and 14 self-checks (299 total per configuration).
The test runner cannot present native sheets in its restricted window-server
context. The regression supplies an attached-sheet window state and uses actual
AppKit first responders; actual sheet behavior was separately exercised in the UI.
Historical notarization scripts pass `bash -n` and are preserved byte-for-byte in
`Scripts/release-history/build26`; they were not executed.

## Live observations

- Created a new untitled document before tests; quit the installed app and launched
  the isolated audit app. All editing used disposable copies.
- After typing in scene 1, Outline → Open in Script selected scene 19, page 15.
  Text typed there was verified in that scene's heading in the saved JSON.
- After the focus repair, Delete, Cmd+Delete, Cmd+1–7 and Tab in the title-page
  author field, search field, and board notes did not change screenplay elements.
  Compared the saved element arrays, not just visible text. Cmd+3 still selected
  Character in the actual script editor. Script Tab's effect was not conclusively
  observed and needs another explicit check.
- Unknown-field JSON displayed an opened-as-copy warning. Its original bytes stayed
  identical after saving and editing a separate copy.
- Save As copied the board image to the new project's Board Images directory;
  SHA-256 matched. Deleted only the disposable old folder, reopened the new project,
  and visually observed the synthetic blue board still rendering.
- Opened a disposable package in Finder. Finder did not immediately write .DS_Store;
  injected a metadata sentinel with that name. Edited/saved in the app successfully.
- The same FDX fixture showed 18 pages in ScreenplayOS and 15 in Final Draft 13.4.0.

## Pagination decision

Do not change line pitch silently. Investigate a versioned screenplay layout profile
against Final Draft's font metrics, paragraph spacing, margins, and continuations.
A change may move scene starts and overflow boundaries. Existing production-locked
projects must retain their original layout profile/locks; adopting new spacing must
be an explicit copy/reflow operation with a comparison, not an automatic migration.
No line-pitch change was made here.

## Source publishing

On October 7, GitHub authentication succeeded. Pushed main through `2ee74fd` and
`v0.1.3-build26-source` atomically, then verified both remote hashes matched local.
No release was published.

## Follow-up persistence fixes

- Restoring a package creates an independent recovery ID. Saving the restored
  window removes only its own checkpoint. The original checkpoint remains intact;
  it can reappear after the restored window closes. This deliberately favors
  preserving recoverable work over automatically deleting an older checkpoint.
- Recovery lists exclude checkpoints owned by any open package window, including
  the checkpoint used to restore that window. Stale open-recovery actions are
  rejected while the checkpoint is owned.
- If publication succeeds but final verification fails, an exact readback allows
  a separate retry baseline. The editor remains dirty and retains recovery until
  a successful save. External changes before or after readback still stop retries.
  Font-only edits follow the same rule.
- Unstyled span edits now validate prefix, suffix, and nonoverlap before mutation,
  matching the existing styled-text boundary checks.

These changes have regression coverage; they have not yet had a separate live UI
pass or been installed over the user's app. The remaining handoff backlog is not
complete. The source upload was subsequently completed as recorded above.

Follow-up automated validation: Debug and Release each pass 253 Swift tests,
37 Python tests, and 14 executable self-tests (304 per configuration). Logs:
`/tmp/screenplay-persistence-debug.log` and `/tmp/screenplay-persistence-release.log`.

## Remaining original live check — 2026-10-08

In the isolated audit app (the earlier focus-fix build, not a fresh installation
of the persistence changes), created a new untitled document. Pressing Tab changed
the visible element type from Scene Heading to Action; Cmd+Z restored Scene Heading.
The app autosaved its new disposable document to Downloads as
`Untitled_Screenplay 23.open-screenplay.json`; it was not an original screenplay.
Quit the audit app afterward. No original source or installed app was modified.
