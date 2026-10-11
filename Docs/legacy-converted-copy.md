# Experimental converted-copy writer

**Status:** Implemented for macOS, new destinations only. Uses the unreleased legacy destination profile. The native app can inspect verified screenplay and board content read-only, but cannot edit these packages; its current Save workflow is unchanged.

From the repository, with the dependency in `Scripts/requirements-inspector.txt` available:

```sh
python3 Scripts/convert-legacy-copy.py convert /absolute/path/original.json /absolute/path/NewCopy.screenplay
python3 Scripts/convert-legacy-copy.py verify /absolute/path/NewCopy.screenplay
```

Conversion creates a new package only. An existing file, directory, or symlink at the destination is rejected. The parent directory must already exist. The source is opened read-only and is never rewritten, renamed, or removed. No network, account, app preferences, or active-document state is involved. These commands are not invoked on user documents by the test suite.

## Commit sequence

1. Read the source as a regular file without following a final symlink; construct and validate the candidate in memory.
2. Create a private, randomly named `.screenplay-conversion-*` staging directory beside the intended destination.
3. Write each payload exclusively, flush its buffers, and request macOS `F_FULLFSYNC`. Unsupported durability operations fail rather than silently weakening the procedure.
4. Store the **exact original source bytes** in `provenance/source.json` and candidate identity/mapping metadata in `provenance/candidate.json`. These are migration records, not additional live screenplay authorities; never include them in future scoped review uploads by default.
5. Sync staging directories and read the package back from disk alone. Verify file membership, hashes, schema, source digest, and the deterministic transformation.
6. Reread the original source. If its bytes changed, retain the stage and stop.
7. Publish with macOS `renamex_np(..., RENAME_EXCL)`, which rejects a destination created by another writer during staging. This is a same-parent, same-filesystem publication, not a replace-existing operation.
8. Sync the parent directory, verify the published package again, and reread the source before reporting success.

A successful result reports the verified revision and destination, plus `app_editing_supported: false`. Candidate `conversion_ready: false` still means the new format is not ready for the app's normal migration/editing workflow; it does not prevent this explicitly requested experimental copy operation.

## Readback and recovery

`read_copy` loads files from the retained package without the original file path or an in-memory candidate. It rejects symlinks, case-colliding paths, unexpected or missing files, unsafe inventory paths, mismatched byte hashes/sizes, invalid payloads, stale source identity, and changed transformation results. It uses the schema and mapping validator as shared verification code; it is independent disk readback, not a separately implemented third-party conformance reader.

On an ordinary failure after staging starts, the CLI returns a nonzero exit status and reports the phase, retained path, whether publication occurred, and error class. It never reports success after a failed durability or readback operation. Complete and incomplete retained stages are left in place; nothing is automatically deleted or promoted. An incomplete stage fails `verify`. A completed stage or published package may pass `verify`, but verification does not retroactively claim that an earlier failed durability operation succeeded.

After abrupt process termination, there may be no diagnostic output. Inspect the destination and the sibling `.screenplay-conversion-*` directory from that attempt; run `verify` before treating either as a valid copy. The original file remains available. Recovery is deliberately explicit: there is no automatic scanning, cleanup, or overwrite operation.

## Evidence and limitations

41 focused Python tests pass, including writer and packaged-media tests. Tests cover successful conversion and disk-only readback, byte-exact source archival, existing destinations, a competing destination created immediately before publication, failures at ten checkpoints, partial writes, directory-sync failures before and after publication, outside source edits, corrupt/missing/unsafe files, CLI behavior, subprocess termination during staging and before/after publication, and board-image relocation and corruption. Input bytes and modification times remain unchanged except in tests that deliberately simulate an external source edit.

This verifies process interruption and injected I/O failures on the current development filesystem. It is not physical power-loss testing, a guarantee for every filesystem/device, or protection against a hostile process swapping ancestor directories. Source rereads detect changes over those intervals; they are not a file lock and cannot prevent later edits. The writer currently supports macOS only and does not overwrite existing packages.

Production locks, legacy offsets, unknown/service fields, and historical metadata retain the destination profile's existing limits. The immutable source archive preserves them, but does not make lock-aware editing or print output conformant. Legacy board PNG versions now receive a validated `film/media.json` registry and content-addressed attachments when every referenced image is present and hash-valid. Missing or unsafe board media blocks the copy rather than producing a falsely complete archive. Other media, revision retention/merge, signing, and format release remain unimplemented.

## Native read-only preview

The Mac app now opens a verified converted package in a separate read-only preview. It displays exact screenplay paragraph text, scene navigation, board order and duration, every packaged take, the selected take, and its model label. It rechecks the revision inventory, package membership, project identity, board/version identity and order, selection, metadata, hashes, byte counts, PNG dimensions, and attachment references before displaying anything. Closing the preview restores the unchanged editable document underneath; Save and autosave do not target the preview.

The next application step is an explicit **Save Converted Copy…** command with a user-selected new destination and a conversion report. It must retain the active legacy document and must not enable editing of the converted package. Editable package adoption remains blocked on recovery, fidelity, and feature-completeness work.
