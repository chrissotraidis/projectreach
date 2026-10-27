"""Exercise the production guest HTTPS bridge against bounded local servers."""
import http.server
import json
import pathlib
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class Handler(http.server.BaseHTTPRequestHandler):
    targets = 0

    def log_message(self, *_args):
        pass

    def do_GET(self):
        if self.path == '/target':
            type(self).targets += 1
        status = {'/redirect': 302, '/error': 503, '/empty': 204}.get(self.path, 200)
        self.send_response(status)
        self.send_header('Signature', 'signed-by-master')
        self.send_header('Signature-Key', 'test-key')
        if self.path == '/redirect':
            self.send_header('Location', '/target')
        if self.path == '/headers':
            self.send_header('X-Large', 'x' * 2000)
        body = b'' if self.path == '/empty' else b'{"ok":true}'
        if self.path == '/chunked':
            self.send_header('Transfer-Encoding', 'chunked')
        else:
            self.send_header('Content-Length', '100' if self.path == '/truncated' else str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(b'b\r\n' + body + b'\r\n0\r\n\r\n' if self.path == '/chunked' else body)
        except (BrokenPipeError, ConnectionResetError):
            pass
        self.close_connection = True


@unittest.skipUnless(sys.platform == 'darwin', 'Apple Foundation HTTPS bridge')
class HTTPSBridgeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.folder = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.folder.cleanup)
        path = pathlib.Path(cls.folder.name)
        cls.binary = path / 'https-bridge'
        harness = path / 'bridge.m'
        harness.write_text(r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "xg_https.m"
uintptr_t xg_base;
static unsigned char memory[65536];
int main(int argc, const char **argv) {
    @autoreleasepool {
        assert(argc == 5);
        memset(memory, 0xa5, sizeof(memory));
        xg_base = (uintptr_t)memory;
        snprintf((char *)memory + 64, 2048, "%s", argv[1]);
        int capacity = atoi(argv[2]), header_capacity = atoi(argv[3]), mode = atoi(argv[4]);
        assert(capacity >= -1 && capacity <= 128 && header_capacity > 0 && header_capacity <= 4096);
        uint32_t status = mode == 1 ? 0 : 4096, size = mode == 2 ? 0 : 4100;
        uint32_t body = capacity == 0 || mode == 3 ? 0 : 16384;
        uint32_t headers = mode == 4 ? UINT32_MAX - 3 : 8192;
        int error_size = mode == 5 ? 4 : 256;
        if (mode == 6) memory[64] = 0xff;
        int result = xh_host_https_get(mode == 7 ? 0 : 64, status, headers, header_capacity,
            body, capacity, size, 32768, error_size);
        int got_status = status ? *(int *)(memory + status) : 0;
        int got_size = size ? *(int *)(memory + size) : 0;
        assert(got_size >= 0 && got_size <= MAX(capacity, 0));
        assert(memory[16383] == 0xa5 && memory[16384 + MAX(capacity, 0)] == 0xa5);
        assert(memory[8191] == 0xa5 && memory[8192 + header_capacity] == 0xa5);
        assert(memory[32767] == 0xa5 && memory[32768 + error_size] == 0xa5);
        NSString *head = mode == 4 ? @"" : [NSString stringWithUTF8String:(char *)memory + 8192];
        NSString *error = [NSString stringWithUTF8String:(char *)memory + 32768];
        assert(head && error);
        NSData *data = [NSData dataWithBytes:memory + 16384 length:(NSUInteger)got_size];
        NSDictionary *answer = @{@"ok": @(result), @"status": @(got_status), @"size": @(got_size),
            @"headers": head, @"error": error, @"body": [data base64EncodedStringWithOptions:0],
            @"body_untouched": @(memory[16384] == 0xa5)};
        NSData *encoded = [NSJSONSerialization dataWithJSONObject:answer options:0 error:nil];
        fwrite(encoded.bytes, 1, encoded.length, stdout);
    }
    return 0;
}
''')
        compiled = subprocess.run(['clang', '-fobjc-arc', '-Wall', '-Wextra', '-Werror',
                                   '-Wno-unused-parameter', '-fsanitize=address,undefined',
                                   '-I', str(ROOT / 'port/xbox'), str(harness),
                                   '-framework', 'Foundation', '-o', str(cls.binary)],
                                  text=True, capture_output=True)
        if compiled.returncode:
            raise AssertionError(compiled.stderr)
        cls.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        cls.addClassCleanup(cls.server.server_close)
        cls.addClassCleanup(cls.server.shutdown)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base = f'http://127.0.0.1:{cls.server.server_port}'

    def request(self, path='/', capacity=128, headers=4096, mode=0):
        url = path if '://' in path else self.base + path
        result = subprocess.run([str(self.binary), url, str(capacity), str(headers), str(mode)],
                                capture_output=True, text=True, timeout=35)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def failed(self, answer):
        self.assertEqual(answer['ok'], 0)
        self.assertEqual(answer['status'], 0)
        self.assertEqual(answer['size'], 0)
        self.assertTrue(answer['error'])
        self.assertTrue(answer['body_untouched'])

    def test_response_status_signed_headers_and_exact_capacity(self):
        for route, status in [('/', 200), ('/error', 503), ('/chunked', 200)]:
            with self.subTest(route=route):
                answer = self.request(route, capacity=11)
                self.assertEqual((answer['ok'], answer['status'], answer['size']), (1, status, 11))
                self.assertEqual(answer['body'], 'eyJvayI6dHJ1ZX0=')
                self.assertIn('signature: signed-by-master\n', answer['headers'].lower())
                self.assertIn('signature-key: test-key\n', answer['headers'].lower())
                self.assertEqual(answer['error'], '')

    def test_redirect_is_returned_without_following_it(self):
        before = Handler.targets
        answer = self.request('/redirect')
        self.assertEqual((answer['ok'], answer['status']), (1, 302))
        self.assertEqual(Handler.targets, before)

    def test_rejects_large_truncated_and_unrepresentable_responses(self):
        self.failed(self.request('/', capacity=10))
        self.failed(self.request('/chunked', capacity=10))
        self.failed(self.request('/truncated'))
        self.failed(self.request('/headers', headers=256))

    def test_empty_body_with_no_guest_body_buffer(self):
        answer = self.request('/empty', capacity=0)
        self.assertEqual((answer['ok'], answer['status'], answer['size']), (1, 204, 0))

    def test_invalid_buffers_urls_and_bounded_error_text(self):
        for mode in (1, 2, 3, 4, 6, 7):
            with self.subTest(mode=mode):
                self.failed(self.request(mode=mode))
        self.failed(self.request(capacity=-1))
        for url in ('http://example.invalid', 'http://127.0.0.1.example.invalid',
                    'file:///etc/hosts', 'https://user:password@example.invalid',
                    'https://example.invalid/#fragment'):
            with self.subTest(url=url):
                self.failed(self.request(url))
        answer = self.request('file:///etc/hosts', mode=5)
        self.failed(answer)
        self.assertEqual(len(answer['error']), 3)

    @unittest.skipUnless(shutil.which('openssl'), 'OpenSSL creates the untrusted local test certificate')
    def test_untrusted_tls_certificate_fails(self):
        path = pathlib.Path(self.folder.name)
        key, cert = path / 'key.pem', path / 'cert.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
                        '-subj', '/CN=127.0.0.1', '-keyout', str(key), '-out', str(cert)],
                       check=True, capture_output=True)
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            answer = self.request(f'https://127.0.0.1:{server.server_port}/')
            self.failed(answer)
        finally:
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    unittest.main()
