"""Apple TV builds are signed only with a profile that can install the app.

The profiles are dictionaries shaped like a decoded provisioning profile;
no keychain or Xcode profile is needed."""
import datetime
import importlib.util
import pathlib
import plistlib
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('tvos_signing', ROOT / 'scripts/xbox/tvos-signing.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)

NOW = datetime.datetime(2026, 11, 17)
CERT = b'certificate'


def profile(bundle='com.example.halopad', team='ABCDE12345', platform='tvOS', days=30, development=True,
            created=1, extended=True):
    entitlements = {'application-identifier': '%s.%s' % (team, bundle),
                    'com.apple.developer.team-identifier': team,
                    'get-task-allow': development,
                    'keychain-access-groups': ['%s.*' % team]}
    if extended:
        entitlements['com.apple.developer.kernel.extended-virtual-addressing'] = True
    return {'Platform': [platform], 'ExpirationDate': NOW + datetime.timedelta(days=days),
            'CreationDate': NOW - datetime.timedelta(days=created), 'Entitlements': entitlements,
            'DeveloperCertificates': [CERT]}


class TvosSigningTests(unittest.TestCase):
    def test_only_unexpired_tvos_development_profiles_for_one_app(self):
        self.assertTrue(signing.usable(profile(), None, None, NOW))
        self.assertFalse(signing.usable(profile(platform='iOS'), None, None, NOW))
        self.assertFalse(signing.usable(profile(days=-1), None, None, NOW))
        self.assertFalse(signing.usable(profile(development=False), None, None, NOW))
        self.assertFalse(signing.usable(profile(bundle='*'), None, None, NOW))

    def test_team_and_bundle_narrow_the_choice(self):
        self.assertTrue(signing.usable(profile(), 'ABCDE12345', 'com.example.halopad', NOW))
        self.assertFalse(signing.usable(profile(), 'ZZZZZ99999', None, NOW))
        self.assertFalse(signing.usable(profile(), None, 'com.example.other', NOW))

    def choose_from(self, profiles, team=None, bundle_id=None, identities=None):
        sha = __import__('hashlib').sha1(CERT).hexdigest().upper()
        with tempfile.TemporaryDirectory() as folder:
            folder = pathlib.Path(folder)
            paths = []
            for index, item in enumerate(profiles):
                path = folder / ('%d.mobileprovision' % index)
                path.write_bytes(plistlib.dumps(item))
                paths.append(path)
            with patch.object(signing, 'PROFILE_FOLDERS', [folder]), \
                    patch.object(signing, 'decode', lambda path: plistlib.loads(pathlib.Path(path).read_bytes())), \
                    patch.object(signing, 'identities', lambda: identities if identities is not None else {sha: 'Apple Development'}), \
                    patch.object(signing.datetime, 'datetime', wraps=datetime.datetime) as clock:
                clock.now.return_value = NOW.replace(tzinfo=datetime.timezone.utc)
                path, chosen, signer = signing.choose(None, team, bundle_id)
                return path.name, chosen, signer, sha

    def test_the_identity_is_the_one_the_profile_names(self):
        name, chosen, signer, sha = self.choose_from([profile()])
        self.assertEqual((name, signer), ('0.mobileprovision', sha))

    def test_no_identity_in_the_keychain_is_refused(self):
        with self.assertRaises(SystemExit):
            self.choose_from([profile()], identities={})

    def test_the_newest_profile_for_one_app_wins(self):
        name, chosen, _, _ = self.choose_from([profile(created=10), profile(created=1)])
        self.assertEqual(name, '1.mobileprovision')

    def test_several_apps_need_a_choice(self):
        with self.assertRaises(SystemExit):
            self.choose_from([profile(), profile(bundle='com.example.other')])
        name, chosen, _, _ = self.choose_from([profile(), profile(bundle='com.example.other')],
                                              team='ABCDE12345', bundle_id='com.example.other')
        self.assertEqual(signing.bundle_of(chosen), ('ABCDE12345', 'com.example.other'))

    def test_only_the_entitlements_the_game_uses_are_kept(self):
        granted = profile()['Entitlements']
        kept = {key: granted[key] for key in signing.KEPT if key in granted}
        self.assertNotIn('keychain-access-groups', kept)
        self.assertNotIn('com.apple.developer.kernel.increased-memory-limit', kept)
        self.assertTrue(kept['com.apple.developer.kernel.extended-virtual-addressing'])


if __name__ == '__main__':
    unittest.main()
