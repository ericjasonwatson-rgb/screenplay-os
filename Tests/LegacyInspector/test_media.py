import base64
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import uuid
import importlib.util

from test_destination import ROOT, rich

spec = importlib.util.spec_from_file_location('legacy_media', ROOT / 'Scripts/legacy_media.py')
media = importlib.util.module_from_spec(spec)
spec.loader.exec_module(media)

PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')


class MediaPlanTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(); self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name); (self.root / 'Board Images').mkdir()
        self.image = self.root / 'Board Images' / 'take.png'; self.image.write_bytes(PNG)
        self.digest = hashlib.sha256(PNG).hexdigest()
        self.document = rich(); board = self.document['board_frames'][0]
        board['image_versions'] = [
            {'id': str(uuid.uuid4()), 'fileURL': 'Board%20Images/take.png', 'sha256': self.digest,
             'prompt': 'Wide', 'model': 'fixture'},
            {'id': str(uuid.uuid4()), 'fileURL': self.image.as_uri(), 'sha256': self.digest,
             'prompt': 'Duplicate bytes', 'model': 'fixture'}]
        board['selected_image_id'] = board['image_versions'][1]['id']
        self.source = self.root / 'project.json'; self.source.write_text(json.dumps(self.document))

    def test_plan_preserves_versions_selection_and_deduplicates_bytes(self):
        before = self.source.read_bytes(); plan = media.build_media_plan(self.source)
        self.assertEqual(plan['project_id'], self.document['project']['id'])
        self.assertEqual(len(plan['media']), 1); self.assertEqual(len(plan['attachments']), 1)
        record = plan['media'][0]
        self.assertEqual([v['id'] for v in record['versions']], [v['id'] for v in self.document['board_frames'][0]['image_versions']])
        self.assertEqual(record['selected_version_id'], self.document['board_frames'][0]['selected_image_id'])
        self.assertEqual(record['versions'][0]['path'], 'attachments/boards/' + self.digest + '.png')
        self.assertEqual((record['versions'][0]['width'], record['versions'][0]['height']), (1, 1))
        self.assertEqual(self.source.read_bytes(), before)

    def test_changed_missing_remote_and_symlink_media_fail_closed(self):
        mutations = [
            lambda item: item.update(sha256='0' * 64),
            lambda item: item.update(fileURL='https://example.com/take.png'),
            lambda item: item.update(fileURL='other/take.png')]
        for mutation in mutations:
            value = json.loads(json.dumps(self.document)); mutation(value['board_frames'][0]['image_versions'][0])
            self.source.write_text(json.dumps(value))
            with self.assertRaises((ValueError, OSError)): media.build_media_plan(self.source)
        self.source.write_text(json.dumps(self.document)); self.image.unlink(); self.image.symlink_to(self.source)
        with self.assertRaises((ValueError, OSError)): media.build_media_plan(self.source)

    def test_invalid_selection_and_non_png_fail_closed(self):
        value = json.loads(json.dumps(self.document)); value['board_frames'][0]['selected_image_id'] = str(uuid.uuid4())
        self.source.write_text(json.dumps(value))
        with self.assertRaises(ValueError): media.build_media_plan(self.source)
        self.image.write_bytes(b'not png'); value = json.loads(json.dumps(self.document))
        value['board_frames'][0]['image_versions'][0]['sha256'] = hashlib.sha256(b'not png').hexdigest()
        value['board_frames'][0]['image_versions'] = value['board_frames'][0]['image_versions'][:1]
        value['board_frames'][0]['selected_image_id'] = value['board_frames'][0]['image_versions'][0]['id']
        self.source.write_text(json.dumps(value))
        with self.assertRaises(ValueError): media.build_media_plan(self.source)
