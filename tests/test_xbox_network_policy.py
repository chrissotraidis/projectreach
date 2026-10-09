"""HaloPad network policy v1: guest bridge, publisher decisions, signatures, app verifier."""
import base64
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import network_bridge as bridge  # noqa: E402
import network_policy as policy  # noqa: E402

CLIENT = (b'\tunsigned int ours = HALO_PORT_NETWORK_VERSION;\n\tunsigned int theirs;\n'
          b'\t/* HALO_PORT_NETWORK_VERSION in a comment */\n' + bridge.CLIENT_ANCHOR +
          b'\tif (theirs == ours && distributed)\n')
SERVER = b'\t\t\t/* the version */\n' + bridge.SERVER_ANCHOR
LOBBY = (b'// HALO_PORT_NETWORK_VERSION\n' + bridge.LOBBY_DEFINE_ANCHOR + b'{\n' + bridge.LOBBY_LISTING +
         b'}\n\t\tif (!listing_read(p, s, &listing) || ' + bridge.LOBBY_FILTER + b'\n')


def engine_tree(root, extra=None):
    files = {bridge.CLIENT: CLIENT, bridge.SERVER: SERVER, bridge.LOBBY: LOBBY,
             bridge.IMPORTS: b'host_sdl_init\n', bridge.LIMITS: b'#define HALO_PORT_NETWORK_VERSION 24\n',
             pathlib.Path('source/other.c'): b'int x;\n', **(extra or {})}
    for path, content in files.items():
        (root / path).parent.mkdir(parents=True, exist_ok=True)
        (root / path).write_bytes(content)
    return files


