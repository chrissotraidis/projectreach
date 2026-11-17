"""The Apple TV page's Steam sign-in (xg_admin.m with XG_ADMIN_STEAM): the
password crosses the network only sealed to the TV's key for this launch.

The server is built for the Mac with a stand-in Steam session that reports
what it receives; the page's sealing (TweetNaCl's nacl.box) runs in Node.
The account and password are made up for the test."""
import http.client
import json
import os
import pathlib
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
XBOX = ROOT / 'port/xbox'
NACL = XBOX / 'third_party/tweetnacl'

MAIN = r'''
#import <Foundation/Foundation.h>
#include <stdarg.h>
#include "xg_admin.h"
#include "xg_steam_admin.h"
void xg_log(const char *format, ...) { (void)format; }
/* a stand-in Steam session: reports what the page delivered */
static int state;
void xg_steam_admin_status(char const *root, struct xg_steam_admin_status *status)
{ (void)root; memset(status, 0, sizeof(*status)); status->state = state; }
int xg_steam_admin_sign_in(char const *root, char const *account, char const *password)
{
	(void)root;
	printf("SIGN-IN %s\n", [[NSJSONSerialization dataWithJSONObject:@[ @(account), @(password) ] options:0 error:nil]
		base64EncodedStringWithOptions:0].UTF8String);
	state = XG_STEAM_GUARD;
	return 1;
}
int xg_steam_admin_code(char const *code) { printf("CODE-IN %s\n", code); return state == XG_STEAM_GUARD; }
void xg_steam_admin_cancel(void) { state = XG_STEAM_OUT; }
int xg_steam_admin_sign_out(void) { return 0; }
int main(int argc, char **argv)
{
	@autoreleasepool {
		NSString *root = @(argv[1]);
		setvbuf(stdout, NULL, _IOLBF, 0);
		if (xg_admin_start([root stringByAppendingPathComponent:@"data"], root, atoi(argv[2]), ^{},
				^(NSString *code) { if (code) printf("CODE %s\n", code.UTF8String); }))
			return 1;
		printf("LISTENING\n");
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ exit(0); });
		[NSRunLoop.mainRunLoop run];
	}
}
'''

# the page's sealing (admin.html, signInSealed), in Node with the page's nacl.min.js
SEAL = r'''
const nacl = require(process.argv[2]);
const [key, challenge, account, password] = JSON.parse(process.argv[3]);
const e = new TextEncoder(), parts = [e.encode(challenge), e.encode(account), e.encode(password)];
const plain = new Uint8Array(parts[0].length + parts[1].length + parts[2].length + 2);
plain.set(parts[0], 0); plain.set(parts[1], parts[0].length + 1); plain.set(parts[2], parts[0].length + parts[1].length + 2);
const mine = nacl.box.keyPair(), nonce = nacl.randomBytes(24);
const b64 = (b) => Buffer.from(b).toString('base64');
const box = nacl.box(plain, nonce, new Uint8Array(Buffer.from(key, 'base64')), mine.secretKey);
console.log(JSON.stringify({ key: b64(mine.publicKey), nonce: b64(nonce), box: b64(box) }));
'''

ACCOUNT, PASSWORD = 'test-account', 'päss wörd "with" \\ quotes'


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun') and shutil.which('node'),
                     'needs the Mac toolchain and Node')
class AdminSteamSignInTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory()
        work = cls.work = pathlib.Path(cls.folder.name)
        (work / 'main.m').write_text(MAIN)
        (work / 'seal.cjs').write_text(SEAL)
        (work / 'home').mkdir()
        (work / 'root').mkdir()
        built = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-Wno-unused-function',
                                '-DXG_ADMIN_STEAM=1', '-I', str(XBOX), str(work / 'main.m'), str(XBOX / 'xg_admin.m'),
                                str(NACL / 'tweetnacl.c'), '-framework', 'Foundation', '-o', str(work / 'admin-test')],
                               capture_output=True, text=True)
        if built.returncode:
            raise AssertionError(built.stderr)
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            cls.port = probe.getsockname()[1]
        cls.server = subprocess.Popen([str(work / 'admin-test'), str(work / 'root'), str(cls.port)],
                                      stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                                      env=dict(os.environ, CFFIXED_USER_HOME=str(work / 'home')))
        assert cls.server.stdout.readline().strip() == 'LISTENING'
        cls.call_raw('POST', '/api/pair/request')
        code = cls.next_line('CODE ')
        cls.token = cls.call_raw('POST', '/api/pair', {'code': code})[1]['token']

    @classmethod
    def tearDownClass(cls):
        cls.server.send_signal(signal.SIGKILL)
        cls.server.wait()
        cls.folder.cleanup()

    @classmethod
    def next_line(cls, prefix):
        while True:
            line = cls.server.stdout.readline().strip()
            if line.startswith(prefix):
                return line[len(prefix):]

    @classmethod
    def call_raw(cls, method, path, body=None, token=None):
        connection = http.client.HTTPConnection('127.0.0.1', cls.port, timeout=10)
        data = json.dumps(body).encode() if body is not None else b''
        headers = {'Content-Length': str(len(data)), 'Content-Type': 'application/json'}
        if token:
            headers['X-Homecoming-Token'] = token
        connection.request(method, path, body=data, headers=headers)
        response = connection.getresponse()
        return response.status, json.loads(response.read() or b'{}')

    def call(self, method, path, body=None):
        return self.call_raw(method, path, body, self.token)

    def sealed(self, account=ACCOUNT, password=PASSWORD):
        status, answer = self.call('GET', '/api/steam/key')
        self.assertEqual(status, 200)
        result = subprocess.run(['node', str(self.work / 'seal.cjs'), str(NACL / 'nacl.min.js'),
                                 json.dumps([answer['key'], answer['challenge'], account, password])],
                                capture_output=True, text=True, check=True)
        return json.loads(result.stdout)

    def test_1_unpaired_browsers_get_no_key(self):
        self.assertEqual(self.call_raw('GET', '/api/steam/key')[0], 401)
        self.assertEqual(self.call_raw('GET', '/api/steam')[0], 401)

    def test_2_the_sealed_password_arrives_exactly(self):
        status, answer = self.call('POST', '/api/steam/sign-in', self.sealed())
        self.assertEqual((status, answer['state']), (200, 'guard'))
        import base64
        received = json.loads(base64.b64decode(self.next_line('SIGN-IN ')))
        self.assertEqual(received, [ACCOUNT, PASSWORD])
        self.call('POST', '/api/steam/cancel')

    def test_3_replayed_tampered_and_plain_sign_ins_are_refused(self):
        sealed = self.sealed()
        self.assertEqual(self.call('POST', '/api/steam/sign-in', sealed)[0], 200)
        self.call('POST', '/api/steam/cancel')
        status, answer = self.call('POST', '/api/steam/sign-in', sealed)                 # the same message again
        self.assertEqual(status, 400)
        self.assertIn('not for this page', answer['error'])

        tampered = self.sealed()
        box = bytearray(__import__('base64').b64decode(tampered['box']))
        box[20] ^= 1
        tampered['box'] = __import__('base64').b64encode(bytes(box)).decode()
        status, answer = self.call('POST', '/api/steam/sign-in', tampered)
        self.assertEqual(status, 400)
        self.assertIn('did not arrive whole', answer['error'])

        status, _ = self.call('POST', '/api/steam/sign-in', {'account': ACCOUNT, 'password': PASSWORD})
        self.assertEqual(status, 400)                                                  # no plain passwords

    def test_4_a_guard_code_reaches_the_session(self):
        self.call('POST', '/api/steam/sign-in', self.sealed())
        self.next_line('SIGN-IN ')
        status, _ = self.call('POST', '/api/steam/code', {'code': ' ab12c '})
        self.assertEqual(status, 200)
        self.assertEqual(self.next_line('CODE-IN '), 'AB12C')                          # trimmed, upper case
        self.call('POST', '/api/steam/cancel')


if __name__ == '__main__':
    unittest.main()
