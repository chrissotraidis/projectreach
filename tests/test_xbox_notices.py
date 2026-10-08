"""Notices follow the selected build inputs and survive actual archive packaging."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts/xbox'))
import candidate
import notices
from test_xbox_candidate import package, SELECTED


class CollectionTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.engine = self.root / 'engine'
        self.headers = self.root / 'headers'
        self.angle = self.root / 'angle'
        self.out = self.root / 'Notices'
        self.put(self.engine, 'LICENSE.md', 'Engine fixture license\n')
        self.put(self.engine, 'tools/android_build.py', 'MUSL_VERSION = "1.2.5"\n')
        self.put(self.engine, 'build/android/third_party/musl-1.2.5/COPYRIGHT', 'libc fixture license\n')
        self.put(self.engine, 'build/android/third_party/SDL3/LICENSE.txt', 'SDL fixture license\n')
        self.put(self.engine, 'port/third_party/monocypher/monocypher.c',
                 '// Copyright Example\n// Permission fixture\n// Warranty fixture\n#include "example.h"\nint code;')
        self.put(self.engine, 'port/assets/fonts/example/OFL.txt', 'Font fixture permission\n')
        self.put(self.headers, 'GLES3/gl3.h',
                 '#ifndef EXAMPLE\n/* Copyright Khronos fixture\nPermission text\n*/\nint code;')
        self.put(self.headers, 'KHR/khrplatform.h', '// Copyright Other fixture\n// Permission text\nint code;')
        self.put(self.angle, 'LICENSE', 'ANGLE fixture license\n')
        self.put(self.angle, 'src/common/third_party/xxhash/LICENSE', 'xxHash fixture license\n')
        self.put(self.angle, 'third_party/zlib/google/compression_utils_portable.cc',
                 '/* Copyright Chromium fixture. See root LICENSE. */\n#include "example.h"\nint code;')
        self.chromium = self.put(self.root, 'Chromium.txt', 'Chromium fixture permission\n')

    def put(self, root, name, text):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def collect(self, **kwargs):
        with patch.object(notices.subprocess, 'check_output', return_value=SELECTED['revision'] + '\n'):
            return notices.write(self.engine, self.headers, self.out, SELECTED['revision'], **kwargs)

    def test_complete_collection_keeps_permissions_and_source_hashes_without_code_or_local_paths(self):
        result = self.collect(angle=self.angle, angle_revision=SELECTED['revision'], chromium_license=self.chromium)
        text = (self.out / 'THIRD-PARTY-NOTICES.txt').read_bytes()
        self.assertIn(b'Permission fixture', text)
        self.assertIn(b'Warranty fixture', text)
        self.assertIn(b'Font fixture permission', text)
        self.assertIn(b'Chromium fixture permission', text)
        self.assertIn(b'// Permission text', text)
        self.assertNotIn(b'int code', text)
        self.assertNotIn(b'#include', text)
        self.assertNotIn(str(self.root), json.dumps(result))
        row = next(x for x in result['components'] if x['source'] == 'Chromium/LICENSE')
        self.assertEqual(row['source_sha256'], hashlib.sha256(self.chromium.read_bytes()).hexdigest())
        self.assertEqual(json.loads((self.out / 'manifest.json').read_text()), result)
        notices.validate(result, text, SELECTED['revision'])

    def test_missing_known_license_fails_before_output(self):
        (self.engine / 'port/third_party/expat').mkdir()
        with self.assertRaises(FileNotFoundError):
            self.collect()
        self.assertFalse(self.out.exists())

    def test_wrong_engine_or_renderer_revision_fails_before_output(self):
        for revisions in (['wrong'], [SELECTED['revision'], 'wrong']):
            with self.subTest(revisions=revisions), \
                    patch.object(notices.subprocess, 'check_output', side_effect=revisions), \
                    self.assertRaisesRegex(ValueError, 'sources differ'):
                notices.write(self.engine, self.headers, self.out, SELECTED['revision'],
                              angle=self.angle, angle_revision=SELECTED['revision'], chromium_license=self.chromium)
            self.assertFalse(self.out.exists())

    def test_missing_header_notice_and_unknown_libc_fail_before_output(self):
        self.put(self.headers, 'GLES3/gl3.h', 'int no_notice;')
        with self.assertRaisesRegex(ValueError, 'missing inline copyright'):
            self.collect()
        self.assertFalse(self.out.exists())
        self.put(self.engine, 'tools/android_build.py', 'NEW_LIBC = "unknown"')
        with self.assertRaisesRegex(ValueError, 'cannot identify'):
            self.collect()
        self.assertFalse(self.out.exists())

    def test_archive_audit_checks_notice_identity_bytes_and_missing_files_on_both_platforms(self):
        manifest = self.collect()
        text = (self.out / 'THIRD-PARTY-NOTICES.txt').read_bytes()
        for platform in ('mac', 'ios'):
            for broken in (None, 'missing', 'text', 'revision', 'manifest'):
                with self.subTest(platform=platform, broken=broken):
                    path = self.root / 'fixture.zip'
                    package(path, platform, notices_schema=1)
                    prefix = ('HaloPad.app/Contents/Resources' if platform == 'mac' else 'Payload/HaloPad.app') + '/Notices/'
                    if broken != 'missing':
                        record = {**manifest, **({'engine_revision': 'wrong'} if broken == 'revision' else {})}
                        with zipfile.ZipFile(path, 'a') as archive:
                            if broken != 'manifest':
                                archive.writestr(prefix + 'manifest.json', json.dumps(record))
                            archive.writestr(prefix + 'THIRD-PARTY-NOTICES.txt', b'wrong' if broken == 'text' else text)
                    with patch.object(candidate.subprocess, 'run'):
                        if broken is None:
                            candidate.audit(path, platform, SELECTED, '0.3.8', '9')
                        else:
                            with self.assertRaises(ValueError):
                                candidate.audit(path, platform, SELECTED, '0.3.8', '9')


if __name__ == '__main__':
    unittest.main()
