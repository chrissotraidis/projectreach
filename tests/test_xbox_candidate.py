"""Candidate updates must preserve previous builds and audit the actual archive."""
import importlib.util
import io
import hashlib
import json
import itertools
import os
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

    def test_zip_aliases_cannot_replace_the_file_that_was_inspected(self):
        for alias in ('Payload/HaloPad.app/./Info.plist', 'Payload//HaloPad.app/Info.plist',
                      'Payload/HaloPad.app/info.plist', 'payload/HaloPad.app/uninspected-file'):
            with self.subTest(alias=alias), tempfile.TemporaryDirectory() as folder:
                path = Path(folder) / 'aliased.ipa'
                package(path, 'ios')
                with zipfile.ZipFile(path, 'a') as archive:
                    archive.writestr(alias, plistlib.dumps({'CFBundleShortVersionString': '9.9.9'}))
                with patch.object(candidate.subprocess, 'run') as sign, self.assertRaises(ValueError):
                    candidate.audit(path, 'ios', SELECTED, '0.3.8', '9')
                sign.assert_not_called()

    def test_unicode_path_collision_is_rejected_before_extracting(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'aliased.ipa'
            package(path, 'ios')
            with zipfile.ZipFile(path, 'a') as archive:
                archive.writestr('Payload/HaloPad.app/caf\u00e9', 'one')
                archive.writestr('Payload/HaloPad.app/cafe\u0301', 'two')
            with patch.object(candidate.subprocess, 'run') as sign, self.assertRaisesRegex(ValueError, 'colliding'):
                candidate.audit(path, 'ios', SELECTED, '0.3.8', '9')
            sign.assert_not_called()


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

    def test_per_stage_timings_persist_and_use_a_monotonic_clock(self):
        clock = itertools.count(100, 0.25)
        with patch.object(candidate.time, 'monotonic', side_effect=lambda: next(clock)):
            result = self.run_cycle()
        stages = result['timings']['stages']
        self.assertEqual(list(stages), ['tests_xbox', 'tests_builder', 'build_mac', 'audit_mac',
                                        'build_ios', 'audit_ios', 'verify_candidate'])
        self.assertTrue(all(stage == {'status': 'passed', 'seconds': 0.25} for stage in stages.values()))
        self.assertEqual(result['timings']['clock'], 'monotonic')
        self.assertGreaterEqual(result['timings']['total_seconds'], sum(stage['seconds'] for stage in stages.values()))
        self.assertIn('finished', result)
        self.assertEqual(json.loads((Path(result['run']) / 'result.json').read_text()), result)
        self.assertEqual(json.loads((self.out / 'latest-built.json').read_text()), result)
        summary = candidate.timing_summary(result)
        self.assertIn('| audit_ios | passed | 0.250 |', summary)
        self.assertIn('Excludes GitHub runner queue/setup', summary)

    def test_reuse_preserves_original_timings_and_does_not_rewrite_receipts(self):
        first = self.run_cycle()
        paths = [Path(first['run']) / 'result.json', self.out / 'latest-built.json',
                 next((self.out / 'states').iterdir()), self.out / 'next-build.json']
        original = {path: path.read_bytes() for path in paths}
        with patch.object(candidate.time, 'monotonic', side_effect=[200.0, 200.5]):
            second = self.run_cycle(summary_path=self.out / 'summary')
        self.assertTrue(second['unchanged'])
        self.assertEqual(second['reuse_check_seconds'], 0.5)
        self.assertEqual(second['timings'], first['timings'])
        self.assertEqual(original, {path: path.read_bytes() for path in paths})
        self.assertIn('original attempt', (self.out / 'summary').read_text())

    def test_library_calls_do_not_pollute_the_hosted_job_summary(self):
        summary = self.out / 'summary'
        with patch.dict(os.environ, {'GITHUB_STEP_SUMMARY': str(summary)}):
            self.run_cycle()
        self.assertFalse(summary.exists())

    def test_optional_summary_failure_cannot_strand_a_successful_candidate(self):
        with patch('sys.stderr', new_callable=io.StringIO) as warning:
            result = self.run_cycle(summary_path=self.out / 'missing/summary')
            reused = self.run_cycle(summary_path=self.out / 'missing/summary')
        self.assertEqual(result['status'], 'built-awaiting-acceptance')
        self.assertEqual(json.loads((self.out / 'latest-built.json').read_text()), result)
        self.assertTrue(reused['unchanged'])
        self.assertIn('could not write candidate timing summary', warning.getvalue())

    def test_optional_summary_failure_cannot_hide_the_original_build_error(self):
        with patch.object(candidate, 'command', side_effect=subprocess.CalledProcessError(7, 'build')), \
                patch('sys.stderr', new_callable=io.StringIO), self.assertRaises(subprocess.CalledProcessError) as error:
            self.run_cycle(summary_path=self.out / 'missing/summary')
        self.assertEqual(error.exception.returncode, 7)
        failed = json.loads(next((self.out / 'states').iterdir()).read_text())
        self.assertEqual(failed['timings']['stages']['tests_xbox']['status'], 'failed')
        self.assertFalse((self.out / 'latest-built.json').exists())

    def test_failed_build_retains_completed_timings_without_touching_previous_pointer(self):
        candidate.write_json(self.out / 'latest-built.json', {'previous': True})
        original_command = self.command
        def fail_mac(argv, log):
            if argv[0] == '/bin/bash':
                raise subprocess.CalledProcessError(1, argv)
            original_command(argv, log)
        with patch.object(candidate, 'command', side_effect=fail_mac), self.assertRaises(subprocess.CalledProcessError):
            self.run_cycle()
        failed = json.loads(next((self.out / 'states').iterdir()).read_text())
        self.assertEqual(failed['status'], 'failed')
        self.assertEqual(list(failed['timings']['stages']), ['tests_xbox', 'tests_builder', 'build_mac'])
        self.assertEqual(failed['timings']['stages']['tests_builder']['status'], 'passed')
        self.assertEqual(failed['timings']['stages']['build_mac']['status'], 'failed')
        self.assertGreaterEqual(failed['timings']['stages']['build_mac']['seconds'], 0)
        self.assertEqual(json.loads((self.out / 'latest-built.json').read_text()), {'previous': True})
        self.assertEqual(json.loads((Path(failed['run']) / 'result.json').read_text()), failed)

    def test_failed_audit_timeout_and_interrupt_are_recorded(self):
        for error in (ValueError('bad archive'), subprocess.TimeoutExpired('audit', 1), KeyboardInterrupt()):
            with self.subTest(error=type(error).__name__):
                with patch.object(candidate, 'audit', side_effect=error), self.assertRaises(type(error)):
                    self.run_cycle(retry=True)
                failed = json.loads(next((self.out / 'states').iterdir()).read_text())
                self.assertEqual(failed['status'], 'failed')
                self.assertEqual(failed['timings']['stages']['audit_mac']['status'], 'failed')
                self.assertNotIn('build_ios', failed['timings']['stages'])
                self.assertIn('total_seconds', failed['timings'])
                self.assertFalse((self.out / 'latest-built.json').exists())

    def test_old_cached_candidate_without_timings_remains_readable(self):
        result = self.run_cycle()
        state = next((self.out / 'states').iterdir())
        previous = json.loads(state.read_text())
        previous.pop('timings')
        candidate.write_json(state, previous)
        reused = self.run_cycle()
        self.assertTrue(reused['unchanged'])
        self.assertNotIn('timings', reused)
        self.assertIn('older candidate has no stage timing', candidate.timing_summary(reused))

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
        failed = json.loads(next((self.out / 'states').iterdir()).read_text())
        self.assertEqual(failed['timings']['stages']['verify_candidate']['status'], 'failed')

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
