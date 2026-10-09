"""Asset-free checks for the small private guest adaptation boundary."""
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import guest_adaptation as adapter


class GuestAdaptationTests(unittest.TestCase):
    def test_water_unique_anchors_and_separate_identity(self):
        base = adapter.ANCHOR + adapter.FILTER_ANCHOR + adapter.COUNT_ANCHOR + adapter.ATOMIC_ANCHOR
        for save, restore in ((0,1),(2,1),(1,0),(1,2),(1,1)):
            original = base + adapter.WATER_SAVE_ANCHOR * save + adapter.WATER_RESTORE_ANCHOR * restore
            with patch.object(adapter, 'SOURCE_SHA256', hashlib.sha256(original).hexdigest()):
                if (save,restore) != (1,1):
                    with self.assertRaisesRegex(ValueError, 'water input changed'):
                        adapter.adapted_source(original, 'render-water-v1')
                else:
                    modified = adapter.adapted_source(original, 'render-water-v1')
                    for fragment in (adapter.WATER_SAVE, adapter.WATER_RESTORE, adapter.COUNT_INSERT, adapter.FILTER_INSERT):
                        self.assertIn(fragment, modified)
                    self.assertNotIn(adapter.WATER_RESTORE_ANCHOR, modified)
                    self.assertNotIn(adapter.WATER_SAVE, adapter.adapted_source(original, 'render-visibility-v1'))
        self.assertNotEqual(adapter.identity('render-water-v1'), adapter.identity('render-visibility-v1'))

    def test_water_copy_restores_current_draw_state(self):
        source = r'''
#include <assert.h>
typedef int GLint;
typedef unsigned GLuint;
enum { GL_READ_FRAMEBUFFER_BINDING, GL_DRAW_FRAMEBUFFER_BINDING,
       GL_SCISSOR_TEST, GL_READ_FRAMEBUFFER, GL_DRAW_FRAMEBUFFER };
static GLint read_fb, draw_fb, scissor;
static void glGetIntegerv(unsigned key, GLint *out) {
    if (key == GL_READ_FRAMEBUFFER_BINDING) *out = read_fb;
    else if (key == GL_DRAW_FRAMEBUFFER_BINDING) *out = draw_fb;
    else { assert(key == GL_SCISSOR_TEST); *out = scissor; }
}
static void glBindFramebuffer(unsigned key, GLuint fb) {
    if (key == GL_READ_FRAMEBUFFER) read_fb = (GLint)fb;
    else { assert(key == GL_DRAW_FRAMEBUFFER); draw_fb = (GLint)fb; }
}
static void glEnable(unsigned key) { assert(key == GL_SCISSOR_TEST); scissor = 1; }
static void glDisable(unsigned key) { assert(key == GL_SCISSOR_TEST); scissor = 0; }
static void copy(void) {
''' + adapter.WATER_SAVE.decode() + r'''
    read_fb = 77; draw_fb = 88; scissor = 0;
''' + adapter.WATER_RESTORE.decode() + r'''
}
int main(void) {
    for (int enabled = 0; enabled <= 1; enabled++) {
        for (int same = 0; same <= 1; same++) {
            read_fb = same ? 42 : 41; draw_fb = 42; scissor = enabled;
            for (int level = 0; level < 4; level++) {
                copy();
                assert(read_fb == (same ? 42 : 41));
                assert(draw_fb == 42 && scissor == enabled);
            }
        }
    }
    return 0;
}
'''
        binary = self.root / 'water-state'
        result = subprocess.run(['clang','-x','c','-','-std=c11','-Wall','-Werror',
                                 '-fsanitize=address,undefined','-o',str(binary)],
                                input=source, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        subprocess.run([str(binary)], check=True, capture_output=True)

    def test_visibility_requires_unique_query_and_capability_anchors(self):
        for count, atomic in ((0, 1), (2, 1), (1, 0), (1, 2)):
            original = (adapter.ANCHOR + adapter.FILTER_ANCHOR +
                        adapter.COUNT_ANCHOR * count + adapter.ATOMIC_ANCHOR * atomic)
            with patch.object(adapter, 'SOURCE_SHA256', hashlib.sha256(original).hexdigest()):
                with self.assertRaisesRegex(ValueError, 'visibility input changed'):
                    adapter.adapted_source(original, 'render-visibility-v1')

    def test_visibility_recipe_and_normalization(self):
        original = adapter.ANCHOR + adapter.FILTER_ANCHOR + adapter.COUNT_ANCHOR + adapter.ATOMIC_ANCHOR
        with patch.object(adapter, 'SOURCE_SHA256', hashlib.sha256(original).hexdigest()):
            modified = adapter.adapted_source(original, 'render-visibility-v1')
        self.assertIn(adapter.COUNT_INSERT, modified)
        self.assertIn(adapter.ATOMIC_REPLACE, modified)
        self.assertNotEqual(adapter.identity('render-visibility-v1'), adapter.identity('render-quality-v1'))
        binary = self.root / 'normalize'
        source = r'''
#include <assert.h>
#include <stdint.h>
typedef unsigned GLuint;
#define HALO_ANDROID 1
#define S_OK 0
static struct { unsigned queries[1]; float query_area[1]; } device;
static unsigned raw;
static void glGetQueryObjectuiv(unsigned id, unsigned token, unsigned *out) {
    assert(id == 9 && token == 0x48504356u); *out = raw;
}
static int query(unsigned *result) {
    unsigned index = 0, samples = 0;
''' + adapter.COUNT_INSERT.decode() + r'''
}
int main(void) {
    device.queries[0] = 9;
    unsigned result;
    for (unsigned scale = 1; scale <= 2; scale++) {
        device.query_area[0] = scale * scale;
        raw = 928 * scale * scale; assert(query(&result) == S_OK && result == 928);
        raw = 2401 * scale * scale; assert(query(&result) == S_OK && result == 2401);
        raw = 0; assert(query(&result) == S_OK && !result);
    }
    raw = 7; device.query_area[0] = 4; assert(query(&result) == S_OK && result == 2);
    assert(query(0) == S_OK);
}
'''
        result = subprocess.run(['clang', '-x', 'c', '-', '-std=c11', '-Wall', '-Werror',
                                 '-fsanitize=address,undefined', '-o', str(binary)],
                                input=source, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        subprocess.run([str(binary)], check=True, capture_output=True)

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.source = self.root / adapter.RENDERER
        self.source.parent.mkdir(parents=True)
        self.original = b'/* synthetic fixture */\n' + adapter.ANCHOR
        self.source.write_bytes(self.original)
        self.addCleanup(patch.stopall)
        # Synthetic bytes use the fallback digest, not the current accepted pin.
        patch.dict('os.environ', {'XBOX_REV': 'synthetic-fixture'}).start()
        patch.object(adapter, 'SOURCE_SHA256', hashlib.sha256(self.original).hexdigest()).start()
        self.identity = adapter.identity('render-scale-v1')

    def test_restore_after_success_and_force_next_rebuild(self):
        before = self.source.stat().st_mtime_ns
        with adapter.renderer_adaptation(self.root, self.identity):
            self.assertIn(adapter.INSERT, self.source.read_bytes())
        self.assertEqual(self.source.read_bytes(), self.original)
        self.assertGreater(self.source.stat().st_mtime_ns, before)

    def test_restore_after_build_failure_and_interrupt(self):
        for exception in (subprocess.CalledProcessError(1, 'ninja'), KeyboardInterrupt()):
            with self.assertRaises(type(exception)):
                with adapter.renderer_adaptation(self.root, self.identity):
                    raise exception
            self.assertEqual(self.source.read_bytes(), self.original)

    def test_preserve_concurrent_edits(self):
        with self.assertRaisesRegex(RuntimeError, 'preserving'):
            with adapter.renderer_adaptation(self.root, self.identity):
                self.source.write_bytes(b'unrelated new edit')
        self.assertEqual(self.source.read_bytes(), b'unrelated new edit')

    def test_changed_upstream_refuses_without_mutation(self):
        changed = self.original + b'new upstream changes'
        self.source.write_bytes(changed)
        with self.assertRaisesRegex(ValueError, 'input changed'):
            with adapter.renderer_adaptation(self.root, self.identity):
                self.fail('must not run build')
        self.assertEqual(self.source.read_bytes(), changed)

    def test_missing_or_ambiguous_anchor_refuses_even_with_valid_hash(self):
        for original in (b'no anchor', adapter.ANCHOR * 2):
            with patch.object(adapter, 'SOURCE_SHA256', hashlib.sha256(original).hexdigest()):
                with self.assertRaisesRegex(ValueError, 'input changed'):
                    adapter.adapted_source(original)

    def test_default_does_not_write_renderer(self):
        before = self.source.stat().st_mtime_ns
        with adapter.renderer_adaptation(self.root, adapter.identity('none')):
            self.assertEqual(self.source.read_bytes(), self.original)
        self.assertEqual(self.source.stat().st_mtime_ns, before)

    def test_unknown_option_refuses(self):
        with self.assertRaisesRegex(ValueError, 'Unknown'):
            adapter.identity('render-scale-v2')

    def test_quality_recipe_has_separate_identity_and_checks_both_anchors(self):
        self.assertNotEqual(adapter.identity('render-scale-v1'), adapter.identity('render-quality-v1'))
        for suffix in (b'', adapter.FILTER_ANCHOR * 2):
            original = self.original + suffix
            with patch.object(adapter, 'SOURCE_SHA256', hashlib.sha256(original).hexdigest()):
                with self.assertRaisesRegex(ValueError, 'filtering input changed'):
                    adapter.adapted_source(original, 'render-quality-v1')
        original = self.original + adapter.FILTER_ANCHOR
        with patch.object(adapter, 'SOURCE_SHA256', hashlib.sha256(original).hexdigest()):
            modified = adapter.adapted_source(original, 'render-quality-v1')
        self.assertIn(adapter.INSERT, modified)
        self.assertIn(adapter.FILTER_INSERT, modified)

    def test_filter_fragment_exclusions_cap_and_explicit_game_request(self):
        # Compile the exact original fragment inserted by the adapter, with
        # inert GL boundaries. Each process gets fresh one-time configuration.
        source = '''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
typedef int GLint;
#define D3DTEXF_POINT 1
#define D3DTEXF_ANISOTROPIC 3
#define D3DTEXF_NONE 0
#define D3DTSS_MAXANISOTROPY 0
#define GL_TEXTURE_MAX_ANISOTROPY_EXT 0x84fe
static int maximum, queries, calls;
static float observed;
static void glGetIntegerv(int name, int *value) { assert(name == 0x84ff); queries++; *value = maximum; }
static void glSamplerParameterf(int sampler, int name, float value) { assert(sampler == 7 && name == 0x84fe); calls++; observed = value; }
static void platform_log(const char *format, ...) { (void)format; }
int main(int argc, char **argv) {
    assert(argc == 11);
    setenv("HALO_TEST_ANISOTROPY", argv[1], 1);
    maximum = atoi(argv[2]);
    struct { int anisotropy; } xgpu_capabilities = {atoi(argv[3])};
    int hires=atoi(argv[4]), mipmapped=atoi(argv[5]), min_filter=atoi(argv[6]);
    int mip_filter=atoi(argv[7]), state[1]={atoi(argv[8])}, sampler=7;
''' + adapter.FILTER_INSERT.decode() + '''
    assert(calls == (atoi(argv[9]) > 0));
    assert(observed == atoi(argv[9]));
    assert(queries == atoi(argv[10]));
    return 0;
}
'''
        executable = self.root / 'filter-test'
        subprocess.run(['clang', '-x', 'c', '-Wall', '-Wextra', '-Werror', '-o', str(executable), '-'],
                       input=source, text=True, capture_output=True, check=True)
        # request, cap, extension, hires, mipmapped, min, mip, game's AF, applied, queries
        cases = [('4',16,1,0,1,2,2,1,4,1), ('16',8,1,0,1,2,2,1,8,1),
                 ('16',0,1,0,1,2,2,1,0,1), ('1',16,1,0,1,2,2,1,0,1),
                 ('invalid',16,1,0,1,2,2,1,0,1), ('4x',16,1,0,1,2,2,1,0,1),
                 ('16',16,0,0,1,2,2,1,0,0), ('16',16,1,1,1,2,2,1,0,0),
                 ('16',16,1,0,0,2,2,1,0,0), ('16',16,1,0,1,1,2,1,0,0),
                 ('16',16,1,0,1,2,0,1,0,0), ('4',16,1,0,1,3,2,16,0,1),
                 ('16',16,1,0,1,3,2,4,16,1)]
        for case in cases:
            with self.subTest(case=case):
                subprocess.run([str(executable), *map(str, case)], check=True)

    def test_failed_build_does_not_publish_new_identity(self):
        out = self.root / 'out'
        out.mkdir()
        manifest = out / 'guest-adaptation.json'
        manifest.write_text(json.dumps({'name': 'previous'}))
        with patch.dict('os.environ', {'HALOPAD_XBOX_GUEST_ADAPTATION': 'render-scale-v1'}), \
             patch.object(adapter.subprocess, 'check_output', return_value=''), \
             patch.object(adapter.subprocess, 'run', side_effect=[None, subprocess.CalledProcessError(1, 'ninja')]):
            with self.assertRaises(subprocess.CalledProcessError):
                adapter.build(self.root, 'ndk', 'compiler', out)
        self.assertEqual(self.source.read_bytes(), self.original)
        self.assertEqual(json.loads(manifest.read_text()), {'name': 'previous'})

    def test_cached_sampler_patch_has_distinct_identity_and_unique_anchor(self):
        original = self.original + adapter.CACHED_FILTER_ANCHOR + adapter.FILTER_ANCHOR
        digest = hashlib.sha256(original).hexdigest()
        legacy = adapter.identity('render-quality-v1')['recipe_sha256']
        with patch.object(adapter, 'SOURCE_SHA256', digest), \
                patch.object(adapter, 'CACHED_FILTER_RENDERERS', {digest}):
            self.assertNotEqual(adapter.identity('render-quality-v1')['recipe_sha256'], legacy)
            modified = adapter.adapted_source(original, 'render-quality-v1')
            self.assertIn(adapter.CACHED_FILTER_ANCHOR + adapter.CACHED_FILTER_INSERT, modified)
            self.assertNotIn(adapter.FILTER_INSERT, modified)
            for count in (0, 2):
                changed = self.original + adapter.CACHED_FILTER_ANCHOR * count
                changed_hash = hashlib.sha256(changed).hexdigest()
                with patch.object(adapter, 'SOURCE_SHA256', changed_hash), \
                        patch.object(adapter, 'CACHED_FILTER_RENDERERS', {changed_hash}):
                    with self.assertRaisesRegex(ValueError, 'filtering input changed'):
                        adapter.adapted_source(changed, 'render-quality-v1')

    def test_cached_filter_preserves_exclusions_and_stable_sampler_keys(self):
        source = '''
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#define HALO_ANDROID 1
typedef unsigned DWORD;
typedef int GLint;
enum { D3DTEXF_NONE=0, D3DTEXF_POINT=1, D3DTEXF_ANISOTROPIC=3 };
static int maximum;
static struct { int anisotropy; } xgpu_capabilities;
static void glGetIntegerv(int name, int *out) { assert(name == 0x84ff); *out=maximum; }
static void platform_log(const char *format, ...) { (void)format; }
static void configure(DWORD *inputs, int hires, int mipmapped) {
''' + adapter.CACHED_FILTER_INSERT.decode() + '''
}
int main(int argc, char **argv) {
    assert(argc == 10);
    setenv("HALO_TEST_ANISOTROPY", argv[1], 1);
    maximum=atoi(argv[2]); xgpu_capabilities.anisotropy=atoi(argv[3]);
    int hires=atoi(argv[4]), mipmapped=atoi(argv[5]);
    DWORD inputs[11]={0}, original[11], cached[11];
    for (int i=0; i<11; ++i) inputs[i]=100+i;
    inputs[0]=atoi(argv[6]); inputs[1]=atoi(argv[7]); inputs[8]=atoi(argv[8]);
    memcpy(original, inputs, sizeof(inputs));
    configure(inputs, hires, mipmapped);
    int applied=atoi(argv[9]);
    assert(inputs[0] == (applied ? D3DTEXF_ANISOTROPIC : original[0]));
    assert(inputs[8] == (applied ? (DWORD)applied : original[8]));
    for (int i=0; i<11; ++i) if (i!=0 && i!=8) assert(inputs[i]==original[i]);
    memcpy(cached, inputs, sizeof(inputs));
    memcpy(inputs, original, sizeof(inputs));
    configure(inputs, hires, mipmapped);
    assert(!memcmp(cached, inputs, sizeof(inputs)));
    return 0;
}
'''
        executable = self.root / 'cached-filter-test'
        compiled = subprocess.run(['clang', '-x', 'c', '-Wall', '-Wextra', '-Werror',
                                   '-fsanitize=address,undefined', '-o', str(executable), '-'],
                                  input=source, text=True, capture_output=True)
        self.assertEqual(compiled.returncode, 0, compiled.stderr)
        # Request, GPU cap/support, HUD, mipmapped, min/mip filters, game AF, override.
        cases = [('4',16,1,0,1,2,2,1,4), ('16',8,1,0,1,2,2,1,8),
                 ('16',0,1,0,1,2,2,1,0), ('1',16,1,0,1,2,2,1,0),
                 ('bad',16,1,0,1,2,2,1,0), ('16',16,0,0,1,2,2,1,0),
                 ('16',16,1,1,1,2,2,1,0), ('16',16,1,0,0,2,2,1,0),
                 ('16',16,1,0,1,1,2,1,0), ('16',16,1,0,1,2,0,1,0),
                 ('4',16,1,0,1,3,2,16,0), ('16',16,1,0,1,3,2,4,16)]
        for case in cases:
            with self.subTest(case=case):
                subprocess.run([str(executable), *map(str, case)], check=True)


class SaveIdentityTests(unittest.TestCase):
    def test_exact_guest_and_legacy_transition(self):
        with tempfile.TemporaryDirectory() as folder:
            executable = pathlib.Path(folder) / 'save-identity'
            subprocess.run(['xcrun', 'clang', '-x', 'objective-c', '-fobjc-arc',
                            '-framework', 'Foundation', '-I', str(ROOT / 'port/ios'),
                            '-o', str(executable), '-'], input='''
#import "HaloPadXboxSaveIdentity.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSString *a = [@"a" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
    NSString *b = [@"b" stringByPaddingToLength:64 withString:@"b" startingAtIndex:0];
    NSString *old = HPXboxSaveIdentity(@{@"revision": @"same-pin", @"guest_sha256": a});
    assert([old isEqualToString:HPXboxSaveIdentity(@{@"revision": @"same-pin", @"guest_sha256": a})]);
    assert(![old isEqualToString:HPXboxSaveIdentity(@{@"revision": @"same-pin", @"guest_sha256": b})]);
    assert(![old isEqualToString:HPXboxSaveIdentity(@{@"revision": @"new-pin", @"guest_sha256": a})]);
    assert(![old isEqualToString:@"same-pin"]); // Legacy markers trigger one backup.
    assert(HPXboxSaveIdentity(@{}) == nil);
    assert(HPXboxSaveIdentity(@{@"revision": @1, @"guest_sha256": a}) == nil);
    assert(HPXboxSaveIdentity(@{@"revision": @"same-pin", @"guest_sha256": @"bad"}) == nil);
} return 0; }
''', text=True, check=True, capture_output=True)
            subprocess.run([str(executable)], check=True)


if __name__ == '__main__':
    unittest.main()
