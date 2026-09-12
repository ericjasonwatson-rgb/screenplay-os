"""Unreleased, in-memory destination construction. No file or network writes."""
import copy
from datetime import datetime, timezone
from decimal import Decimal
import hashlib
import importlib.util
import json
import re
from pathlib import Path
import sys
import uuid

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location('legacy_inspection', Path(__file__).with_name('inspect-legacy.py'))
raw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(raw)
ROOT = Path(__file__).resolve().parent.parent


def load_schema():
    return json.loads((ROOT / 'Specs/drafts/legacy-destination-0.1.schema.json').read_text())


def schema_validate(files):
    # Validation uses a separate Decimal view; the preserved tree never changes.
    from jsonschema import Draft202012Validator, FormatChecker, validators
    schema = load_schema()
    Draft202012Validator.check_schema(schema)
    def is_integer(_, value):
        if type(value) is int:
            return True
        return isinstance(value, Decimal) and value.is_finite() and value == value.to_integral_value()
    checker = Draft202012Validator.TYPE_CHECKER.redefine('integer', is_integer)
    validator = validators.extend(Draft202012Validator, type_checker=checker)
    formats = FormatChecker()
    @formats.checks('date-time')
    def timestamp(value):
        if type(value) is not str or not re.fullmatch(r'\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[Zz]|[+-]\d{2}:\d{2})', value):
            return False
        try:
            return datetime.fromisoformat(value.upper()).tzinfo is not None
        except ValueError:
            return False
    view = json.loads(raw.preserve_json(files), parse_float=Decimal, parse_int=Decimal)
    errors = list(validator(schema, format_checker=formats).iter_errors(view))
    if errors:
        # Do not embed private values in diagnostics.
        raise ValueError('destination schema violation at ' + '/'.join(str(x) for x in errors[0].absolute_path))


