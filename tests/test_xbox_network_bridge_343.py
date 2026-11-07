"""OpenCE 343's early listing filter must agree with every later join gate."""
import hashlib
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import network_bridge as bridge
from test_xbox_network_bridge_294 import browser_sources
from test_xbox_network_policy import engine_tree


def intake():
    return (bridge.LOBBY_INTAKE_DEFINE + b'{\n\tstruct listing listing;\n' + bridge.LOBBY_INTAKE +
            b'\t{\n\t\tif (' + bridge.LOBBY_NEWER + b')\n\t\t\tnewer_heard(key_hash);\n'
            b'\t\treturn 0;\n\t}\n\treturn listing_current(&listing, retained);\n}\n')


class Browser343Tests(unittest.TestCase):
    def engine(self, root):
        sources = browser_sources()
        sources[bridge.LOBBY] = sources[bridge.LOBBY].replace(bridge.LOBBY_NEWER + b'\n', intake())
        sources[bridge.SERVER_MODE_HEADER] = b'#if defined(HALO_ANDROID)\n#define HALO_SERVER_BUILD 0\n#endif\n'
        for path, (count, _) in bridge.SERVER_ONLY_343.items():
            sources[path] = (b'#if HALO_SERVER_BUILD\n' +
                             b'log_version(HALO_PORT_NETWORK_VERSION);\n' * count + b'#endif\n')
        files = engine_tree(root, sources)
        for patcher in (
            mock.patch.object(bridge, 'SERVER_MODE_SHA256', hashlib.sha256(sources[bridge.SERVER_MODE_HEADER]).hexdigest()),
            mock.patch.object(bridge, 'SERVER_ONLY_343', {
                path: (count, hashlib.sha256(sources[path]).hexdigest())
                for path, (count, _) in bridge.SERVER_ONLY_343.items()}),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)
        return files

    def test_intake_and_later_filter_are_both_bridged(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            originals = self.engine(root)
            changes = {p.relative_to(root): changed for p, _, changed in bridge.changes(root)}
            lobby = changes[bridge.LOBBY]
            self.assertIn(bridge.LOBBY_INTAKE_REPLACE, lobby)
            self.assertIn(bridge.LOBBY_FILTER_REPLACE, lobby)
            self.assertIn(bridge.LOBBY_NEWER_REPLACE, lobby)
            self.assertNotIn(bridge.LOBBY_INTAKE, lobby)
            self.assertEqual({p: (root / p).read_bytes() for p in originals}, originals)
            self.assertFalse(set(changes) & set(bridge.SERVER_ONLY_343))

    def test_intake_mutation_or_relocated_server_use_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            originals = self.engine(root)
            (root / bridge.LOBBY).write_bytes(originals[bridge.LOBBY].replace(
                bridge.LOBBY_INTAKE, bridge.LOBBY_INTAKE.replace(b'!=', b'==')))
            with self.assertRaisesRegex(ValueError, 'lobby queue intake'):
                bridge.changes(root)
            (root / bridge.LOBBY).write_bytes(originals[bridge.LOBBY])
            for path in bridge.SERVER_ONLY_343:
                with self.subTest(path=path):
                    (root / path).write_bytes(originals[path].replace(b'#if HALO_SERVER_BUILD', b'#if 1'))
                    with self.assertRaisesRegex(ValueError, 'dedicated-server source/guard'):
                        bridge.changes(root)
                    (root / path).write_bytes(originals[path])

    def test_historical_recipe_is_preserved(self):
        self.assertEqual(hashlib.sha256(bridge.recipe(newer=True, browser=True)).hexdigest(),
                         'dc50e759161fe742eb26734dbaf745724a4cea6bd6cc7e95e2e8316dcbfb94df')
        self.assertNotEqual(bridge.recipe(newer=True, browser=True),
                            bridge.recipe(newer=True, browser=True, queued=True))

    def test_compiled_intake_preserves_invalid_closed_and_expired_filters(self):
        # Compile the emitted function, including the actual insertion anchors,
        # against the production host policy; no engine or game data is needed.
        sources = browser_sources()
        sources[bridge.LOBBY] = sources[bridge.LOBBY].replace(bridge.LOBBY_NEWER + b'\n', intake())
        adapted = bridge.adapt(bridge.LOBBY, sources[bridge.LOBBY])
        start = adapted.index(bridge.LOBBY_INTAKE_DEFINE)
        function = adapted[start:adapted.index(b'\n}\n', start) + 3].decode()
        source = r'''
#include <assert.h>
#include "xg_network_policy.h"
#define HALO_PORT_NETWORK_VERSION 41
#define _listing_closed 1
POLICY_MODE
static struct xg_network_policy policy;
unsigned host_halopad_network_announce_v1(unsigned ours) {
    return xg_network_policy_announce(&policy, ours);
}
unsigned host_halopad_network_accepts_v1(unsigned ours, unsigned theirs) {
    return xg_network_policy_accepts(&policy, ours, theirs);
}
HELPERS
struct listing { unsigned version, flags; };
static unsigned newer, current_checks;
static int listing_read(const unsigned char *payload, int size, struct listing *value) {
    if(size != 2) return 0;
    value->version=payload[0]; value->flags=payload[1]; return 1;
}
static void newer_heard(const unsigned char *key) { assert(*key==7); newer++; }
static int listing_current(const struct listing *value, int retained) {
    (void)value; current_checks++; return retained != -1;
}
FUNCTION
static int check(unsigned version, unsigned flags, int size, int retained) {
    unsigned char payload[2]={(unsigned char)version,(unsigned char)flags}, key=7;
    return listing_wanted(payload,size,retained,&key);
}
int main(void) {
    assert(!check(41,0,1,0) && !newer && !current_checks);
    assert(!check(39,0,2,0) && !check(40,0,2,0) && !newer && !current_checks);
    assert(check(41,0,2,0) && current_checks==1);
    assert(!check(41,0,2,-1) && current_checks==2);
    assert(!check(42,1,2,0) && !newer);
    assert(!check(42,0,2,0) && newer==1);
    assert(xg_network_policy_set(&policy,41,42,41,42));
#ifdef HALO_ANDROID
    assert(check(42,0,2,0) && newer==1);
    assert(!check(42,0,2,-1) && newer==1);
#else
    assert(!check(42,0,2,0) && newer==2);
#endif
    return 0;
}
'''.replace('HELPERS', bridge.LOBBY_DEFINE.decode()).replace('FUNCTION', function)
        with tempfile.TemporaryDirectory() as tmp:
            for android in (False, True):
                executable = pathlib.Path(tmp) / str(android)
                built = subprocess.run(['clang', '-x', 'c', '-', '-std=c11', '-Wall', '-Wextra', '-Werror',
                                        '-fsanitize=address,undefined', '-I', str(ROOT / 'port/xbox'),
                                        '-o', str(executable)], input=source.replace('POLICY_MODE',
                                        '#define HALO_ANDROID 1' if android else ''), text=True, capture_output=True)
                self.assertEqual(built.returncode, 0, built.stderr)
                ran = subprocess.run([str(executable)], capture_output=True)
                self.assertEqual(ran.returncode, 0, ran.stderr.decode())


if __name__ == '__main__':
    unittest.main()
