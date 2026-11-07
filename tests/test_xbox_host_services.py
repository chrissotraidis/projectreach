"""Run the OpenCE343 host services with synthetic platform API boundaries."""
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


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


class HostServicesTests(unittest.TestCase):
    def test_sdl_keyboard_lifecycle_and_browser_failures(self):
        source = (ROOT / 'port/xbox/xg_sdl.c').read_text()
        program = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <strings.h>
typedef int SDL_Window;
typedef unsigned SDL_PropertiesID;
#define SDL_PROP_TEXTINPUT_TYPE_NUMBER "type"
#define SDL_PROP_TEXTINPUT_MULTILINE_BOOLEAN "multiline"
#define SDL_PROP_TEXTINPUT_AUTOCORRECT_BOOLEAN "autocorrect"
static int object, active, stopped, destroyed, requested_type, starts;
static int properties_available = 1, allow_start = 1, opened, allow_open = 1;
static char memory[512];
#define G(type, address) ((type)(memory + (address)))
static void *handle_get(uint32_t handle) { return handle == 1 ? &object : 0; }
static void SDL_StopTextInput(SDL_Window *window) { assert(window == &object); active = 0; stopped++; }
static SDL_PropertiesID SDL_CreateProperties(void) { return properties_available ? 7 : 0; }
static void SDL_SetNumberProperty(SDL_PropertiesID id, const char *name, int value) {
    assert(id == 7 && !strcmp(name, "type")); requested_type = value;
}
static void SDL_SetBooleanProperty(SDL_PropertiesID id, const char *name, bool value) {
    assert(id == 7 && (!strcmp(name, "multiline") || !strcmp(name, "autocorrect")) && !value);
}
static void SDL_StartTextInputWithProperties(SDL_Window *window, SDL_PropertiesID id) {
    assert(window == &object && id == 7); active = allow_start; starts++;
}
static void SDL_DestroyProperties(SDL_PropertiesID id) { assert(id == 7); destroyed++; }
static bool SDL_TextInputActive(SDL_Window *window) { assert(window == &object); return active; }
static bool SDL_OpenURL(const char *url) { assert(url == memory + 1); opened++; return allow_open; }
''' + function(source, 'xh_host_sdl_text_input') + '\n' + function(source, 'xh_host_sdl_open_url') + r'''
int main(void) {
    assert(!xh_host_sdl_text_input(0, 3) && !starts);
    assert(xh_host_sdl_text_input(1, 3) && requested_type == 3 && destroyed == 1);
    assert(!xh_host_sdl_text_input(1, -1) && stopped == 1 && !active);
    allow_start = 0;
    assert(!xh_host_sdl_text_input(1, 4) && destroyed == 2);
    properties_available = 0;
    assert(!xh_host_sdl_text_input(1, 4) && starts == 2);
    assert(!xh_host_sdl_open_url(0));
    strcpy(memory + 1, "file:///private/test");
    assert(!xh_host_sdl_open_url(1) && !opened);
    strcpy(memory + 1, "https://example.invalid/link?key=test");
    assert(xh_host_sdl_open_url(1) && opened == 1);
    allow_open = 0;
    assert(!xh_host_sdl_open_url(1) && opened == 2);
    return 0;
}
'''
        self.compile_and_run(program, objc=False)

    @unittest.skipUnless(sys.platform == 'darwin', 'Apple Foundation and dispatch')
    def test_uikit_browser_dispatch_result_and_invalid_links(self):
        source = (ROOT / 'port/xbox/xg_ios.m').read_text()
        program = r'''
#import <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
#include <assert.h>
#include <stdatomic.h>
#include <stdint.h>
static int opened;
static BOOL allow_open = YES;
static char memory[512];
#define G(type, address) ((type)(memory + (address)))
@interface UIApplication : NSObject
+ (instancetype)sharedApplication;
- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion;
@end
@implementation UIApplication
+ (instancetype)sharedApplication {
    assert(NSThread.isMainThread);
    static UIApplication *application;
    if (!application) application = [self new];
    return application;
}
- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion {
    assert(NSThread.isMainThread && options.count == 0);
    assert([url.host isEqualToString:@"example.invalid"]);
    opened++;
    completion(allow_open);
}
@end
''' + function(source, 'xh_host_sdl_open_url') + r'''
static void attempt(const char *url, int expected) {
    strcpy(memory + 1, url);
    __block atomic_int completed = 0, result = -1;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            atomic_store(&result, xh_host_sdl_open_url(1));
            atomic_store(&completed, 1);
        }
    });
    for (int i = 0; i < 100 && !atomic_load(&completed); i++)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    assert(atomic_load(&completed) && atomic_load(&result) == expected);
}
int main(void) { @autoreleasepool {
    assert(!xh_host_sdl_open_url(0) && !xh_host_sdl_open_url(1));
    attempt("https://example.invalid/link?key=test", 1);
    assert(opened == 1);
    allow_open = NO;
    attempt("https://example.invalid/link?key=test", 0);
    assert(opened == 2);
    attempt("file:///private/test", 0);
    attempt("https:///", 0);
    attempt("bad string", 0);
    assert(opened == 2);
} return 0; }
'''
        self.compile_and_run(program, objc=True)

    def compile_and_run(self, source, objc):
        with tempfile.TemporaryDirectory(prefix='halopad-host-services-') as folder:
            path = pathlib.Path(folder)
            program = path / ('test.m' if objc else 'test.c')
            binary = path / 'test'
            program.write_text(source)
            flags = ['-fobjc-arc', '-fblocks', '-framework', 'Foundation'] if objc else ['-std=c11']
            built = subprocess.run(['clang', '-Wall', '-Wextra', '-Werror', '-fsanitize=address,undefined',
                                    *flags, str(program), '-o', str(binary)], capture_output=True, text=True)
            self.assertEqual(built.returncode, 0, built.stderr)
            run = subprocess.run([str(binary)], capture_output=True, text=True, timeout=10)
            self.assertEqual(run.returncode, 0, run.stderr)


if __name__ == '__main__':
    unittest.main()
