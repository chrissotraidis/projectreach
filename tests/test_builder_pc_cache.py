"""A repeat Xbox build may reuse PC work only when its inputs and outputs match."""
import importlib.util
import json
import os
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('pc_cache', ROOT / 'scripts/builder/pc_cache.py')
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)


class PCCacheTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name).resolve()
        self.work = self.root / f'generated/srw/{cache.PROFILE}/run-fixture'
        self.tools = {'compiler': 'fixture-v1'}
        for name in ('dependencies.lock.json', 'toolchains.lock.json', 'scripts/va-model.py',
                     'port/llasm-runtime/halopad-fixture.llasm', 'config/runtime/imports.txt',
                     'ref/input/haloce.exe', 'ref/input/library.dll',
                     f'generated/analysis/{cache.PROFILE}/image.bin',
                     f'generated/analysis/{cache.PROFILE}/modules/library/image.bin'):
            self.write(name)
        profile = {'original_root': 'ref/input', 'executable': 'haloce.exe',
                   'accepted_sha256': cache.digest(self.root / 'ref/input/haloce.exe'),
                   'modules': {'library': {'file': 'library.dll',
                              'sha256': cache.digest(self.root / 'ref/input/library.dll')}}}
        self.write(f'config/profiles/{cache.PROFILE}.json', json.dumps(profile))
        for name in ('va/haloce.va.ll', 'va/dispatch.ll', 'va/library/library.va.ll',
                     'va/halopad-fixture.ll', 'slices-va-test/haloce.va.o'):
            self.write(str((self.work / name).relative_to(self.root)))
        cache.record(self.root, self.work, self.tools)

    def write(self, name, value='fixture'):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)
        return path

    def test_exact_reuse(self):
        self.assertEqual(cache.lookup(self.root, self.tools), self.work)

    def test_xbox_update_does_not_retranslate_pc(self):
        self.write('config/xbox-engine.lock.json', 'new release')
        self.write('scripts/xbox/guest_adaptation.py', 'new adapter')
        self.write('port/ios/HaloPadXboxUpdate.h', 'new Xbox UI')
        self.assertEqual(cache.lookup(self.root, self.tools), self.work)

    def test_local_pc_source_edit_invalidates(self):
        self.write('scripts/va-model.py', 'changed translator')
        self.assertIsNone(cache.lookup(self.root, self.tools))

    def test_changed_compiler_invalidates(self):
        self.assertIsNone(cache.lookup(self.root, {'compiler': 'fixture-v2'}))

    def test_touched_runtime_source_invalidates_even_if_contents_match(self):
        source = self.root / 'port/llasm-runtime/halopad-fixture.llasm'
        generated = self.work / 'va/halopad-fixture.ll'
        # The app builder rejects IR older than its runtime source, even when
        # checkout/restore changed only timestamps. Do not return that cache.
        newer = generated.stat().st_mtime + 10
        os.utime(source, (newer, newer))
        self.assertIsNone(cache.lookup(self.root, self.tools))
        with self.assertRaisesRegex(ValueError, 'stale'):
            cache.record(self.root, self.work, self.tools)

    def test_changed_original_is_rejected(self):
        self.write('ref/input/haloce.exe', 'changed game')
        self.assertIsNone(cache.lookup(self.root, self.tools))
        with self.assertRaisesRegex(ValueError, 'accepted profile'):
            cache.record(self.root, self.work, self.tools)

    def test_corrupt_or_missing_output_invalidates(self):
        for path in (self.work / 'va/library/library.va.ll', self.work / 'slices-va-test/haloce.va.o',
                     self.root / f'generated/analysis/{cache.PROFILE}/image.bin'):
            with self.subTest(path=path):
                original = path.read_bytes()
                path.write_bytes(b'corrupt')
                self.assertIsNone(cache.lookup(self.root, self.tools))
                path.unlink()
                self.assertIsNone(cache.lookup(self.root, self.tools))
                path.write_bytes(original)

    def test_incomplete_run_cannot_be_recorded(self):
        (self.work / 'va/dispatch.ll').unlink()
        with self.assertRaises(FileNotFoundError):
            cache.record(self.root, self.work, self.tools)

    def test_malformed_receipt_is_a_cache_miss(self):
        for value in ('{', '{}', 'null', '[]'):
            self.write(str(cache.RECEIPT), value)
            self.assertIsNone(cache.lookup(self.root, self.tools))

    def test_work_outside_profile_is_rejected(self):
        data = json.loads((self.root / cache.RECEIPT).read_text())
        data['work'] = str(self.root.parent)
        self.write(str(cache.RECEIPT), json.dumps(data))
        self.assertIsNone(cache.lookup(self.root, self.tools))


if __name__ == '__main__':
    unittest.main()
