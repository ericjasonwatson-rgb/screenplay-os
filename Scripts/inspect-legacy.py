#!/usr/bin/env python3
"""Read-only legacy JSON risk inventory. No app model, conversion, or output-file writes."""
import argparse
import hashlib
import json
import re
import copy
from pathlib import Path
import sys
import uuid


class Number(str):
    """Exact JSON numeric token, never converted through floating point."""


def parse_source(data):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise ValueError('duplicate JSON object key')
            result[key] = value
        return result

    def invalid_constant(value):
        raise ValueError('non-JSON numeric constant')

    value = json.loads(data.decode('utf-8'), object_pairs_hook=pairs,
                       parse_int=Number, parse_float=Number,
                       parse_constant=invalid_constant)
    # Escaped unpaired surrogates are accepted by Python but are not Unicode text.
    def unicode_check(node):
        if isinstance(node, str):
            node.encode('utf-8', errors='strict')
        elif isinstance(node, dict):
            for key, child in node.items():
                unicode_check(key)
                unicode_check(child)
        elif isinstance(node, list):
            for child in node:
                unicode_check(child)
    unicode_check(value)
    return value


def pointer(path, key):
    return path + '/' + str(key).replace('~', '~0').replace('/', '~1')


def kind(value):
    if isinstance(value, Number):
        return 'number'
    if value is None:
        return 'null'
    if isinstance(value, bool):
        return 'boolean'
    if isinstance(value, str):
        return 'string'
    if isinstance(value, dict):
        return 'object'
    return 'array'


def valid_uuid(value):
    if type(value) is not str:
        return False
    try:
        return str(uuid.UUID(value)) == value.lower()
    except ValueError:
        return False


