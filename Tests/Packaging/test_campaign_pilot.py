"""Portable checks of the synthetic pilot generator, not native UI acceptance."""
from __future__ import annotations

import base64
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "Scripts/prepare-campaign-pilot.py"
pilot = types.ModuleType("campaign_pilot")
pilot.__file__ = str(SCRIPT)
exec(compile(SCRIPT.read_bytes(), str(SCRIPT), "exec"), pilot.__dict__)


class CampaignPilotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.corpus = json.loads((ROOT / pilot.CORPUS).read_text())
        cls.payloads, cls.manifest = pilot.prepare_payloads(ROOT)

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        # macOS's /var and /tmp are symlinks; supply the real temporary parent.
        self.directory = Path(self.temporary.name).resolve()

    def test_exact_five_accepted_originals_and_text_without_normalization(self):
        docs = {name for name in self.payloads if name.startswith("documents/")}
        self.assertEqual(docs, {"documents/" + name + ".docx" for name in pilot.ACCEPTED})
        self.assertEqual(len(self.payloads), 13)
        for row in self.corpus["fixtures"]:
            if row["expectedFailure"] is not None:
                self.assertNotIn("documents/" + row["filename"], self.payloads)
                continue
            original = self.payloads["documents/" + row["filename"]]
            expected = self.payloads["expected/" + row["name"] + ".txt"]
            self.assertEqual(original, base64.b64decode(row["originalBase64"], validate=True))
            self.assertEqual(expected, row["expectedText"].encode("utf-8"))
            self.assertEqual(hashlib.sha256(original).hexdigest(), row["originalSHA256"])
            self.assertEqual(hashlib.sha256(expected).hexdigest(), row["extractedSHA256"])
            self.assertEqual(len(expected.split(b"\n")), row["expectedLineCount"])
            self.assertFalse(expected.endswith(b"\n"))
        self.assertIn("Cafe\u0301".encode(), self.payloads["expected/brief-v1.txt"])

    def test_metadata_only_original_changes_but_body_is_identical(self):
        self.assertNotEqual(self.payloads["documents/deliverables-v2.docx"],
                            self.payloads["documents/deliverables-v2-metadata-only.docx"])
        self.assertEqual(self.payloads["expected/deliverables-v2.txt"],
                         self.payloads["expected/deliverables-v2-metadata-only.txt"])

    def test_manifest_covers_all_payloads_and_exact_source_commit(self):
        manifest = json.loads(self.payloads["manifest.json"])
        self.assertEqual(manifest, self.manifest)
        self.assertEqual(manifest["sourceCommit"], subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip())
        self.assertIs(type(manifest["sourceDirty"]), bool)
        self.assertEqual(manifest["acceptedDocumentCount"], 5)
        self.assertEqual(len(manifest["documents"]), 5)
        self.assertIn("not asserted", manifest["verification"])
        self.assertEqual({row["path"] for row in manifest["files"]},
                         set(self.payloads) - {"manifest.json"})
        for row in manifest["files"]:
            value = self.payloads[row["path"]]
            self.assertEqual(row["bytes"], len(value))
            self.assertEqual(row["sha256"], hashlib.sha256(value).hexdigest())
        inputs = {row["path"] for row in manifest["sourceFiles"]}
        self.assertTrue({pilot.CORPUS, pilot.CHECKER, pilot.WALKTHROUGH, pilot.LINE_MAP,
                         "Scripts/prepare-campaign-pilot.py"}.issubset(inputs))
        for row in manifest["sourceFiles"]:
            value = (ROOT / row["path"]).read_bytes()
            self.assertEqual(row["bytes"], len(value))
            self.assertEqual(row["sha256"], hashlib.sha256(value).hexdigest())

    def test_line_map_and_walkthrough_are_exact_checked_in_bytes(self):
        self.assertEqual(self.payloads["expected-lines.txt"], (ROOT / pilot.LINE_MAP).read_bytes())
        self.assertEqual(self.payloads["walkthrough.md"], (ROOT / pilot.WALKTHROUGH).read_bytes())

    def test_rejected_payloads_are_never_base64_decoded(self):
        original_decode = base64.b64decode
        with mock.patch.object(pilot.base64, "b64decode", wraps=original_decode) as decode:
            result = pilot.validate_accepted(self.corpus)
        self.assertEqual(len(result), 5)
        self.assertEqual(decode.call_count, 5)
        self.assertEqual([call.args[0] for call in decode.call_args_list],
                         [row["originalBase64"] for row in self.corpus["fixtures"][:5]])

    def test_rejects_invalid_base64_hash_text_line_count_and_filename(self):
        changes = (
            ("originalBase64", "not base64!"), ("originalBase64", ""),
            ("originalBase64", self.corpus["fixtures"][0]["originalBase64"] + "\n"),
            ("originalSHA256", "0" * 64), ("originalSHA256", "A" * 64),
            ("extractedSHA256", "0" * 64), ("expectedText", "altered"),
            ("expectedLineCount", 999), ("expectedLineCount", True),
            ("filename", "../brief-v1.docx"), ("filename", "/brief-v1.docx"),
            ("filename", "nested/brief-v1.docx"), ("filename", "brief-v1.exe"),
            ("filename", "..\\brief-v1.docx"), ("filename", "brief-v1.docx\x00"),
            ("originalBase64", "A" * (pilot.MAX_ORIGINAL * 2)),
            ("expectedText", "x" * (pilot.MAX_TEXT + 1)),
        )
        for field, value in changes:
            with self.subTest(field=field, value=str(value)[:40]):
                corpus = copy.deepcopy(self.corpus)
                corpus["fixtures"][0][field] = value
                with self.assertRaises(ValueError):
                    pilot.validate_accepted(corpus)

    def test_rejects_unexpected_accepted_ids_duplicate_ids_and_missing_ids(self):
        for mode in ("promoted rejection", "renamed accepted", "duplicate", "missing", "rejected accepted"):
            with self.subTest(mode=mode):
                corpus = copy.deepcopy(self.corpus)
                if mode == "promoted rejection":
                    corpus["fixtures"][5]["expectedFailure"] = None
                elif mode == "renamed accepted":
                    corpus["fixtures"][0]["name"] = "new-unreviewed-file"
                elif mode == "duplicate":
                    corpus["fixtures"].append(copy.deepcopy(corpus["fixtures"][0]))
                elif mode == "missing":
                    corpus["fixtures"].pop(0)
                else:
                    corpus["fixtures"][0]["expectedFailure"] = "unsafeArchive"
                corpus["fixtureCount"] = len(corpus["fixtures"])
                with self.assertRaises(ValueError):
                    pilot.validate_accepted(corpus)

    def test_rejects_duplicate_json_keys(self):
        with self.assertRaisesRegex(ValueError, "Duplicate JSON"):
            json.loads('{"version": 1, "version": 2}', object_pairs_hook=pilot.unique_object)

    def test_rejects_changed_original_even_if_attacker_updates_its_hash(self):
        # A digest alone would accept arbitrary bytes. The independent checked-in
        # XML/oracle reconstruction must reject this self-consistent alteration.
        root = self.directory / "checkout"
        (root / "Scripts").mkdir(parents=True)
        shutil.copyfile(ROOT / pilot.CHECKER, root / pilot.CHECKER)
        shutil.copytree(ROOT / "Tests/Fixtures/CampaignAgency", root / "Tests/Fixtures/CampaignAgency")
        corpus = copy.deepcopy(self.corpus)
        changed = b"not a DOCX; hashes alone must not establish acceptance"
        corpus["fixtures"][0]["originalBase64"] = base64.b64encode(changed).decode()
        corpus["fixtures"][0]["originalSHA256"] = hashlib.sha256(changed).hexdigest()
        (root / pilot.CORPUS).write_text(json.dumps(corpus, ensure_ascii=False, indent=2) + "\n")
        with self.assertRaisesRegex(ValueError, "independently validated"):
            pilot.prepare_payloads(root)
        self.assertFalse((root / "documents").exists())

    def test_new_directory_writes_only_the_expected_private_files(self):
        output = self.directory / "pilot"
        self.assertEqual(pilot.write_new_directory(output, self.payloads), output)
        actual = {path.relative_to(output).as_posix() for path in output.rglob("*") if path.is_file()}
        self.assertEqual(actual, set(self.payloads))
        for name, value in self.payloads.items():
            self.assertEqual((output / name).read_bytes(), value)
            self.assertEqual(stat.S_IMODE((output / name).stat().st_mode) & 0o077, 0)
        self.assertEqual(stat.S_IMODE(output.stat().st_mode) & 0o077, 0)

    def test_existing_destination_is_never_changed_even_if_empty(self):
        empty, occupied, regular = (self.directory / name for name in ("empty", "occupied", "file"))
        empty.mkdir()
        occupied.mkdir()
        (occupied / "keep.txt").write_bytes(b"keep")
        regular.write_bytes(b"original")
        for path in (empty, occupied, regular):
            with self.subTest(path=path.name), self.assertRaises(FileExistsError):
                pilot.write_new_directory(path, self.payloads)
        self.assertEqual(list(empty.iterdir()), [])
        self.assertEqual((occupied / "keep.txt").read_bytes(), b"keep")
        self.assertEqual(regular.read_bytes(), b"original")

    def test_rejects_destination_symlinks_and_parent_symlinks(self):
        target = self.directory / "target"
        target.mkdir()
        live = self.directory / "live-link"
        dead = self.directory / "dead-link"
        live.symlink_to(target, target_is_directory=True)
        dead.symlink_to(self.directory / "does-not-exist", target_is_directory=True)
        for path in (live, dead, live / "pilot", live / "nested" / "pilot"):
            with self.subTest(path=path), self.assertRaises(OSError):
                pilot.write_new_directory(path, self.payloads)
        self.assertEqual(list(target.iterdir()), [])
        self.assertTrue(dead.is_symlink())

    def test_rejects_missing_parent_traversal_and_unexpected_output_paths(self):
        for path in (self.directory / "absent" / "pilot", self.directory / ".." / "pilot", Path(".")):
            with self.subTest(path=path), self.assertRaises((OSError, ValueError)):
                pilot.write_new_directory(path, self.payloads)
        payloads = dict(self.payloads)
        payloads["../escape.txt"] = b"unsafe"
        with self.assertRaisesRegex(ValueError, "Unexpected pilot output"):
            pilot.write_new_directory(self.directory / "pilot", payloads)
        self.assertFalse((self.directory / "pilot").exists())

    def test_unexpected_file_during_write_is_not_overwritten_or_cleaned_up(self):
        output = self.directory / "pilot"
        real_mkdir = os.mkdir

        def inject_file(path, *args, **kwargs):
            result = real_mkdir(path, *args, **kwargs)
            if path == "documents":
                (output / "documents/brief-v1.docx").write_bytes(b"unexpected writer")
            return result

        with mock.patch.object(pilot.os, "mkdir", side_effect=inject_file):
            with self.assertRaises(FileExistsError):
                pilot.write_new_directory(output, self.payloads)
        self.assertEqual((output / "documents/brief-v1.docx").read_bytes(), b"unexpected writer")
        self.assertFalse((output / "manifest.json").exists())

    def test_failed_payload_write_leaves_no_completion_manifest(self):
        output = self.directory / "pilot"
        with mock.patch.object(pilot.os, "fsync", side_effect=OSError("injected write failure")):
            with self.assertRaisesRegex(OSError, "injected write failure"):
                pilot.write_new_directory(output, self.payloads)
        self.assertTrue(output.is_dir())
        self.assertFalse((output / "manifest.json").exists())
        # A later retry cannot turn an unreviewed partial folder into a full kit.
        with self.assertRaises(FileExistsError):
            pilot.write_new_directory(output, self.payloads)

    def test_reader_rejects_symlink_fifo_directory_and_oversized_input(self):
        regular, link, fifo = (self.directory / name for name in ("regular", "link", "fifo"))
        regular.write_bytes(b"test")
        link.symlink_to(regular)
        os.mkfifo(fifo)
        self.assertEqual(pilot.read_regular(regular, 4), b"test")
        for path, maximum in ((regular, 3), (link, 4), (fifo, 4), (self.directory, 4)):
            with self.subTest(path=path), self.assertRaises((OSError, ValueError)):
                pilot.read_regular(path, maximum)

    def test_cli_creates_once_and_refuses_second_run_without_modification(self):
        output = self.directory / "cli-pilot"
        command = [sys.executable, str(SCRIPT), "--output", str(output)]
        first = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertIn("Prepared 5 synthetic DOCX", first.stdout)
        before = {path.relative_to(output): path.read_bytes() for path in output.rglob("*") if path.is_file()}
        second = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(second.returncode, 0)
        after = {path.relative_to(output): path.read_bytes() for path in output.rglob("*") if path.is_file()}
        self.assertEqual(before, after)
        self.assertEqual(len(after), 13)


if __name__ == "__main__":
    unittest.main()
