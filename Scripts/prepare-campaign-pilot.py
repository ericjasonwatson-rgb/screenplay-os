#!/usr/bin/env python3
"""Materialize the five accepted synthetic Campaign DOCX fixtures for a local pilot.

Standard library only. No app, user documents, network, ZIP extraction, or fixture
rewrites. The destination must be absent under existing, nonsymlink directories.
"""
from __future__ import annotations

import argparse
import base64
import binascii
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import types

ROOT = Path(__file__).resolve().parents[1]
CORPUS = "Tests/Fixtures/CampaignAgency/corpus.json"
CHECKER = "Scripts/check-campaign-agency-fixtures.py"
WALKTHROUGH = "Docs/campaign-pilot-walkthrough.md"
LINE_MAP = "Tests/Fixtures/CampaignAgency/expected-lines.txt"
ACCEPTED = (
    "brief-v1", "deliverables-v1", "production-memo-v1",
    "deliverables-v2", "deliverables-v2-metadata-only",
)
MAX_INPUT = 1024 * 1024
MAX_ORIGINAL = 256 * 1024
MAX_TEXT = 64 * 1024


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_regular(path: Path, maximum: int = MAX_INPUT) -> bytes:
    """Bounded descriptor read, including nonregular and changed-file checks."""
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as stream:
        before = os.fstat(stream.fileno())
        if not stat.S_ISREG(before.st_mode) or before.st_size > maximum:
            raise ValueError(f"Input is not a bounded regular file: {path.name}")
        data = stream.read(maximum + 1)
        after = os.fstat(stream.fileno())
        signature = lambda info: (info.st_size, info.st_mtime_ns, info.st_ctime_ns)
        if len(data) > maximum or len(data) != before.st_size or signature(before) != signature(after):
            raise ValueError(f"Input changed or exceeds its limit: {path.name}")
        return data


def unique_object(pairs: list[tuple]) -> dict:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON key: {key}")
        result[key] = value
    return result


