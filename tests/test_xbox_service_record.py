"""Asset-free capability/focus checks; optional exact-source rollback integration.

HALOPAD_SERVICE_RECORD_ENGINE may point at an existing clean OpenCE337 checkout.
The integration test reads it and adapts temporary copies of source files only.
It never fetches, configures, builds or changes that checkout.
"""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts/xbox'))
import guest_adaptation as guest


def production_function(source, name):
    match = re.search(r'^(?:static )?[^\n;{}]*\b' + re.escape(name) +
                      r'\([^;{}]*\)\s*\{', source, re.M)
    if not match:
        raise AssertionError('missing production function ' + name)
    end = source.index('{', match.start()) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[match.start():end]


class ServiceRecordTests(unittest.TestCase):
    def setUp(self):
        self.env = patch.dict(os.environ, {}, clear=True)
        self.env.start()
        self.addCleanup(self.env.stop)

    def test_default_recipe_and_pin_remain_unchanged(self):
        self.assertEqual(guest.identity('none'), {'name': 'none'})
        self.assertIsNone(guest.service_record.identity('any-revision'))

    def test_opt_in_requires_exact_explicit_revision_and_boolean_flag(self):
        os.environ['HALOPAD_SERVICE_RECORD'] = '1'
        for revision in (None, '', 'latest', 'a' * 40):
            with self.assertRaisesRegex(ValueError, 'requires explicit XBOX_REV='):
                guest.service_record.identity(revision)
        os.environ['XBOX_REV'] = guest.service_record.REVISION
        identity = guest.identity('none')
        self.assertEqual(identity['service_record']['event_size'], 320)
        self.assertEqual(identity['service_record']['event_version'], 1)
        self.assertEqual(identity['service_record']['upstream_revision'], os.environ['XBOX_REV'])
        self.assertEqual(len(identity['service_record']['recipe_sha256']), 64)
        os.environ['HALOPAD_SERVICE_RECORD'] = 'yes'
        with self.assertRaisesRegex(ValueError, 'must be 0 or 1'):
            guest.identity('none')

    def test_sdl_proof_rejects_service_record_before_build_preparation(self):
        os.environ['HALOPAD_SERVICE_RECORD'] = '1'
        ran = subprocess.run(['/bin/sh', str(ROOT / 'scripts/xbox/build-mac.sh')],
                             env=os.environ, capture_output=True, text=True)
        self.assertEqual(ran.returncode, 2)
        self.assertIn('UIKit host', ran.stderr)
        self.assertIn('build-ios.sh --mac', ran.stderr)

    def test_focus_delivers_initial_state_and_retains_rapid_loss_regain(self):
        source = r'''
#include <assert.h>
#include "xg_focus_input.h"
int main(void) {
    struct xg_focus_input focus = XG_FOCUS_INPUT_INITIALIZER;
    int active = -1;
    xg_focus_set(&focus, 1);
    xg_focus_created(&focus);
    assert(xg_focus_next(&focus, &active) && active == 1);
    assert(!xg_focus_next(&focus, &active));
    xg_focus_set(&focus, 0);  /* native modal or UIKit resignation */
    xg_focus_set(&focus, 1);  /* resumed before guest polls */
    assert(xg_focus_next(&focus, &active) && active == 0);
    assert(xg_focus_next(&focus, &active) && active == 1);
    assert(!xg_focus_next(&focus, &active));
    xg_focus_set(&focus, 0);
    xg_focus_set(&focus, 0);
    assert(xg_focus_next(&focus, &active) && active == 0);
    assert(!xg_focus_next(&focus, &active));
    xg_focus_created(&focus); /* a recreated inactive window still gets state */
    assert(xg_focus_next(&focus, &active) && active == 0);
    xg_focus_set(&focus, 1);
    assert(xg_focus_next(&focus, &active) && active == 1);
    return 0;
}
'''
        with tempfile.TemporaryDirectory(prefix='halopad-focus-') as temporary:
            binary = Path(temporary) / 'focus'
            built = subprocess.run(['clang', '-x', 'c', '-', '-std=c11', '-Wall', '-Wextra',
                                    '-Werror', '-fsanitize=address,undefined', '-I',
                                    str(ROOT / 'port/xbox'), '-o', str(binary)],
                                   input=source, text=True, capture_output=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            ran = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)

    def test_production_modal_lifecycle_cancels_input_and_preserves_background(self):
        native = (ROOT / 'port/xbox/xg_ios.m').read_text()
        functions = '\n'.join(production_function(native, name) for name in
            ('pads_set_active', 'xg_ios_set_native_modal_active', 'hw_push',
             'xg_ios_set_touch_pad', 'xg_ios_add_touch_look', 'xg_ios_game_menu_visible'))
        source = r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#include <pthread.h>
