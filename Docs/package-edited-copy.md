# Native edited-copy persistence

`PackageEditedCopy` provides a macOS disk loader and new-copy writer for the minimal two-file profile accepted by `PackageTextSession`. It is not wired to a Mac editing screen, autosave, or Save menu yet. Existing converted project packages remain unsupported for editing.

The loader enumerates the complete directory and rejects every additional file or directory, including unknown companions and `.DS_Store`. It opens the package and its files without following final-component symlinks, rejects nonregular files and files above 32 MiB, then checks the same bytes again. The command layer validates editing eligibility. Unsupported files are never filtered out to obtain a writable subset.

Save receives the edited session and original source path. It compares the source against the session's original snapshot, updates only the manifest modification timestamp and screenplay text, and validates the resulting minimal profile. It creates a private sibling staging directory (0700) and exclusive files (0600). Writes handle short writes and interruptions. Each file uses `fsync` and macOS `F_FULLFSYNC`; the stage directory is synchronized before publication. Unsupported flush behavior fails rather than silently downgrading the operation.

Staged bytes are compared against the complete candidate and reopened through the loader. The source is rechecked. `renamex_np` with `RENAME_EXCL` publishes to a new destination atomically without replacing an existing directory, file, or symlink. The parent directory is synchronized; published files are reread, compared, and reopened. A final source comparison precedes success. A destination inside the source package, or equal to it, is rejected before staging.

Any failure after staging starts returns the failure phase, retained recovery path, and whether publication occurred. Partial stages remain partial; they are not advertised as verified packages. Published copies remain available even if the final check fails. No automatic deletion, rollback, or overwrite occurs. The original package is never written by this adapter.

The returned receipt includes destination, the local session revision, and SHA-256 values for both saved files. These are verification results, not persisted project revision ancestry. Minimal packages have no project envelope; adding a `project.json` inventory, object revisions, or provenance would require a richer supported profile. Those records are deliberately not fabricated here.

## Verification and limits

Tests exercise new-copy reopen, Unicode text and stable identity through an independent Foundation projection, exact unchanged source bytes, receipt hashes, injected failures at seven transaction boundaries, source changes before publication, competing destination creation, corrupt staged readback, unknown files, symlink packages, and nested destinations. Injection is in-process fault testing, not a simulated power cut or proof of all filesystem/hardware behavior.

Source comparisons detect observed changes; they are not an exclusive lock or a guarantee against a malicious process racing directory paths. Intermediate source path components are resolved by the operating system. The caller must use a trusted local location. Crash recovery retains the untouched original and staged/published output; there is no recovery browser or automatic retry yet.

Next work is a minimal-package editing UI with an explicit Save Edited Copy action and visible recovery errors. Rich project editing still requires adapters for locks, references, unknown semantics, project/object revisions, and inventory coherence. This writer must not be extended by dropping those records.
