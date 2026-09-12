import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest
from test_inspector import fixture, ROOT, PROJECT, ELEMENT

spec = importlib.util.spec_from_file_location('destination', ROOT / 'Scripts/legacy_destination.py')
destination = importlib.util.module_from_spec(spec)
spec.loader.exec_module(destination)
raw = destination.raw
STAMP = '2026-09-12T12:00:00+00:00'


def rich():
    value = fixture()
    value['shots'] = [{'id': '00000000-0000-4000-8000-000000000020', 'scene_spine_id': 'S001',
                       'shot_number': 9, 'label': 'Keep label', 'setup': 'coverage', 'status': 'selected',
                       'source_refs': [{'screenplay_element_id': ELEMENT}], 'notes': 'Keep notes'}]
    value['script_notes'] = [{'id': '00000000-0000-4000-8000-000000000021', 'scene_spine_id': 'S001',
                              'screenplay_element_id': ELEMENT, 'body': 'Note', 'status': 'resolved', 'created_at': STAMP}]
    value['board_frames'] = [{'id': '00000000-0000-4000-8000-000000000022', 'scene_spine_id': 'S001',
                             'shot_id': value['shots'][0]['id'], 'frame_number': 1, 'label': 'Board', 'prompt': '',
                             'duration_seconds': 4.5, 'status': 'selected', 'notes': '', 'source_refs': []}]
    value['outline'] = [{'id': '00000000-0000-4000-8000-000000000023', 'template': 'custom', 'order': 1,
                         'name': 'Beat', 'purpose': '', 'notes': '', 'linked_scene_spine_ids': ['S001']}]
    return value


def build(value):
    return destination.build_candidate(json.dumps(value).encode(), STAMP)


