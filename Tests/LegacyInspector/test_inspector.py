import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('inspector', ROOT / 'Scripts/inspect-legacy.py')
inspector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspector)
SCHEMA = json.loads((ROOT / 'Specs/legacy/open-screenplay-1.0.schema.json').read_text())
PROJECT = '00000000-0000-4000-8000-000000000001'
SCRIPT = '00000000-0000-4000-8000-000000000002'
ELEMENT = '00000000-0000-4000-8000-000000000003'


def fixture():
    return {'format': 'open-screenplay', 'format_version': '1.0',
            'project': {'id': PROJECT, 'screenplay_id': SCRIPT,
                        'metadata': {'title': '', 'author': '', 'created_at': '2026-09-12T00:00:00Z', 'modified_at': '2026-09-12T00:00:00Z'}},
            'screenplay': {'id': SCRIPT, 'metadata': {'title': ''}, 'revision': 0,
                          'elements': [{'id': ELEMENT, 'type': 'scene_heading', 'text': 'PRIVATE SCRIPT e\u0301 👩🏽‍🚀\n', 'spine_id': 'S001', 'external_ids': {}}]}}


class InspectorTests(unittest.TestCase):
    def inspect(self, value):
        return inspector.inspect_bytes(json.dumps(value).encode(), SCHEMA)

    def codes(self, report):
        return {f['code'] for f in report['findings']}

    def test_reader_accepts_legacy_and_current_identifiers(self):
        legacy = fixture()
        current = copy.deepcopy(legacy)
        current['format'] = 'screenplayos'
        current_schema = json.loads((ROOT / 'Specs/screenplayos-1.0.schema.json').read_text())
        self.assertEqual(inspector.inspect_bytes(json.dumps(legacy).encode(), SCHEMA)['dialect'], 'legacy-monolithic-candidate')
        self.assertEqual(inspector.inspect_bytes(json.dumps(current).encode(), current_schema)['dialect'], 'legacy-monolithic-candidate')

    def test_supported_empty_and_unicode_scripts(self):
        value = fixture()
        for elements in [[], value['screenplay']['elements']]:
            value['screenplay']['elements'] = elements
            report = self.inspect(value)
            self.assertEqual(report['dialect'], 'legacy-monolithic-candidate')
            self.assertFalse(any(f['severity'] == 'blocker' for f in report['findings']), report)
            self.assertNotIn('PRIVATE SCRIPT', json.dumps(report))

    def test_nested_escaped_duplicate_keys_rejected(self):
        for data in [b'{"x":{"a":1,"\\u0061":2}}', b'{"x":NaN}', b'{"x":"\\ud800"}', b'\xff']:
            report = inspector.inspect_bytes(data, SCHEMA)
            self.assertIn('invalid_json', self.codes(report))
            self.assertEqual(report['source_sha256'], hashlib.sha256(data).hexdigest())

    def test_numeric_tokens_unknown_data_and_unicode_preserved(self):
        data = b'{"unknown":{"big":123456789012345678901234567890,"precise":1.234567890123456789e+200,"text":"e\\u0301"}}'
        tree = inspector.parse_source(data)
        self.assertEqual(tree['unknown']['big'], '123456789012345678901234567890')
        self.assertIsInstance(tree['unknown']['big'], inspector.Number)
        self.assertEqual(tree['unknown']['precise'], '1.234567890123456789e+200')
        self.assertEqual(tree['unknown']['text'], 'e\u0301')
        report = inspector.inspect_bytes(data, SCHEMA)
        record = next(x for x in report['inventory'] if x['path'] == '/unknown/big')
        self.assertEqual(record['type'], 'number')
        self.assertEqual(record['disposition'], 'opaque_preservation_required')

    def test_version_and_shape_are_both_checked(self):
        for change in [{'format_version': '2.0'}, {'screenplay': []}, {'format': 'something-else'}]:
            value = fixture()
            value.update(change)
            self.assertIn('unsupported_dialect', self.codes(self.inspect(value)))

    def test_duplicate_ids_and_ambiguous_scene_links(self):
        value = fixture()
        value['screenplay']['elements'].append(copy.deepcopy(value['screenplay']['elements'][0]))
        value['shots'] = [{'id': '00000000-0000-4000-8000-000000000004', 'scene_spine_id': 'S001'}]
        codes = self.codes(self.inspect(value))
        self.assertTrue({'duplicate_identity', 'ambiguous_scene_alias', 'reference_ambiguous'} <= codes)

    def test_missing_links_and_invalid_identity_are_not_repaired(self):
        value = fixture()
        value['project']['screenplay_id'] = PROJECT
        value['screenplay']['elements'][0]['id'] = 'not-a-uuid'
        value['shots'] = [{'scene_spine_id': 'S999'}]
        codes = self.codes(self.inspect(value))
        self.assertTrue({'invalid_uuid', 'screenplay_identity_mismatch', 'reference_unresolved'} <= codes)

    def test_raw_editorial_and_locks_never_normalized(self):
        value = fixture()
        value['editorial_spine'] = {'sequences': [{'id': PROJECT, 'beats': [{'edit_clips': [{'source_start_seconds': 9.375, 'timeline_start_seconds': 50, 'notes': 'keep raw'}]}]}]}
        value['screenplay']['production_page_lock'] = {'text': 'keep lock', 'pageStarts': [0, 12]}
        data = json.dumps(value).encode()
        before = inspector.parse_source(data)
        report = inspector.inspect_bytes(data, SCHEMA)
        self.assertEqual(inspector.parse_source(data), before)
        self.assertIn('raw_editorial_preserved', self.codes(report))
        self.assertIn('production_lock', self.codes(report))
        self.assertTrue(any(x['path'].endswith('/source_start_seconds') for x in report['inventory']))

    def test_cli_read_only_and_exit_codes(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'source.json'
            for data, expected in [(json.dumps(fixture()).encode(), 0), (b'{"a":1,"a":2}', 1)]:
                path.write_bytes(data)
                path.chmod(0o444)
                before = path.stat().st_mtime_ns
                run = subprocess.run([sys.executable, str(ROOT / 'Scripts/inspect-legacy.py'), str(path)], capture_output=True)
                self.assertEqual(run.returncode, expected, run.stderr)
                self.assertTrue(json.loads(run.stdout)['source_unchanged_at_readback'])
                self.assertEqual(path.read_bytes(), data)
                self.assertEqual(path.stat().st_mtime_ns, before)
                self.assertEqual(list(Path(folder).iterdir()), [path])
                path.chmod(0o644)
            run = subprocess.run([sys.executable, str(ROOT / 'Scripts/inspect-legacy.py'), str(path / 'missing')], capture_output=True)
            self.assertEqual(run.returncode, 2)


if __name__ == '__main__':
    unittest.main()
