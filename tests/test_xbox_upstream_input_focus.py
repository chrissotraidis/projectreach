"""Exercise UIKit's event bridge against the exact OpenCE343 input consumer.

Requires the local engine checkout (or HALOPAD_TEST_ENGINE) and SDL3 headers.
No game assets, running app, controller or device are needed.
"""
import ast
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
REV343 = 'fc9deb0b10eaae1d62caedb0710968b4e77e6e16'


def function(source, name):
    match = re.search(r'^int ' + name + r'\([^;{}]*\)\s*\{', source, re.M)
    if not match:
        raise AssertionError('missing production function ' + name)
    end = source.index('{', match.start()) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[match.start():end]


class UpstreamInputFocusTests(unittest.TestCase):
    def test_uikit_events_enable_upstream_touch_and_controller_input(self):
        checkout = pathlib.Path(os.environ.get(
            'HALOPAD_TEST_ENGINE', ROOT / 'ref/xbox-build/vol/engine'))

        def upstream(path):
            result = subprocess.run(['git', '-C', str(checkout), 'show', REV343 + ':' + path],
                                    capture_output=True, text=True)
            if result.returncode:
                self.skipTest('exact OpenCE343 source unavailable; set HALOPAD_TEST_ENGINE')
            return result.stdout

        # Reuse upstream's config/profile boundary fixtures without executing its
        # pytest module. The remapping policy and input processing stay unmodified.
        fixture = ast.parse(upstream('tools/test_controller_remap.py'))
        constants = {target.id: ast.literal_eval(node.value)
                     for node in fixture.body if isinstance(node, ast.Assign)
                     for target in node.targets
                     if isinstance(target, ast.Name) and target.id in ('COMMON', 'INPUT')}
        platform = upstream('port/linux/src/sdl_platform.c')
        platform_header = upstream('port/linux/src/sdl_platform.h')
        state = re.search(r'struct platform_input_state\n\{.*?\n\};',
                          platform_header, re.S).group()
        focus_cases = platform.split('\t\tcase SDL_EVENT_WINDOW_FOCUS_LOST:', 1)[1]
        focus_cases = '\t\tcase SDL_EVENT_WINDOW_FOCUS_LOST:' + focus_cases.split(
            '\n#ifdef HALO_ANDROID\n\t\tcase SDL_EVENT_FINGER_DOWN:', 1)[0]
        policy = ''
        for path in ('port/linux/include/controller_buttons.h',
                     'port/linux/include/controller_remap.h',
                     'port/linux/src/controller_remap.c'):
            policy += re.sub(r'^#include[^\n]*\n', '', upstream(path), flags=re.M)
        remapper = re.sub(r'^#include[^\n]*\n', '',
                          upstream('port/linux/src/controller_remap_input.c'), flags=re.M)
        inputs = constants['INPUT'].replace(',focused=1,', ',')
        inputs = inputs.replace('struct platform_input_state {int focused;};',
                                state + '\nstatic struct platform_input_state input_state;')
        inputs = inputs.replace('p->focused=focused;', '(void)consume; *p=input_state;')
        self.assertNotIn('focused=1', inputs)

        include_flags = []
        if shutil.which('pkg-config'):
            flags = subprocess.run(['pkg-config', '--cflags', 'sdl3'],
                                   capture_output=True, text=True)
            if flags.returncode == 0:
                import shlex
                include_flags = shlex.split(flags.stdout)
        if not include_flags:
            for include in ('/opt/homebrew/include', '/usr/local/include', '/usr/include'):
                if (pathlib.Path(include) / 'SDL3/SDL_events.h').is_file():
                    include_flags = ['-I', include]
                    break
            else:
                self.skipTest('SDL3 headers unavailable')

        host = (ROOT / 'port/xbox/xg_ios.m').read_text()
        focus = host.split('/* ---------- application focus, delivered before queued input */', 1)[1]
        focus = focus.split('static void xg_ios_observe_focus', 1)[0]
        poll = function(host, 'xh_host_sdl_poll_event')
        prefix = r'''
#include <SDL3/SDL_events.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "xg_scoreboard_input.h"
#define TRUE 1
#define PLATFORM_MOUSE_BUTTON_COUNT 8
typedef int BOOL;
static SDL_Event host_event;
#define G(type, address) ((void)(address), (type)&host_event)
#define HW_EVENTS 128
#define PADS 8
static SDL_Event hw_events[HW_EVENTS];
static unsigned hw_head, hw_tail;
static int pads[PADS + 1], pad_announced[PADS + 1], touch_trace;
static float touch_look_x, touch_look_y;
static struct xg_scoreboard_input touch_scoreboard;
static pthread_mutex_t pad_lock = PTHREAD_MUTEX_INITIALIZER;
static uint32_t xh_host_sdl_ticks(void) { return 123; }
static void pads_refresh(void) {}
'''
        # The focus cases are the real upstream event consumer. Stub only its
        # unrelated cursor side effects, keeping the desktop/ARM64 guest branch.
        consumer = r'''
static int mouse_buttons_pressed[8], scoreboard_pointer_active, look_at_clipboard;
static int mouse_warp_capture;
static SDL_Window *platform_window;
static void platform_mouse_capture(BOOL capture) { (void)capture; }
#define SDL_SetWindowMouseGrab(window, value) ((void)(window), (void)(value))
#define SDL_ShowCursor() ((void)0)
static void consume_host_event(void) {
    switch (host_event.type) {
''' + focus_cases + r'''
    default: break;
    }
}
'''
        main = r'''
static void check_pad(XINPUT_GAMEPAD raw, int enabled) {
    XINPUT_GAMEPAD pad = raw, neutral = {0};
    assert(!controller_remap_input(0, &pad, 1));
    assert(!memcmp(&pad, enabled ? &raw : &neutral, sizeof(pad)));
}
static void next_focus(unsigned expected) {
    assert(xh_host_sdl_poll_event(1));
    assert(host_event.type == expected && host_event.window.windowID == 1);
    assert(host_event.window.timestamp == 123000000ull);
    consume_host_event();
}
int main(void) {
    /* Both native touch and hardware occupy the physical gamepad path. */
    for (int menus = 0; menus < 2; menus++) for (int hardware = 0; hardware < 2; hardware++) {
        XINPUT_GAMEPAD raw = {0};
        raw.wButtons = hardware ? XINPUT_GAMEPAD_DPAD_RIGHT : XINPUT_GAMEPAD_START;
        raw.bAnalogButtons[hardware ? 7 : 0] = 255;
        raw.sThumbLX = 17000; raw.sThumbRY = -19000;
        menu[0] = menus;
        controller_remap_input_reset();
        memset(&input_state, 0, sizeof(input_state));
        app_focus.active = app_focus.reported = -1; app_focus.lost = 0;
        hw_head = hw_tail = 0;
        check_pad(raw, 0); /* Exact343 static-zero startup suppresses input. */
        xg_ios_set_focus(1);
        if (!xh_host_sdl_poll_event(1)) {
            check_pad(raw, 0);
            puts("REGRESSION: no host focus event; upstream discards all pad input");
            return 42;
        }
        assert(host_event.type == SDL_EVENT_WINDOW_FOCUS_GAINED);
        consume_host_event();
        check_pad(raw, 1);
        xg_ios_set_focus(1);
        assert(!xh_host_sdl_poll_event(1)); /* No duplicate event each frame. */

        /* A full queue cannot hide loss or a quick loss/regain transition. */
        hw_tail = HW_EVENTS;
        for (int i = 0; i < HW_EVENTS; i++) hw_events[i].type = SDL_EVENT_KEY_DOWN;
        input_state.keys[SDL_SCANCODE_W] = 1;
        input_state.mouse_buttons[1] = 1;
        xg_ios_set_focus(0);
        assert(hw_head == hw_tail); /* No stale key-down after the focus reset. */
        xg_ios_set_focus(1);
        hw_events[hw_tail++ % HW_EVENTS].type = SDL_EVENT_KEY_UP;
        next_focus(SDL_EVENT_WINDOW_FOCUS_LOST);
        assert(!input_state.keys[SDL_SCANCODE_W] && !input_state.mouse_buttons[1]);
        check_pad(raw, 0);
        next_focus(SDL_EVENT_WINDOW_FOCUS_GAINED);
        check_pad(raw, 1);
        assert(hw_head == HW_EVENTS && xh_host_sdl_poll_event(1));
        assert(host_event.type == SDL_EVENT_KEY_UP && hw_head == HW_EVENTS + 1);
        hw_head = hw_tail;
        assert(!xh_host_sdl_poll_event(1));
        xg_ios_set_focus(0);
        next_focus(SDL_EVENT_WINDOW_FOCUS_LOST);
        check_pad(raw, 0);
    }
    puts("PASS: exact343 consumes UIKit focus and preserves touch/controller input");
    return 0;
}
'''
        base = prefix + constants['COMMON'] + policy + inputs + remapper
        with tempfile.TemporaryDirectory(prefix='halopad-upstream-input-') as temporary:
            binary = pathlib.Path(temporary) / 'test'

            def run(poll_source):
                program = base + focus + poll_source + consumer + main
                build = subprocess.run(['clang', '-x', 'c', '-', '-std=c11',
                                        '-fsanitize=address,undefined', '-pthread',
                                        '-I', str(ROOT / 'port/xbox'), *include_flags,
                                        '-o', str(binary)], input=program, text=True,
                                       capture_output=True)
                self.assertEqual(build.returncode, 0, build.stderr)
                return subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)

            result = run(poll)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS: exact343', result.stdout)

            # Remove just the new delivery block: this must recreate the released
            # host's failure, so the test cannot pass on the remapper alone.
            broken, count = re.subn(
                r'\tif \(xg_ios_poll_focus_event\(out\)\)\n\t\{.*?\n\t\}', '', poll, count=1, flags=re.S)
            self.assertEqual(count, 1)
            result = run(broken)
            self.assertEqual(result.returncode, 42, result.stdout + result.stderr)
            self.assertIn('upstream discards all pad input', result.stdout)


if __name__ == '__main__':
    unittest.main()
