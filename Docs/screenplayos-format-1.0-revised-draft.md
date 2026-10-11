# OPEN SCREENPLAY FORMAT 1.0
## Founding Native Document Standard

**Status:** REVISED DRAFT FOR IMPLEMENTATION — not yet a released standard  
**Draft revision:** 3 — 2026-09-12
**Purpose:** An open native document format for screenplay authorship and the free creative layer  
**Principle:** The document belongs to the writer. Its usefulness must survive the application.

This revision preserves the founding premises and proposes concrete rules where the original draft left implementation choices open. “Must” describes a requirement of the proposed standard; it does not assert that the current ScreenplayOS prototype implements it. The release gates at the end must be completed before calling an implementation conformant to version 1.0.

## 1. Ownership and independence

A writer must be able to recover their screenplay and manually created creative work without ScreenplayOS, a subscription, an account, or a remote service.

The format must be publicly documented, versioned, portable, and human-readable where practical. Core data must use openly specified encodings and have no vendor-specific runtime dependency, DRM, license check, or required remote identifier.

The specification and schemas must be available under an explicit open license allowing independent implementation. This requirement does not require the application itself to be open source. The particular specification license remains to be selected before release.

**Design test:** If ScreenplayOS disappeared, a competent developer must be able to reconstruct the screenplay, notes, named versions, entities, shot lists, and shot-to-script links using the published specification and ordinary file-processing tools.

## 2. Native package

The native extension is `.screenplay`. A working document is a directory/package:

```text
My Film.screenplay/
    manifest.json
    screenplay.json
    notes.json             # optional
    entities.json          # optional
    shots.json             # optional
    settings.json          # optional
    extensions.json        # optional
    versions/              # optional
    attachments/           # optional
```

Only `manifest.json` and `screenplay.json` are required. An absent optional file means that feature is absent; a reader must not manufacture empty optional files merely by opening the package.

All JSON files use UTF-8. Readers must reject duplicate object keys as ambiguous. Array order is significant where this specification defines it. Object key order and insignificant JSON whitespace have no meaning.

Paths within a package are relative, use `/`, and must not escape the package. Attachments and versions must not require symbolic links, absolute filesystem paths, or network access. A reader must reject traversal paths rather than follow them.

The full-project extension direction is specified in `project-format-decision.md`: optional `project.json` and `film/` records enrich this same package. They do not change the two required core files, duplicate screenplay text, or create a paid format. Their schemas and migration are not yet implemented. A core-only writer must preserve unknown companion data; a project-aware reader must detect when external edits have made revision inventories stale.

A ZIP of the package may be used for transport. ZIP is a transport representation, not a second native content model. The extraction rules must enforce the same package-path restrictions.

## 3. Manifest and version declaration

The manifest contains document-level metadata, not screenplay content:

```json
{
  "format": "open-screenplay",
  "format_version": "1.0",
  "document_id": "7e915d29-47a7-4c77-96aa-5b062c3381be",
  "title": "My Film",
  "author": "Eric Watson",
  "created_at": "2026-09-12T07:00:00Z",
  "modified_at": "2026-09-12T07:00:00Z"
}
```

All fields shown are required. `author` may be an empty string. Timestamps use RFC 3339 with an explicit UTC offset or `Z`. Timestamps are descriptive metadata, not a concurrency-control mechanism.

The document UUID identifies the work across saves, relocation, and named versions. Save As preserves it by default. A deliberate “Duplicate as New Work” operation creates a new document UUID and must explain its identity semantics. A document's filesystem name is not its identity.

`format_version` identifies the document contract. A specification's editorial draft revision is separate from the file format version.

## 4. Canonical authored content

`screenplay.json` holds the screenplay and, optionally, authored title-page content:

```json
{
  "id": "7e915d29-47a7-4c77-96aa-5b062c3381be",
  "elements": [
    {
      "id": "a1fbd3b5-6f17-46e4-9bf6-b58e0c0bc304",
      "type": "action",
      "text": "The Mewseum is hushed and bright."
    }
  ]
}
```

The root `id` must equal the manifest's `document_id`. Element order is screenplay order. An empty element array is valid. Blank elements are valid and must not be silently removed.

An optional `title_page` object may contain `title`, `subtitle`, `author`, `contact`, and `draft_date` strings. These are authored display text; `draft_date` is not required to be a machine timestamp. Manifest title and author are catalog metadata. A reader must not silently replace title-page wording with manifest values.

