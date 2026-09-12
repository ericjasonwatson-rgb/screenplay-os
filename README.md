# ScreenplayOS Starter

This repository is the first open-core starter for ScreenplayOS: an open native screenplay document model with Final Draft FDX treated as a compatibility adapter, not the internal standard.

## What is included

- `Specs/open-screenplay-1.0.schema.json`: draft JSON Schema for Open Screenplay 1.0.
- `Sources/ScreenplayDomain`: Swift domain model for projects, screenplays, elements, shots, and script-linked shot references.
- `Sources/ScreenplayFDX`: minimal FDX importer that maps Final Draft paragraphs into native screenplay elements.
- `Sources/ScreenplayOSApp`: first macOS app shell with an editable screenplay surface.
- `Sources/screenplay-inspect`: CLI tool for inspecting FDX files and emitting native Open Screenplay JSON.
- `Tests/Fixtures/Defenders_of_Cat_Island_Pilot_Final_Draft.fdx`: canonical compatibility fixture from the uploaded pilot.
- Regression tests for domain encoding and FDX import.

## Product architecture direction

- See `Docs/product-architecture.md` for the current integrated product architecture.
- See `Docs/ui-ux-design-constitution.md` for the professional UI/UX design constitution.
- See `Docs/platform-architecture.md` for the local-first, multi-platform product architecture.
- ScreenplayOS follows a three-region workspace model: Navigation, Workspace, and Context.
- ScreenplayOS is organized around one film represented through five primary views: Outline, Script, Shot, Boards, and Edit.
- The canonical project model is separate from platform UI so macOS, iPadOS, iOS, and Web can become different interfaces onto the same film.
- Snapshots provide named local versions beside the project file, with restore creating a safety checkpoint first.
- Script Notes attach comments to real screenplay elements and scenes, so notes travel with the project across Outline, Script, Shot, Boards, and Edit.
- Script focus can collapse the experience toward the screenplay itself.
- The app keeps a shared selection context so the right-side inspector can respond to scenes, screenplay elements, outline beats, shots, board frames, production records, and editorial beats.
- View switching preserves the shared film context: Outline, Script, Shot, Boards, and Edit should stay on the same scene, shot, or board wherever possible.
- The Context Inspector exposes compact actions based on the selected object, such as Source, Generate Shots, Generate Boards, Link Outline Beat, Accept, and Ignore.
- The Context Inspector shows compact metadata for the selected object, including scene identity, page, cast, locations, linked outline beats, shot and board counts, source links, status, and editorial marker state.
- Command-K opens a searchable command palette for file actions, navigation, focus mode, context refresh, cleanup, proposals, shots, boards, and edit-spine navigation.
- The main toolbar stays intentionally compact; secondary navigation and production commands live in Command-K and the app menus.
- Focus mode retreats Navigation and Context so the screenplay can become the primary working surface.
- UI styling should come from shared ScreenplayOS tokens for colors, spacing, radii, typography, and control sizing.
- AI should appear as contextual capability inside the tool rather than as a dominant separate chat surface.

## Quick start

```sh
./Scripts/test.sh
swift run screenplay-self-test
swift run ScreenplayOS
swift run screenplay-inspect Tests/Fixtures/Defenders_of_Cat_Island_Pilot_Final_Draft.fdx
swift run screenplay-inspect Tests/Fixtures/Defenders_of_Cat_Island_Pilot_Final_Draft.fdx --json
```

`./Scripts/test.sh` runs the editor safety regressions and the domain/import self-tests. It also supplies the Swift Testing framework paths needed by Command Line Tools-only installations. The editor tests use temporary files and isolated preferences.

New scripts automatically save to an unused filename in Downloads (adding a number when the title already exists). Once saved, edits continue updating that same file. Blank screenplay elements are preserved during saves. If a save fails, New and Open retain the current script so you can retry Save or use Save As.

In Xcode, open `Package.swift`, choose the `ScreenplayOS` scheme, then press Run.

## First editor behaviors

