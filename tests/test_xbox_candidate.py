"""Candidate updates must preserve previous builds and audit the actual archive."""
import importlib.util
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import candidate

SELECTED = {'revision': 'a' * 40, 'release': 'build-148', 'channel': 'latest'}
SOURCE = {'commit': 'b' * 40, 'tree_sha256': 'c' * 64, 'xcode': 'fixture', 'guest_compiler': 'fixture'}


def package(path, platform, build='9', **changes):
    mac = platform == 'mac'
    bundle = 'HaloPad.app' if mac else 'Payload/HaloPad.app'
    res = bundle + ('/Contents/Resources' if mac else '')
    info = {'CFBundleIdentifier': 'dev.halopad.HaloPad', 'CFBundleShortVersionString': '0.3.8',
            'CFBundleVersion': build, 'CFBundleSupportedPlatforms': ['MacOSX' if mac else 'iPhoneOS']}
    engine = {**SELECTED, 'guest_sha256': hashlib.sha256(b'guest').hexdigest(), 'network_version': 23}
    engine.update(changes)
    with zipfile.ZipFile(path, 'w') as z:
        z.writestr(bundle + ('/Contents/Info.plist' if mac else '/Info.plist'), plistlib.dumps(info))
        z.writestr(res + '/data/xbox/build.json', json.dumps(engine))
        z.writestr(res + '/data/xbox/halo_guest.elf', b'guest')
        z.writestr(res + '/data/xbox/brokers.txt', 'broker.invalid')


