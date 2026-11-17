"""The Apple TV's web page (port/xbox/xg_admin.m), compiled for the Mac and
driven over HTTP: pairing, map uploads and what it refuses.

The maps are synthetic: only the header fields the server checks (no game
data). Preferences go to a temporary home (CFFIXED_USER_HOME)."""
import http.client
import json
import os
import pathlib
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
XBOX = ROOT / 'port/xbox'

MAIN = r'''
#import <Foundation/Foundation.h>
#include <signal.h>
#include <stdarg.h>
#include "xg_admin.h"
void xg_log(const char *format, ...)
{
	va_list arguments;
	va_start(arguments, format);
	vfprintf(stderr, format, arguments);
	fputc('\n', stderr);
	va_end(arguments);
}
int main(int argc, char **argv)
{
	@autoreleasepool {
		NSString *root = @(argv[1]);
		setvbuf(stdout, NULL, _IOLBF, 0);
		if (xg_admin_start([root stringByAppendingPathComponent:@"data"], root, atoi(argv[2]),
				^{ printf("READY\n"); },
				^(NSString *code) { printf("CODE %s\n", code ? code.UTF8String : "-"); }))
			return 1;
		/* SIGUSR1: what the app does on returning to the foreground */
		signal(SIGUSR1, SIG_IGN);
		dispatch_source_t reopen = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGUSR1, 0, dispatch_get_main_queue());
		dispatch_source_set_event_handler(reopen, ^{ xg_admin_reopen(); printf("REOPENED\n"); });
		dispatch_resume(reopen);
		printf("LISTENING\n");
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ exit(0); });
		[NSRunLoop.mainRunLoop run];
	}
}
'''


def synthetic_map(build=b'01.10.12.2276', size=0x1000):
    data = bytearray(size)
    data[0:4] = b'daeh'
    data[4:8] = (5).to_bytes(4, 'little')
    data[0x40:0x40 + len(build)] = build
    data[0x7fc:0x800] = b'toof'
    return bytes(data)


