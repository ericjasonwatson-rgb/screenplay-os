"""Read-only media migration plan for legacy board image versions."""
import hashlib
import importlib.util
import os
from pathlib import Path
import stat
import struct
import sys
from urllib.parse import unquote, urlparse
import uuid

sys.dont_write_bytecode = True
_spec = importlib.util.spec_from_file_location('legacy_inspection', Path(__file__).with_name('inspect-legacy.py'))
raw = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(raw)

MAX_IMAGE_BYTES = 100 * 1024 * 1024


def _read_regular(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_IMAGE_BYTES:
            raise ValueError('board image must be a bounded regular file')
        return stream.read()


def _resolve(source, value):
    if not isinstance(value, str) or not value:
        raise ValueError('board image URL is missing')
    parsed = urlparse(value)
    if parsed.scheme not in ('', 'file') or parsed.netloc not in ('', 'localhost') or parsed.query or parsed.fragment:
        raise ValueError('board image must be a local file')
    path = Path(unquote(parsed.path))
    if not path.is_absolute():
        parts = path.parts
        if len(parts) != 2 or parts[0] != 'Board Images' or parts[1] in ('', '.', '..'):
            raise ValueError('relative board image must be one file in Board Images')
        path = source.parent / path
    return path


def _png_dimensions(data):
    if len(data) < 24 or data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise ValueError('board image is not a PNG')
    width, height = struct.unpack('>II', data[16:24])
    if not (1 <= width <= 32768 and 1 <= height <= 32768):
        raise ValueError('board image dimensions are invalid')
    return width, height


def build_media_plan(source_path):
    """Inspect without writing. Returned source paths are for the later staged writer."""
    source = Path(source_path).absolute()
    document = raw.parse_source(_read_regular(source))
    project_id = uuid.UUID(document['project']['id'])
    attachments, media = {}, []
    for board in document.get('board_frames', []):
        versions = board.get('image_versions', [])
        selected = board.get('selected_image_id')
        if selected is not None and selected not in [item.get('id') for item in versions]:
            raise ValueError('selected board image is missing')
        if not versions:
            continue
        asset_id = str(uuid.uuid5(project_id, 'board-media:' + board['id'].lower()))
        migrated = []
        for item in versions:
            declared = item.get('sha256')
            if not isinstance(declared, str) or len(declared) != 64 or any(c not in '0123456789abcdef' for c in declared):
                raise ValueError('board image digest is invalid')
            path = _resolve(source, item.get('fileURL', item.get('file_url')))
            data = _read_regular(path)
            actual = hashlib.sha256(data).hexdigest()
            if actual != declared:
                raise ValueError('board image digest does not match its bytes')
            width, height = _png_dimensions(data)
            relative = 'attachments/boards/' + actual + '.png'
            attachments.setdefault(relative, {'source_path': str(path), 'sha256': actual, 'bytes': len(data)})
            migrated.append({'id': item['id'], 'path': relative, 'sha256': actual,
                             'bytes': len(data), 'media_type': 'image/png',
                             'width': width, 'height': height,
                             'prompt': item.get('prompt', ''), 'model': item.get('model', '')})
        media.append({'id': asset_id, 'board_id': board['id'], 'shot_id': board['shot_id'],
                      'selected_version_id': selected, 'versions': migrated})
    return {'version': 1, 'project_id': str(project_id), 'media': media, 'attachments': attachments}