class AuditTests(unittest.TestCase):
    def test_legacy_candidate_can_be_retrieved_but_not_submitted_without_notices(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(candidate.subprocess, 'run'):
            path = Path(folder) / 'legacy.ipa'; package(path, 'ios')
            candidate.audit(path, 'ios', SELECTED, '0.3.8', '9')
            with self.assertRaisesRegex(ValueError, 'notice inventory is incomplete'):
                candidate.audit(path, 'ios', SELECTED, '0.3.8', '9', require_notices=True)

    def test_actual_archive_identity_and_hash_on_both_platforms(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(candidate.subprocess, 'run') as sign:
            for platform in ('ios', 'mac'):
                path = Path(folder) / (platform + '.zip'); package(path, platform)
                result = candidate.audit(path, platform, SELECTED, '0.3.8', '9')
                self.assertEqual(result['network_version'], 23)
                self.assertEqual(result['sha256'], candidate.digest(path))
                self.assertEqual(sign.call_args.args[0][:4], ['codesign', '--verify', '--deep', '--strict'])

    def test_wrong_commit_protocol_guest_or_application_build_rejected(self):
        for changes, build in (({'revision': 'd' * 40}, '9'), ({'network_version': None}, '9'),
                               ({'network_version': True}, '9'), ({'guest_sha256': '0' * 64}, '9'), ({}, '8')):
            with self.subTest(changes=changes, build=build), tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / 'a.ipa'; package(path, 'ios', build, **changes)
                with self.assertRaises(ValueError):
                    candidate.audit(path, 'ios', SELECTED, '0.3.8', '9')

    def test_private_or_unsafe_content_rejected_before_signature(self):
        for extra in ('Payload/HaloPad.app/data/PC/image.bin', 'Payload/HaloPad.app/embedded.mobileprovision', '../escape'):
            with self.subTest(extra=extra), tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / 'a.ipa'; package(path, 'ios')
                with zipfile.ZipFile(path, 'a') as z: z.writestr(extra, 'private')
                with patch.object(candidate.subprocess, 'run') as sign, self.assertRaises(ValueError):
                    candidate.audit(path, 'ios', SELECTED, '0.3.8', '9')
                sign.assert_not_called()

    def test_invalid_signature_is_not_accepted(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'a.ipa'; package(path, 'ios')
            with patch.object(candidate.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'codesign')), \
                    self.assertRaises(subprocess.CalledProcessError):
                candidate.audit(path, 'ios', SELECTED, '0.3.8', '9')


class CycleTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.out = Path(self.folder.name)
        self.calls = []
        for target, value in (('source_identity', SOURCE), ('release.resolve', SELECTED)):
            obj = candidate.release if target.startswith('release.') else candidate
            patcher = patch.object(obj, target.split('.')[-1], return_value=value)
            patcher.start(); self.addCleanup(patcher.stop)
        patcher = patch.object(candidate, 'command', side_effect=self.command)
        patcher.start(); self.addCleanup(patcher.stop)
        patcher = patch.object(candidate.subprocess, 'run')
        patcher.start(); self.addCleanup(patcher.stop)

    def command(self, argv, log):
        self.calls.append(argv)
        log.write_text('fixture command')
        if argv[0] == '/bin/bash':
            platform = 'mac' if '--mac' in argv else 'ios'
            flag = '--zip' if platform == 'mac' else '--ipa'
            path = Path(argv[argv.index(flag) + 1])
            package(path, platform, argv[argv.index('--app-build') + 1])

    def run_cycle(self, **kwargs):
        return candidate.iterate(self.out, '0.3.8', 9, **kwargs)

    def test_success_repeat_skips_and_does_not_allocate_another_build(self):
        first = self.run_cycle(); count = len(self.calls)
        second = self.run_cycle()
        self.assertEqual(first['status'], 'built-awaiting-acceptance')
        self.assertEqual(first['acceptance'], dict(gameplay=False, consumer_upgrade=False, publication=False))
        self.assertTrue(second['unchanged']); self.assertEqual(len(self.calls), count)
        self.assertEqual(json.loads((self.out / 'next-build.json').read_text()), 10)
        self.assertEqual(set(first['artifacts']), {'ios', 'mac'})

    def test_failure_preserves_previous_pointer_and_skips_until_retry(self):
        previous = {'status': 'previous fixture'}
        candidate.write_json(self.out / 'latest-built.json', previous)
        with patch.object(candidate, 'command', side_effect=subprocess.CalledProcessError(1, 'build')):
            with self.assertRaises(subprocess.CalledProcessError): self.run_cycle()
        self.assertEqual(json.loads((self.out / 'latest-built.json').read_text()), previous)
        result = self.run_cycle()
        self.assertEqual(result['status'], 'failed'); self.assertTrue(result['unchanged'])
        self.assertEqual(len(self.calls), 0)
        result = self.run_cycle(retry=True)
        self.assertEqual(result['build'], '10')
        self.assertEqual(len(list((self.out / 'runs').iterdir())), 2)

    def test_source_change_during_build_does_not_publish_candidate_pointer(self):
        with patch.object(candidate, 'source_identity', side_effect=[SOURCE, {**SOURCE, 'tree_sha256': 'changed'}]):
            with self.assertRaisesRegex(ValueError, 'source changed'): self.run_cycle()
        self.assertFalse((self.out / 'latest-built.json').exists())

    def test_metadata_only_commit_change_does_not_rebuild(self):
        self.run_cycle(); count = len(self.calls)
        with patch.object(candidate, 'source_identity', return_value={**SOURCE, 'commit': 'e' * 40}):
            self.assertTrue(self.run_cycle()['unchanged'])
        self.assertEqual(len(self.calls), count)

    def test_retained_artifact_corruption_fails_closed(self):
        result = self.run_cycle()
        Path(result['artifacts']['ios']['path']).write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'retained candidate changed'): self.run_cycle()

    def test_network_failure_keeps_previous_pointer(self):
        candidate.write_json(self.out / 'latest-built.json', {'previous': True})
        with patch.object(candidate.release, 'resolve', side_effect=OSError('offline')):
            with self.assertRaises(OSError): self.run_cycle()
        self.assertEqual(json.loads((self.out / 'latest-built.json').read_text()), {'previous': True})
        self.assertFalse((self.out / 'next-build.json').exists())


if __name__ == '__main__':
    unittest.main()