Text is authoritative. Parsed headings, inferred characters, pagination, breakdowns, and analysis must never replace authored text merely because they disagree with it.

## 5. Elements and stable identity

Every element requires `id`, `type`, and `text`. `id` is a UUID string and must be unique within the document. Readers must not assume a particular UUID generation version. IDs are permanent for the lifetime of the object and must not be regenerated during import normalization, reordering, renumbering, or saving.

Version 1.0 recognizes:

```text
scene_heading
action
character
dialogue
parenthetical
transition
general
shot
page_break
```

`general` represents authored material without a more specific screenplay role. `shot` is an authored shot-direction paragraph; it is distinct from a production shot-list record.

A `page_break` is an explicit authored layout instruction with empty text. It does not store a page number or a rendered page.

Unknown type strings must be preserved. A reader that cannot render the type must present its text using a neutral fallback and identify the unsupported type when useful. Unknown types must not cause the document to be discarded.

## 6. Text and formatting ranges

The exact decoded Unicode text is authoritative. Readers must not silently uppercase, trim, recompose Unicode, replace punctuation, or strip blank paragraphs on open or save. An editing command may make such changes when its behavior is explicit and undoable.

A reader must preserve embedded line breaks in an element. Treating them as paragraph splits is an editing operation, not an automatic normalization.

Optional `runs` add formatting to the element's text:

```json
{
  "start": 4,
  "length": 16,
  "style": { "italic": true }
}
```

For this proposed contract, offsets count **Unicode scalar values**, starting at zero. They do not count UTF-8 bytes, UTF-16 code units, or user-perceived grapheme clusters. A range is half-open: `[start, start + length)`. These rules also apply to text ranges in source links and note anchors.

`start` and `length` are nonnegative integers and must stay within the text. Editors should place interactive selections at grapheme boundaries, converting from their platform's native indexing. Conformance fixtures must include emoji sequences, combining marks, and non-Latin text.

Initial style keys are `bold`, `italic`, `underline`, and `strikethrough`, with Boolean values. Base text is unstyled. When runs overlap, later runs override earlier runs for keys they explicitly specify; other style keys retain their prior value. Formatting is subordinate to text. Invalid ranges must be reported without losing the underlying text.

## 7. Scenes, numbers, and characters

A scene heading's original `text` always wins. An optional `scene` object may contain a permanent scene UUID and descriptive parsing metadata such as `interior_exterior`, `location`, and `time`.

A distinct scene UUID is required when other records refer to that scene by `scene_id`. Basic screenplay text remains valid without a scene entity model. Each declared scene UUID must be unique. It identifies the scene, not its current heading wording or numbered position.

Optional `scene_number` is a string such as `23A`. It is a presentation identifier. Changing it must not change scene identity or break notes, shots, or other references. Internal strings such as `S001` must not be treated as substitutes for permanent scene UUIDs.

Character cue text likewise remains authoritative. Optional `entity_id` links may refer to `entities.json`. The cue remains readable and valid without that link.

## 8. Entities

`entities.json` may contain `characters` and `locations` arrays. Each entity has a UUID, a canonical display `name`, and optional `aliases` strings. Entities are authored conveniences or optional indexes, not prerequisites for interpreting the screenplay.

Inferred entities must not silently rewrite character cues or scene headings. Renaming an entity and replacing authored text are separate operations unless the user explicitly requests both.

## 9. Notes and source anchors

`notes.json` contains a `notes` array. Each note requires a UUID, `text`, an `anchor`, and a Boolean `resolved` value. The basic anchor is:

```json
{
  "element_id": "a1fbd3b5-6f17-46e4-9bf6-b58e0c0bc304"
}
```

An anchor may additionally include `start` and `length`, together, under the range rules above. Notes do not alter screenplay text. Resolution must not delete note content.

Editors must preserve references when the referenced object survives an edit. When paragraphs merge, references to retained material should move to the surviving paragraph. When exact ranges cannot be mapped reliably, an editor must make the loss of precision explicit rather than invent an exact selection. A paragraph-level link is an acceptable downgrade.

If source material is deleted completely, retain the note or production record and its historical reference. Report the missing source and support explicit reattachment or deletion. Do not silently attach it to an unrelated paragraph. A dangling reference is a validation warning and repairable state, not a reason to discard the document.

Undo/Redo must restore text, identities, and reference changes together. These are editor behavior requirements for safe native-format editing, not a mandate for any particular history implementation.