def inspect_bytes(data, schema):
    report = {
        'inspector_version': '0.1',
        'source_sha256': hashlib.sha256(data).hexdigest(),
        'source_bytes': len(data),
        'dialect': 'unrecognized',
        'conversion_available': False,
        'scope': 'Read-only risk inventory; not schema conformance or a migration plan.',
        'inventory': [], 'identities': [], 'references': [], 'findings': [],
    }
    def finding(severity, code, path, message):
        report['findings'].append(dict(severity=severity, code=code, path=path, message=message))

    try:
        root = parse_source(data)
    except (ValueError, UnicodeError, RecursionError):
        finding('blocker', 'invalid_json', '', 'Invalid UTF-8/JSON, duplicate keys, invalid Unicode, or excessive nesting. Source was not changed.')
        return report

    if not isinstance(root, dict):
        finding('blocker', 'unsupported_shape', '', 'Expected a legacy project object.')
        return report
    shaped = (isinstance(root.get('project'), dict)
              and isinstance(root.get('screenplay'), dict)
              and isinstance(root['screenplay'].get('elements'), list))
    if shaped:
        report['dialect'] = 'legacy-monolithic-candidate'
    if not shaped or root.get('format') != 'open-screenplay' or root.get('format_version') != '1.0':
        finding('blocker', 'unsupported_dialect', '', 'Structure and supported legacy declarations must agree; a version label alone is insufficient.')

    ids = {}
    aliases = {}
    raw_references = []
    # Only schema-understood record paths are interpreted as identities/references.
    # Unknown payload is inventoried but never guessed to be a creative object.
    def walk(value, spec, path, understood=True):
        if '$ref' in spec:
            spec = schema['$defs'][spec['$ref'].split('/')[-1]]
        report['inventory'].append(dict(path=path, type=kind(value),
            disposition='unmapped_known_field' if understood else 'opaque_preservation_required'))
        expected = spec.get('type')
        if expected:
            options = expected if isinstance(expected, list) else [expected]
            actual = kind(value)
            matches = actual in options or (actual == 'number' and 'integer' in options and not any(c in value for c in '.eE'))
            if not matches:
                finding('blocker', 'field_type', path, 'Value does not match the legacy field type.')
        if 'const' in spec and value != spec['const']:
            finding('blocker', 'field_constant', path, 'Unsupported legacy declaration.')
        if 'enum' in spec and value not in spec['enum']:
            finding('warning', 'unsupported_value', path, 'Unsupported value must be retained without normalization.')
        if spec.get('format') == 'uuid' and not valid_uuid(value):
            finding('blocker', 'invalid_uuid', path, 'Expected a canonical UUID string; automatic repair is not available.')
        if isinstance(value, dict):
            properties = spec.get('properties', {})
            for key in spec.get('required', []):
                if key not in value:
                    finding('blocker', 'missing_field', pointer(path, key), 'Required legacy field is absent; no value was invented.')
            if understood and 'id' in properties and 'id' in value and valid_uuid(value['id']):
                identity = value['id'].lower()
                report['identities'].append(dict(path=pointer(path, 'id'), id=value['id']))
                # Production-lock baseline elements intentionally repeat live element IDs.
                historical = '/production_page_lock/' in path or '/page_lock/' in path
                if not historical:
                    if identity in ids:
                        finding('blocker', 'duplicate_identity', pointer(path, 'id'), 'Identity also occurs at ' + ids[identity])
                    else:
                        ids[identity] = pointer(path, 'id')
            if path.startswith('/screenplay/elements/') and value.get('type') == 'scene_heading':
                alias = value.get('spine_id')
                if type(alias) is str and alias.strip():
                    aliases.setdefault(alias, []).append(path)
                    if alias != alias.strip():
                        finding('blocker', 'noncanonical_scene_alias', pointer(path, 'spine_id'), 'Whitespace in scene alias requires explicit mapping; it was not trimmed.')
                else:
                    finding('warning', 'missing_scene_alias', path, 'Scene needs an explicit new scene-identity mapping; none was assigned.')
            for key, child in value.items():
                child_path = pointer(path, key)
                child_spec = properties.get(key)
                child_known = understood and child_spec is not None
                if child_spec is None:
                    additional = spec.get('additionalProperties')
                    if understood and isinstance(additional, dict):
                        child_spec, child_known = additional, True
                    elif understood:
                        finding('warning', 'unknown_field', child_path, 'Retain this subtree exactly in a future migration; no target mapping exists yet.')
                if child_known and key in ('scene_spine_id', 'linked_scene_spine_ids'):
                    values = child if isinstance(child, list) else [child]
                    for i, ref in enumerate(values):
                        raw_references.append((pointer(child_path, i) if isinstance(child, list) else child_path, ref, 'scene', key))
                uuid_refs = {'screenplay_id', 'screenplay_element_id', 'shot_id', 'board_frame_id', 'outline_beat_id', 'context_record_id', 'source_element_ids', 'shot_ids', 'board_frame_ids'}
                if child_known and key in uuid_refs:
                    values = child if isinstance(child, list) else [child]
                    for i, ref in enumerate(values):
                        raw_references.append((pointer(child_path, i) if isinstance(child, list) else child_path, ref, 'uuid', key))
                walk(child, child_spec or {}, child_path, child_known)
        elif isinstance(value, list):
            for i, child in enumerate(value):
                walk(child, spec.get('items', {}), pointer(path, i), understood)

    walk(root, schema, '')
    for alias, paths in aliases.items():
        if len(paths) > 1:
            finding('blocker', 'ambiguous_scene_alias', paths[0], 'Multiple headings use this alias; dependent references cannot be mapped automatically.')
    for path, value, category, key in raw_references:
        if value is None:
            continue
        if category == 'scene':
            matches = aliases.get(value, []) if type(value) is str else []
            state = 'resolved' if len(matches) == 1 else ('ambiguous' if matches else 'unresolved')
        else:
            target = ids.get(value.lower()) if valid_uuid(value) else None
            prefixes = {
                'screenplay_id': ('/screenplay/id',),
                'screenplay_element_id': ('/screenplay/elements/',),
                'source_element_ids': ('/screenplay/elements/',),
                'shot_id': ('/shots/',), 'shot_ids': ('/shots/',),
                'board_frame_id': ('/board_frames/',), 'board_frame_ids': ('/board_frames/',),
                'outline_beat_id': ('/outline/',),
                'context_record_id': ('/production_context/entities/', '/production_context/notes/'),
            }
            state = 'resolved' if target and target.startswith(prefixes[key]) else 'unresolved'
        report['references'].append(dict(path=path, kind=category, status=state))
        if state != 'resolved':
            finding('blocker' if state == 'ambiguous' else 'warning', 'reference_' + state, path, 'Keep the original reference; do not guess a replacement.')
    if shaped:
        project, script = root['project'], root['screenplay']
        if project.get('screenplay_id') != script.get('id'):
            finding('blocker', 'screenplay_identity_mismatch', '/project/screenplay_id', 'Project and screenplay identities disagree.')
        if any('lock' in key for key in script):
            finding('warning', 'production_lock', '/screenplay', 'Preserve original lock data and offset units; lock conversion is not implemented.')
    if 'editorial_spine' in root:
        finding('info', 'raw_editorial_preserved', '/editorial_spine', 'Inspected raw records only; clip order, timing, IDs, and offsets were not regenerated.')
    finding('info', 'mapping_deferred', '', 'No identities assigned or fields converted. All target mappings and full schema/semantic validation remain future work.')
    return report


