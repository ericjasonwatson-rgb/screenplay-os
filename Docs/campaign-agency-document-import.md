# Local agency document import

Status: bounded DOCX/text implementation in draft PR6. Exact native verification
belongs to the final PR head and CI run. Interactive acceptance is still required.

## Enabled workflow

In Campaign > Campaign Brief & Scope > Agency Sources, select local UTF-8 text
(`.txt`, `.md`, `.fountain`) or a supported Word `.docx` file. The source is read
without modifying it, off the main actor, then shown as plain, read-only text.
Review the extraction warnings before **Import Preview Locally**. No text is
adopted automatically into a screenplay, deliverable or assumption.

A DOCX import retains the exact original bytes and original SHA-256 separately
from exact extracted UTF-8 bytes and their SHA-256. It also retains its filename
without directory path, extractor version `docx-body-text-v1`, notices, import time
and immutable document/revision IDs. **Save Retained Original…** writes an explicit
private local copy of those original bytes. The full private campaign backup
includes them; screenplay/package exports still do not include the campaign.

The producer must review the extracted text against the original. A local review
record does not authenticate the sender, authorize spending or prove the extraction
contains all meaningful content. Reviewed line citations pin both source revision
and campaign target state. Revised originals require fresh review even if their
extracted text is unchanged. Frozen baselines retain their original evidence.

## DOCX extraction contract

This is a narrow local ZIP/XML reader, not an Office renderer or Word automation.
It never extracts members to disk, follows relationships, loads remote resources,
executes embedded code, invokes a shell, or sends data to a provider.

- Raw input: at most 2 MiB, nonempty regular file, no final symlink. Exact descriptor
  bytes are read once, with size/mtime/ctime checked again before extraction.
- Archive: at most 256 regular members, 4 MiB per inflated member and 8 MiB total.
  Stored and raw-DEFLATE entries are supported. Local/central metadata, declared
  sizes, contiguous records, stream completion and CRC are checked. ZIP64,
  encryption, multipart archives, unsafe paths, case/Unicode-colliding duplicate
  names, directory/symlink members and hidden/trailing records are rejected.
- XML: UTF-8 only. The optional declaration is inspected within a bounded prefix.
  DTD/entity declarations, external relationships, excessive nesting and unsupported
  encodings are rejected. XMLParser external entity resolution remains disabled.
  Every XML/relationship member is preflighted, including unused parts.
- Text: the body uses exact decoded text nodes, explicit tabs/line breaks and
  deterministic paragraph separators. XML itself normalizes source CR/CRLF according
  to its specification. Word tables and text boxes flatten in XML order, not a claim
  of visual reading order. Nested paragraph boundaries are explicit. Formatting,
  headers/footers, comments, page layout and images are not imported; warnings remain
  visible with provenance. Fields, tracked changes, content controls, alternative
  content, embedded objects and other ambiguous/active structures fail closed.
- Output: at most 256 KiB UTF-8. Over-limit data is rejected, never truncated.
  Line citations refer to the extracted body, not Word pages or semantic clauses.

If an ordinary DOCX uses an unsupported feature, resolve it in the source or export
verified UTF-8 text. A supported subset is preferable to silently dropping an
unreviewed contractual or creative requirement.

## PDF remains disabled

Both the file-reader entry point and extraction helper reject `.pdf` before any
PDF parser is called, and PDF is absent from the picker. Legacy `.doc`, images and
OCR are also unsupported. Export verified UTF-8 text or a supported DOCX instead.

PDFKit's `PDFDocument(data:)` and `page.string` are synchronous native parsing calls.
Checking file size, page count and extracted length afterward cannot bound their
internal memory/time cost or interrupt hostile compressed object graphs. A safe
new PDF path needs a separately isolated parser with tested resource/cancellation
behavior before it is enabled. No new PDFKit extractor or success fixtures remain
in this slice. The unrelated existing screenplay PDF importer is unchanged.

## Cancellation, concurrency and persistence

The source reader permits only one active read/extraction app-wide through a
nonblocking admission lock. New attempts while it is busy fail promptly. Parsing
checks cancellation at entry, archive members and XML boundaries. Cancel/close
invalidates the preview token, so late results cannot publish or persist. No network
operation, account, consent to share, or paid capability is involved.

The campaign working draft permits 1 MiB of retained extracted source bytes,
4 MiB of retained original-document bytes, 32 revisions and 256 reviews/citations
each. Baselines duplicate pinned evidence and the existing 16 MiB ledger cap can
therefore be reached earlier. Failed persistence leaves the saved state active.
These are prototype limits, not a large document archive or full crash-durability
claim. Native main-thread save/validation latency still needs measurement.

The optional original-provenance field is omitted for old text revisions. Old v1
ledgers retain their JSON shape and no screenplay schema migration occurs. Unknown
fields, unsupported extractor versions, mismatched hashes or extracted-text binding
fail closed. Neither provenance nor historical decisions are cryptographic signatures.

Backup restore and normal ledger reads now share a descriptor-bound limit+1 reader,
with nonregular-file/symlink rejection and post-read consistency checks. The store's
cooperating lock/byte lease and owner-only staged replacement remain in place. This
is not a defense against a malicious same-user filesystem actor or cross-device sync.

## Validation and remaining gates

Automated fixtures cover normal stored/deflated DOCX, Unicode and whitespace,
tables/textboxes, nested paragraphs, declarations/DTDs/entities, external links,
unsupported content, malformed/CRC/traversal/ZIP64/nonregular archives, inflation
limits, cancellation, original/extracted-byte persistence, old ledger compatibility,
review invalidation, undo, source preservation and bounded backup reads. All fixtures
are synthetic; no user agency documents or credentials are published.

Before release, test actual agency DOCX samples, reading order against Word,
interrupted picker/read/preview flows, repeated cancellation, tab switch/close/reopen,
review/citation revisions, Save Retained Original, backup/restore and laptop/keyboard/
accessibility behavior. Unit tests do not establish those interactive outcomes.
