"""Exercise UIKit focus notifications and the production guest event queue."""
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def function(source, name):
    match = re.search(r'^(?:static )?[^\n;{}]*\b' + re.escape(name) + r'\([^;{}]*\)\s*\{', source, re.M)
    if not match:
        raise AssertionError('missing production function ' + name)
    end = source.index('{', match.start()) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[match.start():end]


@unittest.skipUnless(sys.platform == 'darwin', 'Apple Foundation and dispatch')
class InputFocusTests(unittest.TestCase):
    def test_startup_notifications_and_input_order(self):
        native = (ROOT / 'port/xbox/xg_ios.m').read_text()
        startup = function(native, 'xg_ios_start')
        self.assertLess(startup.index('xg_ios_observe_focus();'), startup.index('xg_start_game(boot)'))
        focus = native[native.index('static struct { int active, reported, lost; }'):
                       native.index('void xh_host_halopad_input_context_v1')]
        queue = native[native.index('#define HW_EVENTS '):native.index('/* ---------- application focus')]
        program = r'''
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "xg_scoreboard_input.h"
/* SDL's event boundary and UIKit application state are synthetic. The focus
 * observer, state machine, queue writer and complete event poll are real. */
typedef uint64_t Uint64;
typedef uint32_t SDL_JoystickID;
enum {
    SDL_EVENT_WINDOW_FOCUS_GAINED = 1, SDL_EVENT_WINDOW_FOCUS_LOST,
    SDL_EVENT_KEY_DOWN, SDL_EVENT_KEY_UP, SDL_EVENT_MOUSE_MOTION,
    SDL_EVENT_GAMEPAD_ADDED, SDL_SCANCODE_PAGEDOWN, SDL_SCANCODE_PAGEUP,
    SDLK_PAGEDOWN, SDLK_PAGEUP
};
typedef union {
    uint32_t type;
    struct { uint32_t type; Uint64 timestamp; } common;
    struct { uint32_t type; Uint64 timestamp; uint32_t windowID; } window;
    struct { uint32_t type; Uint64 timestamp; uint32_t windowID; int scancode, key, down; } key;
    struct { uint32_t type; Uint64 timestamp; uint32_t windowID; float xrel, yrel; } motion;
    struct { uint32_t type; Uint64 timestamp; SDL_JoystickID which; } gdevice;
} SDL_Event;
enum { UIApplicationStateActive, UIApplicationStateInactive, UIApplicationStateBackground };
static NSString *const UIApplicationWillResignActiveNotification = @"willResignActive";
static NSString *const UIApplicationDidBecomeActiveNotification = @"didBecomeActive";
@interface UIApplication : NSObject
@property(nonatomic) int applicationState;
+ (instancetype)sharedApplication;
@end
@implementation UIApplication
+ (instancetype)sharedApplication {
    assert(NSThread.isMainThread);
    static UIApplication *application;
    if (!application) application = [self new];
    return application;
}
@end
#define PADS 8
static void *pads[PADS + 1];
static uint8_t pad_announced[PADS + 1];
static pthread_mutex_t pad_lock = PTHREAD_MUTEX_INITIALIZER;
static struct xg_scoreboard_input touch_scoreboard;
static float touch_look_x, touch_look_y;
static int touch_trace;
static SDL_Event result;
#define G(type, address) ((void)(address), (type)&result)
static uint32_t xh_host_sdl_ticks(void) { return 123; }
static void pads_refresh(void) {}
''' + queue + focus + function(native, 'hw_push') + '\n' + function(native, 'xh_host_sdl_poll_event') + r'''
static void expect(uint32_t type) {
    assert(xh_host_sdl_poll_event(0));
    assert(result.type == type && result.common.timestamp == 123000000);
    if (type == SDL_EVENT_WINDOW_FOCUS_GAINED || type == SDL_EVENT_WINDOW_FOCUS_LOST)
        assert(result.window.windowID == 1);
}
static void notify(NSString *name) {
    [NSNotificationCenter.defaultCenter postNotificationName:name object:UIApplication.sharedApplication];
}
static void queue_key(void) {
    SDL_Event key = {0};
    key.key.type = SDL_EVENT_KEY_DOWN;
    key.key.down = 1;
    key.key.scancode = 42;
    hw_push(&key);
}
int main(int argc, const char **argv) { @autoreleasepool {
    assert(argc == 2 && !xh_host_sdl_poll_event(0));
    UIApplication *application = UIApplication.sharedApplication;
    application.applicationState = atoi(argv[1]);
    xg_ios_observe_focus();
    expect(application.applicationState == UIApplicationStateActive ?
           SDL_EVENT_WINDOW_FOCUS_GAINED : SDL_EVENT_WINDOW_FOCUS_LOST);
    assert(!xh_host_sdl_poll_event(0));
    /* An inactive/background startup must wait for the actual activation. */
    if (application.applicationState != UIApplicationStateActive) {
        application.applicationState = UIApplicationStateActive;
        notify(UIApplicationDidBecomeActiveNotification);
        expect(SDL_EVENT_WINDOW_FOCUS_GAINED);
    }
    xg_ios_observe_focus();
    notify(UIApplicationDidBecomeActiveNotification);
    notify(UIApplicationDidBecomeActiveNotification);
    assert(!xh_host_sdl_poll_event(0));

    /* A loss clears pending key-down, relative motion and scoreboard presses
     * before a quick resume, even if the hardware queue was already full. */
    for (int i = 0; i < HW_EVENTS + 1; i++) queue_key();
    assert(hw_tail - hw_head == HW_EVENTS);
    touch_look_x = 3;
    touch_look_y = -4;
    xg_scoreboard_drag(&touch_scoreboard, 160);
    notify(UIApplicationWillResignActiveNotification);
    notify(UIApplicationDidBecomeActiveNotification);
    expect(SDL_EVENT_WINDOW_FOCUS_LOST);
    expect(SDL_EVENT_WINDOW_FOCUS_GAINED);
    assert(!xh_host_sdl_poll_event(0));
    assert(hw_head == hw_tail && touch_look_x == 0 && touch_look_y == 0);

    notify(UIApplicationWillResignActiveNotification);
    expect(SDL_EVENT_WINDOW_FOCUS_LOST);
    notify(UIApplicationWillResignActiveNotification);
    assert(!xh_host_sdl_poll_event(0));

    /* Gain is independent of queue capacity and precedes all input. The
     * existing keyboard, look and controller event paths still drain. */
    notify(UIApplicationDidBecomeActiveNotification);
    for (int i = 0; i < HW_EVENTS + 1; i++) queue_key();
    touch_look_x = 7;
    touch_look_y = -8;
    pads[1] = &result;
    expect(SDL_EVENT_WINDOW_FOCUS_GAINED);
    for (int i = 0; i < HW_EVENTS; i++) {
        expect(SDL_EVENT_KEY_DOWN);
        assert(result.key.scancode == 42 && result.key.down);
    }
    expect(SDL_EVENT_MOUSE_MOTION);
    assert(result.motion.xrel == 7 && result.motion.yrel == -8);
    expect(SDL_EVENT_GAMEPAD_ADDED);
    assert(result.gdevice.which == 1);
    assert(!xh_host_sdl_poll_event(0));

    /* A delivered scoreboard key still gets its release after cancellation. */
    xg_scoreboard_drag(&touch_scoreboard, 80);
    expect(SDL_EVENT_KEY_DOWN);
    assert(result.key.scancode == SDL_SCANCODE_PAGEDOWN);
    notify(UIApplicationWillResignActiveNotification);
    notify(UIApplicationDidBecomeActiveNotification);
    expect(SDL_EVENT_WINDOW_FOCUS_LOST);
    expect(SDL_EVENT_WINDOW_FOCUS_GAINED);
    expect(SDL_EVENT_KEY_UP);
    assert(result.key.scancode == SDL_SCANCODE_PAGEDOWN);
    assert(!xh_host_sdl_poll_event(0));
} return 0; }
'''
        with tempfile.TemporaryDirectory(prefix='halopad-input-focus-') as folder:
            path = pathlib.Path(folder)
            source = path / 'focus.m'
            binary = path / 'focus'
            source.write_text(program)
            built = subprocess.run(['clang', '-Wall', '-Wextra', '-Werror', '-fobjc-arc',
                                    '-fblocks', '-fsanitize=address,undefined', '-pthread',
                                    '-framework', 'Foundation', '-I', str(ROOT / 'port/xbox'),
                                    str(source), '-o', str(binary)], capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            for state in ('0', '1', '2'):
                with self.subTest(startup_state=state):
                    run = subprocess.run([str(binary), state], capture_output=True, text=True, timeout=10)
                    self.assertEqual(run.returncode, 0, run.stderr)


if __name__ == '__main__':
    unittest.main()