def _construct(data, created_at):
    schema = json.loads((ROOT / 'Specs/open-screenplay-1.0.schema.json').read_text())
    plan = raw.create_mapping(data, schema)
    if plan['status'] == 'blocked':
        raise ValueError('legacy inspection blockers must be resolved first')
    inspection = raw.inspect_bytes(data, schema)
    if any(ref['status'] != 'resolved' for ref in inspection['references']):
        raise ValueError('unresolved or ambiguous reference: retain source for explicit repair')
    source = raw.parse_source(data)
    digest = hashlib.sha256(data).hexdigest()
    project_id = source['project']['id']
    namespace = uuid.UUID(project_id)
    def identity(role):
        return str(uuid.uuid5(namespace, 'legacy-destination-0.1:' + role))
    scene_map, aliases = {}, {}
    for element in source['screenplay']['elements']:
        if element['type'] == 'scene_heading':
            scene_map[element['id']] = identity('scene:' + element['id'].lower())
            alias = element.get('spine_id')
            if alias:
                aliases[alias] = scene_map[element['id']]
    existing = {item['id'].lower() for item in inspection['identities']}
    if existing.intersection(scene_map.values()) or len(set(scene_map.values())) != len(scene_map):
        raise ValueError('new scene identity collision')
    reference_paths = {item['path'] for item in inspection['references'] if item['kind'] == 'scene'}
    changes = []
    def translate(value, path):
        if isinstance(value, list):
            return [translate(child, raw.pointer(path, index)) for index, child in enumerate(value)]
        if not isinstance(value, dict):
            return copy.deepcopy(value)
        output = {key: translate(child, raw.pointer(path, key)) for key, child in value.items()}
        p = raw.pointer(path, 'scene_spine_id')
        if p in reference_paths:
            if 'scene_id' in output:
                raise ValueError('existing scene_id requires explicit reconciliation')
            output['scene_id'] = aliases[value['scene_spine_id']]
            changes.append({'source': p, 'target_scene_id': output['scene_id']})
        p = raw.pointer(path, 'linked_scene_spine_ids')
        if 'linked_scene_spine_ids' in value and (not value['linked_scene_spine_ids'] or raw.pointer(p, 0) in reference_paths):
            # Only known outline beats, not similarly named unknown extension fields.
            if path.startswith('/outline/') and len(path.split('/')) == 3:
                if 'linked_scene_ids' in output:
                    raise ValueError('existing linked_scene_ids requires explicit reconciliation')
                output['linked_scene_ids'] = [aliases[item] for item in value['linked_scene_spine_ids']]
                changes.extend({'source': raw.pointer(p, i), 'target_scene_id': id} for i, id in enumerate(output['linked_scene_ids']))
        return output
    translated = translate(source, '')
    elements = copy.deepcopy(source['screenplay']['elements'])
    for element in elements:
        if element['id'] in scene_map:
            if 'scene' in element:
                raise ValueError('existing scene metadata requires explicit reconciliation')
            element['scene'] = {'id': scene_map[element['id']]}
    metadata = source['project']['metadata']
    files = {
        'manifest.json': {'format': 'open-screenplay', 'format_version': '1.0',
                          'document_id': source['screenplay']['id'], **{key: metadata[key] for key in ('title', 'author', 'created_at', 'modified_at')}},
        'screenplay.json': {'id': source['screenplay']['id'], 'elements': elements},
        # Immutable migration archive, explicitly not a second editable screenplay.
        'extensions.json': {'extensions': {'dev.screenplayos.legacy': {
            'version': '0.1', 'source_sha256': digest, 'role': 'immutable-migration-archive', 'source': copy.deepcopy(source)}}},
    }
    if 'title_page' in source:
        files['screenplay.json']['title_page'] = copy.deepcopy(source['title_page'])
    if 'script_notes' in source:
        notes = []
        for original in translated['script_notes']:
            if any(key in original for key in ('text', 'anchor', 'resolved')):
                raise ValueError('note target field collision')
            if original['status'] not in ('open', 'resolved'):
                raise ValueError('unsupported note resolution state')
            note = copy.deepcopy(original)
            note['text'] = note.pop('body')
            note['anchor'] = {'element_id': note.pop('screenplay_element_id')}
            note['resolved'] = note.pop('status') == 'resolved'
            notes.append(note)
        files['notes.json'] = {'notes': notes}
    if 'shots' in source:
        groups = {}
        for original in translated['shots']:
            shot = copy.deepcopy(original)
            scene_id = shot['scene_id']
            groups.setdefault(scene_id, [])
            if 'ordinal' in shot:
                raise ValueError('shot ordinal collision')
            shot['ordinal'] = len(groups[scene_id]) + 1
            for ref in shot['source_refs']:
                if 'element_id' in ref:
                    raise ValueError('source reference field collision')
                ref['element_id'] = ref.pop('screenplay_element_id')
                # Legacy offsets are preserved without claiming scalar-range conversion.
            groups[scene_id].append(shot)
        files['shots.json'] = {'shot_addenda': [
            {'id': identity('shot-addendum:' + scene), 'scene_id': scene, 'shots': shots}
            for scene, shots in groups.items()]}
    for source_key, file, wrapper in [
        ('outline', 'film/outline.json', 'beats'), ('board_frames', 'film/boards.json', 'boards'),
        ('editorial_spine', 'film/edit.json', None), ('production_context', 'film/production.json', None),
        ('proposals', 'film/proposals.json', 'proposals'), ('activity', 'film/activity.json', 'activity')]:
        if source_key in translated:
            files[file] = {wrapper: translated[source_key]} if wrapper else translated[source_key]
    revision = identity('revision:' + digest + ':' + created_at)
    objects = []
    # Only schema-understood source identities and deliberately allocated IDs.
    # Never infer an object from an arbitrary unknown extension's "id" key.
    records = [(item['id'], item['path']) for item in inspection['identities']]
    records += [(id, 'scene') for id in scene_map.values()]
    records += [(item['id'], 'shot-addendum') for item in files.get('shots.json', {}).get('shot_addenda', [])]
    if len({id.lower() for id, _ in records}) != len(records):
        raise ValueError('destination identity collision')
    for id, kind in records:
        objects.append({'id': id, 'kind': kind, 'revision_id': identity('object:' + id.lower() + ':' + revision),
                        'parents': [], 'state': 'active'})
    files['project.json'] = {'format': 'open-screenplay-project', 'format_version': '0.1-draft',
        'project_id': project_id, 'screenplay_id': source['screenplay']['id'],
        'head': {'id': revision, 'parents': [], 'created_at': created_at, 'objects': objects,
                 'files': {file: {'sha256': hashlib.sha256(raw.preserve_json(content)).hexdigest(),
                                  'bytes': len(raw.preserve_json(content))} for file, content in files.items()}}}
    return {'candidate_version': '0.1', 'source_sha256': digest, 'scene_map': scene_map,
            'reference_mapping': changes, 'files': files, 'conversion_ready': False,
            'limitations': ['No package writer or app migration is enabled.',
                            'Unknown/service/lock data remains in the immutable legacy archive.',
                            'No media registry, history reconstruction, or synchronization is implemented.']}


def validate_candidate(data, candidate):
    if candidate.get('conversion_ready') is not False or candidate.get('candidate_version') != '0.1':
        raise ValueError('unsupported candidate state')
    if candidate.get('source_sha256') != hashlib.sha256(data).hexdigest():
        raise ValueError('candidate is stale')
    schema_validate(candidate['files'])
    # Regenerate the deterministic mapping to verify content and references, not
    # just shape or a checksum that could have been recomputed after a bad edit.
    timestamp = candidate['files']['project.json']['head']['created_at']
    expected = _construct(data, timestamp)
    if raw.preserve_json(candidate) != raw.preserve_json(expected):
        raise ValueError('candidate values, identities, references or inventory differ from the mapping')
    return True


def build_candidate(data, created_at=None):
    created_at = created_at or datetime.now(timezone.utc).isoformat()
    candidate = _construct(data, created_at)
    validate_candidate(data, candidate)
    return candidate
