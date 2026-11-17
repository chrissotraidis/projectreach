"""The admin page reads the player's disc in their browser (admin.html,
readDisc): the reader is taken from the page and run in Node against small
synthetic Xbox disc images built here (no game data)."""
import json
import pathlib
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
PAGE = ROOT / 'port/xbox/admin/admin.html'
SECTOR = 2048


def directory(entries):
    """An XDVDFS directory: entries chained through their right child."""
    data = bytearray()
    offsets = []
    for name, *_ in entries:
        offsets.append(len(data))
        data += bytes(14 + len(name))
        data += bytes(-len(data) % 4)
    for index, (name, sector, size, is_directory) in enumerate(entries):
        at = offsets[index]
        right = offsets[index + 1] // 4 if index + 1 < len(entries) else 0
        struct.pack_into('<HHIIBB', data, at, 0, right, sector, size, 0x10 if is_directory else 0x20, len(name))
        data[at + 14:at + 14 + len(name)] = name.encode()
    return bytes(data)


def halo_map(build, size=4096):
    data = bytearray(size)
    data[0:4] = b'daeh'
    data[4:8] = (5).to_bytes(4, 'little')
    data[0x40:0x40 + len(build)] = build.encode()
    data[0x7fc:0x800] = b'toof'
    return bytes(data)


def disc(maps, base=0, with_ui=True, files=None):
    """A disc image with maps/ (name -> bytes) and default.xbe, its game partition at base."""
    files = dict(files or {})
    sectors = {}
    next_sector = 40
    content = {}
    for name, data in list(maps.items()) + [('default.xbe', b'XBEH' + bytes(60))]:
        sectors[name] = next_sector
        content[next_sector] = data
        next_sector += (len(data) + SECTOR - 1) // SECTOR
    maps_dir = directory([(name, sectors[name], len(data), False) for name, data in maps.items()])
    maps_sector = next_sector
    content[maps_sector] = maps_dir
    next_sector += 1
    root = directory([('maps', maps_sector, len(maps_dir), True), ('default.xbe', sectors['default.xbe'], 64, False)])
    root_sector = next_sector
    content[root_sector] = root
    image = bytearray(base + (root_sector + 1) * SECTOR)
    struct.pack_into('<20sII', image, base + 0x10000, b'MICROSOFT*XBOX*MEDIA', root_sector, len(root))
    for sector, data in content.items():
        image[base + sector * SECTOR:base + sector * SECTOR + len(data)] = data
    return bytes(image)


@unittest.skipUnless(shutil.which('node'), 'needs Node')
class DiscReaderTests(unittest.TestCase):
    def read(self, image):
        page = PAGE.read_text()
        reader = page[page.index('const SECTOR'):page.index('/* ---- the page */')]
        with tempfile.TemporaryDirectory() as folder:
            folder = pathlib.Path(folder)
            (folder / 'disc.iso').write_bytes(image)
            (folder / 'reader.mjs').write_text(reader + '''
import { openAsBlob } from "node:fs";
try {
    const disc = await readDisc(await openAsBlob(process.argv[2]));
    console.log(JSON.stringify({ maps: disc.maps, total: disc.total, build: disc.build }));
} catch (error) { console.log(JSON.stringify({ error: error.message })); }
''')
            result = subprocess.run(['node', str(folder / 'reader.mjs'), str(folder / 'disc.iso')],
                                    capture_output=True, text=True, check=True)
            return json.loads(result.stdout)

    def test_maps_are_found_with_their_offsets(self):
        maps = {'a10.map': halo_map('01.10.12.2276', 6000), 'UI.MAP': halo_map('01.10.12.2276')}
        image = disc(maps)
        found = self.read(image)
        self.assertEqual(found['build'], '01.10.12.2276')
        self.assertEqual([m['name'] for m in found['maps']], ['ui.map', 'a10.map'])   # ui.map first, names lower-cased
        self.assertEqual(found['total'], 6000 + 4096)
        for entry in found['maps']:
            original = maps['UI.MAP' if entry['name'] == 'ui.map' else entry['name']]
            self.assertEqual(image[entry['offset']:entry['offset'] + entry['size']], original)

    def test_game_partition_after_the_video_partition(self):
        found = self.read(disc({'ui.map': halo_map('01.10.12.2276')}, base=0x2080000))
        self.assertEqual(found['maps'][0]['name'], 'ui.map')

    def test_not_a_disc_or_not_halo_is_refused(self):
        self.assertIn('not an Xbox disc image', self.read(bytes(0x20000))['error'])
        self.assertIn('no ui.map', self.read(disc({'a10.map': halo_map('01.10.12.2276')}))['error'])

    def test_maps_must_be_halo_maps_of_one_build(self):
        mixed = {'ui.map': halo_map('01.10.12.2276'), 'a10.map': halo_map('01.01.14.2342')}
        self.assertIn('different builds', self.read(disc(mixed))['error'])
        broken = {'ui.map': halo_map('01.10.12.2276'), 'a10.map': b'x' * 4096}
        self.assertIn('not a Halo Xbox map', self.read(disc(broken))['error'])

    def test_unsafe_names_are_left_out(self):
        found = self.read(disc({'ui.map': halo_map('01.10.12.2276'), '..map': halo_map('01.10.12.2276'),
                                'notes.txt': b'hello'}))
        self.assertEqual([m['name'] for m in found['maps']], ['ui.map'])


if __name__ == '__main__':
    unittest.main()