def validate_accepted(data: dict) -> list[tuple[dict, bytes, bytes]]:
    """Decode only fixed accepted IDs; rejected originals are never decoded."""
    if (not isinstance(data, dict) or type(data.get("version")) is not int
            or data["version"] != 1 or data.get("synthetic") is not True
            or not isinstance(data.get("fixtures"), list)
            or type(data.get("fixtureCount")) is not int
            or data["fixtureCount"] != len(data["fixtures"])):
        raise ValueError("Unsupported synthetic corpus metadata")
    rows = {}
    for row in data["fixtures"]:
        if not isinstance(row, dict) or not isinstance(row.get("name"), str):
            raise ValueError("Invalid fixture record")
        name = row["name"]
        if name in rows:
            raise ValueError("Duplicate fixture ID")
        rows[name] = row
        if ("expectedFailure" not in row
                or (row["expectedFailure"] is None) != (name in ACCEPTED)):
            raise ValueError("Only the fixed accepted fixture IDs may enter a pilot")
    if not set(ACCEPTED).issubset(rows):
        raise ValueError("The five accepted fixture IDs are required")
    result = []
    for name in ACCEPTED:
        row = rows[name]
        if row.get("filename") != name + ".docx":
            raise ValueError("Fixture filename must be its fixed safe DOCX basename")
        encoded, expected = row.get("originalBase64"), row.get("expectedText")
        if (not isinstance(encoded, str) or len(encoded) > 4 * ((MAX_ORIGINAL + 2) // 3)
                or not isinstance(expected, str)):
            raise ValueError("Fixture bytes or text are invalid or oversized")
        original = base64.b64decode(encoded, validate=True)
        text = expected.encode("utf-8")
        if (not original or len(original) > MAX_ORIGINAL or len(text) > MAX_TEXT
                or base64.b64encode(original).decode("ascii") != encoded):
            raise ValueError("Original bytes must have bounded canonical base64")
        for key, value in (("originalSHA256", original), ("extractedSHA256", text)):
            if not isinstance(row.get(key), str) or not re.fullmatch(r"[0-9a-f]{64}", row[key]):
                raise ValueError("Invalid fixture SHA-256")
            if sha256(value) != row[key]:
                raise ValueError(f"Fixture hash mismatch: {name} / {key}")
        if (type(row.get("expectedLineCount")) is not int
                or row["expectedLineCount"] != len(expected.split("\n"))):
            raise ValueError("Exact extracted line count mismatch")
        result.append((row, original, text))
    return result


def prepare_payloads(root: Path) -> tuple[dict[str, bytes], dict]:
    """Validate checked-in corpus against independently authored XML/text oracles."""
    inputs = {}

    def capture(path: Path, maximum: int = MAX_INPUT) -> bytes:
        value = read_regular(path, maximum)
        relative = path.relative_to(root).as_posix()
        if relative in inputs and inputs[relative] != value:
            raise ValueError(f"Source changed during validation: {relative}")
        inputs[relative] = value
        return value

    raw = capture(root / CORPUS)
    data = json.loads(raw.decode("utf-8"), object_pairs_hook=unique_object)
    accepted = validate_accepted(data)
    # Execute only our checked-in checker, not content from the corpus. Setting
    # read_local records the exact source bytes checked and avoids .pyc writes.
    checker = types.ModuleType("campaign_fixture_checker")
    checker.__file__ = str(root / CHECKER)
    exec(compile(capture(root / CHECKER), checker.__file__, "exec"), checker.__dict__)
    checker.read_local = capture
    rebuilt = checker.corpus()
    canonical = (json.dumps(rebuilt, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if raw != canonical:
        raise ValueError("Corpus differs from independently validated source/oracle bytes")
    line_map = capture(root / LINE_MAP)
    if line_map != checker.render_line_map(rebuilt):
        raise ValueError("Checked-in line map differs from the exact extracted text")
    payloads = {}
    documents = []
    for row, original, expected in accepted:
        document_path = "documents/" + row["filename"]
        text_path = "expected/" + row["name"] + ".txt"
        payloads[document_path] = original
        payloads[text_path] = expected  # No added newline or Unicode normalization.
        documents.append({
            "id": row["name"], "document": document_path, "expectedText": text_path,
            "originalSHA256": row["originalSHA256"],
            "extractedSHA256": row["extractedSHA256"],
            "expectedLineCount": row["expectedLineCount"],
        })
    payloads["expected-lines.txt"] = line_map
    payloads["walkthrough.md"] = capture(root / WALKTHROUGH)
    capture(root / "Scripts/prepare-campaign-pilot.py")
    revision = subprocess.check_output(
        ["git", "rev-parse", "--verify", "HEAD"], cwd=root, text=True).strip()
    if not re.fullmatch(r"(?:[0-9a-f]{40}|[0-9a-f]{64})", revision):
        raise ValueError("Cannot identify the exact source commit")
    dirty = bool(subprocess.check_output(
        ["git", "status", "--porcelain", "--untracked-files=all"], cwd=root, text=True))
    manifest = {
        "version": 1, "synthetic": True, "acceptedDocumentCount": len(documents),
        "sourceCommit": revision, "sourceDirty": dirty,
        "verification": "Fixture bytes checked locally; native app and CI results not asserted.",
        "documents": documents,
        "sourceFiles": [{"path": name, "bytes": len(value), "sha256": sha256(value)}
                        for name, value in sorted(inputs.items())],
        "files": [{"path": name, "bytes": len(value), "sha256": sha256(value)}
                  for name, value in sorted(payloads.items())],
        "manifestNote": "files hashes every generated payload except this manifest itself. "
                        "Hashes identify bytes, not authenticity, a signature or approval.",
    }
    payloads["manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    return payloads, manifest


def open_directory(path: Path) -> int:
    """Walk existing directories without following even intermediate symlinks."""
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    fd = os.open(path.anchor, flags)
    try:
        for part in path.parts[1:]:
            child = os.open(part, flags, dir_fd=fd)
            os.close(fd)
            fd = child
        return fd
    except BaseException:
        os.close(fd)
        raise


def write_new_directory(destination: Path, payloads: dict[str, bytes]) -> Path:
    """Exclusive writes under a new 0700 directory; never replace or merge files.

    A failed write leaves an incomplete directory, never a completed manifest.
    There is deliberately no recursive cleanup of unexpected user-visible state.
    This is local fixture tooling, not a sandbox against malicious same-user races.
    """
    expected = {"manifest.json", "walkthrough.md", "expected-lines.txt"}
    expected.update("documents/" + name + ".docx" for name in ACCEPTED)
    expected.update("expected/" + name + ".txt" for name in ACCEPTED)
    if set(payloads) != expected or any(not isinstance(value, bytes) for value in payloads.values()):
        raise ValueError("Unexpected pilot output set")
    if ".." in destination.parts or not destination.name or destination == Path("."):
        raise ValueError("Choose a new named directory, without parent traversal")
    destination = Path(os.path.abspath(destination))
    parent_fd = open_directory(destination.parent)
    output_fd = None
    try:
        os.mkdir(destination.name, 0o700, dir_fd=parent_fd)
        output_fd = os.open(destination.name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent_fd)
        for directory in ("documents", "expected"):
            os.mkdir(directory, 0o700, dir_fd=output_fd)
        # Manifest is the completion marker and is written only after all payloads.
        names = sorted(set(payloads) - {"manifest.json"}) + ["manifest.json"]
        for name in names:
            relative = Path(name)
            target_fd = output_fd
            if relative.parent != Path("."):
                target_fd = os.open(str(relative.parent), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=output_fd)
            try:
                fd = os.open(relative.name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=target_fd)
                with os.fdopen(fd, "wb") as stream:
                    stream.write(payloads[name])
                    stream.flush()
                    os.fsync(stream.fileno())
            finally:
                if target_fd != output_fd:
                    os.close(target_fd)
    finally:
        if output_fd is not None:
            os.close(output_fd)
        os.close(parent_fd)
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path, help="New absent directory; its parent must already exist")
    args = parser.parse_args()
    try:
        payloads, manifest = prepare_payloads(ROOT)
        destination = write_new_directory(args.output, payloads)
    except (OSError, ValueError, binascii.Error, subprocess.SubprocessError) as error:
        print(f"Pilot not prepared: {error}", file=sys.stderr)
        print("Existing paths are never replaced. If a write failed, do not use partial output; choose a new directory.", file=sys.stderr)
        return 1
    print(f"Prepared 5 synthetic DOCX files in {destination}")
    print(f"Source commit: {manifest['sourceCommit']} (dirty: {str(manifest['sourceDirty']).lower()})")
    print("Read walkthrough.md. No app was opened or built; no screenplay or campaign state was changed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
