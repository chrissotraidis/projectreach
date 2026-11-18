"""A map loaded over the last one must not draw from the last one's buffers (#45)."""
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import guest_adaptation as guest

static_geometry = guest.static_geometry

REV343 = 'fc9deb0b10eaae1d62caedb0710968b4e77e6e16'
REV359 = '1519c65facbb068e44b956da2769198a83a17847'
SECTION = (b'#ifdef HALO_ANDROID\n/* ---------- static geometry', b'/* ---------- vertex data */')

# The renderer's static geometry section against a GL that keeps each buffer's
# bytes. Two matches in a row: map B loads into map A's memory in a later frame.
HARNESS = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
typedef int BOOL;
typedef unsigned long DWORD;
typedef unsigned int GLuint, GLenum;
typedef int GLsizei;
typedef long GLsizeiptr;
#define TRUE 1
#define FALSE 0
#define HALO_ANDROID 1
#define GL_NO_ERROR 0
#define GL_ARRAY_BUFFER 0x8892
#define GL_ELEMENT_ARRAY_BUFFER 0x8893
#define GL_STATIC_DRAW 0x88E4
static int android_geometry_fixes = 1;
static struct { int statistics; } debug_settings;
static unsigned char window[1 << 16];
#define PLATFORM_PHYSICAL_TO_VIRTUAL(p) ((void *)(window + (unsigned long)(p)))
static struct { unsigned char *bytes; unsigned long size; } gl[64];
static GLuint next_name = 1, bound;
static void glGenBuffers(GLsizei n, GLuint *names) { while (n--) *names++ = next_name++; }
static void glDeleteBuffers(GLsizei n, const GLuint *names)
{ while (n--) { free(gl[*names].bytes); gl[*names].bytes = 0; names++; } }
static void glBufferData(GLenum target, GLsizeiptr size, const void *data, GLenum usage)
{
	(void)target; (void)usage;
	free(gl[bound].bytes);
	gl[bound].bytes = malloc((size_t)size);
	memcpy(gl[bound].bytes, data, (size_t)size);
	gl[bound].size = (unsigned long)size;
}
static GLenum glGetError(void) { return GL_NO_ERROR; }
static void state_array_buffer(GLuint buffer) { bound = buffer; }
static void state_element_array_buffer(GLuint buffer) { bound = buffer; }
static void xgpu_gl_state_invalidate(void) {}
static void platform_log(const char *format, ...) { (void)format; }
void xgpu_static_range_add(const void *start, unsigned long size, int indices);
#include "static_geometry.inc"
#ifdef UNFIXED
static void static_buffers_verify(unsigned long frame) { (void)frame; }
#endif

static void load(unsigned char seed)
{
	unsigned long index;
	for (index = 0x1000; index < 0x5000; index++)
		window[index] = (unsigned char)(seed + index * 7);
}

/* a draw reads the cache's buffer, or streams the memory itself */
static void draw(unsigned long offset, unsigned long size)
{
	GLuint buffer;
	unsigned long at, serial;
	if (!static_buffer_range((unsigned long)window + offset, size, FALSE, &buffer, &at, &serial))
		return;
	if (memcmp(gl[buffer].bytes + at, window + offset, size))
	{
		fprintf(stderr, "the draw at %#lx read the last map's geometry\n", offset);
		exit(1);
	}
}

int main(void)
{
	/* map A: its bsp's vertices, and its lightmap vertices to the same end */
	static_buffers_verify(1);
	load(1);
	xgpu_static_range_add(window + 0x1000, 0x4000, 0);
	xgpu_static_range_add(window + 0x3000, 0x2000, 0);
	draw(0x1000, 0x4000);
	/* the next match: map B in the same memory, its bsp starting higher */
	static_buffers_verify(2);
	load(9);
	xgpu_static_range_add(window + 0x1800, 0x3800, 0);
	draw(0x1800, 0x3800);
	draw(0x2000, 0x100);
	return 0;
}
'''


def exact_renderer(test):
    checkout = pathlib.Path(os.environ.get('HALOPAD_TEST_ENGINE', guest.ENGINE_CHECKOUT))
    shown = subprocess.run(['git', '-C', str(checkout), 'show', f'{REV359}:{guest.RENDERER}'], capture_output=True)
    if shown.returncode:
        test.skipTest('exact OpenCE359 source unavailable; set HALOPAD_TEST_ENGINE')
    return shown.stdout


def run_harness(renderer, *defines):
    start = renderer.index(SECTION[0])
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        (work / 'static_geometry.inc').write_bytes(renderer[start:renderer.index(SECTION[1], start)])
        (work / 'harness.c').write_text(HARNESS)
        compiled = subprocess.run(['clang', '-std=gnu89', '-w', '-fsanitize=address,undefined', *defines,
                                   '-I', tmp, str(work / 'harness.c'), '-o', str(work / 'harness')],
                                  capture_output=True, text=True)
        if compiled.returncode:
            raise AssertionError(compiled.stderr)
        return subprocess.run([str(work / 'harness')], capture_output=True, text=True)


class StaticGeometryTests(unittest.TestCase):
    def test_only_build359s_network_recipe_takes_the_fix(self):
        with patch.dict(os.environ, {'HALOPAD_XBOX_LATEST': '0'}), \
             patch.object(static_geometry, 'recipe', return_value=b'') as recipe:
            guest.identity('network-policy-v1', REV343)
            guest.identity('render-camera-v1', REV359)
            recipe.assert_not_called()
            guest.identity('network-policy-v1', REV359)
            recipe.assert_called_once()

    def test_a_changed_renderer_stops_the_build(self):
        before, _ = static_geometry.edits()[0]
        with self.assertRaisesRegex(ValueError, 'review upstream'):
            static_geometry.adapt(b'/* no static geometry here */\n')
        with self.assertRaisesRegex(ValueError, 'review upstream'):
            static_geometry.adapt(before + before)

    def test_the_next_map_never_draws_the_last_ones_geometry(self):
        original = exact_renderer(self)
        with patch.dict(os.environ, {'XBOX_REV': REV359, 'HALOPAD_XBOX_LATEST': '0'}):
            adapted = guest.adapted_source(original, 'network-policy-v1')
        fixed = run_harness(adapted)
        self.assertEqual(fixed.returncode, 0, fixed.stderr)
        unfixed = run_harness(original, '-DUNFIXED')
        self.assertNotEqual(unfixed.returncode, 0)
        self.assertIn("last map's geometry", unfixed.stderr)


if __name__ == '__main__':
    unittest.main()

