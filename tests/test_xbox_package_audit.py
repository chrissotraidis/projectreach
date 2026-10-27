"""Strict release audits fail on wrong identities, aliased archives and guest code changes."""
import json
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import candidate
import package_audit as audit

SELECTED = {'revision': 'a' * 40, 'release': 'build-999'}
VERSION, BUILD = '1.2.3', '7'


def guest(timestamp=b'Jan 01 2026\x0012:00:00\x00', code=b'code' * 4):
    """Small guest with a read-only HALO header, RX text and read-only data."""
    base = audit.image_layout()[0]
    rodata = b'%s | compiled %s %s\0' + timestamp + b'\0' * 32
    names = b'\0.text\0.rodata\0.shstrtab\0'
    data = bytearray(1280)
    ident = b'\x7fELF\x02\x01\x01' + bytes(9)
    struct.pack_into('<16sHHIQQQIHHHHHH', data, 0, ident, 2, 183, 1, base,
                     64, 1024, 0, 64, 56, 3, 64, 4, 3)
    for offset, flags, start, address, size in [(64, 4, 256, base, 48),
            (120, 5, 384, base + 0x80, len(code)), (176, 4, 512, base + 0x1000, len(rodata))]:
        struct.pack_into('<IIQQQQQQ', data, offset, 1, flags, start, address, address, size, size, 1)
    data[256:260] = b'HALO'
    data[384:384 + len(code)] = code
    data[512:512 + len(rodata)] = rodata
    data[768:768 + len(names)] = names
    for index, section in enumerate([(0, 0, 0, 0, 0, 0, 0, 0, 0, 0),
            (1, 1, 6, base + 0x80, 384, len(code), 0, 0, 4, 0),
            (7, 1, 2, base + 0x1000, 512, len(rodata), 0, 0, 1, 0),
            (15, 3, 0, 0, 768, len(names), 0, 0, 1, 0)]):
        struct.pack_into('<IIQQQQIIQQ', data, 1024 + index * 64, *section)
    return bytes(data)


def fixture_expectations():
    angle = json.loads((ROOT / 'config/xbox-angle.lock.json').read_text())
    notice_text = b'Example notice\nSecond notice\n'
    manifest = {'schema': 1, 'engine_revision': SELECTED['revision'],
                'angle_revision': angle['revision'], 'notices_sha256': audit.digest(notice_text),
                'components': [{'source': name + '/LICENSE', 'source_sha256': 'a' * 64,
                                'notice_sha256': audit.digest(text)} for name, text in
                               [('example', b'Example notice\n'), ('second', b'Second notice\n')]]}
    return {'network': 41, 'adaptation': {'name': 'network-policy-v1', 'recipe_sha256': 'b' * 64},
            'upstream_sources': {}, 'runtime_sources': audit.runtime_manifest.sources(),
            'angle': angle, 'notices': {'manifest': manifest, 'text': notice_text},
            'visibility': {'name': 'counted-visibility-v1', 'inputs': {'input.mm': 'c' * 64},
                           'bridge_sha256': 'd' * 64, 'recipe_sha256': 'e' * 64}}


def package(path, platform, expected, *, changes=None, image=None, notice_changes=None, extra=None):
    mac = platform == 'mac'
    bundle = 'HaloPad.app' if mac else 'Payload/HaloPad.app'
    prefix = bundle + ('/Contents/Resources' if mac else '')
    info = {'CFBundleIdentifier': 'dev.halopad.HaloPad', 'CFBundleShortVersionString': VERSION,
            'CFBundleVersion': BUILD, 'CFBundleSupportedPlatforms': ['MacOSX' if mac else 'iPhoneOS']}
    image = guest() if image is None else image
    engine = {**SELECTED, 'guest_sha256': audit.digest(image), 'network_version': expected['network'],
              'renderer': 'angle-metal', 'sdk': 'maccatalyst' if mac else 'iphoneos', 'notices_schema': 1,
              'guest_adaptation': expected['adaptation'], 'runtime_sources': expected['runtime_sources'],
              'angle_source': expected['angle'], 'angle_feature_overrides': [],
              'visibility_backend': {**expected['visibility'], 'outputs': {'input.mm': 'f' * 64}}}
    engine.update(changes or {})
    notice_text = expected['notices']['text']
    notices = json.loads(json.dumps(expected['notices']['manifest']))
    notices.update(notice_changes or {})
    with zipfile.ZipFile(path, 'w') as archive:
        archive.writestr(bundle + ('/Contents/Info.plist' if mac else '/Info.plist'), plistlib.dumps(info))
        archive.writestr(prefix + '/data/xbox/build.json', json.dumps(engine))
        archive.writestr(prefix + '/data/xbox/halo_guest.elf', image)
        archive.writestr(prefix + '/data/xbox/brokers.txt', 'broker.invalid')
        archive.writestr(prefix + '/Notices/manifest.json', json.dumps(notices))
        archive.writestr(prefix + '/Notices/THIRD-PARTY-NOTICES.txt', notice_text)
        if extra:
            archive.writestr(extra, b'extra')


