"""Regression checks against the real packaged app, including damaged copies."""
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('verify', 'Scripts/verify-tester-app.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TesterBundleTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='Tester Bundle With Spaces ')
        self.addCleanup(self.temp.cleanup)
        self.app = Path(self.temp.name) / 'ScreenplayOS.app'
        shutil.copytree(os.environ['TESTER_APP'], self.app)
        self.revision = os.environ['TESTER_REVISION']

    def test_relocated_bundle(self):
        module.verify(self.app, self.revision)

    def test_missing_domain_resources_rejected(self):
        shutil.rmtree(self.app / 'Contents/Resources/ScreenplayOSStarter_ScreenplayDomain.bundle')
        with self.assertRaises(FileNotFoundError):
            module.verify(self.app, self.revision)

    def test_missing_executable_permission_rejected(self):
        (self.app / 'Contents/MacOS/ScreenplayOS').chmod(0o644)
        with self.assertRaisesRegex(ValueError, 'permission'):
            module.verify(self.app, self.revision)

    def test_wrong_commit_rejected(self):
        with self.assertRaisesRegex(ValueError, 'SourceCommit'):
            module.verify(self.app, '0' * 40)

    def test_wrong_bundle_type_rejected(self):
        path = self.app / 'Contents/Info.plist'
        info = plistlib.loads(path.read_bytes())
        info['CFBundlePackageType'] = 'BNDL'
        path.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, 'PackageType'):
            module.verify(self.app, self.revision)


if __name__ == '__main__':
    unittest.main()
