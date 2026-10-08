"""Compile and execute generated guest wrappers with a deterministic GL backend."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('gl_helpers', ROOT / 'scripts/xbox/gen-host-gl-helpers.py')
helpers = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helpers)

HEADER = 'void host_gl_read_buffer(unsigned int buffer, unsigned int offset, unsigned int size, void *data);\n'
SOURCE = '''#include "host.h"
#include <GLES3/gl32.h>
#include <string.h>
/* glGetBufferSubData is deliberately unavailable; this comment is not a call. */
void host_gl_read_buffer(uint32_t buffer, uint32_t offset, uint32_t size, void *data)
{
    glBindBuffer(GL_COPY_READ_BUFFER, buffer);
    const void *mapping = glMapBufferRange(GL_COPY_READ_BUFFER, offset, size, GL_MAP_READ_BIT);
    if (mapping) { memcpy(data, mapping, size); glUnmapBuffer(GL_COPY_READ_BUFFER); }
    else { memset(data, 0, size); }
    glBindBuffer(GL_COPY_READ_BUFFER, 0);
}
'''


class GLHelperTests(unittest.TestCase):
    def test_generated_new_helper_copies_guest_bytes_and_handles_map_failure(self):
        generated = helpers.generate(SOURCE, HEADER, 'host_gl_read_buffer\n', '')
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'GLES3').mkdir()
            (root / 'GLES3/gl32.h').write_text('''#pragma once
#include <stdint.h>
#define GL_COPY_READ_BUFFER 0x8F36
#define GL_MAP_READ_BIT 1
typedef void (*PFNGLBINDBUFFERPROC)(unsigned int,unsigned int);
typedef void *(*PFNGLMAPBUFFERRANGEPROC)(unsigned int,intptr_t,intptr_t,unsigned int);
typedef unsigned char (*PFNGLUNMAPBUFFERPROC)(unsigned int);
''')
            (root / 'bridge.c').write_text(generated)
            (root / 'test.c').write_text(r'''
#include "xg_host.h"
#include <assert.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <GLES3/gl32.h>
uintptr_t xg_base;
static unsigned char gpu[16] = {1,2,3,4,5,6,7,8};
static unsigned bound, maps, unmaps, failed;
static void bind_buffer(unsigned target, unsigned buffer) {
    assert(target == GL_COPY_READ_BUFFER); bound = buffer;
}
static void *map_buffer(unsigned target, intptr_t offset, intptr_t size, unsigned flags) {
    assert(target == GL_COPY_READ_BUFFER && bound == 7 && flags == GL_MAP_READ_BIT);
    assert(offset == 2 && size == 4); maps++; return failed ? NULL : gpu + offset;
}
static unsigned char unmap_buffer(unsigned target) {
    assert(target == GL_COPY_READ_BUFFER && bound == 7); unmaps++; return 1;
}
void *xg_gl_proc(const char *name) {
    if (!strcmp(name,"glBindBuffer")) return bind_buffer;
    if (!strcmp(name,"glMapBufferRange")) return map_buffer;
    if (!strcmp(name,"glUnmapBuffer")) return unmap_buffer;
    abort();
}
void xg_fatal(const char *format, ...) { (void)format; abort(); }
void xh_host_gl_read_buffer(uint32_t,uint32_t,uint32_t,uint32_t);
int main(void) {
    unsigned char guest[64]; memset(guest,0xa5,sizeof guest); xg_base=(uintptr_t)guest;
    xh_host_gl_read_buffer(7,2,4,20);
    assert(!memcmp(guest+20,gpu+2,4) && guest[19]==0xa5 && guest[24]==0xa5);
    assert(maps==1 && unmaps==1 && bound==0);
    failed=1; xh_host_gl_read_buffer(7,2,4,20);
    assert(!memcmp(guest+20,"\0\0\0\0",4) && guest[19]==0xa5 && guest[24]==0xa5);
    assert(maps==2 && unmaps==1 && bound==0);
    return 0;
}
''')
            subprocess.run(['clang', '-Wall', '-Wextra', '-Werror', '-I', str(root),
                            '-I', str(ROOT / 'port/xbox'), str(root / 'bridge.c'),
                            str(root / 'test.c'), '-o', str(root / 'test')], check=True, capture_output=True)
            subprocess.run([str(root / 'test')], check=True, capture_output=True)

    def test_existing_override_is_retained_and_unrelated_functions_not_exported(self):
        output = helpers.generate(SOURCE, HEADER, 'host_gl_read_buffer\n',
            'void xh_host_gl_read_buffer(uint32_t a, uint32_t b, uint32_t c, uint32_t d) {}')
        self.assertNotIn('xh_host_gl_read_buffer(', output)
        self.assertNotIn('glMapBufferRange', output)

    def test_unsupported_new_abi_requires_explicit_implementation(self):
        for declaration in ('void *host_gl_read_buffer(void);',
                            'void host_gl_read_buffer(struct item *data);',
                            'void host_gl_read_buffer(void **data);',
                            'void host_gl_read_buffer(int count, ...);'):
            with self.subTest(declaration=declaration), self.assertRaises(ValueError):
                helpers.generate(SOURCE, declaration, 'host_gl_read_buffer\n', '')

    def test_unknown_import_or_shared_helper_state_fails_early(self):
        with self.assertRaisesRegex(ValueError, 'no portable implementation'):
            helpers.generate(SOURCE, HEADER, 'host_gl_future\n', '')
        for extra in ('static int counter;', 'extern int counter;', 'host_gl_wait_frame(0);'):
            with self.subTest(extra=extra), self.assertRaisesRegex(ValueError, 'stateful or dependent'):
                helpers.generate(SOURCE.replace('    glBindBuffer(', extra + '\n    glBindBuffer(', 1),
                                 HEADER, 'host_gl_read_buffer\n', '')


if __name__ == '__main__':
    unittest.main()
