# Read-only legacy inspector

The first migration tool is available as a standalone Python 3 script using only the standard library. It does not import the application, change preferences, normalize scenes, rebuild edits, assign IDs, convert files, or write an output file. The existing `screenplay-inspect` Swift executable remains an FDX inspection tool; this new script handles legacy monolithic JSON only.

From the repository:

```sh
python3 Scripts/inspect-legacy.py /absolute/path/to/project.open-screenplay.json
```

The JSON report is printed to standard output. Exit 0 means no blockers were found by the implemented checks, **not** that the file is conformant or safe to migrate. Exit 1 means inspection found blockers; exit 2 means input could not be read. Packages and FDX are outside this tool's scope.

The report includes:

- Source byte count and SHA-256, detected legacy shape, and a second-read byte comparison.
- Every parsed value's JSON Pointer, type, and known/unmapped versus opaque-preservation disposition.
- Known record UUIDs, duplicate/invalid identity risks, project/screenplay linkage, scene-alias ambiguity, and selected UUID/scene-reference resolution.
- Missing required fields and basic type/enum/declaration checks against the repository's legacy schema.
- Unknown-field/type warnings and production-lock preservation warnings.
- Explicit confirmation that editorial records were inspected raw rather than regenerated.

Script text, notes, and prompts are not emitted as values. Reports still contain object IDs and JSON keys/paths, including user-defined keys; treat reports as local project metadata. There are no network operations. A second read detects changes during that interval, not future changes or an exclusive file lock.

Numbers remain exact lexical tokens in the raw tree, including large integers and high-precision exponents. No floating-point conversion occurs. Duplicate keys (including equivalent escaped key spellings), non-JSON numeric constants, invalid UTF-8, and unpaired Unicode surrogates are rejected. Unknown subtrees are inspected without guessing creative identity from arbitrary `id` keys. The optional mapping layer supplies a tested raw JSON preservation encoder and reconstruction checks. It does not supply a package writer or establish a complete migration round trip.

## Current limitations

This is a risk inventory, not a complete JSON Schema validator or migration plan. It does not check every schema constraint, date, range, source type, cross-record semantic relationship, package path, asset, or conflict. The legacy schema itself does not describe every current optional field; such fields are conservatively reported as unknown, never discarded. Duplicate creative UUIDs are conservatively blocked. Ambiguous scene aliases require explicit repair. Missing historical references remain unresolved instead of being reattached.

All known fields remain marked unmapped: no target payload schemas, identity assignments, conversion, or lossless claim are supplied. The application still uses its existing save path. The in-memory preservation and initial field-mapping layer is now implemented; see `legacy-field-mapping.md` and use `--mapping`. Complete active target schemas and transformations remain unfinished before any converted-copy writer.

## Verification

Eight automated tests cover empty/Unicode scripts, malformed/duplicate JSON, exact numeric tokens and unknown data, dialect detection, duplicate identities/ambiguous aliases, invalid/missing links, raw editorial/lock data, and the command-line read-only behavior. CLI tests verify unchanged bytes, unchanged modification time, and no new files in the input directory, including read-only input files. These tests run at the start of `Scripts/test.sh` and independently with:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/LegacyInspector -v
```

## Destination validation

Use `--candidate` to validate draft payloads and stable scene/reference mappings in memory; see `legacy-destination-candidate.md`. This optional mode requires the dependency in `Scripts/requirements-inspector.txt`. It prints metadata only and never enables conversion or writes a package.
