# Shot-based board images: initial local implementation

The Shot Composer and Board Details offer **Generate board image**. This opens a blue review panel with an editable prompt made from the selected shot's label, setup, and notes. Only the displayed prompt is sent, and only when the user presses **Send prompt & generate board**. It uses the saved OpenAI Keychain connection and a separately editable image-model ID. No live paid request was made during implementation validation.

The integration uses the [OpenAI Images API](https://developers.openai.com/api/docs/guides/image-generation), with one low-quality landscape PNG per request. Requests use an ephemeral session, reject redirects, bound the response size, and validate PNG dimensions and decoding. Cancellation and closing the panel discard late responses. The prompt and model used for a result are frozen separately from editable controls.

**Save image & use board** creates a new PNG chosen by the user; it never overwrites an existing image. Adoption requires the same document, screenplay elements, shot, and related boards as the generation snapshot. The existing board identity and duration are retained. A shot without a board gets a new board with the existing default duration. Applying images and selecting prior versions are undoable. Generating placeholder boards now adds missing boards rather than deleting existing authored boards.

## Storage boundary

This is a legacy-project feature, not implementation or conformance of the draft portable package attachment standard. Optional `image_versions` and `selected_image_id` fields are added to legacy `board_frames`. Each image version records its UUID, local file URL, SHA-256, approved prompt, and image model. Versions use the existing JSON Codable field names `id`, `fileURL`, `sha256`, `prompt`, and `model`. Old boards decode with no images. Images remain separate PNG files; no image bytes enter screenplay text or autosave JSON. Local recovery and Undo retain references, not copies of the image files.

The UI explicitly discloses this limitation: sending or relocating the screenplay alone does not make images portable. Do not advertise packaged sharing, attachment recovery, or portable snapshots for this feature. Missing or changed image files show an unavailable-image placeholder rather than deleting board data. Existing older app builds may not preserve these new optional fields; use the current build for projects with board images.

## Deferred

Portable attachment copying and relinking, reference-image inputs, continuity libraries, multiple candidates per request, provider/model discovery for image capabilities, and live provider/manual UI validation remain outstanding. Anthropic dialogue connections are not routed into the OpenAI image endpoint. Existing EDL/FCPXML exports remain timing guides; attaching images does not turn them into linked-media exports.