class BridgeTests(unittest.TestCase):
    def test_four_sites_and_imports(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            engine_tree(root)
            result = {path.relative_to(root): modified for path, _, modified in bridge.changes(root)}
        self.assertIn(b'host_halopad_network_accepts_v1(ours, theirs)', result[bridge.CLIENT])
        self.assertLess(result[bridge.CLIENT].index(bridge.CLIENT_ANCHOR),
                        result[bridge.CLIENT].index(b'host_halopad_network_accepts_v1(ours'))
        self.assertIn(b'announced >> 8', result[bridge.SERVER])
        self.assertIn(bridge.SERVER_ANCHOR, result[bridge.SERVER])  # kept for non-Android builds
        self.assertIn(b'halopad_network_announced() >> 8', result[bridge.LOBBY])
        self.assertIn(b'!halopad_network_accepts(listing.version) ||', result[bridge.LOBBY])
        self.assertNotIn(bridge.LOBBY_FILTER, result[bridge.LOBBY])
        self.assertTrue(result[bridge.IMPORTS].endswith(
            b'\nhost_halopad_network_announce_v1\nhost_halopad_network_accepts_v1\n'))

    def test_unreviewed_use_or_changed_anchor_stops(self):
        for extra in ({pathlib.Path('port/linux/src/new.c'): b'int v = HALO_PORT_NETWORK_VERSION;\n'},
                      {bridge.CLIENT: CLIENT + b'\tours = HALO_PORT_NETWORK_VERSION;\n'}):
            with tempfile.TemporaryDirectory() as tmp, self.assertRaisesRegex(ValueError, 'unreviewed'):
                engine_tree(pathlib.Path(tmp), extra)
                bridge.changes(pathlib.Path(tmp))
        with tempfile.TemporaryDirectory() as tmp, self.assertRaisesRegex(ValueError, 'anchor changed'):
            engine_tree(pathlib.Path(tmp), {bridge.SERVER: SERVER.replace(b'& 0xFF', b'&0xFF')})
            bridge.changes(pathlib.Path(tmp))
        with self.assertRaisesRegex(ValueError, 'already declares'):
            bridge.adapt(bridge.IMPORTS, b'host_halopad_network_accepts_v1\n')

    def test_native_policy_rules(self):
        source = r'''
#include <assert.h>
#include "xg_network_policy.h"
int main(void) {
    struct xg_network_policy p = {0};
    assert(xg_network_policy_announce(&p, 24) == 24 && xg_network_policy_accepts(&p, 24, 24));
    assert(!xg_network_policy_accepts(&p, 24, 25) && !xg_network_policy_accepts(&p, 24, 23));
    assert(xg_network_policy_set(&p, 24, 26, 24, 26));
    assert(xg_network_policy_announce(&p, 24) == 26);
    assert(xg_network_policy_accepts(&p, 24, 25) && xg_network_policy_accepts(&p, 24, 26));
    assert(!xg_network_policy_accepts(&p, 24, 27) && !xg_network_policy_accepts(&p, 24, 23));
    /* a policy for another engine never applies */
    assert(xg_network_policy_announce(&p, 25) == 25 && !xg_network_policy_accepts(&p, 25, 26));
    /* rows that could refuse our own version, or announce less, are rejected */
    assert(!xg_network_policy_set(&p, 24, 26, 25, 26) && !p.set);
    assert(!xg_network_policy_set(&p, 24, 23, 23, 26) && !xg_network_policy_set(&p, 24, 27, 24, 26));
    assert(!xg_network_policy_set(&p, 24, 24, 24, 70000) && !xg_network_policy_set(&p, 0, 0, 0, 0));
    assert(xg_network_policy_announce(&p, 24) == 24 && !xg_network_policy_accepts(&p, 24, 25));
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp)
            (path / 'test.c').write_text(source)
            subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', '-I', str(ROOT / 'port/xbox'),
                            str(path / 'test.c'), '-o', str(path / 'test')], check=True)
            subprocess.run([str(path / 'test')], check=True)


DELTA = '''#define DELTA_LEGACY_VERSIONS(X) \\
\tX(11, "build-76", breaking) /* settings */ \\
\tX(23, "build-147", additive) /* maps */ \\
\tX(24, "build-149", additive) /* vehicles */ \\
\tX(25, "build-170", additive) /* new */

#define DELTA_OTHER X(26, "build-180", breaking)
'''


class DecisionTests(unittest.TestCase):
    def test_classification_reads_only_the_table(self):
        self.assertEqual(policy.classification(DELTA), {11: 'breaking', 23: 'additive', 24: 'additive', 25: 'additive'})
        self.assertEqual(policy.network_version(b'#define HALO_PORT_NETWORK_VERSION 24\n'), 24)
        with self.assertRaises(policy.PolicyError):
            policy.network_version(b'#define HALO_PORT_NETWORK_VERSION 24\n#define HALO_PORT_NETWORK_VERSION 25\n')

    def test_decisions(self):
        kinds = policy.classification(DELTA)
        self.assertEqual(policy.decide(24, 24, kinds), (policy.exact(24), 'current'))
        self.assertEqual(policy.decide(24, 25, kinds, upstream_tag='build-170'),
                         ({'announce': 25, 'minimum': 24, 'maximum': 25, 'follows': 'build-170'}, 'following'))
        previous = {'announce': 25, 'minimum': 24, 'maximum': 25}
        # 26 is unclassified in the table (DELTA_OTHER is not the table): keep the last approval
        self.assertEqual(policy.decide(24, 26, kinds, previous), (previous, 'waiting'))
        self.assertEqual(policy.decide(24, 26, {**kinds, 26: 'breaking'}, previous), (previous, 'needs-release'))
        self.assertEqual(policy.decide(24, 26, kinds, previous, approved_through=26)[1], 'following')
        self.assertEqual(policy.decide(10, 12, kinds), (policy.exact(10), 'needs-release'))

    def test_plan_is_stable_monotonic_and_withdrawable(self):
        kinds = policy.classification(DELTA)
        document, report = policy.plan(None, {24}, 25, 'build-170', kinds, now=1000)
        first = json.loads(document)
        self.assertEqual(first['serial'], 1000)
        self.assertEqual(report['engines']['24']['status'], 'following')
        self.assertEqual(policy.plan(first, {24}, 25, 'build-171', kinds, now=2000)[0], None)  # rows unchanged
        withdrawn = json.loads(policy.plan(first, {24}, 25, 'build-170', kinds, mode='exact', now=900)[0])
        self.assertEqual(withdrawn['serial'], 1001)
        self.assertEqual(withdrawn['engines']['24'], policy.exact(24))
        # an older engine's row is kept while a newer engine is added
        both = json.loads(policy.plan(first, {25}, 25, 'build-170', kinds, now=3000)[0])
        self.assertEqual(set(both['engines']), {'24', '25'})

    def test_document_checks(self):
        good = {'format': 1, 'serial': 5, 'engines': {'24': policy.exact(24)}}
        policy.check_document(json.dumps(good).encode())
        for bad in ({**good, 'serial': True}, {**good, 'serial': 0}, {**good, 'format': 2},
                    {**good, 'engines': {'024': policy.exact(24)}},
                    {**good, 'engines': {'24': {'announce': 25, 'minimum': 25, 'maximum': 25}}},
                    {**good, 'engines': {'24': {'announce': 24.0, 'minimum': 24, 'maximum': 24}}},
                    {**good, 'engines': {'24': {**policy.exact(24), 'follows': 'a b'}}}):
            with self.assertRaises(policy.PolicyError):
                policy.check_document(json.dumps(bad).encode())


OPENSSL = shutil.which('openssl')


def test_key(folder):
    key = pathlib.Path(folder) / 'key.pem'
    subprocess.run([OPENSSL, 'ecparam', '-name', 'prime256v1', '-genkey', '-noout', '-out', str(key)],
                   check=True, capture_output=True)
    return key


def raw_public(pem_or_key, private=False):
    args = [OPENSSL, 'ec', '-in', str(pem_or_key), '-pubout', '-outform', 'DER']
    if not private:
        args.insert(2, '-pubin')
    return subprocess.run(args, check=True, capture_output=True).stdout[-65:]


@unittest.skipUnless(OPENSSL, 'openssl is required')
class SignatureTests(unittest.TestCase):
    def test_round_trip_and_tampering(self):
        with tempfile.TemporaryDirectory() as tmp:
            key = test_key(tmp)
            document, _ = policy.plan(None, {24}, 25, 'build-170', policy.classification(DELTA), now=1000)
            envelope = policy.sign(document, key)
            public = policy.public_key_of(key)
            self.assertEqual(policy.verify(envelope, public)['engines']['24']['announce'], 25)
            outer = json.loads(envelope)
            outer['document'] = base64.b64encode(document.replace(b'25', b'26')).decode()
            with self.assertRaisesRegex(policy.PolicyError, 'does not verify'):
                policy.verify(json.dumps(outer).encode(), public)
            with self.assertRaisesRegex(policy.PolicyError, 'does not verify'):
                policy.verify(envelope, policy.PUBLIC_KEY)  # the production key did not sign it

    def test_app_key_matches_published_public_key(self):
        header = (ROOT / 'port/ios/HaloPadXboxNetworkPolicy.h').read_text()
        block = header[header.index('HPNetworkPolicyPublicKey[65]'):]
        block = block[block.index('{') + 1:block.index('}')]
        constant = bytes(int(b, 16) for b in re.findall(r'0x([0-9a-f]{2})', block))
        self.assertEqual(constant, raw_public(policy.PUBLIC_KEY))

    @unittest.skipUnless(sys.platform == 'darwin', 'Security.framework is required')
    def test_app_verifier(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp)
            key = test_key(tmp)
            kinds = policy.classification(DELTA)
            first, _ = policy.plan(None, {24}, 25, 'build-170', kinds, now=1000)
            newer, _ = policy.plan(json.loads(first), {24}, 25, 'build-170', kinds, mode='exact', now=1000)
            (path / 'first.json').write_bytes(policy.sign(first, key))
            (path / 'newer.json').write_bytes(policy.sign(newer, key))
            outer = json.loads((path / 'first.json').read_text())
            outer['document'] = base64.b64encode(first.replace(b'"announce": 25', b'"announce": 26')).decode()
            (path / 'tampered.json').write_text(json.dumps(outer))
            loose = json.dumps({'format': 1, 'serial': 7, 'engines': {'24': {'announce': 25, 'minimum': 25,
                                'maximum': 25}}}).encode()
            envelope = json.loads((path / 'first.json').read_text())
            signature = subprocess.run([OPENSSL, 'dgst', '-sha256', '-sign', str(key)], input=loose,
                                       check=True, capture_output=True).stdout
            envelope.update(document=base64.b64encode(loose).decode(), signature=base64.b64encode(signature).decode())
            (path / 'signed-but-narrowing.json').write_text(json.dumps(envelope))
            key_bytes = ', '.join(f'0x{b:02x}' for b in raw_public(key, private=True))
            source = r'''
#import "HaloPadXboxNetworkPolicy.h"
#include <assert.h>
static NSData *file(const char *name) { return [NSData dataWithContentsOfFile:[@"%DIR%" stringByAppendingPathComponent:@(name)]]; }
int main(void) { @autoreleasepool {
    (void)HPNetworkPolicyCached; (void)HPNetworkPolicyRefresh;
    const unsigned char bytes[65] = { %KEY% };
    NSData *key = [NSData dataWithBytes:bytes length:65];
    NSDictionary *first = HPNetworkPolicyRead(file("first.json"), 24, key);
    assert([first[@"serial"] isEqual:@1000]);
    assert([first[@"row"][@"announce"] isEqual:@25] && [first[@"row"][@"minimum"] isEqual:@24] &&
           [first[@"row"][@"maximum"] isEqual:@25] && [first[@"row"][@"follows"] isEqual:@"build-170"]);
    assert(HPNetworkPolicyRead(file("first.json"), 25, key)[@"row"] == nil);   /* other engines: exact */
    assert(!HPNetworkPolicyRead(file("first.json"), 24, HPNetworkPolicyDefaultKey()));
    assert(!HPNetworkPolicyRead(file("tampered.json"), 24, key));
    assert(!HPNetworkPolicyRead(file("signed-but-narrowing.json"), 24, key));
    assert(!HPNetworkPolicyRead([@"{}" dataUsingEncoding:NSUTF8StringEncoding], 24, key));
    assert(!HPNetworkPolicyRead(nil, 24, key));
    NSURL *cache = [NSURL fileURLWithPath:@"%DIR%/cache/network-policy.json"];
    assert(!HPNetworkPolicyStore(file("tampered.json"), 24, cache, key));
    assert(HPNetworkPolicyStore(file("first.json"), 24, cache, key));
    assert(!HPNetworkPolicyStore(file("first.json"), 24, cache, key));          /* same serial */
    assert(HPNetworkPolicyStore(file("newer.json"), 24, cache, key));
    assert(!HPNetworkPolicyStore(file("first.json"), 24, cache, key));          /* never rolls back */
    NSDictionary *cached = HPNetworkPolicyRead([NSData dataWithContentsOfURL:cache], 24, key);
    assert([cached[@"serial"] isEqual:@1001] && [cached[@"row"][@"announce"] isEqual:@24]);
    assert([HPNetworkPolicySummary(24, cached) isEqual:@"Online play: OpenCE network version 24."]);
    assert([HPNetworkPolicySummary(24, first) containsString:@"versions 24 to 25"]);
    assert([HPNetworkPolicySourceURL().absoluteString isEqual:HPNetworkPolicyURL]);
    setenv("HALOPAD_NETWORK_POLICY_URL", "https://evil.invalid/network-policy.json", 1);
    assert([HPNetworkPolicySourceURL().absoluteString isEqual:HPNetworkPolicyURL]);
    setenv("HALOPAD_NETWORK_POLICY_URL", "https://raw.githubusercontent.com/chrissotraidis/projectreach/test/network-policy.json", 1);
    assert([HPNetworkPolicySourceURL().absoluteString hasSuffix:@"/test/network-policy.json"]);
} return 0; }
'''.replace('%DIR%', str(path)).replace('%KEY%', key_bytes)
            (path / 'test.m').write_text(source)
            subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror', '-I', str(ROOT / 'port/ios'),
                            str(path / 'test.m'), '-framework', 'Foundation', '-framework', 'Security',
                            '-o', str(path / 'test')], check=True)
            subprocess.run([str(path / 'test')], check=True)


if __name__ == '__main__':
    unittest.main()
