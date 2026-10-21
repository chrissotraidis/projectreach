"""Exercise the actual Darwin disc extractor with inert, synthetic XDVDFS files.

These fixtures establish parser/publication behavior, not game compatibility.
"""
import ctypes
import pathlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
BUILD = b'01.10.12.2276'
PROGRESS = ctypes.CFUNCTYPE(None, ctypes.c_double, ctypes.c_void_p)


@unittest.skipUnless(sys.platform == 'darwin', 'native Apple content types require Darwin')
class XboxDiscPickerTests(unittest.TestCase):
    def test_picker_accepts_generic_and_specific_disc_types(self):
        implementation = (ROOT / 'port/ios/HaloPadXbox.m').read_text()
        helper = re.search(r'static NSArray<UTType \*> \*xbox_disc_content_types\(void\)\n\{.*?\n\}',
                           implementation, re.S)
        self.assertIsNotNone(helper)
        source = '''
#import <Foundation/Foundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
''' + helper[0] + '''
int main(void) { @autoreleasepool {
    NSArray<UTType *> *allowed = xbox_disc_content_types();
    NSArray<UTType *> *discs = @[
        UTTypeDiskImage, [UTType typeWithFilenameExtension:@"iso"],
        [UTType typeWithFilenameExtension:@"xiso"], UTTypeData
    ];
    for (UTType *disc in discs) {
        BOOL accepted = NO;
        for (UTType *type in allowed) accepted |= [disc conformsToType:type];
        if (!accepted) { fprintf(stderr, "Rejected %s\\n", disc.identifier.UTF8String); return 1; }
    }
    for (UTType *type in allowed) {
        if ([UTTypeFolder conformsToType:type]) return 2;
    }
} return 0; }
'''
        with tempfile.TemporaryDirectory(prefix='halopad-disc-types-') as folder:
            root = pathlib.Path(folder)
            (root / 'types.m').write_text(source)
            subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                            str(root / 'types.m'), '-framework', 'Foundation',
                            '-framework', 'UniformTypeIdentifiers', '-o', str(root / 'types')],
                           check=True, capture_output=True)
            subprocess.run([str(root / 'types')], check=True, capture_output=True)