class DestinationTests(unittest.TestCase):
    def test_schema_is_valid_and_minimal_payloads_validate(self):
        candidate = build(fixture())
        destination.schema_validate(candidate['files'])
        self.assertFalse(candidate['conversion_ready'])
        self.assertEqual(candidate['files']['manifest.json']['document_id'], candidate['files']['screenplay.json']['id'])
        self.assertNotIn('shots.json', candidate['files'])
        value = fixture(); value['screenplay']['elements'] = []
        self.assertEqual(build(value)['files']['screenplay.json']['elements'], [])

    def test_scene_and_shot_references_share_one_identity(self):
        candidate = build(rich())
        id = candidate['scene_map'][ELEMENT]
        files = candidate['files']
        self.assertEqual(files['screenplay.json']['elements'][0]['scene']['id'], id)
        self.assertEqual(files['shots.json']['shot_addenda'][0]['scene_id'], id)
        self.assertEqual(files['film/boards.json']['boards'][0]['scene_id'], id)
        self.assertEqual(files['film/outline.json']['beats'][0]['linked_scene_ids'], [id])
        self.assertEqual(files['notes.json']['notes'][0]['anchor']['element_id'], ELEMENT)
        self.assertTrue(files['notes.json']['notes'][0]['resolved'])
        self.assertEqual(files['shots.json']['shot_addenda'][0]['shots'][0]['shot_number'], raw.Number('9'))

    def test_scene_ids_survive_reorder_and_heading_rename(self):
        value = rich()
        other = copy.deepcopy(value['screenplay']['elements'][0])
        other['id'] = '00000000-0000-4000-8000-000000000030'; other['spine_id'] = 'S002'
        value['screenplay']['elements'].append(other)
        before = build(value)['scene_map']
        value['screenplay']['elements'].reverse()
        value['screenplay']['elements'][0]['text'] = 'EXT. OTHER - NIGHT'
        self.assertEqual(build(value)['scene_map'], before)

    def test_missing_ambiguous_and_colliding_references_block(self):
        for mutation in [lambda v: v['shots'][0].update(scene_spine_id='S999'),
                         lambda v: v['screenplay']['elements'].append(copy.deepcopy(v['screenplay']['elements'][0])),
                         lambda v: v['shots'][0].update(scene_id=PROJECT),
                         lambda v: v['screenplay']['elements'][0].update(scene={'id': PROJECT})]:
            value = rich(); mutation(value)
            with self.assertRaises(ValueError): build(value)

    def test_unknown_values_are_archived_exactly_not_interpreted_as_ids(self):
        value = rich()
        value['future'] = {'id': PROJECT, 'number': 'TOKEN', 'text': 'e\u0301'}
        data = json.dumps(value).replace('"TOKEN"', '123456789012345678901234567890.123456789').encode()
        candidate = destination.build_candidate(data, STAMP)
        archive = candidate['files']['extensions.json']['extensions']['dev.screenplayos.legacy']['source']
        self.assertEqual(raw.preserve_json(archive), raw.preserve_json(raw.parse_source(data)))
        self.assertEqual(sum(x['id'] == PROJECT for x in candidate['files']['project.json']['head']['objects']), 1)

    def test_schema_rejects_bad_uuid_time_and_wrong_payload_types(self):
        for file, key, bad in [('manifest.json', 'created_at', 'not-a-date'), ('manifest.json', 'document_id', 'bad'), ('screenplay.json', 'elements', {})]:
            files = build(fixture())['files']; files[file][key] = bad
            with self.assertRaises(ValueError): destination.schema_validate(files)

    def test_changed_data_and_recomputed_digests_still_fail(self):
        value = rich(); data = json.dumps(value).encode(); candidate = build(value)
        candidate['files']['screenplay.json']['elements'][0]['text'] = 'silently changed'
        with self.assertRaises(ValueError): destination.validate_candidate(data, candidate)
        candidate = build(value)
        with self.assertRaises(ValueError): destination.validate_candidate(data+b' ', candidate)

    def test_edit_timing_and_locks_survive_without_regeneration(self):
        value = rich()
        clip = {'id': '00000000-0000-4000-8000-000000000040', 'scene_spine_id': 'S001',
                'source_element_ids': [], 'label': 'Existing trim', 'source_kind': 'production_media',
                'timeline_start_seconds': 50, 'timeline_duration_seconds': 7.25,
                'source_start_seconds': 9.375, 'status': 'locked', 'notes': 'Keep this'}
        value['editorial_spine'] = {'sequences': [{
            'id': '00000000-0000-4000-8000-000000000041', 'name': 'Sequence', 'order': 2,
            'beats': [{'id': '00000000-0000-4000-8000-000000000042', 'order': 3, 'scene_spine_id': 'S001',
                       'title': '', 'source_element_ids': [], 'shot_ids': [], 'board_frame_ids': [],
                       'edit_clips': [clip], 'edit_notes': '', 'marker_category': 'scene', 'status': 'in_edit'}]}]}
        value['screenplay']['production_page_lock'] = {'text': 'Keep locks', 'pageStarts': [0, 4]}
        candidate = build(value)
        migrated = candidate['files']['film/edit.json']['sequences'][0]['beats'][0]['edit_clips'][0]
        for key in ('id', 'notes', 'timeline_start_seconds', 'timeline_duration_seconds', 'source_start_seconds'):
            self.assertEqual(raw.preserve_json(migrated[key]), raw.preserve_json(raw.parse_source(json.dumps(clip[key]).encode())))
        self.assertEqual(migrated['scene_id'], candidate['scene_map'][ELEMENT])
        archive = candidate['files']['extensions.json']['extensions']['dev.screenplayos.legacy']['source']
        self.assertIn('production_page_lock', archive['screenplay'])

    def test_cli_is_read_only_and_prints_no_payload_values(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'script.json'; data = json.dumps(rich()).encode(); path.write_bytes(data)
            before = path.stat().st_mtime_ns; path.chmod(0o444)
            result = subprocess.run([sys.executable, str(ROOT/'Scripts/inspect-legacy.py'), str(path), '--candidate'], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn('PRIVATE SCRIPT', result.stdout.decode())
            self.assertIn('validated_files', json.loads(result.stdout)['candidate'])
            self.assertEqual(path.read_bytes(), data); self.assertEqual(path.stat().st_mtime_ns, before)
            self.assertEqual(list(Path(folder).iterdir()), [path])
            path.chmod(0o644)
            broken = rich(); broken['shots'][0]['scene_spine_id'] = 'S999'
            path.write_text(json.dumps(broken))
            result = subprocess.run([sys.executable, str(ROOT/'Scripts/inspect-legacy.py'), str(path), '--candidate'], capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(json.loads(result.stdout)['candidate']['status'], 'blocked')
