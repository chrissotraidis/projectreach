"""Asset-free regressions for the reviewed OpenCE 244/273 adaptation layout."""
import hashlib
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'scripts/xbox'))
import guest_adaptation as guest
from test_xbox_network_policy import LOBBY, engine_tree

border = guest.border_sampling
network = guest.network_bridge


class Guest244Tests(unittest.TestCase):
    def run_c(self, source, expected=0):
        with tempfile.TemporaryDirectory() as tmp:
            executable = pathlib.Path(tmp) / 'regression'
            built = subprocess.run(['clang', '-x', 'c', '-', '-std=c11', '-Wall', '-Werror',
                                    '-fsanitize=address,undefined', '-o', str(executable)],
                                   input=source, text=True, capture_output=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            ran = subprocess.run([str(executable)], capture_output=True)
            self.assertEqual(ran.returncode, expected, ran.stderr.decode())

    def test_counted_visibility_keeps_pending_and_completed_results(self):
        source = r'''
#include <assert.h>
#define HALO_ANDROID 1
typedef unsigned GLuint;
enum { GL_QUERY_RESULT=1, VISIBILITY_ALL_SAMPLES=1000000 };
static struct { unsigned queries[1]; float query_area[1]; } device = {{9}, {4}};
static unsigned raw=3712, ready, known=7, unread=1, reads;
static void glGetQueryObjectuiv(unsigned query, unsigned token, unsigned *out) {
    assert(query==9 && ready && (token==1 || token==0x48504356u)); reads++; *out=raw;
}
static unsigned query(void) {
    unsigned index=0, samples=0;
    if (unread && ready) {
FRAGMENT
        known=samples; unread=0;
    }
    return known;
}
int main(void) {
    if(query()!=7 || reads) return 1;
    ready=1; if(query()!=928 || reads!=1 || unread) return 2;
    ready=0; raw=0; if(query()!=928 || reads!=1) return 3;
    unread=1; if(query()!=928 || reads!=1) return 4;
    ready=1; if(query()!=0 || reads!=2) return 5;
    raw=7; unread=1; if(query()!=2 || reads!=3) return 6;
    return 0;
}
'''
        for renderer in (border.GLES_244_RENDERER_SHA256, border.GLES_273_RENDERER_SHA256):
            with self.subTest(renderer=renderer):
                original, adapted = guest.counting_recipe(renderer)
                self.run_c(source.replace('FRAGMENT', original.decode()), expected=2)
                self.run_c(source.replace('FRAGMENT', adapted.decode()))

    def test_hdr_presentation_cannot_redirect_the_drawable_on_fbo_cache_miss(self):
        source = r'''
typedef unsigned GLuint;
enum { GL_READ_FRAMEBUFFER=1, GL_DRAW_FRAMEBUFFER=2, GL_SCISSOR_TEST=3,
       GL_TRUE=1, GL_COLOR_BUFFER_BIT=4 };
static GLuint read_fb, draw_fb, cached;
static int cleared;
static GLuint framebuffer_get(GLuint texture, GLuint depth) {
    (void)texture; (void)depth;
    if(!cached) { cached=9; read_fb=draw_fb=cached; }
    return cached;
}
static void glBindFramebuffer(unsigned kind, GLuint value) {
    if(kind==GL_READ_FRAMEBUFFER) read_fb=value; else draw_fb=value;
}
static void glDisable(unsigned v) { (void)v; }
static void glColorMask(int a,int b,int c,int d) { (void)a;(void)b;(void)c;(void)d; }
static void glClearColor(float a,float b,float c,float d) { (void)a;(void)b;(void)c;(void)d; }
static void glClear(unsigned v) { (void)v; cleared=(int)draw_fb; }
static int present(int shader) {
    struct { struct { GLuint texture; } target; } buffer={{5}}, *back_buffer=&buffer;
    int window_height=600, height=480, y;
FRAGMENT
    (void)y;
    if(shader) read_fb=17; /* HDR's successful shader needs no blit. */
    else {
READ_BIND
    }
    return draw_fb!=0 || cleared!=0 || (!shader && read_fb!=9);
}
int main(void) {
    for(int warm=0;warm<2;warm++) for(int shader=0;shader<2;shader++) {
        read_fb=draw_fb=42; cached=warm?9:0; cleared=-1;
        if(present(shader)) return 1;
    }
    return 0;
}
'''
        source = source.replace('READ_BIND', guest.PRESENT_READ.decode())
        for renderer in (border.GLES_244_RENDERER_SHA256, border.GLES_273_RENDERER_SHA256):
            with self.subTest(renderer=renderer):
                original, adapted = guest.presentation_recipe(renderer)
                self.run_c(source.replace('FRAGMENT', original.decode()), expected=1)
                self.run_c(source.replace('FRAGMENT', adapted.decode()))

    def test_border_preserves_render_target_flag_and_checks_exact_shader(self):
        for build in (244, 273):
            with self.subTest(build=build):
                renderer = getattr(border, f'GLES_{build}_RENDERER_SHA256')
                edits = border.renderer_edits(renderer)
                source = b'\n'.join(a for a, _ in edits)
                patched = border.apply_edits(source, edits)
                self.assertIn(b'description.hires, target != NULL);', patched)
                self.assertIn(b'hp_border_configure(stage, gl_target, description.levels, description.hires);', patched)
                shader = b'\n'.join(a for a, _ in border.GLES_SHADER_EDITS)
                with patch.object(border, f'GLES_{build}_SHADER_SHA256', hashlib.sha256(shader).hexdigest()):
                    self.assertIn(b'hp_border_sample', border.adapt_shader(shader, renderer))
                    with self.assertRaises(ValueError):
                        border.adapt_shader(shader + b'unreviewed', renderer)
                    for other in (206, 244, 273):
                        if other == build:
                            continue
                        other_renderer = (border.GLES_RENDERER_SHA256 if other == 206 else
                                          getattr(border, f'GLES_{other}_RENDERER_SHA256'))
                        with self.assertRaises(ValueError):
                            border.adapt_shader(shader, other_renderer)

    def test_newer_lobby_count_uses_the_same_policy_and_rejects_unreviewed_sites(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            engine_tree(root, {network.LOBBY: LOBBY + network.LOBBY_NEWER})
            changes = network.changes(root)
            result = next(after for path, _, after in changes if path == root / network.LOBBY)
            self.assertIn(network.LOBBY_NEWER_REPLACE, result)
            self.assertNotIn(network.LOBBY_NEWER, result)
            for changed in (LOBBY + network.LOBBY_NEWER * 2,
                            LOBBY + network.LOBBY_NEWER.replace(b'>', b'>='),
                            LOBBY + network.LOBBY_NEWER + b'\nint extra=HALO_PORT_NETWORK_VERSION;'):
                (root / network.LOBBY).write_bytes(changed)
                with self.assertRaisesRegex(ValueError, 'unreviewed'):
                    network.check_uses(root)
        self.assertNotEqual(network.recipe(), network.recipe(newer=True))