- Click into any screenplay line to edit it.
- Press Return in a line to create the next screenplay element and move the cursor into it.
- Press Return in the middle of a line to split it at the cursor.
- Press Backspace at the start of a non-empty line to merge it into the previous screenplay element.
- Use the top sidebar mode control to switch between Outline, Script, Shot, Boards, and Edit.
- Switching views keeps the current scene in context; Shot, Boards, and Edit also preserve the current shot or board when available.
- Script includes Navigator, Proposals, Activity, Search, Format, and Title Page.
- Outline includes Proposals, Activity, and story structure mapping.
- Shot keeps the selected scene script visible beside the shot list, with shot controls attached to the list pane.
- Boards keeps the selected scene script visible beside the board sequence, with board timing and prompt controls attached to the board pane.
- Edit keeps the selected scene script visible beside the viewer, timeline, and Story Spine.
- Production context and reports are supporting workspace panels, not primary modes.
- Turn AI proposals on or off independently in Outline, Script, Shot, Boards, and Edit.
- Boardomatic durations synchronize into the Edit Spine as editable clips with scene, shot, board, source line, start-time, and duration metadata.
- Edit Exports creates CSV files for scene breakdowns, shot lists, board frames, edit guides, and edit timeline handoff.
- Use New or Command-N to start a blank screenplay with a title page and first scene heading.
- Use Open Recent to return to scripts you opened or saved recently.
- Use Snapshots to create named local checkpoints before major rewrites, scene moves, shot generation, board timing changes, or restores.
- Use Notes to add comments to the selected script line, review notes for the current scene, and resolve or reopen them.
- Script lines with open notes show a small note marker in the page gutter; click it to open Notes for that line.
- Press Command-K to open the command palette, type to filter commands, press Return to run the top match, or press Escape to close it.
- The top document bar and Document section show which file is currently active.
- Click a scene in the sidebar to jump to that part of the screenplay.
- Use the Format section to jump to basic formatting issues.
- Use Find / Replace in the sidebar to search, jump to matches, replace selected, or replace all.
- Use Rename Character to update matching Character cues throughout the screenplay.
- On Character lines, matching character names appear as clickable autocomplete suggestions.
- Use the Elements menu in the toolbar to change the selected line type.
- Use the bottom status bar to see the current element, page count, current scene, Return/Tab behavior, focus mode, page appearance, and zoom.
- The editor groups paragraphs into writing surfaces that expand for long text; labels identify the corresponding PDF page or page range.
- Pagination keeps Character cues with following Dialogue and Scene Headings with following Action where possible.
- PDF export splits long text across pages. The page count and report page references use the PDF layout. Editing keeps each paragraph intact; the writing surface is not an exact print preview.
- Use the Context panel to build reviewable production context from the script.
- Refresh From Script extracts suggested characters, locations, props, VFX candidates, and format notes.
- Mark context records as Suggested, Accepted, or Ignored so future AI workflows can use reviewed context.
- Use the Breakdown panel to review each scene as a production unit with page, cast, location, props, VFX, notes, revisions, and action beats.
- Each scene breakdown includes a stable edit-spine ID so later production and edit workflows can trace back to the script.
- Select a scene in Breakdown, then use Generate Shot List to create editable scene-linked shot cards.
- Shot cards include a stable shot label, setup type, status, notes, and source link back to the screenplay.
- Use Boards to generate editable board frames from the selected scene's shot list.
- Board frames preserve the shot ID, scene spine ID, visual prompt, duration, status, notes, and source link back to the screenplay.
- Boards can function as a first Boardomatic pass: boards carry timing so the scene can be judged as images in time before real footage exists.
- Boardomatic playback can play/pause through the selected scene's boards, jump to previous/next boards, scrub the playhead, and keep Boards/Edit focused on the active board clip.
- Use Proposals in any mode to generate reviewable AI suggestion cards for the current workflow.
- Proposal cards can be marked Suggested, Accepted, Rejected, or Applied without changing screenplay text.
- Apply runs only trusted app actions: navigation, cleanup, shot-list generation, board generation, context refresh, or accepting a targeted context record.
- Proposal Apply does not rewrite screenplay text.
- Use Activity in any mode to review a saved audit trail of major workflow actions.
- Use Outline mode as an optional structure tool before or alongside the screenplay.
- Outline center stage shows scene cards generated from the actual screenplay scenes.
- Outline scene cards can add, duplicate, delete, and move scenes earlier or later.
- Moving a scene in Outline moves that same scene range in Script and keeps the Edit Spine ordered to match.
- Selecting a scene card updates the Script Preview pane, and Open in Script preserves the selected scene.
- Outline can seed editable templates, track mapping coverage, and link beats to scene spine IDs.
- Outline templates include Hero's Journey, Three-Act Structure, Save the Cat, TV Teaser / Acts / Tag, Character Arc, Mystery / Investigation, and Custom Blank.
- Linked outline scenes can jump back to the screenplay.
- Outline AI can suggest scene-to-outline mappings, and Apply links the proposed scene to the proposed beat.
- Use the Reports panel to preview Scene, Character, Location, Revision, and Production Context reports.
- Export Report creates a plain text report for handoff, review, or production planning.
- Use Edit Exports to create a selected-scene packet, breakdown CSV, shot CSV, board CSV, Edit Guide CSV, or Edit Timeline CSV.
- Use Edit Spine to inspect and track the editorial beat map that carries scene identity toward editing software such as Premiere.
- Edit Guide CSV exports ordered edit markers with scene IDs, shot references, board references, marker status, and edit notes.
- Edit Timeline CSV exports one row per edit clip with 24 fps timecode, start/end seconds, duration, scene ID, shot ID, board ID, source kind, and source script references.
- Character and Location reports use Accepted context first, then Suggested context, then script-derived fallback data.
- Use the right-side Context Inspector to run local screenplay-context jobs.
- Starter prompts can create continuity questions, production risks, shot candidates, and character arc notes.
- Context jobs show their status and add reviewable notes without changing screenplay text.
- Turn on Revision Mode from the toolbar, the Format panel, or Shift-Command-R.
- Edited, inserted, split, or retyped lines get a colored revision mark while Revision Mode is on.
- Choose a revision label and color in the Format panel.
- Use Clear Revision Marks after a draft has been accepted.
- Press Tab while editing to cycle the selected line through screenplay element types.
- Press Shift-Tab to cycle backward.
- Type `INT.`, `EXT.`, `INT/EXT.`, or `I/E.` at the beginning of an Action line to turn it into a Scene Heading.
- Press Command-1 to make the selected line a Scene Heading.
- Press Command-2 to make the selected line Action.
- Press Command-3 to make the selected line Character.
- Press Command-4 to make the selected line Dialogue.
- Press Command-5 to make the selected line Parenthetical.
- Press Command-6 to make the selected line Transition.
- Press Command-7 to make the selected line Shot.
- Press Command-Z or the undo button to restore the previous screenplay state.
- Use the trash button to delete the selected screenplay element.
- Press Delete on an empty selected line to remove that screenplay element.
- Use Clean Script or Shift-Command-K to remove empty screenplay elements and normalize casing.
- Use Command-Delete to remove empty screenplay elements only.
- Use Command-S or the save button to save as native Open Screenplay JSON.
- Use Shift-Command-E or Export PDF to create a formatted PDF with a title page.
- Use Option-Command-E or Export Report to create the selected report as a `.txt` file.
- Use Command-O to open either `.fdx` imports or saved `.json` Open Screenplay documents.
- On launch, the app reopens the saved JSON in Downloads if one exists.
- Empty FDX paragraphs are skipped during import instead of appearing as dead space.
- FDX import reads only real top-level script paragraphs, ignoring nested Final Draft metadata paragraphs.
- Explicit FDX page breaks are preserved during import and respected during pagination.
- The editor and PDF use element-specific spacing based on the fixture; their text sizing is not yet identical:
  - Scene Heading, Action, and Shot at 1.5 inches
  - Character at 3.5 inches
  - Dialogue at 2.5 inches
  - Parenthetical at 3.0 inches
  - Transition right-aligned from 5.5 to 7.1 inches