class GuestTests(unittest.TestCase):
    def test_identical_and_timestamp_only_guests_pass(self):
        self.assertTrue(audit.compare_guests({'mac': guest(), 'ios': guest()})['bit_identical'])
        result = audit.compare_guests({'mac': guest(), 'ios': guest(b'Jan 01 2026\x0012:00:01\x00')})
        self.assertFalse(result['bit_identical'])
        self.assertEqual(result['differing_bytes'], 1)
        self.assertEqual(len(set(result['text_section_sha256'].values())), 1)

    def test_changed_executable_and_non_timestamp_data_fail(self):
        code = guest(code=b'new!' * 4)
        changed = bytearray(guest()); changed[600] = 1
        for image in (code, bytes(changed)):
            with self.subTest(image=image[:16]), self.assertRaisesRegex(ValueError, 'outside'):
                audit.compare_guests({'mac': guest(), 'ios': image})

    def test_malformed_identical_elf_is_not_accepted(self):
        for offset, value, form in ((40, 999999, '<Q'), (58, 1, '<H'), (62, 999, '<H'),
                                    (1024 + 3 * 64 + 24, 999999, '<Q')):
            bad = bytearray(guest()); struct.pack_into(form, bad, offset, value)
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                audit.compare_guests({'mac': bytes(bad), 'ios': bytes(bad)})
        with self.assertRaises(ValueError):
            audit.compare_guests({'mac': b'bad', 'ios': b'bad'})

    def test_timestamp_exception_rejects_writable_or_executable_storage(self):
        for offset, value, form in ((176 + 4, 5, '<I'), (176 + 4, 6, '<I'),
                                    (1024 + 2 * 64 + 8, 3, '<Q')):
            a = bytearray(guest()); b = bytearray(guest(b'Jan 01 2026\x0012:00:01\x00'))
            struct.pack_into(form, a, offset, value); struct.pack_into(form, b, offset, value)
            with self.subTest(offset=offset), self.assertRaises(ValueError):
                audit.compare_guests({'mac': bytes(a), 'ios': bytes(b)})

    def test_load_addresses_sizes_and_header_obey_guest_loader_contract(self):
        base = audit.image_layout()[0]
        for offset, value in ((64 + 16, 0xffffffffffff0000), (64 + 16, 1 << 32),
                              (64 + 16, base - 1), (176 + 16, 0xfffffff0),
                              (176 + 16, 0xfffff000), (176 + 40, 1 << 32),
                              (120 + 40, 1), (120 + 8, 999999),
                              (120 + 16, base + 1)):
            bad = bytearray(guest()); struct.pack_into('<Q', bad, offset, value)
            with self.subTest(offset=offset, value=value), self.assertRaises(ValueError):
                audit.compare_guests({'mac': bytes(bad), 'ios': bytes(bad)})
        bad = bytearray(guest()); bad[256:260] = b'NOPE'
        with self.assertRaisesRegex(ValueError, 'HALO header'):
            audit.elf_sections(bytes(bad))

    def test_timestamp_exception_requires_unique_marker(self):
        a = bytearray(guest()); b = bytearray(guest(b'Jan 01 2026\x0012:00:01\x00'))
        duplicate = b'%s | compiled %s %s\0Jan 01 2026\x0012:00:00\0'
        a[850:850 + len(duplicate)] = duplicate; b[850:850 + len(duplicate)] = duplicate
        with self.assertRaisesRegex(ValueError, 'uniquely'):
            audit.compare_guests({'mac': bytes(a), 'ios': bytes(b)})


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.expected = fixture_expectations()
        mocked = patch.object(audit, 'expectations', return_value=self.expected)
        mocked.start(); self.addCleanup(mocked.stop)
        original_run = subprocess.run
        def run(argv, *args, **kwargs):
            if argv[0] == 'codesign':
                return subprocess.CompletedProcess(argv, 0)
            return original_run(argv, *args, **kwargs)
        mocked = patch.object(subprocess, 'run', side_effect=run)
        self.sign = mocked.start(); self.addCleanup(mocked.stop)

    def check(self, **kwargs):
        path = self.root / 'ios.ipa'; package(path, 'ios', self.expected, **kwargs)
        return audit.audit_packages({'ios': path}, SELECTED, VERSION, BUILD, engine_checkout=self.root)

    def test_strict_archive_passes_and_retains_separate_acceptance_limits(self):
        result = self.check()
        self.assertTrue(result['pass'])
        self.assertEqual(result['network_version'], 41)
        self.assertIn('no gameplay', result['limits'])
        self.assertIn('not independently re-derived', result['limits'])

    def test_runtime_network_sdk_angle_and_adaptation_drift_fail(self):
        for changes in ({'runtime_sources': {}}, {'network_version': 42}, {'sdk': 'iphonesimulator'},
                        {'guest_adaptation': {}}, {'angle_source': {}}, {'angle_feature_overrides': ['test']},
                        {'renderer': 'legacy'}, {'guest_sha256': '0' * 64}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.check(changes=changes)

    def test_counted_visibility_hashes_and_notice_records_are_required(self):
        for outputs in ({}, {'input.mm': None}, {'input.mm': 'not-a-hash'}):
            with self.subTest(outputs=outputs), self.assertRaisesRegex(ValueError, 'visibility'):
                self.check(changes={'visibility_backend': {**self.expected['visibility'], 'outputs': outputs}})
        for changes in ({'components': []}, {'components': [{'source': 'no hashes'}]},
                        {'notices_sha256': '0' * 64}, {'angle_revision': 'wrong'}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.check(notice_changes=changes)

    def test_notice_inventory_and_each_record_must_match_source(self):
        components = self.expected['notices']['manifest']['components']
        for changed in (components[:1], [{**components[0], 'notice_sha256': '0' * 64}, components[1]],
                        [{**components[0], 'source_sha256': '0' * 64}, components[1]]):
            with self.subTest(components=changed), self.assertRaisesRegex(ValueError, 'complete expected'):
                self.check(notice_changes={'components': changed})

    def test_pair_requires_equal_visibility_outputs_and_guest_code(self):
        paths = {platform: self.root / (platform + '.zip') for platform in ('mac', 'ios')}
        for platform, path in paths.items(): package(path, platform, self.expected)
        result = audit.audit_packages(paths, SELECTED, VERSION, BUILD, engine_checkout=self.root)
        self.assertTrue(result['cross_platform_guest_comparison']['bit_identical'])
        package(paths['ios'], 'ios', self.expected, changes={'visibility_backend': {
            **self.expected['visibility'], 'outputs': {'input.mm': '0' * 64}}})
        with self.assertRaisesRegex(ValueError, 'Cross-platform counted'):
            audit.audit_packages(paths, SELECTED, VERSION, BUILD, engine_checkout=self.root)
        package(paths['ios'], 'ios', self.expected, image=guest(code=b'new!' * 4))
        with self.assertRaisesRegex(ValueError, 'outside'):
            audit.audit_packages(paths, SELECTED, VERSION, BUILD, engine_checkout=self.root)

    def test_alias_paths_rejected_before_codesign(self):
        for extra in ('Payload/HaloPad.app/./Info.plist', 'Payload/HaloPad.app//Info.plist',
                      'Payload/HaloPad.app/info.plist', '../outside'):
            self.sign.reset_mock()
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.check(extra=extra)
            self.assertFalse(any(call.args[0][0] == 'codesign' for call in self.sign.call_args_list))

    def test_bad_platform_and_signature_fail(self):
        with self.assertRaises(ValueError):
            audit.audit_packages({'sim': self.root / 'a'}, SELECTED, VERSION, BUILD, engine_checkout=self.root)
        with patch.object(candidate, 'audit', side_effect=subprocess.CalledProcessError(1, 'codesign')), \
                self.assertRaises(subprocess.CalledProcessError):
            self.check()


class SourceTests(unittest.TestCase):
    def test_unknown_revision_refused_even_when_latest_mode_is_enabled(self):
        with patch.dict('os.environ', {'HALOPAD_XBOX_LATEST': '1'}), \
                patch.object(audit, 'exact_source') as read, self.assertRaisesRegex(ValueError, 'reviewed'):
            audit.expectations(SELECTED, Path('/unused'))
        read.assert_not_called()

    def test_exact_revision_is_used_and_wrong_header_or_source_fails(self):
        guest_module = audit.runtime_manifest.guest_adaptation
        raw = {guest_module.RENDERER: b'renderer', guest_module.CAMERA_SOURCE: b'camera',
               guest_module.border_sampling.SHADER: b'shader'}
        adaptation = {'name': 'network-policy-v1', 'upstream_renderer_sha256': audit.digest(b'renderer'),
                      'upstream_camera_sha256': audit.digest(b'camera'), 'recipe_sha256': 'f' * 64}
        def source(checkout, revision, path):
            self.assertEqual(revision, SELECTED['revision'])
            return b'#define HALO_PORT_NETWORK_VERSION 41\n' if path == audit.network_policy.LIMITS else raw[path]
        with patch.dict(guest_module.REVIEWED_RENDERERS, {SELECTED['revision']: adaptation['upstream_renderer_sha256']}), \
                patch.dict(guest_module.REVIEWED_CAMERA, {SELECTED['revision']: adaptation['upstream_camera_sha256']}), \
                patch.object(guest_module, 'identity', return_value=adaptation), \
                patch.object(guest_module.border_sampling, 'shader_hash', return_value=audit.digest(b'shader')), \
                patch.object(guest_module.border_sampling, 'adapt_shader'), \
                patch.object(audit, 'collect_notices', return_value=fixture_expectations()['notices']), \
                patch.object(audit, 'exact_source', side_effect=source):
            self.assertEqual(audit.expectations(SELECTED, Path('/engine'), 41)['network'], 41)
            with self.assertRaisesRegex(ValueError, 'network'):
                audit.expectations(SELECTED, Path('/engine'), 42)
            raw[guest_module.RENDERER] = b'changed'
            with self.assertRaisesRegex(ValueError, 'source differs'):
                audit.expectations(SELECTED, Path('/engine'))

    def test_notice_collection_requires_exact_clean_engine_and_angle(self):
        angle = {'revision': 'b' * 40}
        for heads in ([SELECTED['revision'], 'wrong'], ['wrong']):
            with patch.object(subprocess, 'check_output', side_effect=heads), \
                    patch.object(subprocess, 'run'), patch.object(audit.notices, 'write') as collect, \
                    self.assertRaisesRegex(ValueError, 'HEAD differs'):
                audit.collect_notices(Path('/engine'), SELECTED['revision'], angle,
                                      Path('/headers'), Path('/angle'))
            collect.assert_not_called()
        with patch.object(subprocess, 'check_output', return_value=SELECTED['revision']), \
                patch.object(subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'git diff')), \
                patch.object(audit.notices, 'write') as collect, self.assertRaises(subprocess.CalledProcessError):
            audit.collect_notices(Path('/engine'), SELECTED['revision'], angle,
                                  Path('/headers'), Path('/angle'))
        collect.assert_not_called()

    def test_notice_collection_reuses_complete_builder_inventory(self):
        expected = fixture_expectations()
        def collect(engine, headers, destination, revision, **kwargs):
            self.assertEqual((engine, headers, revision), (Path('/engine'), Path('/headers'), SELECTED['revision']))
            self.assertEqual(kwargs['angle'], Path('/angle'))
            self.assertEqual(kwargs['angle_revision'], expected['angle']['revision'])
            destination.mkdir()
            (destination / 'THIRD-PARTY-NOTICES.txt').write_bytes(expected['notices']['text'])
            return expected['notices']['manifest']
        with patch.object(subprocess, 'check_output', side_effect=[SELECTED['revision'], expected['angle']['revision']]), \
                patch.object(subprocess, 'run') as diff, patch.object(audit.notices, 'write', side_effect=collect):
            result = audit.collect_notices(Path('/engine'), SELECTED['revision'], expected['angle'],
                                           Path('/headers'), Path('/angle'))
        self.assertEqual(result, expected['notices'])
        self.assertEqual(diff.call_count, 2)
        self.assertTrue(all(call.kwargs['check'] for call in diff.call_args_list))

    def test_different_runtime_checkout_rejected(self):
        with patch.object(audit.runtime_manifest, 'ROOT', Path('/another')), \
                self.assertRaisesRegex(ValueError, 'different source'):
            audit.expectations(SELECTED, Path('/engine'))


if __name__ == '__main__':
    unittest.main()