## 10. Shot lists and shot identity

Shot lists and shot-to-script links are part of the free standard. Store scene addenda in `shots.json`:

```json
{
  "shot_addenda": [
    {
      "id": "493e98fd-3c54-40cb-bd19-87c0a55389d7",
      "scene_id": "323ed47e-d5df-4fcf-950e-0f8b784bfc92",
      "shots": [
        {
          "id": "8b64eade-e282-4a26-b654-90babf5d2a0c",
          "ordinal": 1,
          "label": "4.1",
          "description": "INSERT — black hair",
          "framing": "INSERT",
          "movement": null,
          "notes": "",
          "source_refs": [
            { "element_id": "a1fbd3b5-6f17-46e4-9bf6-b58e0c0bc304" }
          ]
        }
      ]
    }
  ]
}
```

Shot array order is canonical order. `ordinal`, when present, is its one-based display position and must agree with that order. `label` is presentation text and may reflect production numbering. Neither identifies the shot.

Each shot requires a UUID and description. The other illustrated shot fields are optional. `source_refs` may use the same element and range structure as note anchors. A shot without a source link remains readable. Reordering shots or renumbering scenes must never regenerate shot UUIDs.

## 11. Pagination and production locks

Rendered pages and ordinary computed page numbers are not canonical screenplay content. They are derived from text, settings, and a layout engine. Reflow does not create a different screenplay.

Explicit page breaks are authored instructions. Production page-lock constraints are also distinct from rendered pages: they can express a production requirement to retain labels or omitted positions without making a cached layout authoritative.

A **separately documented, optional open extension** may store production lock constraints, frozen labels, omitted positions, and identity-based anchors. It must not be required to read or recover the screenplay. A reader that lacks the extension may paginate normally, must preserve the extension unchanged when it can, and must not claim that its output honors those locks.

This draft does not standardize a production-lock extension schema. Before releasing one, specify anchor units, edits and deletions, duplicate text, paragraph splits and merges, inserted-page lettering, omitted pages, and output conformance. Do not silently migrate the prototype's lock representation or discard existing production constraints.

## 12. Document settings

Optional `settings.json` contains a `formatting` object. Proposed version 1.0 defaults are:

```json
{
  "formatting": {
    "paper": "US_LETTER",
    "font_family": "Courier Prime",
    "font_size": 12
  }
}
```

Font size is in points. Settings are rendering preferences, not guarantees of identical pagination. A reader must disclose a font substitution that materially affects layout.

The complete default layout profile—including margins, line spacing, element indents, title-page treatment, and continuation conventions—must be published before final release. Until it is, identical pagination across implementations is not a conformance claim. Unknown settings must be preserved under the same rules as other unknown fields.

## 13. Attachments

Attachments may use openly documented media formats under `attachments/`. References must use relative package paths. No essential authored content may exist only behind a remote URL.

Attachment naming and any index must be documented before interoperable attachment references are released. Missing attachments must be reported without preventing recovery of the text. Unreferenced files must not be deleted as an automatic cleanup step.

## 14. Independently recoverable named versions

Named versions may live in `versions/<version-id>/`. Every named version requires metadata identifying the version, its human-readable name, creation time, and the format version it uses.

For version 1.0, prefer a complete logical snapshot: manifest, screenplay, and all optional authored data present when the version was captured. An implementation may use deduplicated local storage only if the published recovery procedure can reconstruct the snapshot using the package alone.

A snapshot must include or resolve all attachments needed by that snapshot. It must remain recoverable after the current document changes. A snapshot containing only screenplay text must be identified as a screenplay-only snapshot; it must not be presented as a complete version of notes, entities, and shot lists.

## 15. Extensions and paid OS data

`extensions.json` contains an `extensions` object keyed by a stable namespace, for example `com.example.story-intelligence`. Each extension defines its own version and publicly documents any data necessary to recover authored work stored within it.

Paid AI interpretation, embeddings, generated analyses, semantic relationships, and other OS-specific state must not become required core structure. They belong in optional extensions or companion project data.

Manually created work remains recoverable regardless of which feature or product tier created it. If an application lets a writer manually author boards or other creative material outside the version 1.0 core, it must provide a documented, subscription-independent way to recover that material. Labeling it an extension is not an exemption from the ownership principle.

No subscription or license state belongs in the screenplay package. A reader must not need a paid extension implementation simply to preserve its opaque data.

## 16. Unknown data and safe editing

