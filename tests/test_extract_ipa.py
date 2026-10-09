"""Exercise real ZIP input at the downloaded-app boundary; never run its executable."""
import hashlib
import importlib.util
from pathlib import Path
import plistlib
import stat
import tempfile
import unittest
import zipfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('extract_ipa', ROOT / 'scripts/extract-ipa.py')
ipa = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ipa)


class ExtractIPATests(unittest.TestCase):
    def make_archive(self, root, extra=None, platform='iPhoneOS'):
        archive = root / 'HaloPad.ipa'
        with zipfile.ZipFile(archive, 'w') as z:
            z.writestr(ipa.APP + '/Info.plist', plistlib.dumps({
                'CFBundleIdentifier': 'dev.halopad.HaloPad',
                'CFBundleExecutable': 'HaloPad', 'CFBundleSupportedPlatforms': [platform]}))
            executable = zipfile.ZipInfo(ipa.APP + '/HaloPad')
            executable.external_attr = (stat.S_IFREG | 0o755) << 16
            z.writestr(executable, b'inert executable fixture')
            z.writestr(ipa.APP + '/data/xbox/build.json', '{}')
            if extra:
                for name, content in extra:
                    z.writestr(name, content)
        return archive

    def test_extract_preserves_bytes_and_executable_mode_without_changing_ipa(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive = self.make_archive(root, [('__MACOSX/._Payload', b'metadata')])
            before = hashlib.sha256(archive.read_bytes()).hexdigest()
            app = ipa.extract(archive, root / 'out')
            self.assertEqual((app / 'HaloPad').read_bytes(), b'inert executable fixture')
            self.assertTrue((app / 'HaloPad').stat().st_mode & stat.S_IXUSR)
            self.assertFalse((root / 'out/__MACOSX').exists())
            self.assertEqual(hashlib.sha256(archive.read_bytes()).hexdigest(), before)

    def test_unsafe_paths_and_extra_apps_fail_before_extracting(self):
        names = ['../escaped', '/escaped', ipa.APP + '/../../escaped',
                 ipa.APP + '/data\\escaped', ipa.APP + '/data/./file',
                 'Payload/Other.app/executable', ipa.APP + '/INFo.plist']
        for name in names:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                archive = self.make_archive(root, [(name, b'fixture')])
                with self.assertRaises(ValueError):
                    ipa.extract(archive, root / 'out')
                self.assertFalse((root / 'out').exists())

    def test_symlinks_and_special_files_are_rejected(self):
        for kind in (stat.S_IFLNK, stat.S_IFIFO):
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                entry = zipfile.ZipInfo(ipa.APP + '/link')
                entry.external_attr = (kind | 0o777) << 16
                archive = self.make_archive(root, [(entry, b'/outside')])
                with self.assertRaises(ValueError):
                    ipa.extract(archive, root / 'out')
                self.assertFalse((root / 'out').exists())

    def test_non_device_apps_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive = self.make_archive(root, platform='iPhoneSimulator')
            with self.assertRaisesRegex(ValueError, 'iPhone/iPad'):
                ipa.extract(archive, root / 'out')

    def test_existing_destination_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            archive = self.make_archive(root)
            (root / 'out').mkdir()
            (root / 'out/keep').write_bytes(b'preserve')
            with self.assertRaises(FileExistsError):
                ipa.extract(archive, root / 'out')
            self.assertEqual(list((root / 'out').iterdir()), [root / 'out/keep'])

    def test_oversized_package_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(ipa, 'MAX_BYTES', 1):
            root = Path(folder)
            archive = self.make_archive(root)
            with self.assertRaisesRegex(ValueError, 'size'):
                ipa.extract(archive, root / 'out')


if __name__ == '__main__':
    unittest.main()