def free_port():
    with socket.socket() as probe:
        probe.bind(('127.0.0.1', 0))
        return probe.getsockname()[1]


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun'), 'needs the Mac toolchain')
class AdminPageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory()
        work = pathlib.Path(cls.folder.name)
        (work / 'main.m').write_text(MAIN)
        (work / 'home').mkdir()
        (work / 'root').mkdir()
        shutil.copy(XBOX / 'admin/admin.html', work / 'admin.html')    # the tool's "bundle" is its folder
        built = subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-Wall', '-Werror', '-Wno-unused-function',
                                '-I', str(XBOX), str(work / 'main.m'), str(XBOX / 'xg_admin.m'),
                                '-framework', 'Foundation', '-o', str(work / 'admin-test')],
                               capture_output=True, text=True)
        if built.returncode:
            raise AssertionError(built.stderr)
        cls.port = free_port()
        cls.root = work / 'root'
        cls.server = subprocess.Popen([str(work / 'admin-test'), str(cls.root), str(cls.port)],
                                      stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                                      env=dict(os.environ, CFFIXED_USER_HOME=str(work / 'home')))
        cls.lines = []
        line = cls.server.stdout.readline()
        assert line.strip() == 'LISTENING', line

    @classmethod
    def tearDownClass(cls):
        cls.server.kill()
        cls.server.wait()
        cls.folder.cleanup()

    def call(self, method, path, body=None, token=None, raw=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.port, timeout=10)
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else b'')
        connection.putrequest(method, path)
        connection.putheader('Content-Length', str(len(data)))
        if token:
            connection.putheader('X-Homecoming-Token', token)
        connection.endheaders()
        if data:
            connection.send(data)
        response = connection.getresponse()
        text = response.read()
        try:
            return response.status, json.loads(text or b'{}')
        except ValueError:
            return response.status, text

    def code(self):
        """the newest code the TV would show"""
        while True:
            line = self.server.stdout.readline().strip()
            if line.startswith('CODE ') and line != 'CODE -':
                return line[5:]

    def pair(self):
        self.assertEqual(self.call('POST', '/api/pair/request')[0], 200)
        status, answer = self.call('POST', '/api/pair', {'code': self.code()})
        self.assertEqual(status, 200)
        self.assertRegex(answer['token'], r'^[0-9a-f]{64}$')
        return answer['token']

    def upload(self, token, maps, total=None):
        status, answer = self.call('POST', '/api/import/begin?total=%d' % (total or sum(map(len, maps.values()))),
                                   token=token)
        self.assertEqual(status, 200, answer)
        for name, data in maps.items():
            status, answer2 = self.call('PUT', '/api/import/map?id=%s&name=%s' % (answer['id'], name), raw=data, token=token)
            self.assertEqual(status, 200, answer2)
        return answer['id'], self.call('POST', '/api/import/finish?id=%s' % answer['id'], token=token)

    def test_1_unpaired_requests_are_refused(self):
        self.assertEqual(self.call('GET', '/')[0], 200)                 # the page itself is public
        for method, path in [('GET', '/api/status'), ('POST', '/api/import/begin?total=10')]:
            status, answer = self.call(method, path)
            self.assertEqual(status, 401)
            self.assertTrue(answer['pair'])
        self.assertEqual(self.call('GET', '/api/status', token='ab' * 32)[0], 401)
        self.assertEqual(self.call('GET', '/api/pair')[1], {'paired': 0})

    def test_2_wrong_codes_end_the_code(self):
        self.call('POST', '/api/pair/request')
        right = self.code()
        wrong = '000000' if right != '000000' else '111111'
        for left in (4, 3, 2, 1):
            status, answer = self.call('POST', '/api/pair', {'code': wrong})
            self.assertEqual(status, 403)
            self.assertIn('%d tries left' % left, answer['error'])
        self.assertEqual(self.call('POST', '/api/pair', {'code': wrong})[0], 403)
        self.assertEqual(self.call('POST', '/api/pair', {'code': right})[0], 410)   # ended

    def test_3_maps_install_and_bad_ones_are_refused(self):
        token = self.pair()
        self.assertEqual(self.call('GET', '/api/pair', token=token)[1], {'paired': 1})
        self.assertIn(self.call('POST', '/api/pair', {'code': '123456'})[0], (403, 410))   # that code is spent

        _, (status, answer) = self.upload(token, {'ui.map': synthetic_map(), 'a10.map': synthetic_map()})
        self.assertEqual((status, answer['maps'], answer['build']), (200, 2, '01.10.12.2276'))
        installed = self.root / 'data/maps'
        self.assertEqual(sorted(p.name for p in installed.iterdir()), ['a10.map', 'ui.map'])
        status, answer = self.call('GET', '/api/status', token=token)
        self.assertEqual((answer['installed']['maps'], answer['import']['state']), (['a10', 'ui'], 'done'))

        # a map of another build, a map with no header, no ui.map: refused, the installed maps kept
        for maps in ({'ui.map': synthetic_map(), 'b30.map': synthetic_map(b'01.01.14.2342')},
                     {'ui.map': synthetic_map(), 'b30.map': b'x' * 0x1000},
                     {'b30.map': synthetic_map()}):
            _, (status, answer) = self.upload(token, maps)
            self.assertEqual(status, 422, answer)
            self.assertEqual(sorted(p.name for p in installed.iterdir()), ['a10.map', 'ui.map'])
        self.assertEqual(list((self.root / 'import').iterdir()), [])            # nothing left staged

    def test_4_unsafe_names_and_old_imports_are_refused(self):
        token = self.pair()
        status, answer = self.call('POST', '/api/import/begin?total=8192', token=token)
        first = answer['id']
        self.assertEqual(self.call('PUT', '/api/import/map?id=%s&name=../x.map' % first, raw=b'x', token=token)[0], 400)
        self.assertEqual(self.call('PUT', '/api/import/map?id=%s&name=notes.txt' % first, raw=b'x', token=token)[0], 400)
        self.call('POST', '/api/import/begin?total=8192', token=token)        # a new import replaces it
        self.assertEqual(self.call('PUT', '/api/import/map?id=%s&name=ui.map' % first, raw=synthetic_map(),
                                   token=token)[0], 409)
        self.assertFalse((self.root / 'x.map').exists())

    def test_5_the_page_answers_after_its_socket_is_reopened(self):
        # (tvOS can take a suspended app's listening socket; the app reopens it on
        # returning to the foreground with xg_admin_reopen)
        for _ in range(2):
            self.server.send_signal(__import__('signal').SIGUSR1)
            while self.server.stdout.readline().strip() != 'REOPENED':
                pass
            time.sleep(0.3)
            self.assertEqual(self.call('GET', '/')[0], 200)


if __name__ == '__main__':
    unittest.main()