- The first automatic type flow is intentionally small:
  - scene heading -> action
  - character -> dialogue
  - parenthetical -> dialogue
  - dialogue -> action
  - transition -> scene heading

The architectural boundary is:

```text
FDX file
  -> compatibility importer
  -> Open Screenplay domain model
  -> editor / OS features
```

The editor should never become a wrapper around Final Draft's data model.

## Recovery and edit history

Undo and Redo restore the screenplay element selection with the document. Redo is available with Command-Shift-Z; a new edit clears the redo history. History is local to the open document and remains limited to 100 undo states. Adjacent native typing is grouped while pauses stay under 1.2 seconds. Paste, caret movement, paragraph changes, explicit Save, and structural edits start separate groups. Undo/Redo restores the recorded caret or selection within the paragraph.

New snapshots live under `ScreenplayOS Snapshots/<project ID>/` beside the saved file. Older shared-folder snapshots remain available when their embedded project ID matches. Snapshot filenames are unique even when created rapidly. Restore verifies project identity, requires a successful safety snapshot, and writes the restored file before replacing the live document. Restores can be undone and redone.

## Pagination status

Print layout splits action and dialogue at word boundaries where possible, and at grapheme boundaries for unbroken text. It retains the source paragraph IDs and content. Explicit page breaks are honored, and character cues stay with the beginning of dialogue when space permits. Tests check page height bounds, Unicode, source preservation, and complete text extraction from exported PDFs.

The writing surface expands to keep long paragraphs accessible. Exact on-screen print preview, linked editing across page boundaries, production page locking, and continuation handling across separate dialogue elements or explicit page breaks remain unfinished.

Automatic print-page breaks within a dialogue paragraph now add `(MORE)` and a repeated speaker cue with `(CONT'D)` when a usable preceding character cue is available. These markers are generated only for print layout and do not modify the source script.

## Live editor smoke checks

An isolated app using the current writing surface was tested on this Mac with temporary scripts and separate preferences:

- New document accepts lowercase typing and displays a complete uppercase scene heading.
- Return creates and focuses an action element; subsequent text stays in that element.
- Undo and Redo restore typed text while keeping the active element focused.
- A long pasted paragraph remains accessible and accepts further typing at its end after moving between editing sections.
- Save, New, Open, and arrow-key navigation recover the full saved passage, including its final appended text.

These checks caught and fixed focus transfer on new native text views, capitalization replacing the caret position, and focus loss when a paragraph moves to another editing section. Exact caret restoration for every middle-of-paragraph reflow, and text selection across paragraphs remain unfinished.

Grouped typing and selected-word replacement were also checked in the live editor. One Undo removes a continuously typed sentence; Redo restores it. Replacing a selected word by typing is one undo group, and Undo restores the original selected range.