#include <SDL3/SDL_events.h>
#include "xg_profile_input.h"
#include "xg_focus_input.h"
#include "xg_scoreboard_input.h"
#define XG_SERVICE_RECORD 1
#define HW_EVENTS 128
static SDL_Event hw_events[HW_EVENTS];
static unsigned hw_head, hw_tail;
static pthread_mutex_t pad_lock = PTHREAD_MUTEX_INITIALIZER;
static struct xg_focus_input pad_focus = XG_FOCUS_INPUT_INITIALIZER;
static int pad_application_active, pad_native_modal_active, touch_trace;
#define pad_active (!XG_SERVICE_RECORD || pad_focus.active)
static struct xg_touch_input touch_input;
static struct xg_profile_input touch_profile;
static struct xg_scoreboard_input touch_scoreboard;
static float touch_look_x, touch_look_y;
''' + functions + r'''
int main(void) {
    @autoreleasepool {
        assert(xg_ios_game_menu_visible()); /* unknown is hidden */
        touch_profile.received = touch_profile.valid = 1;
        touch_profile.menu = 0;
        assert(!xg_ios_game_menu_visible());
        touch_profile.valid = 0;
        assert(xg_ios_game_menu_visible());
        touch_profile.valid = touch_profile.menu = 1;
        pads_set_active(1);
        assert(pad_active);
        struct xg_touch_pad held = { .buttons = 1 };
        SDL_Event event = {0};
        xg_ios_set_touch_pad(&held);
        hw_push(&event);
        xg_ios_add_touch_look(10, -5);
        assert(touch_input.current.buttons && hw_tail != hw_head && touch_look_x == 10);
        xg_ios_set_native_modal_active(1);
        assert(!pad_active && !touch_input.current.buttons && !touch_input.pending.buttons);
        assert(hw_tail == hw_head && touch_look_x == 0 && touch_look_y == 0);
        xg_ios_set_touch_pad(&held);
        hw_push(&event);
        xg_ios_add_touch_look(10, -5);
        assert(!touch_input.current.buttons && hw_tail == hw_head && touch_look_x == 0);
        pads_set_active(1); /* foreground notification beneath the modal */
        assert(!pad_active);
        pads_set_active(0); /* owner dismisses while the app is backgrounded */
        xg_ios_set_native_modal_active(0);
        assert(!pad_active);
        pads_set_active(1);
        assert(pad_active);
        xg_ios_set_touch_pad(&held);
        assert(touch_input.current.buttons); /* new input is accepted after resume */
        struct xg_touch_pad released = {0};
        xg_ios_set_touch_pad(&released);
        xg_ios_set_touch_pad(&held);
        assert(touch_input.current.buttons);
    }
    return 0;
}
'''
        with tempfile.TemporaryDirectory(prefix='halopad-modal-') as temporary:
            binary = Path(temporary) / 'modal'
            built = subprocess.run(['clang', '-x', 'objective-c', '-', '-fobjc-arc',
                                    '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
                                    '-I', str(ROOT / 'port/xbox'), '-I/opt/homebrew/include',
                                    '-framework', 'Foundation', '-pthread', '-o', str(binary)],
                                   input=source, text=True, capture_output=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            ran = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(ran.returncode, 0, ran.stdout + ran.stderr)


class ExactServiceRecordSourceTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get('HALOPAD_SERVICE_RECORD_ENGINE'),
                         'set HALOPAD_SERVICE_RECORD_ENGINE for existing-source integration')
    def test_exact_source_composition_restoration_and_tamper_rejection(self):
        engine = Path(os.environ['HALOPAD_SERVICE_RECORD_ENGINE'])
        originals = {relative: (engine / relative).read_bytes()
                     for relative in guest.service_record.SHA256}
        for relative, original in originals.items():
            self.assertEqual(hashlib.sha256(original).hexdigest(),
                             guest.service_record.SHA256[relative], str(relative))
        with tempfile.TemporaryDirectory(prefix='halopad-service-source-') as temporary:
            copied = Path(temporary)
            for relative, original in originals.items():
                (copied / relative).parent.mkdir(parents=True, exist_ok=True)
                (copied / relative).write_bytes(original)
            with patch.dict(os.environ, {'HALOPAD_SERVICE_RECORD': '1',
                                         'XBOX_REV': guest.service_record.REVISION}):
                identity = guest.identity('none')
                for fail in (False, True):
                    try:
                        with guest.renderer_adaptation(copied, identity):
                            imports = (copied / guest.service_record.profile_input.IMPORTS).read_bytes()
                            for name in (b'host_halopad_input_context_v1',
                                         b'host_halopad_progress_kill_v1',
                                         b'host_halopad_progress_menu_v1',
                                         b'host_halopad_career_event_v1'):
                                self.assertEqual(imports.count(name), 1)
                            if fail:
                                raise InterruptedError('synthetic build interruption')
                    except InterruptedError:
                        self.assertTrue(fail)
                    for relative, original in originals.items():
                        self.assertEqual((copied / relative).read_bytes(), original)
                changed = next(iter(originals))
                (copied / changed).write_bytes(originals[changed] + b'/* external edit */\n')
                before = {p: (copied / p).read_bytes() for p in originals}
                with self.assertRaisesRegex(ValueError, 'source changed'):
                    with guest.renderer_adaptation(copied, identity):
                        self.fail('tampered source was accepted')
                for relative, original in before.items():
                    self.assertEqual((copied / relative).read_bytes(), original)
                (copied / changed).write_bytes(originals[changed])
                with self.assertRaisesRegex(RuntimeError, 'preserving it for manual review'):
                    with guest.renderer_adaptation(copied, identity):
                        (copied / changed).write_bytes(b'concurrent external source edit')
                self.assertEqual((copied / changed).read_bytes(), b'concurrent external source edit')
                for relative, original in originals.items():
                    if relative != changed:
                        self.assertEqual((copied / relative).read_bytes(), original)
        # The authoritative checkout was never changed by the integration test.
        for relative, original in originals.items():
            self.assertEqual((engine / relative).read_bytes(), original)


if __name__ == '__main__':
    unittest.main()