def inspect_file(path, schema):
    # This tool only reads source bytes; reports go to stdout, never a chosen file.
    data = Path(path).read_bytes()
    report = inspect_bytes(data, schema)
    report['source_unchanged_at_readback'] = Path(path).read_bytes() == data
    if not report['source_unchanged_at_readback']:
        report['findings'].append(dict(severity='blocker', code='source_changed', path='',
            message='Source changed during inspection; rerun against a stable copy.'))
    return report



_NUMBER = re.compile(r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?\Z')


def preserve_json(value):
    """Encode the raw tree without numeric coercion or Unicode normalization."""
    def encode(node):
        if isinstance(node, Number):
            if not _NUMBER.fullmatch(node):
                raise ValueError('invalid numeric token')
            return str(node)
        if node is None:
            return 'null'
        if type(node) is bool:
            return 'true' if node else 'false'
        if type(node) is int:
            return str(node)
        if type(node) is str:
            node.encode('utf-8', errors='strict')
            return json.dumps(node, ensure_ascii=False)
        if type(node) is list:
            return '[' + ','.join(encode(child) for child in node) + ']'
        if type(node) is dict:
            if any(type(key) is not str for key in node):
                raise ValueError('JSON keys must be strings')
            return '{' + ','.join(encode(key) + ':' + encode(node[key]) for key in sorted(node)) + '}'
        raise ValueError('unsupported value; floats must not enter the preservation tree')
    return encode(value).encode('utf-8')


def mapping_destination(path):
    """Conservative field rules. All other values retain their original pointer."""
    exact = {
        '/format': ('manifest.json', '/format'),
        '/format_version': ('manifest.json', '/format_version'),
        '/project/id': ('project.json', '/project_id'),
        '/project/screenplay_id': ('project.json', '/screenplay_id'),
        '/screenplay/id': ('screenplay.json', '/id'),
        '/screenplay/elements': ('screenplay.json', '/elements'),
    }
    for key in ('title', 'author', 'created_at', 'modified_at'):
        exact['/project/metadata/' + key] = ('manifest.json', '/' + key)
    if path in exact:
        return 'mapped', *exact[path]
    # A field path, not a name match anywhere inside an unknown extension.
    if re.fullmatch(r'/screenplay/elements/[0-9]+/(id|type|text)', path):
        return 'mapped', 'screenplay.json', path[len('/screenplay'):]
    if re.fullmatch(r'/title_page/(title|subtitle|author|contact|draft_date)', path):
        return 'mapped', 'screenplay.json', path
    return 'preserved_opaque', 'extensions.json', pointer('/extensions/dev.screenplayos.legacy/fields', path)


def create_mapping(data, schema):
    """Build validated field fragments in memory; these are NOT package files."""
    inspection = inspect_bytes(data, schema)
    plan = {
        'mapping_version': '0.1', 'source_sha256': inspection['source_sha256'],
        'source_bytes': len(data), 'conversion_ready': False,
        'target_drafts': {'core': '1.0-unreleased', 'project': '0.1-draft'},
        'findings': [item for item in inspection['findings'] if item['code'] != 'mapping_deferred'],
        'structure': [], 'mappings': [],
        'payload_fragments': {}, 'preservation_verified': False,
        'identity_assignments': [],
    }
    if any(item['severity'] == 'blocker' for item in inspection['findings']):
        plan['status'] = 'blocked'
        # Inventory still explicitly marks every parsed source node as blocked.
        plan['blocked_fields'] = [item['path'] for item in inspection['inventory']]
        return plan
    root = parse_source(data)
    def walk(value, path):
        if isinstance(value, dict) and value:
            plan['structure'].append(dict(path=path, type='object', disposition='preserved_opaque', keys=list(value)))
            for key, child in value.items():
                walk(child, pointer(path, key))
        elif isinstance(value, list) and value:
            plan['structure'].append(dict(path=path, type='array', disposition='preserved_opaque', length=len(value)))
            for index, child in enumerate(value):
                walk(child, pointer(path, index))
        else:
            disposition, file, target = mapping_destination(path)
            fragments = plan['payload_fragments'].setdefault(file, {})
            if target in fragments:
                raise ValueError('mapping destination collision')
            fragments[target] = copy.deepcopy(value)
            plan['mappings'].append(dict(source=path, type=kind(value),
                disposition=disposition, file=file, target=target))
    walk(root, '')
    plan['status'] = 'field_fragments_only'
    validate_mapping(data, plan)
    plan['preservation_verified'] = True
    return plan


def recover_mapping(plan):
    """Recover the legacy tree solely from field fragments and structural records."""
    structures = {}
    leaves = {}
    used = set()
    for item in plan['structure']:
        if item.get('disposition') != 'preserved_opaque':
            raise ValueError('unsupported structural disposition')
        if item['path'] in structures:
            raise ValueError('duplicate structural record')
        structures[item['path']] = item
    for item in plan['mappings']:
        source = item['source']
        if source in leaves or source in structures:
            raise ValueError('duplicate source mapping')
        expected = mapping_destination(source)
        if (item['disposition'], item['file'], item['target']) != expected:
            raise ValueError('unsupported mapping rule')
        address = (item['file'], item['target'])
        if address in used:
            raise ValueError('duplicate target mapping')
        used.add(address)
        value = plan['payload_fragments'][item['file']][item['target']]
        if kind(value) != item['type']:
            raise ValueError('mapped value type changed')
        if isinstance(value, (dict, list)) and value:
            raise ValueError('nonempty subtree hidden in a leaf')
        leaves[source] = value
    actual = {(file, target) for file, fragments in plan['payload_fragments'].items() for target in fragments}
    if used != actual:
        raise ValueError('unaccounted target fragment')
    visited = set()
    def restore(path):
        visited.add(path)
        if path in leaves:
            return copy.deepcopy(leaves[path])
        item = structures[path]
        if item['type'] == 'object':
            keys = item['keys']
            if len(keys) != len(set(keys)) or any(type(key) is not str for key in keys):
                raise ValueError('invalid structural keys')
            return {key: restore(pointer(path, key)) for key in keys}
        if item['type'] != 'array' or type(item['length']) is not int or item['length'] < 1:
            raise ValueError('invalid structural array')
        return [restore(pointer(path, index)) for index in range(item['length'])]
    result = restore('')
    if visited != structures.keys() | leaves.keys():
        raise ValueError('unreachable source mapping')
    return result


def validate_mapping(data, plan):
    """Reject stale plans, changed values/types, missing coverage, or wrong routes."""
    if plan.get('mapping_version') != '0.1' or plan.get('status') != 'field_fragments_only':
        raise ValueError('unsupported or blocked mapping')
    if plan.get('source_sha256') != hashlib.sha256(data).hexdigest() or plan.get('source_bytes') != len(data):
        raise ValueError('source changed since planning')
    if plan.get('conversion_ready') is not False or plan.get('identity_assignments') != []:
        raise ValueError('conversion or identity assignment is not implemented')
    restored = recover_mapping(plan)
    # Serialization distinguishes booleans, numeric tokens and numeric-looking strings.
    # Dict ordering is irrelevant; array order, exact tokens and Unicode are preserved.
    if preserve_json(restored) != preserve_json(parse_source(data)):
        raise ValueError('source values or structure changed')
    encoded = preserve_json(restored)
    if preserve_json(parse_source(encoded)) != encoded:
        raise ValueError('preservation round trip failed')
    return True

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', help='Legacy monolithic JSON file (not FDX or a package)')
    parser.add_argument('--mapping', action='store_true', help='Validate draft field mapping in memory; print metadata only')
    args = parser.parse_args()
    try:
        schema = json.loads((Path(__file__).resolve().parent.parent / 'Specs/open-screenplay-1.0.schema.json').read_text())
        report = inspect_file(args.source, schema)
        if args.mapping:
            data = Path(args.source).read_bytes()
            if hashlib.sha256(data).hexdigest() != report['source_sha256']:
                raise ValueError('source changed before mapping')
            plan = create_mapping(data, schema)
            # Full fragments contain private creative data and remain in memory.
            report['findings'] = [item for item in report['findings'] if item['code'] != 'mapping_deferred']
            report['scope'] = 'Read-only inspection and validated field fragments; not package conformance or conversion.'
            report['mapping'] = {key: value for key, value in plan.items()
                                 if key not in ('payload_fragments', 'findings')}
            if Path(args.source).read_bytes() != data:
                raise ValueError('source changed during mapping')
    except (OSError, RecursionError, ValueError) as error:
        print(json.dumps({'error': type(error).__name__, 'conversion_available': False}), file=sys.stderr)
        return 2
    print(json.dumps(report, ensure_ascii=True, indent=2))
    return 1 if any(f['severity'] == 'blocker' for f in report['findings']) else 0


if __name__ == '__main__':
    sys.exit(main())
