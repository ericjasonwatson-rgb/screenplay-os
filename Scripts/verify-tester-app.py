"""Validate a relocated tester bundle; no source checkout resources are consulted."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys


def verify(app, revision):
    app = Path(app)
    contents = app / 'Contents'
    info = plistlib.loads((contents / 'Info.plist').read_bytes())
    expected = {
        'CFBundleExecutable': 'ScreenplayOS', 'CFBundlePackageType': 'APPL',
        'CFBundleIdentifier': 'com.screenplayos.tester',
        'LSMinimumSystemVersion': '13.0', 'ScreenplayOSSourceCommit': revision,
        'ScreenplayOSBuildConfiguration': 'release',
        'ScreenplayOSDistribution': 'Local tester (ad-hoc, not notarized)',
    }
    for key, value in expected.items():
        if info.get(key) != value:
            raise ValueError(f'{key}: expected {value!r}, got {info.get(key)!r}')
    if info['ScreenplayOSRevision'].endswith('-dirty'):
        raise ValueError('Dirty source build')
    executable = contents / 'MacOS/ScreenplayOS'
    if not os.access(executable, os.X_OK):
        raise ValueError('Executable permission missing')
    resources = contents / 'Resources'
    for name in ['ScreenplayOS.icns', 'ScreenplayOSAppIcon.png',
                 'ScreenplayOSStarter_ScreenplayOSApp.bundle/ScreenplayOS.icns',
                 'ScreenplayOSStarter_ScreenplayOSApp.bundle/ScreenplayOSAppIcon.png',
                 'LegacyConverter/Scripts/convert-legacy-copy.py',
                 'LegacyConverter/Specs/screenplayos-1.0.schema.json']:
        if not (resources / name).is_file():
            raise ValueError(f'Missing resource: {name}')
    json.loads((resources / 'ScreenplayOSStarter_ScreenplayDomain.bundle/pricing.json').read_text())
    arches = subprocess.check_output(['lipo', '-archs', str(executable)], text=True).split()
    if set(arches) != {'arm64', 'x86_64'}:
        raise ValueError(f'Expected universal executable; got {arches}')
    linked = subprocess.check_output(['otool', '-L', str(executable)], text=True)
    for line in linked.splitlines():
        if line.startswith('\t'):
            dependency = line.strip().split(' (')[0]
            if not dependency.startswith(('/System/Library/', '/usr/lib/')):
                raise ValueError(f'Non-system runtime dependency: {dependency}')
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    signature = subprocess.run(['codesign', '-dv', str(app)], capture_output=True, text=True, check=True).stderr
    if 'Signature=adhoc' not in signature or 'TeamIdentifier=not set' not in signature:
        raise ValueError('Expected ad-hoc signature without a developer team')
    print(f'PASS: universal, self-contained, ad-hoc tester bundle at {revision}')


if __name__ == '__main__':
    verify(*sys.argv[1:])