Readers may ignore unknown fields and extensions for display. Writers must preserve unknown fields, unsupported type values, extension payloads, and unrecognized package files when saving an existing document, subject to package-path safety rules.

Preservation means semantic JSON preservation; byte-for-byte JSON whitespace and key order are not required. Opaque non-JSON files must remain byte-for-byte intact unless explicitly edited.

If a writer cannot preserve data, it must not silently overwrite the original. It must explain the limitation and offer read-only use or a separately named, explicitly lossy conversion. The original must remain intact.

A parser built solely from a closed set of application structs is insufficient if decoding and re-encoding silently drops unknown content. Preservation must be part of the storage architecture.

## 17. Saving, conflicts, and recovery

Opening, validating, or internally migrating a document must not modify its stored source. A writer must commit the current format only as part of an authorized save workflow. Autosave may participate only after that workflow has established a writable document and any required migration consent.

A save must preserve a recoverable previous state until the new package is complete. Writing each JSON file atomically is not enough if an interruption can leave a manifest and screenplay from different save generations. The implementation must define a package-level transaction and crash-recovery strategy, then verify it with interrupted-save tests.

Detect outside modifications before replacing an existing document. Do not rely only on `modified_at`. Explain conflicts and preserve local work separately when an overwrite is blocked. Do not claim exclusive protection against concurrent external writers unless the implementation actually provides it.

Recovery copies must preserve authored optional data along with the screenplay. Close, Quit, New, and Open must not silently discard unsaved changes after a failed save.

## 18. Versioning and migration

Readers must declare which format versions they understand. Compatible minor versions may add optional data without changing the meaning of existing fields. Incompatible changes require a new major version.

An older reader must not assume that it can safely edit a newer version merely because it can parse its JSON. It may offer a read-only or text-recovery view. Unsupported newer content remains protected by the unknown-data rules.

Migration must preserve the source, keep UUIDs and references stable wherever possible, disclose transformations, and write the new representation only on an authorized save. A migration that loses information requires a separate output and an explicit loss report.

The current ScreenplayOS monolithic JSON files are a legacy prototype representation. Their filename or version label is not proof of conformance to this package specification. Native migration must recognize their actual structure and preserve the original files. Existing scene identifiers, ranges, production data, and page locks require explicit mapping rules.

## 19. Validation and conformance

Publish JSON Schemas for the manifest and every standardized JSON file, plus semantic validation rules for matters JSON Schema alone cannot check: cross-file IDs, references, ranges, package paths, versions, and snapshot completeness.

A proposed command-line interface is:

```text
screenplay validate MyFilm.screenplay
```

Validation must distinguish:

- **Errors:** malformed JSON, duplicate keys or identities, invalid required fields, unsafe paths, impossible range bounds, contradictory required identity metadata.
- **Warnings:** unresolved historical references, missing optional attachments, unsupported types/settings/extensions, or rendering substitutions.

Useful text must remain recoverable even when a document needs repair. Validation must not silently rewrite the package.

Provide conformance fixtures for minimal documents, blank elements, all core types, Unicode ranges, optional authored files, unknown fields/types/extensions, renamed and merged sources, missing sources, named-version recovery, interrupted saves, and migration. Include at least one independent reader or recovery utility in release verification.

## 20. Interchange

FDX, Fountain, plain text, and PDF are compatibility formats. They must not dictate the native architecture. Import/export must report unsupported features and meaningful losses; it must not pretend that interchange round-trips preserve every native feature.

The free creative layer must cover screenplay text, notes, versions, characters, locations, shot lists, and shot/script references in the documented native format.

## 21. Release gates and unresolved details

Before declaring Open Screenplay Format 1.0 released:

1. Select the specification/schema license and publish stable versioned documentation.
2. Publish all core file schemas and semantic validation rules.
3. Finalize and test the proposed Unicode-scalar range convention across platforms.
4. Publish the complete default layout profile and font-substitution policy.
5. Specify attachment references and the named-version metadata/storage contract.
6. Implement unknown-data preservation, package transactions, conflicts, and recovery.
7. Publish a loss-aware migration path from the prototype and test identity/reference preservation.
8. Validate independent recovery of every part of the free creative layer.

The optional production-lock extension may ship separately once documented and tested. Its absence must not block reading, writing, or recovering the core screenplay.

**Final test:** A writer's manually created work must remain understandable, portable, and recoverable when the original application and its business no longer exist.
