import errno
import base64
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from test_destination import ROOT, rich

spec = importlib.util.spec_from_file_location('legacy_copy', ROOT / 'Scripts/legacy_copy.py')
writer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(writer)


@unittest.skipUnless(sys.platform == 'darwin', 'exclusive publication is macOS-only')
class CopyTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.source = self.root / 'original.json'
        self.data = json.dumps(rich(), indent=3).encode() + b'\n'
        self.source.write_bytes(self.data)
        self.source.chmod(0o444)
        self.modified = self.source.stat().st_mtime_ns
        self.target = self.root / 'converted.screenplay'

    def unchanged(self):
        self.assertEqual(self.source.read_bytes(), self.data)
        self.assertEqual(self.source.stat().st_mtime_ns, self.modified)

    def test_copy_reads_back_independently_and_archives_exact_original_bytes(self):
        result = writer.write_copy(self.source, self.target)
        self.assertTrue(result['verified'])
        self.assertFalse(result['app_editing_supported'])
        self.assertTrue(writer.read_copy(self.target)['verified'])
        self.assertEqual((self.target/'provenance/source.json').read_bytes(), self.data)
        self.assertEqual(set(self.root.iterdir()), {self.source, self.target})
        self.unchanged()

    def test_board_media_is_packaged_deduplicated_relocated_and_verified(self):
        png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
        digest = hashlib.sha256(png).hexdigest()
        folder = self.root / 'Board Images'; folder.mkdir(); image = folder / 'take.png'; image.write_bytes(png)
        value = rich(); board = value['board_frames'][0]
        board['image_versions'] = [
            {'id': '00000000-0000-4000-8000-000000000061', 'fileURL': 'Board%20Images/take.png',
             'sha256': digest, 'prompt': 'Wide', 'model': 'fixture'},
            {'id': '00000000-0000-4000-8000-000000000062', 'fileURL': image.as_uri(),
             'sha256': digest, 'prompt': 'Again', 'model': 'fixture'}]
        board['selected_image_id'] = board['image_versions'][1]['id']
        self.source.chmod(0o644); self.data = json.dumps(value, indent=3).encode() + b'\n'; self.source.write_bytes(self.data)
        self.source.chmod(0o444); self.modified = self.source.stat().st_mtime_ns

        result = writer.write_copy(self.source, self.target)
        self.assertEqual(result['media_attachments'], 1)
        attachment = self.target / 'attachments' / 'boards' / (digest + '.png')
        self.assertEqual(attachment.read_bytes(), png)
        registry = json.loads((self.target / 'film/media.json').read_text())
        self.assertEqual(len(registry['media'][0]['versions']), 2)
        self.assertEqual(registry['media'][0]['selected_version_id'], board['selected_image_id'])
        relocated = self.root / 'relocated.screenplay'; self.target.rename(relocated)
        self.assertTrue(writer.read_copy(relocated)['verified'])
        attachment = relocated / 'attachments' / 'boards' / (digest + '.png')
        attachment.write_bytes(png + b'changed')
        with self.assertRaises(ValueError): writer.read_copy(relocated)
        self.unchanged()

    def test_existing_file_directory_and_symlink_are_not_replaced(self):
        for kind in ['file', 'directory', 'symlink']:
            target = self.root / (kind + '.screenplay')
            if kind == 'file': target.write_bytes(b'owned')
            elif kind == 'directory': target.mkdir()
            else: target.symlink_to(self.source)
            with self.assertRaises(FileExistsError): writer.write_copy(self.source, target)
            self.assertTrue(target.is_dir() if kind == 'directory' else target.exists())
        self.unchanged()

    def test_destination_race_uses_exclusive_publication(self):
        def race(phase, stage):
            if phase == 'before_publish':
                self.target.mkdir()
                (self.target/'owned.txt').write_text('other writer')
        with self.assertRaises(writer.CopyFailure) as failure:
            writer.write_copy(self.source, self.target, race)
        self.assertFalse(failure.exception.published)
        self.assertEqual((self.target/'owned.txt').read_text(), 'other writer')
        self.assertTrue(writer.read_copy(failure.exception.recovery_path)['verified'])
        self.unchanged()

    def test_failures_at_each_checkpoint_never_claim_success(self):
        phases = ['staging_created', 'write:manifest.json', 'write:screenplay.json',
                  'write:project.json', 'write:provenance/source.json', 'write:provenance/candidate.json',
                  'staged_readback', 'before_publish', 'published', 'published_readback']
        for i, stop in enumerate(phases):
            target = self.root / (str(i)+'.screenplay')
            def fail(phase, stage):
                if phase == stop: raise OSError(errno.ENOSPC, 'simulated disk full')
            with self.assertRaises(writer.CopyFailure) as result:
                writer.write_copy(self.source, target, fail)
            retained = Path(result.exception.recovery_path)
            self.assertTrue(retained.exists())
            self.assertEqual(result.exception.published, stop in ('published', 'published_readback'))
            if stop in ('staged_readback', 'before_publish', 'published', 'published_readback'):
                self.assertTrue(writer.read_copy(retained)['verified'])
            self.unchanged()

    def test_partial_write_and_sync_failure_leave_original_recoverable(self):
        def partial(path, data):
            path.write_bytes(data[:5])
            raise OSError(errno.ENOSPC, 'simulated mid-write failure')
        with patch.object(writer, '_write_new', partial):
            with self.assertRaises(writer.CopyFailure) as result: writer.write_copy(self.source, self.target)
        self.assertFalse(self.target.exists())
        with self.assertRaises((OSError, ValueError, KeyError)): writer.read_copy(result.exception.recovery_path)
        with patch.object(writer, '_sync_directory', side_effect=OSError(errno.EIO, 'sync failure')):
            with self.assertRaises(writer.CopyFailure): writer.write_copy(self.source, self.target)
        self.assertFalse(self.target.exists())
        original_sync = writer._sync_directory
        def fail_parent(path):
            if Path(path).resolve() == self.root.resolve():
                raise OSError(errno.EIO, 'parent durability failure after publication')
            return original_sync(path)
        with patch.object(writer, '_sync_directory', fail_parent):
            with self.assertRaises(writer.CopyFailure) as result:
                writer.write_copy(self.source, self.target)
        self.assertTrue(result.exception.published)
        self.assertTrue(writer.read_copy(self.target)['verified'])
        self.unchanged()

    def test_source_change_prevents_publication(self):
        def alter(phase, stage):
            if phase == 'before_publish':
                self.source.chmod(0o644)
                self.source.write_bytes(self.data+b' ')
        with self.assertRaises(writer.CopyFailure) as result:
            writer.write_copy(self.source, self.target, alter)
        self.assertFalse(self.target.exists())
        self.assertEqual(self.source.read_bytes(), self.data+b' ')
        self.assertEqual((Path(result.exception.recovery_path)/'provenance/source.json').read_bytes(), self.data)

    def test_corruption_missing_source_and_unsafe_inventory_are_rejected(self):
        writer.write_copy(self.source, self.target)
        screenplay = self.target/'screenplay.json'; saved = screenplay.read_bytes()
        screenplay.write_bytes(saved+b' ')
        with self.assertRaises(ValueError): writer.read_copy(self.target)
        screenplay.write_bytes(saved)
        project = self.target/'project.json'; original = project.read_bytes()
        value = json.loads(original); value['head']['files']['../escape'] = {'bytes': 0, 'sha256': '0'*64}
        project.write_text(json.dumps(value))
        with self.assertRaises(ValueError): writer.read_copy(self.target)
        project.write_bytes(original)
        (self.target/'provenance/source.json').unlink()
        with self.assertRaises(OSError): writer.read_copy(self.target)
        self.unchanged()

    def test_symlink_payload_and_extra_files_are_rejected(self):
        writer.write_copy(self.source, self.target)
        extra = self.target/'unexpected'; extra.write_text('extra')
        with self.assertRaises(ValueError): writer.read_copy(self.target)
        extra.unlink()
        screenplay = self.target/'screenplay.json'; screenplay.unlink(); screenplay.symlink_to(self.source)
        with self.assertRaises(ValueError): writer.read_copy(self.target)
        self.unchanged()
        fifo = self.root / 'not-a-regular-file'
        os.mkfifo(fifo)
        with self.assertRaises(ValueError): writer._read_regular(fifo)

    def test_cli_convert_and_verify(self):
        tool = str(ROOT/'Scripts/convert-legacy-copy.py')
        for args in [('convert', str(self.source), str(self.target)), ('verify', str(self.target))]:
            run = subprocess.run([sys.executable, tool, *args], capture_output=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertTrue(json.loads(run.stdout)['verified'])
        self.unchanged()

    def test_abrupt_process_exit_before_and_after_publish(self):
        code = """import sys, os
sys.dont_write_bytecode=True
sys.path.insert(0,sys.argv[1])
from legacy_copy import write_copy
def stop(phase, path):
    if phase == sys.argv[4]: os._exit(73)
write_copy(sys.argv[2],sys.argv[3],stop)
"""
        for i, phase in enumerate(['write:screenplay.json', 'before_publish', 'published']):
            target = self.root / ('crash'+str(i)+'.screenplay')
            before = set(self.root.iterdir())
            run = subprocess.run([sys.executable, '-c', code, str(ROOT/'Scripts'), str(self.source), str(target), phase])
            self.assertEqual(run.returncode, 73)
            new = set(self.root.iterdir()) - before
            self.assertEqual(len(new), 1)
            retained = new.pop()
            if phase != 'write:screenplay.json': self.assertTrue(writer.read_copy(retained)['verified'])
            else:
                with self.assertRaises((OSError, ValueError)): writer.read_copy(retained)
            self.assertEqual(target.exists(), phase == 'published')
            self.unchanged()