def directory(entries):
    """A right-linked tree, with entries at four-byte-aligned offsets."""
    records = []
    for name, sector, size, attributes in entries:
        name = name.encode('ascii') if isinstance(name, str) else name
        record = bytearray(struct.pack('<HHIIBB', 0, 0, sector, size, attributes,
                                       len(name)) + name)
        record.extend(b'\0' * (-len(record) % 4))
        records.append(record)
    result = bytearray()
    for index, record in enumerate(records):
        if index + 1 < len(records):
            struct.pack_into('<H', record, 2, (len(result) + len(record)) // 4)
        result.extend(record)
    return result


def image(names=('ui.map',), map_size=2048):
    data = bytearray((43 + len(names) * ((map_size + 2047) // 2048)) * 2048)
    sectors = [43 + i * ((map_size + 2047) // 2048) for i in range(len(names))]
    maps = directory([(name, sector, map_size, 0) for name, sector in zip(names, sectors)])
    root = directory([('maps', 41, len(maps), 0x10), ('default.xbe', 42, 4, 0)])
    data[0x10000:0x10000 + 28] = b'MICROSOFT*XBOX*MEDIA' + struct.pack('<II', 40, len(root))
    data[40 * 2048:40 * 2048 + len(root)] = root
    data[41 * 2048:41 * 2048 + len(maps)] = maps
    data[42 * 2048:42 * 2048 + 4] = b'XBEH'
    for sector in sectors:
        start = sector * 2048
        data[start:start + 8] = b'daeh' + struct.pack('<I', 5)
        data[start + 0x40:start + 0x40 + len(BUILD)] = BUILD
        data[start + 0x7fc:start + 0x800] = b'toof'
    return data


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('clang'),
                     'native Apple extractor requires Darwin and clang')
class XboxDiscImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.library_dir = tempfile.TemporaryDirectory(prefix='halopad-xiso-library-')
        library = pathlib.Path(cls.library_dir.name) / 'xiso.dylib'
        subprocess.run(['clang', '-std=c11', '-Wall', '-Wextra', '-Werror',
                        '-dynamiclib', str(ROOT / 'port/xbox/xg_xiso.c'), '-o', str(library)],
                       check=True, capture_output=True)
        cls.library = ctypes.CDLL(str(library))
        cls.extract = cls.library.xg_extract_maps
        cls.extract.argtypes = [ctypes.c_char_p, ctypes.c_char_p, PROGRESS, ctypes.c_void_p,
                                ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p,
                                ctypes.c_size_t]
        cls.extract.restype = ctypes.c_int

    @classmethod
    def tearDownClass(cls):
        cls.library_dir.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='halopad-xiso-fixture-')
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.disc = self.root / 'fixture.iso'
        self.destination = self.root / 'data'

    def run_import(self, data=None, during_copy=None):
        self.disc.write_bytes(image() if data is None else data)
        build = ctypes.create_string_buffer(b'unchanged', 64)
        error = ctypes.create_string_buffer(b'unchanged', 512)
        fractions = []
        failures = []

        @PROGRESS
        def progress(fraction, _):
            fractions.append(fraction)
            if during_copy and len(fractions) == 1:
                try:
                    during_copy()
                except Exception as exc:
                    failures.append(exc)

        result = self.extract(bytes(self.disc), bytes(self.destination), progress, None,
                              build, len(build), error, len(error))
        if failures:
            raise failures[0]
        return result, build.value, error.value.decode(), fractions

    def assert_rejected(self, data):
        result, build, error, fractions = self.run_import(data)
        self.assertEqual(result, -1)
        self.assertEqual(build, b'')
        self.assertTrue(error)
        self.assertEqual(fractions, [])
        self.assertFalse(self.destination.exists(), 'validation must precede staging')

    def test_valid_and_canonical_names(self):
        data = image(('UI.MAP', 'A10.MAP'))
        result, build, error, fractions = self.run_import(data)
        self.assertEqual((result, build, error), (0, BUILD, ''))
        self.assertEqual(sorted(p.name for p in (self.destination / 'maps').iterdir()),
                         ['a10.map', 'ui.map'])
        self.assertEqual((self.destination / 'maps/ui.map').read_bytes(), data[43 * 2048:44 * 2048])
        self.assertEqual(fractions, sorted(fractions))
        self.assertEqual(fractions[-1], 1)
        self.assertEqual(list(self.destination.glob('maps.import-*')), [])

    def test_unsafe_names(self):
        for name in ('../ui.map', '/ui.map', 'ui\\.map', '.', '..', b'ui\0.map', b'ui\x1f.map',
                     'ui:map', 'ui.map ', 'ui.txt', ''):
            with self.subTest(name=name):
                self.assert_rejected(image(('ui.map', name)))

    def test_case_alias(self):
        self.assert_rejected(image(('ui.map', 'UI.MAP')))

    def test_directory_tree_invalid_pointers(self):
        for pointer in (1, 0xffff):
            with self.subTest(pointer=pointer):
                data = image(('ui.map', 'a10.map'))
                struct.pack_into('<H', data, 41 * 2048 + 2, pointer)
                self.assert_rejected(data)

    def test_directory_cycle(self):
        data = image(('ui.map', 'a10.map'))
        second = struct.unpack_from('<H', data, 41 * 2048 + 2)[0] * 4
        struct.pack_into('<H', data, 41 * 2048 + second + 2, second // 4)
        self.assert_rejected(data)

    def test_directory_size_bounds(self):
        for size in (0, 13, 0xffffffff, 1024 * 1024 + 1):
            with self.subTest(size=size):
                data = image()
                struct.pack_into('<I', data, 0x10000 + 24, size)
                self.assert_rejected(data)

    def test_map_extent_bounds(self):
        for sector, size in ((0xffffffff, 2048), (43, 2047), (43, 0xffffffff)):
            with self.subTest(sector=sector, size=size):
                data = image()
                struct.pack_into('<II', data, 41 * 2048 + 4, sector, size)
                self.assert_rejected(data)

    def test_truncated_map(self):
        self.assert_rejected(image()[:-1])

    def test_header_validation_before_first_map_is_written(self):
        for offset, value in ((0, b'xxxx'), (4, struct.pack('<I', 7)),
                              (0x40, b'\0'), (0x40, b'x' * 32), (0x7fc, b'xxxx')):
            with self.subTest(offset=offset):
                data = image(('ui.map', 'a10.map'))
                data[44 * 2048 + offset:44 * 2048 + offset + len(value)] = value
                self.assert_rejected(data)

    def test_mixed_map_builds(self):
        data = image(('ui.map', 'a10.map'))
        data[44 * 2048 + 0x40] = ord('9')
        self.assert_rejected(data)

    def test_map_subdirectory(self):
        data = image()
        data[41 * 2048 + 12] = 0x10
        self.assert_rejected(data)

    def test_maps_must_be_directory_and_xbe_must_be_file(self):
        for maps_attribute, xbe_attribute, magic in ((0, 0, b'XBEH'), (16, 16, b'XBEH'),
                                                    (16, 0, b'nope')):
            with self.subTest(attributes=(maps_attribute, xbe_attribute, magic)):
                data = image()
                data[40 * 2048 + 12] = maps_attribute
                second = struct.unpack_from('<H', data, 40 * 2048 + 2)[0] * 4
                data[40 * 2048 + second + 12] = xbe_attribute
                data[42 * 2048:42 * 2048 + 4] = magic
                self.assert_rejected(data)

    def test_existing_maps_file_directory_and_link_are_preserved(self):
        self.destination.mkdir()
        maps = self.destination / 'maps'
        maps.write_bytes(b'keep file')
        self.assertEqual(self.run_import()[0], -1)
        self.assertEqual(maps.read_bytes(), b'keep file')
        maps.unlink()  # Only this inert test fixture, never a player folder.
        maps.mkdir()
        (maps / 'save-marker').write_bytes(b'keep directory')
        self.assertEqual(self.run_import()[0], -1)
        self.assertEqual((maps / 'save-marker').read_bytes(), b'keep directory')
        other = self.root / 'other'
        other.mkdir()
        self.destination = other
        (other / 'maps').symlink_to(maps, target_is_directory=True)
        self.assertEqual(self.run_import()[0], -1)
        self.assertTrue((other / 'maps').is_symlink())
        self.assertEqual((maps / 'save-marker').read_bytes(), b'keep directory')

    def test_destination_link_is_refused(self):
        real = self.root / 'real'
        real.mkdir()
        self.destination.symlink_to(real, target_is_directory=True)
        self.assertEqual(self.run_import()[0], -1)
        self.assertEqual(list(real.iterdir()), [])

    def test_old_partial_and_saves_are_untouched(self):
        self.destination.mkdir()
        for name in ('maps.partial', 'maps.import-old', 'saves'):
            folder = self.destination / name
            folder.mkdir()
            (folder / 'marker').write_bytes(b'keep')
        self.assertEqual(self.run_import()[0], 0)
        for name in ('maps.partial', 'maps.import-old', 'saves'):
            self.assertEqual((self.destination / name / 'marker').read_bytes(), b'keep')

    def test_publication_race_does_not_replace_existing_maps(self):
        def publish_other_maps():
            (self.destination / 'maps').mkdir()
            (self.destination / 'maps/marker').write_bytes(b'other import')
        result, build, _, _ = self.run_import(during_copy=publish_other_maps)
        self.assertEqual((result, build), (-1, b''))
        self.assertEqual((self.destination / 'maps/marker').read_bytes(), b'other import')
        self.assertEqual(len(list(self.destination.glob('maps.import-*'))), 1)
        self.assertFalse((self.destination / 'maps/ui.map').exists())

    def test_interrupted_copy_is_not_published_or_reused(self):
        def truncate_source():
            with self.disc.open('r+b') as file:
                file.truncate(44 * 2048)
        result, build, _, _ = self.run_import(image(map_size=3 * 1024 * 1024), truncate_source)
        self.assertEqual((result, build), (-1, b''))
        self.assertFalse((self.destination / 'maps').exists())
        stages = list(self.destination.glob('maps.import-*'))
        self.assertEqual(len(stages), 1)
        partial_contents = (stages[0] / 'ui.map').read_bytes()
        self.assertEqual(self.run_import()[0], 0)
        self.assertEqual((stages[0] / 'ui.map').read_bytes(), partial_contents)


if __name__ == '__main__':
    unittest.main()
