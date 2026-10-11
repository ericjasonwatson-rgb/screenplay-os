# Shot-based board images: initial local implementation

The Shot Composer and Board Details offer **Generate board image**. This opens a blue panel where the user edits directing intent. **Review exact request** then composes and displays the complete frozen request from that intent, the selected shot, its covered screenplay, and linked adopted continuity records. Nothing is sent until **Send to OpenAI** is pressed. The app recomposes immediately before submission and rejects a changed script, shot, Bible record, or consent record. It uses the saved OpenAI Keychain connection and a separately editable image-model ID. No live paid request was made during implementation validation.

The integration uses the [OpenAI Images API](https://developers.openai.com/api/docs/guides/image-generation), with one low-quality landscape PNG per request. Requests use an ephemeral session, reject redirects, bound the response size, and validate PNG dimensions and decoding. Cancellation and closing the panel discard late responses. The prompt and model used for a result are frozen separately from editable controls.

**Save image & use board** creates a new PNG chosen by the user; it never overwrites an existing image. Adoption requires the same document, screenplay elements, shot, and related boards as the generation snapshot. The existing board identity and duration are retained. A shot without a board gets a new board with the existing default duration. Applying images and selecting prior versions are undoable. Generating placeholder boards now adds missing boards rather than deleting existing authored boards.

## Storage boundary

This is a legacy-project feature, not implementation or conformance of the draft portable package attachment standard. Optional `image_versions` and `selected_image_id` fields are added to legacy `board_frames`. Each image version records its UUID, local file URL, SHA-256, approved prompt, and image model. Versions use the existing JSON Codable field names `id`, `fileURL`, `sha256`, `prompt`, and `model`. Old boards decode with no images. Images remain separate PNG files; no image bytes enter screenplay text or autosave JSON. Local recovery and Undo retain references, not copies of the image files.

The UI explicitly discloses this limitation: sending or relocating the screenplay alone does not make images portable. Do not advertise packaged sharing, attachment recovery, or portable snapshots for this feature. Missing or changed image files show an unavailable-image placeholder rather than deleting board data. Existing older app builds may not preserve these new optional fields; use the current build for projects with board images.

## Take migration foundation

`Take` now defines the provider-neutral media candidate needed before video generation: stable shot and optional board identity, ordered media, duration and in/out points, candidate/selected/rejected state, note, and local provenance. `BoardTakeMigration` projects every legacy `BoardImageVersion` into a take without changing the saved screenplay schema or deleting the legacy record. The projection keeps IDs, order, paths, hashes, prompt/model provenance, timing, notes, and selection, and it can reconstruct the exact legacy image records. Corrupt selection, duplicate IDs, wrong-shot application, multiple selected takes, and video-to-image downgrade fail closed.

`TakeLedger`, `TakeFileStore`, and `TakeController` now add a versioned,
project-bound local sidecar for that projection. The store validates source and
media hashes, local paths, timing, provenance, unique identity, and unambiguous
selection; writes atomically with owner-only permissions; and rejects symlinks.
Selection changes reach disk before the controller publishes them. The app now
rebuilds this sidecar from authoritative `board_frames` whenever board versions
or their selection changes. Invalid legacy digests remain readable in the
lossless projection, but fail closed instead of entering the stricter sidecar.
This is durable local service state, not portable canonical project data.

Board Details now presents image versions as a horizontal take strip with a
thumbnail, take number, model, and selected state. Choosing a card still uses
the existing undoable `BoardFrame.selectedImageID` mutation, so the screenplay
document remains authoritative and older compatible files keep working. A
projection error is shown without mutating the screenplay. Compare-two review,
media playback, and canonical package persistence remain future work.

## Deferred

Reference-image inputs, multiple generated candidates per request, provider/model discovery for image capabilities, and live paid-provider validation remain outstanding. Anthropic dialogue connections are not routed into the OpenAI image endpoint. Existing EDL/FCPXML exports remain timing guides; attaching images does not turn them into linked-media exports.

The current development build received a manual UI pass on 2026-10-10 using an isolated ad-hoc bundle: directing-intent display, exact grounded preview, honest unavailable cost, provider/model/parameters, cancellation without send, and both nested dismissals were observed. This does not validate a paid provider response.

## Build 23 update: context, billing, and portable board copies

The reviewed, editable prompt now includes up to 7,000 characters from the shot's linked scene, including character cues, action, and dialogue. No scene text is sent until the user presses the explicit send button. The existing stale-input and explicit-adoption checks remain in force. A no-credit HTTP 429 message now explains that waiting will not restore a balance and offers an OpenAI billing link.

**Use board in project** stores a validated immutable, content-addressed PNG in `Board Images/` beside the saved legacy JSON. An unsaved screenplay must be saved first. Saved JSON uses relative URLs for images in that folder; in-memory references are resolved against the document location. Relative paths are limited to one filename inside `Board Images/`, and symlink escapes are rejected. Existing absolute image references still work. Save As alone may retain links to the original media location; use the portable-copy command to gather media.

**File → Export Portable Project Copy…** creates a new folder containing `Project.open-screenplay.json` and all current board-image versions, including unselected versions. Export validates image hashes and PNGs, stages the copy, and refuses to publish an incomplete copy or overwrite an existing destination. Move or ZIP the whole folder, then open its JSON in this build or later. This exports the current authored project; external media other than board images and named snapshot history are not gathered. The original document and files are unchanged.

This remains a legacy project transport folder, not migration to the draft `.screenplay` package or a claim of package-format conformance. Older builds do not resolve these relative media references. No media is deleted automatically, including images retained for Undo or snapshots.

Dialog review: shell refresh signals cover the AI dialog and board-generation snapshot. Title-page and package-preview states already force a shell refresh; print preview uses local SwiftUI state, and package-editor preview observes its editor directly. Regression coverage includes AI open/dismiss and title-page open/dismiss. Live checks verified provider, board, title-page, and print-preview dismissal; this does not claim every macOS system panel was exercised.

Build 24 hardening: portable copying runs off the interface thread with a shared progress/result banner; duplicate exports are disabled while one runs. Relative filenames use URL component encoding, and managed PNG symlinks are rejected. See `build24-audit.md` for validation and remaining limits.
