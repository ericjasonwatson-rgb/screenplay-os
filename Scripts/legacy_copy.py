"""macOS-only, new-destination writer for the unreleased migration profile."""
import ctypes
import copy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys
import tempfile

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location('legacy_destination', Path(__file__).with_name('legacy_destination.py'))
destination = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(destination)
raw = destination.raw
_media_spec = importlib.util.spec_from_file_location('legacy_media', Path(__file__).with_name('legacy_media.py'))
legacy_media = importlib.util.module_from_spec(_media_spec)
_media_spec.loader.exec_module(legacy_media)


class CopyFailure(Exception):
    def __init__(self, phase, recovery_path, published, cause):
        super().__init__('Copy failed during ' + phase + '; retained output requires verification.')
        self.phase, self.recovery_path, self.published = phase, str(recovery_path), published
        self.cause = type(cause).__name__


def _read_regular(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError('expected a regular file')
        return stream.read()


def _sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def _write_new(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())
        # macOS SDK sys/fcntl.h: flush the device cache as well as filesystem buffers.
        # Unsupported filesystems fail rather than receiving a silent weaker guarantee.
        fcntl.fcntl(stream.fileno(), 51)  # F_FULLFSYNC


def _publish_exclusive(stage, target):
    if sys.platform != 'darwin':
        raise OSError('exclusive publication currently supports macOS only')
    library = ctypes.CDLL(None, use_errno=True)
    rename = library.renamex_np
    rename.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    rename.restype = ctypes.c_int
    # macOS SDK sys/stdio.h: RENAME_EXCL rejects any existing destination.
    if rename(os.fsencode(stage), os.fsencode(target), 0x00000004):
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


def read_copy(package):
    """Read from disk alone; verify bytes, schema, source archive, and mapping."""
    package = Path(package)
    if package.is_symlink() or not package.is_dir():
        raise ValueError('expected an ordinary package directory')
    names = set()
    folded = set()
    for parent, dirs, files in os.walk(package, followlinks=False):
        for name in dirs + files:
            path = Path(parent) / name
            if path.is_symlink():
                raise ValueError('symlinks are not allowed in a converted copy')
            relative = path.relative_to(package).as_posix()
            if relative.casefold() in folded:
                raise ValueError('case-colliding package paths')
            folded.add(relative.casefold())
            if name in files:
                names.add(relative)
    metadata = raw.parse_source(_read_regular(package / 'provenance/candidate.json'))
    original = _read_regular(package / 'provenance/source.json')
    project = raw.parse_source(_read_regular(package / 'project.json'))
    inventory = project['head']['files']
    allowed = set(destination.load_schema()['properties']) - {'project.json'}
    attachment_names = {name for name in inventory if name.startswith('attachments/boards/')}
    json_names = set(inventory) - attachment_names
    if (not isinstance(inventory, dict) or not json_names <= allowed or
            any(name != 'attachments/boards/' + Path(name).stem + '.png' or
                len(Path(name).stem) != 64 or any(c not in '0123456789abcdef' for c in Path(name).stem)
                for name in attachment_names)):
        raise ValueError('unsafe or unsupported inventory path')
    expected = set(inventory) | {'project.json', 'provenance/source.json', 'provenance/candidate.json'}
    if names != expected:
        raise ValueError('missing or unaccounted package file')
    payloads = {}
    attachment_bytes = {}
    for name, entry in inventory.items():
        data = _read_regular(package / name)
        if hashlib.sha256(data).hexdigest() != entry['sha256'] or len(data) != int(entry['bytes']):
            raise ValueError('payload bytes do not match the committed inventory')
        if name in attachment_names: attachment_bytes[name] = data
        else: payloads[name] = raw.parse_source(data)
    if not isinstance(metadata, dict) or 'files' in metadata:
        raise ValueError('invalid candidate metadata')
    registry = payloads.pop('film/media.json', None)
    base_project = copy.deepcopy(project)
    for name in attachment_names | ({'film/media.json'} if registry is not None else set()):
        base_project['head']['files'].pop(name, None)
    candidate = {**metadata, 'files': {'project.json': base_project, **payloads}}
    destination.validate_candidate(original, candidate)
    if registry is None:
        if attachment_bytes: raise ValueError('attachments require a media registry')
    else:
        if registry.get('project_id') != project.get('project_id'):
            raise ValueError('media registry project mismatch')
        legacy_media.validate_packaged_media(registry, payloads.get('film/boards.json', {}).get('boards', []), attachment_bytes)
    return {'source_sha256': hashlib.sha256(original).hexdigest(),
            'project_revision': project['head']['id'], 'payload_files': len(payloads),
            'media_attachments': len(attachment_bytes), 'verified': True, 'app_editing_supported': False}


def write_copy(source, target, checkpoint=lambda phase, stage: None):
    """Never overwrite a destination; checkpoint is an in-process test seam."""
    if sys.platform != 'darwin':
        raise ValueError('converted-copy writer currently supports macOS only')
    source, target = Path(source).absolute(), Path(target).absolute()
    if target.suffix != '.screenplay':
        raise ValueError('destination must end in .screenplay')
    # Resolve the existing parent once; stage and destination share one filesystem.
    parent = target.parent.resolve(strict=True)
    target = parent / target.name
    if os.path.lexists(target):
        raise FileExistsError('destination already exists')
    original = _read_regular(source)
    candidate = destination.build_candidate(original)
    media_plan = legacy_media.build_media_plan(source)
    stage = Path(tempfile.mkdtemp(prefix='.screenplay-conversion-', dir=parent))
    phase, published = 'staging_created', False
    try:
        checkpoint(phase, stage)
        files = copy.deepcopy(candidate['files'])
        payloads = {name: raw.preserve_json(value) for name, value in files.items()}
        if media_plan['media']:
            registry = {'version': media_plan['version'], 'project_id': media_plan['project_id'], 'media': media_plan['media']}
            payloads['film/media.json'] = raw.preserve_json(registry)
            for name, entry in media_plan['attachments'].items():
                data = _read_regular(entry['source_path'])
                if hashlib.sha256(data).hexdigest() != entry['sha256'] or len(data) != entry['bytes']:
                    raise ValueError('board image changed during staging')
                payloads[name] = data
            for name in ['film/media.json', *media_plan['attachments']]:
                data = payloads[name]
                files['project.json']['head']['files'][name] = {'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)}
            payloads['project.json'] = raw.preserve_json(files['project.json'])
        payloads['provenance/source.json'] = original
        payloads['provenance/candidate.json'] = raw.preserve_json({key: value for key, value in candidate.items() if key != 'files'})
        for name, data in payloads.items():
            phase = 'write:' + name
            path = stage / name
            path.parent.mkdir(parents=True, exist_ok=True)
            _write_new(path, data)
            checkpoint(phase, stage)
        for folder, _, _ in os.walk(stage, topdown=False):
            _sync_directory(folder)
        phase = 'staged_readback'
        checkpoint(phase, stage)
        read_copy(stage)
        phase = 'before_publish'
        checkpoint(phase, stage)
        if _read_regular(source) != original:
            raise ValueError('source changed during conversion')
        _publish_exclusive(stage, target)
        published = True
        phase = 'published'
        checkpoint(phase, target)
        _sync_directory(parent)
        phase = 'published_readback'
        checkpoint(phase, target)
        result = read_copy(target)
        if _read_regular(source) != original:
            raise ValueError('source changed before final confirmation')
        return {**result, 'destination': str(target), 'source_unchanged_at_confirmation': True}
    except Exception as error:
        # Keep both complete and incomplete output for diagnosis/recovery.
        # Never delete a competing destination or roll back a published copy.
        raise CopyFailure(phase, target if published else stage, published, error) from error
