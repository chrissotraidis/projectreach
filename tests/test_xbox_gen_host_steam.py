"""HaloPad's copies of upstream's Steam host change exactly what they mean to.

The inputs are small stand-ins written for these tests, shaped like the lines
gen-host-steam.py looks for; upstream's files are not needed."""
import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('gen_host_steam', ROOT / 'scripts/xbox/gen-host-steam.py')
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

DOWNLOADS = '''#include <stdint.h>
#define GUEST_POINTER(address) ((void *)(uintptr_t)(address))
static int move_folder(char const *from, char const *to)
{
	return posix_mcc_share_publish(from, to);
}
int host_steam_open(unsigned int root) { return open_at((char const *)GUEST_POINTER(root)); }
'''

HASH = ''.join('void *p%d = (void *)(uintptr_t)%s;\n' % (i, name) for i, name in enumerate([
    'request_address', 'result_address', 'path_address', 'digest_address', 'size_address',
    'request->data_root', 'request->paths[type]', 'request_address']))

IMPORTS = 'host_sdl_poll\nhost_steam_open\nhost_mcc_hash_start\nhost_sha256_digest\n'


class GenHostSteamTests(unittest.TestCase):
    def test_guest_addresses_convert_through_gp(self):
        out = gen.steam_downloads(DOWNLOADS)
        self.assertIn('#define GUEST_POINTER(address) GP(address)', out)
        self.assertNotIn('(uintptr_t)(address)', out)

    def test_downloads_publish_with_darwin_rename(self):
        # Upstream's publish is Linux-only (ENOTSUP elsewhere): every install
        # failed on Apple platforms until this call was redirected.
        out = gen.steam_downloads(DOWNLOADS)
        self.assertIn('return xg_mcc_share_publish(from, to);', out)
        self.assertNotIn('posix_mcc_share_publish(from, to)', out)
        self.assertIn('int xg_mcc_share_publish(const char *from, const char *to);', out)

    def test_moved_publish_call_stops_generation(self):
        with self.assertRaises(SystemExit):
            gen.steam_downloads(DOWNLOADS.replace('return posix_mcc_share_publish(from, to);',
                                                  'return posix_mcc_share_publish(to, from);'))

    def test_second_publish_call_stops_generation(self):
        with self.assertRaises(SystemExit):
            gen.steam_downloads(DOWNLOADS + 'int again(void) { return posix_mcc_share_publish(from, to); }\n')

    def test_cast_outside_the_macro_stops_generation(self):
        with self.assertRaises(SystemExit):
            gen.steam_downloads(DOWNLOADS + 'void *raw = (void *)(uintptr_t)7;\n')

    def test_hash_casts_are_counted(self):
        out = gen.mcc_hash(HASH)
        self.assertEqual(out.count('(uintptr_t)GP('), gen.HASH_EXPECTED)
        self.assertIn('(uintptr_t)GP(request->paths[type])', out)
        with self.assertRaises(SystemExit):
            gen.mcc_hash(HASH + 'void *extra = (void *)(uintptr_t)path_address;\n')

    def test_cast_prefix_of_a_longer_name_is_not_converted(self):
        out = gen.mcc_hash(HASH + 'void *q = (void *)(uintptr_t)path_address_end;\n')
        self.assertIn('(uintptr_t)path_address_end', out)

    def test_only_steam_and_hash_imports_are_renamed(self):
        header, count = gen.names_header(IMPORTS)
        self.assertEqual(count, 3)
        self.assertIn('#define host_steam_open xh_host_steam_open', header)
        self.assertIn('#define host_sha256_digest xh_host_sha256_digest', header)
        self.assertNotIn('host_sdl_poll', header)

    def test_generate_writes_three_files(self):
        with tempfile.TemporaryDirectory() as folder:
            engine, out = pathlib.Path(folder) / 'engine', pathlib.Path(folder) / 'out'
            (engine / 'port/android/host').mkdir(parents=True)
            out.mkdir()
            (engine / 'port/android/host_imports.list').write_text(IMPORTS)
            (engine / 'port/android/host/steam_downloads.c').write_text(DOWNLOADS)
            (engine / 'port/android/host/host_mcc_hash.c').write_text(HASH)
            gen.generate(engine, out)
            self.assertEqual(sorted(p.name for p in out.iterdir()),
                             ['xg_mcc_hash.c', 'xg_steam_downloads.c', 'xg_steam_names.h'])


if __name__ == '__main__':
    unittest.main()
