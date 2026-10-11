#!/usr/bin/env python3
"""Copy the public site into an existing Sites dist directory.

Keeps the canonical download URL in Website/release.json for email rendering,
but omits it from the browser-facing release.json. Existing downloads remain.
"""
import argparse
import json
import shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('destination', type=Path, help='existing Sites dist directory')
args = parser.parse_args()
destination = args.destination.resolve()
if not destination.is_dir():
    parser.error('destination must be an existing directory')
for name in ('index.html', 'style.css', 'site.js'):
    shutil.copy2(HERE / name, destination / name)
(destination / 'assets').mkdir(exist_ok=True)
shutil.copy2(HERE / 'assets' / 'ScreenplayOSLogo.png', destination / 'assets' / 'ScreenplayOSLogo.png')
shutil.copytree(HERE / 'assets' / 'screenshots', destination / 'assets' / 'screenshots', dirs_exist_ok=True)
release = json.loads((HERE / 'release.json').read_text())
public = {key: release[key] for key in ('version', 'build', 'releaseDate')}
(destination / 'release.json').write_text(json.dumps(public, indent=2) + '\n')
print(f'Prepared public site at {destination} without the download URL')
