"""Asset-free checks for OpenCE 294's browser and dedicated-server uses."""
import hashlib
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import network_bridge as bridge
from test_xbox_network_policy import CLIENT, SERVER, engine_tree


def browser_sources():
    return {
        bridge.CLIENT: CLIENT + bridge.CLIENT_TELL + b'}\n',
        bridge.LOBBY: (bridge.LOBBY_TOKEN_DEFINE + b'{\n' + bridge.LOBBY_LISTING + b'}\n' +
                       bridge.LOBBY_DEFINE_ANCHOR + b'{}\n' + bridge.LOBBY_FILTER + b'\n' +
                       bridge.LOBBY_NEWER + b'\n' + b''.join(a for a, _ in bridge.LOBBY_SORT_EDITS)),
        bridge.MENU: bridge.MENU_DEFINE + b'{\n' + b''.join(a for a, _ in bridge.MENU_EDITS) + b'}\n',
    }


class Browser294Tests(unittest.TestCase):
    def engine(self, root):
        files = engine_tree(root, browser_sources())
        guard = b'#if defined(HALO_ANDROID) || defined(HALO_WEB)\n#define HALO_SERVER_BUILD 0\n#endif\n'
        fixtures = {bridge.SERVER_MODE_HEADER: guard}
        for path, (count, _) in bridge.SERVER_ONLY.items():
            fixtures[path] = (b'#if HALO_SERVER_BUILD\n' +
                              b'log_version(HALO_PORT_NETWORK_VERSION);\n' * count + b'#endif\n')
        for path, source in fixtures.items():
            (root / path).parent.mkdir(parents=True, exist_ok=True)
            (root / path).write_bytes(source)
        # Synthetic, asset-free inputs replace only the exact source identities.
        hashes = mock.patch.object(bridge, 'SERVER_ONLY', {
            path: (count, hashlib.sha256(fixtures[path]).hexdigest())
            for path, (count, _) in bridge.SERVER_ONLY.items()})
        header = mock.patch.object(bridge, 'SERVER_MODE_SHA256', hashlib.sha256(guard).hexdigest())
        for patcher in (hashes, header):
            patcher.start()
            self.addCleanup(patcher.stop)
        return {**files, **fixtures}

    def test_old_recipes_are_unchanged_and_browser_is_distinct(self):
        self.assertEqual(hashlib.sha256(bridge.recipe()).hexdigest(),
                         'ba7be9c931ef2821a718d61bedb6a8ddb148a4e83a3646654fa3e426807dc33d')
        self.assertEqual(hashlib.sha256(bridge.recipe(newer=True)).hexdigest(),
                         '55bb6c369019a153094e7270fea471ca7d025fd0fb45d1aa9ece622daac650aa')
        self.assertNotEqual(bridge.recipe(newer=True), bridge.recipe(newer=True, browser=True))

    def test_every_live_site_is_adapted_and_server_files_are_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            originals = self.engine(root)
            result = {path.relative_to(root): changed for path, _, changed in bridge.changes(root)}
            self.assertEqual(set(result), {bridge.CLIENT, bridge.SERVER, bridge.LOBBY, bridge.MENU, bridge.IMPORTS})
            self.assertEqual(result[bridge.CLIENT].count(b'host_halopad_network_accepts_v1(ours, theirs)'), 2)
            lobby = result[bridge.LOBBY]
            self.assertLess(lobby.index(bridge.LOBBY_DEFINE), lobby.index(bridge.LOBBY_TOKEN_DEFINE))
            for before, after in (*bridge.LOBBY_SORT_EDITS, *bridge.MENU_EDITS):
                source = lobby if (before, after) in bridge.LOBBY_SORT_EDITS else result[bridge.MENU]
                self.assertIn(after, source)
                self.assertNotIn(before, source)
            self.assertIn(bridge.LOBBY_NEWER_REPLACE, lobby)
            self.assertIn(bridge.LOBBY_FILTER_REPLACE, lobby)
            self.assertEqual({path: (root / path).read_bytes() for path in originals}, originals)

    def test_unknown_or_relocated_uses_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            originals = self.engine(root)
            for path in (bridge.CLIENT, bridge.LOBBY, bridge.MENU, *bridge.SERVER_ONLY):
                with self.subTest(path=path):
                    (root / path).write_bytes(originals[path] + b'int extra = HALO_PORT_NETWORK_VERSION;\n')
                    with self.assertRaisesRegex(ValueError, 'unreviewed'):
                        bridge.changes(root)
                    (root / path).write_bytes(originals[path])
            unknown = root / 'port/linux/src/server_new.c'
            unknown.write_bytes(b'int v = HALO_PORT_NETWORK_VERSION;\n')
            with self.assertRaisesRegex(ValueError, 'unreviewed'):
                bridge.changes(root)
            unknown.unlink()
            for path in (*bridge.SERVER_ONLY, bridge.SERVER_MODE_HEADER):
                with self.subTest(guard=path):
                    # Same number of version uses, but the compile guard is lost.
                    (root / path).write_bytes(originals[path].replace(b'#if ', b'#if 1 /* changed */ || ', 1))
                    with self.assertRaisesRegex(ValueError, 'dedicated-server source/guard'):
                        bridge.changes(root)
                    (root / path).write_bytes(originals[path])

    def test_changed_browser_anchor_with_same_token_count_fails(self):
        mutations = [
            (bridge.CLIENT, bridge.CLIENT_TELL, bridge.CLIENT_TELL.replace(b'char message[400]', b'char message[401]')),
            (bridge.LOBBY, bridge.LOBBY_NEWER, bridge.LOBBY_NEWER.replace(b'>', b'>=')),
            (bridge.LOBBY, bridge.LOBBY_FILTER, bridge.LOBBY_FILTER.replace(b'!=', b'==')),
        ]
        mutations += [(path, before, before.replace(b'!=', b'==').replace(b' > ', b' >= '))
                      for path, edits in ((bridge.LOBBY, bridge.LOBBY_SORT_EDITS), (bridge.MENU, bridge.MENU_EDITS))
                      for before, _ in edits]
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            originals = self.engine(root)
            for path, before, after in mutations:
                with self.subTest(path=path, before=before):
                    self.assertNotEqual(before, after)
                    (root / path).write_bytes(originals[path].replace(before, after))
                    with self.assertRaisesRegex(ValueError, 'anchor changed'):
                        bridge.changes(root)
                    (root / path).write_bytes(originals[path])

    def test_compiled_policy_covers_sort_display_join_and_lockstep_rejection(self):
        sources = browser_sources()
        lobby = bridge.adapt(bridge.LOBBY, sources[bridge.LOBBY])
        menu = bridge.adapt(bridge.MENU, sources[bridge.MENU])
        client = bridge.adapt(bridge.CLIENT, sources[bridge.CLIENT])
        # Compile the expressions emitted at each actual bridge site with the
        # production host policy, including a synthetic non-exact policy. The
        # production policy publisher still permits no version transitions.
        expressions = [
            re.search(rb'int other_version = (.*);', lobby)[1].decode().replace('game.network_version', 'v'),
            re.search(rb'int before_other = (.*);', lobby)[1].decode().replace('before->network_version', 'v'),
            re.search(rb'\n\t\tother_version = (.*);', menu)[1].decode().replace('game->network_version', 'v'),
        ]
        expressions += [match.decode().replace('game->network_version', 'v')
                        for match in re.findall(rb'\n\tif \(([^\n]+)\)\n', menu)]
        self.assertEqual(len(expressions), 5)
        newer = re.findall(rb'game->network_version > (.*?) \?', menu)
        self.assertEqual(newer, [b'halopad_network_announced()', b'halopad_network_announced()'])
        filters = '\n'.join(f'assert(({expression}) == !expected);' for expression in expressions)
        insertions = client.count(bridge.CLIENT_INSERT)
        self.assertEqual(insertions, 2)
        source = r'''
#include <assert.h>
#include "xg_network_policy.h"
#define HALO_PORT_NETWORK_VERSION 39
POLICY_MODE
static struct xg_network_policy policy;
unsigned int host_halopad_network_announce_v1(unsigned int ours) {
    return xg_network_policy_announce(&policy, ours);
}
unsigned int host_halopad_network_accepts_v1(unsigned int ours, unsigned int theirs) {
    return xg_network_policy_accepts(&policy, ours, theirs);
}
HELPERS
static int compatible(unsigned theirs, int distributed) {
    unsigned ours=HALO_PORT_NETWORK_VERSION;
INSERT
    return ours==theirs && distributed;
}
static int explanation(unsigned theirs) {
    unsigned ours=HALO_PORT_NETWORK_VERSION;
INSERT
    return theirs==ours ? 0 : theirs>ours ? 1 : -1;
}
static void check(unsigned v, int expected) {
GATES
    assert(compatible(v,1)==expected);
    assert(!compatible(v,0));
    if(expected) assert(explanation(v)==0);
}
int main(void) {
    assert(halopad_network_announced()==39);
    check(38,0); check(39,1); check(40,0); check(41,0);
    assert(xg_network_policy_set(&policy,38,40,38,40));
    check(38,0); check(39,1); check(40,0);
    assert(xg_network_policy_set(&policy,39,41,39,41));
#ifdef HALO_ANDROID
    assert(halopad_network_announced()==41);
    check(38,0); check(39,1); check(40,1); check(41,1); check(42,0);
#else
    assert(halopad_network_announced()==39);
    check(38,0); check(39,1); check(40,0); check(41,0); check(42,0);
#endif
    return 0;
}
'''.replace('HELPERS', bridge.LOBBY_DEFINE.decode()).replace('INSERT', bridge.CLIENT_INSERT.decode()).replace('GATES', filters)
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
