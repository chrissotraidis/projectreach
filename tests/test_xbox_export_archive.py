"""Private archive preparation preserves the IPA and never requests upload."""
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/xbox'))
import export_archive


class ExportArchiveTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.ipa = self.root / 'source.ipa'
        self.out = self.root / 'staged'
        self.info = {'CFBundleIdentifier': 'dev.halopad.HaloPad', 'CFBundleExecutable': 'HaloPad',
                     'CFBundleSupportedPlatforms': ['iPhoneOS'], 'DTPlatformName': 'iphoneos',
                     'CFBundleShortVersionString': '0.3.8', 'CFBundleVersion': '14'}
        self.result = {'status': 'built-awaiting-acceptance', 'version': '0.3.8', 'build': '14',
                       'engine': {}, 'acceptance': {'consumer_upgrade': False}, 'artifacts': {'ios': {}}}
        self.write_ipa()
        p = patch.object(export_archive.candidate, 'audit'); self.audit = p.start(); self.addCleanup(p.stop)
        p = patch.object(export_archive, 'check', return_value={'com.apple.developer.team-identifier': 'TEAM'})
        self.check = p.start(); self.addCleanup(p.stop)
        p = patch.object(export_archive.subprocess, 'run', return_value=subprocess.CompletedProcess(
            [], 0, '', 'Authority=Apple Development: Fixture\n'))
        self.commands = p.start(); self.addCleanup(p.stop)

    def write_ipa(self):
        with zipfile.ZipFile(self.ipa, 'w') as z:
            z.writestr('Payload/HaloPad.app/Info.plist', plistlib.dumps(self.info))
            z.writestr('Payload/HaloPad.app/HaloPad', b'fixture executable')
        self.result['artifacts']['ios'] = {'path': str(self.ipa), 'sha256': export_archive.candidate.digest(self.ipa)}

    def prepare(self):
        return export_archive.prepare(self.result, self.out, self.root / 'profile', 'fixture identity')

    def test_archive_identity_local_export_and_unchanged_source(self):
        before = self.ipa.read_bytes()
        archive, options = self.prepare()
        self.assertEqual(before, self.ipa.read_bytes())
        info = plistlib.loads((archive / 'Info.plist').read_bytes())
        self.assertEqual(info['ApplicationProperties']['CFBundleVersion'], '14')
        self.assertEqual(info['ApplicationProperties']['SigningIdentity'], 'Apple Development: Fixture')
        self.assertEqual(plistlib.loads(options.read_bytes())['destination'], 'export')
        self.assertFalse(plistlib.loads(options.read_bytes())['manageAppVersionAndBuildNumber'])
        self.assertFalse(json.loads((self.out / 'source.json').read_text())['uploaded'])
        self.assertFalse(self.result['acceptance']['consumer_upgrade'])
        self.audit.assert_called_once()
        self.check.assert_called_once_with(self.root / 'profile', 'dev.halopad.HaloPad', 'fixture identity')
        with self.assertRaises(FileExistsError):
            self.prepare()

    def test_missing_platform_metadata_stops_before_signing(self):
        del self.info['DTPlatformName']; self.write_ipa()
        with self.assertRaisesRegex(ValueError, 'platform metadata'):
            self.prepare()
        self.check.assert_not_called()
        self.commands.assert_not_called()
        self.assertFalse(self.out.exists())

    def test_changed_ipa_rejected_before_signing(self):
        self.ipa.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'changed after'):
            self.prepare()
        self.commands.assert_not_called()
        self.assertFalse(self.out.exists())

    def test_profile_rejection_preserves_source_and_leaves_no_archive(self):
        self.check.side_effect = ValueError('profile rejected')
        before = self.ipa.read_bytes()
        with self.assertRaisesRegex(ValueError, 'profile rejected'):
            self.prepare()
        self.assertEqual(before, self.ipa.read_bytes())
        self.commands.assert_not_called()
        self.assertFalse(self.out.exists())


if __name__ == '__main__':
    unittest.main()
