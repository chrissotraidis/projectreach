"""A consumer feed must describe the exact audited IPA and retain old staging."""
import hashlib
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/xbox'))
import update_source
import candidate


class UpdateSourceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.result = {'status': 'built-awaiting-acceptance', 'version':'0.3.8', 'build':'13',
                       'engine': {'revision':'a'*40, 'release':'build-150'}, 'artifacts':{},
                       'acceptance': {'gameplay':False, 'consumer_upgrade':False, 'publication':False}}
        for platform in ('ios', 'mac'):
            mac = platform == 'mac'
            bundle = 'HaloPad.app' if mac else 'Payload/HaloPad.app'
            resources = bundle + ('/Contents/Resources' if mac else '')
            info = {'CFBundleIdentifier':'dev.halopad.HaloPad', 'CFBundleShortVersionString':'0.3.8',
                    'CFBundleVersion':'13', 'CFBundleSupportedPlatforms':['MacOSX' if mac else 'iPhoneOS'],
                    'LSMinimumSystemVersion' if mac else 'MinimumOSVersion':'14.4' if mac else '17.4',
                    'NSLocalNetworkUsageDescription':'Find Halo games.'}
            package = self.root / (platform + '.zip')
            with zipfile.ZipFile(package, 'w') as z:
                z.writestr(bundle + ('/Contents/Info.plist' if mac else '/Info.plist'), plistlib.dumps(info))
                z.writestr(resources + '/data/xbox/build.json', json.dumps({**self.result['engine'],
                    'network_version':24, 'guest_sha256':hashlib.sha256(b'guest').hexdigest()}))
                z.writestr(resources + '/data/xbox/halo_guest.elf', b'guest')
                z.writestr(resources + '/data/xbox/brokers.txt', 'broker.invalid')
            self.result['artifacts'][platform] = {'path':str(package),'sha256':candidate.digest(package)}
        # Exercise real archive/identity audits; only macOS signature tools are inert.
        p = patch.object(candidate.subprocess, 'run'); p.start(); self.addCleanup(p.stop)
        p = patch.object(update_source.subprocess, 'check_output', return_value=plistlib.dumps(
            {k:True for k in update_source.REQUIRED})); self.entitlements=p.start(); self.addCleanup(p.stop)

    def stage(self):
        return update_source.stage(self.result, self.root / 'staged', 'v0.3.8')

    def test_exact_packages_feed_and_preserved_acceptance_state(self):
        metadata = self.stage(); out = self.root / 'staged'
        feed = json.loads((out / 'altstore.json').read_text()); app=feed['apps'][0]
        version = app['versions'][0]
        self.assertEqual(feed['sourceURL'], update_source.app_channel.BASE + '/altstore.json')
        self.assertNotIn('/releases/latest/',feed['sourceURL'])
        self.assertEqual((version['version'], version['buildVersion']), ('0.3.8','13'))
        self.assertEqual(version['size'], (out / 'HaloPad.ipa').stat().st_size)
        self.assertEqual(version['downloadURL'], metadata['artifacts']['ios']['url'])
        self.assertEqual(version['minOSVersion'], '17.4')
        self.assertEqual(set(app['appPermissions']['entitlements']), update_source.REQUIRED)
        self.assertEqual(candidate.digest(out / 'HaloPad.ipa'), self.result['artifacts']['ios']['sha256'])
        self.assertFalse(json.loads((out / 'review.json').read_text())['published'])
        self.assertFalse(self.result['acceptance']['consumer_upgrade'])

    def test_modified_package_and_wrong_engine_rejected_before_staging(self):
        p=Path(self.result['artifacts']['ios']['path']); p.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'changed since'): self.stage()
        self.assertFalse((self.root / 'staged').exists())

    def test_restage_uses_original_candidate_date_for_identical_retry_bytes(self):
        self.result['started'] = '2026-10-08T08:00:00+00:00'
        self.stage()
        update_source.stage(self.result, self.root/'retry', 'v0.3.8')
        for name in ('altstore.json', 'halopad-update.json', 'SHA256SUMS'):
            self.assertEqual((self.root/'staged'/name).read_bytes(), (self.root/'retry'/name).read_bytes())

    def test_failed_candidate_and_path_like_tag_rejected(self):
        self.result['status']='failed'
        with self.assertRaises(ValueError): self.stage()
        self.result['status']='built-awaiting-acceptance'
        with self.assertRaises(ValueError): update_source.stage(self.result, self.root/'out','../v1')

    def test_missing_entitlement_and_existing_staging_are_not_overwritten(self):
        self.entitlements.return_value=plistlib.dumps({})
        with self.assertRaisesRegex(ValueError, 'entitlements'): self.stage()
        self.entitlements.return_value=plistlib.dumps({k:True for k in update_source.REQUIRED})
        self.stage(); before=(self.root/'staged/altstore.json').read_bytes()
        with self.assertRaises(FileExistsError): self.stage()
        self.assertEqual(before,(self.root/'staged/altstore.json').read_bytes())


if __name__ == '__main__':
    unittest.main()
