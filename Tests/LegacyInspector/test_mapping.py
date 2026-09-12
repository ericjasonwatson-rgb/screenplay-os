import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path
import unittest

from test_inspector import inspector, fixture, SCHEMA, ROOT


def source():
    value = fixture()
    value['future'] = {'a/b~c': [None, True, False, {}, [], '123', 'e\u0301 👩🏽‍🚀'], 'number': 'TOKEN'}
    value['screenplay']['elements'][0]['future_style'] = {'weight': 'retained'}
    return json.dumps(value).replace('"TOKEN"', '123456789012345678901234567890.0000000000000000001e+40').encode()


class MappingTests(unittest.TestCase):
    def test_raw_encoder_keeps_numeric_tokens_unicode_and_empty_values(self):
        data = b'{"a":-0,"b":1.230000e-50,"c":123456789012345678901234567890,"d":"123","e":[true,false,null,{},[]],"f":"e\\u0301"}'
        tree = inspector.parse_source(data)
        encoded = inspector.preserve_json(tree)
        self.assertIn(b'1.230000e-50', encoded)
        self.assertIn(b'"a":-0', encoded)
        self.assertIn(b'"d":"123"', encoded)
        self.assertEqual(inspector.preserve_json(inspector.parse_source(encoded)), encoded)
        self.assertEqual(inspector.parse_source(encoded)['f'], 'e\u0301')

    def test_encoder_rejects_float_and_invalid_number_tokens(self):
        for value in [1.2, float('nan'), inspector.Number('01'), inspector.Number('Infinity'), inspector.Number('1,2'), {1: 'key'}]:
            with self.assertRaises(ValueError):
                inspector.preserve_json(value)

    def test_every_field_recovers_without_original_source(self):
        data = source()
        plan = inspector.create_mapping(data, SCHEMA)
        self.assertTrue(plan['preservation_verified'])
        self.assertFalse(plan['conversion_ready'])
        self.assertEqual(plan['identity_assignments'], [])
        # This API receives only the plan, never original bytes or a backup subtree.
        recovered = inspector.recover_mapping(plan)
        self.assertEqual(inspector.preserve_json(recovered), inspector.preserve_json(inspector.parse_source(data)))
        routes = {item['source']: item for item in plan['mappings']}
        self.assertEqual(routes['/screenplay/elements/0/text']['disposition'], 'mapped')
        self.assertEqual(routes['/screenplay/elements/0/future_style/weight']['disposition'], 'preserved_opaque')
        self.assertIn('/future/a~1b~0c/0', routes)
        self.assertEqual(routes['/future/a~1b~0c/3']['type'], 'object')

    def test_exact_source_digest_and_mapping_version_gate_reuse(self):
        data = source()
        plan = inspector.create_mapping(data, SCHEMA)
        self.assertTrue(inspector.validate_mapping(data, plan))
        with self.assertRaises(ValueError):
            inspector.validate_mapping(data + b' ', plan)
        plan['mapping_version'] = '999'
        with self.assertRaises(ValueError):
            inspector.validate_mapping(data, plan)

    def test_missing_duplicate_misrouted_or_unaccounted_fields_fail(self):
        data = source()
        original = inspector.create_mapping(data, SCHEMA)
        mutations = [
            lambda p: p['mappings'].pop(),
            lambda p: p['mappings'].append(copy.deepcopy(p['mappings'][0])),
            lambda p: p['mappings'][0].update(file='wrong.json'),
            lambda p: p['payload_fragments']['manifest.json'].update({'/unaccounted': 'extra'}),
            lambda p: p['structure'].append({'path': '/unreachable', 'type': 'object', 'keys': []}),
        ]
        for mutate in mutations:
            plan = copy.deepcopy(original)
            mutate(plan)
            with self.assertRaises((ValueError, KeyError)):
                inspector.validate_mapping(data, plan)

    def test_changed_unknown_value_or_numeric_type_fails(self):
        data = source()
        for replacement in ['rounded', '123456789012345678901234567890.0000000000000000001e+40', inspector.Number('1')]:
            plan = inspector.create_mapping(data, SCHEMA)
            entry = next(item for item in plan['mappings'] if item['source'] == '/future/number')
            plan['payload_fragments'][entry['file']][entry['target']] = replacement
            with self.assertRaises(ValueError):
                inspector.validate_mapping(data, plan)

    def test_array_order_and_container_shape_changes_fail(self):
        data = source()
        plan = inspector.create_mapping(data, SCHEMA)
        entry = next(item for item in plan['structure'] if item['path'] == '/future/a~1b~0c')
        entry['length'] -= 1
        with self.assertRaises(ValueError):
            inspector.validate_mapping(data, plan)
        plan = inspector.create_mapping(data, SCHEMA)
        items = [item for item in plan['mappings'] if item['source'] in ('/future/a~1b~0c/1', '/future/a~1b~0c/2')]
        a, b = items
        fragments = plan['payload_fragments'][a['file']]
        fragments[a['target']], fragments[b['target']] = fragments[b['target']], fragments[a['target']]
        with self.assertRaises(ValueError):
            inspector.validate_mapping(data, plan)

    def test_blocked_input_has_no_candidate_fragments(self):
        for data in [b'{"a":1,"a":2}', source().replace(b'"1.0"', b'"99.0"'), source().replace(b'S001', b' S001')]:
            plan = inspector.create_mapping(data, SCHEMA)
            self.assertEqual(plan['status'], 'blocked')
            self.assertEqual(plan['payload_fragments'], {})
            self.assertFalse(plan['preservation_verified'])

    def test_raw_locks_and_editorial_do_not_acquire_fake_target_semantics(self):
        value = fixture()
        value['screenplay']['production_page_lock'] = {'text': 'a\n', 'pageStarts': [0, 2]}
        value['editorial_spine'] = {'sequences': [{
            'id': '00000000-0000-4000-8000-000000000010', 'name': 'Keep this edit', 'order': 2,
            'beats': [{'id': '00000000-0000-4000-8000-000000000011', 'order': 7,
                       'scene_spine_id': 'S001', 'title': 'Existing beat',
                       'source_element_ids': [], 'shot_ids': [], 'board_frame_ids': [],
                       'edit_notes': 'Do not rebuild', 'marker_category': 'scene', 'status': 'in_edit',
                       'edit_clips': [{'id': '00000000-0000-4000-8000-000000000012',
                                       'scene_spine_id': 'S001', 'source_element_ids': [],
                                       'label': 'Existing clip', 'source_kind': 'production_media',
                                       'timeline_start_seconds': 50, 'timeline_duration_seconds': 7.25,
                                       'source_start_seconds': 9.375, 'status': 'locked', 'notes': 'Keep trim'}]}]}]}
        value['ai_settings'] = {'writing_enabled': False, 'directing_enabled': False, 'production_enabled': False, 'future_toggle': False}
        data = json.dumps(value).encode()
        plan = inspector.create_mapping(data, SCHEMA)
        self.assertTrue(plan['preservation_verified'])
        for item in plan['mappings']:
            if 'lock' in item['source'] or item['source'].startswith(('/editorial_spine', '/ai_settings')):
                self.assertEqual(item['disposition'], 'preserved_opaque')
        self.assertEqual(inspector.recover_mapping(plan), inspector.parse_source(data))

    def test_cli_mapping_is_read_only_and_omits_creative_values(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'source.json'
            data = source()
            path.write_bytes(data)
            path.chmod(0o444)
            before = path.stat().st_mtime_ns
            result = subprocess.run([sys.executable, str(ROOT / 'Scripts/inspect-legacy.py'), str(path), '--mapping'], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(result.stdout)
            self.assertTrue(report['mapping']['preservation_verified'])
            self.assertNotIn('payload_fragments', report['mapping'])
            self.assertNotIn('PRIVATE SCRIPT', result.stdout.decode())
            self.assertEqual(path.read_bytes(), data)
            self.assertEqual(path.stat().st_mtime_ns, before)
            self.assertEqual(list(Path(folder).iterdir()), [path])
