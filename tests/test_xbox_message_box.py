"""The guest's sparse button indices must survive the native dialog bridge."""
import pathlib
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class XboxMessageBoxTests(unittest.TestCase):
    def test_button_indices_defaults_and_failure(self):
        source = (ROOT / 'port/xbox/xg_sdl.c').read_text()
        start = source.index('int xh_host_sdl_show_message_box(')
        end = source.index('\nint xh_host_sdl_get_gamepads(', start)
        program = r'''
#include <SDL3/SDL_messagebox.h>
#include <assert.h>
#include <stdint.h>
#include <string.h>
static char memory[] = "\0Title\0Body\0First\0Third";
#define G(type, address) ((type)(memory + (address)))
static int mode, calls;
bool SDL_ShowMessageBox(const SDL_MessageBoxData *question, int *answer) {
    calls++;
    assert(!strcmp(question->title, "Title"));
    assert(!strcmp(question->message, "Body"));
    assert(question->numbuttons == 2);
    assert(question->buttons[0].buttonID == 0);
    assert(question->buttons[1].buttonID == 2);
    assert(!strcmp(question->buttons[0].text, "First"));
    assert(!strcmp(question->buttons[1].text, "Third"));
    assert(question->buttons[0].flags == 0);
    assert(question->buttons[1].flags ==
        (SDL_MESSAGEBOX_BUTTON_RETURNKEY_DEFAULT | SDL_MESSAGEBOX_BUTTON_ESCAPEKEY_DEFAULT));
    *answer = mode == 1 ? 0 : 2;
    return mode != 2;
}
''' + source[start:end] + r'''
int main(void) {
    assert(xh_host_sdl_show_message_box(0, 1, 7, 2, 12, 0, 18) == 2);
    mode = 1;
    assert(xh_host_sdl_show_message_box(0, 1, 7, 2, 12, 0, 18) == 0);
    mode = 2;
    assert(xh_host_sdl_show_message_box(0, 1, 7, 2, 12, 0, 18) == -1);
    assert(xh_host_sdl_show_message_box(0, 1, 7, 2, 0, 0, 0) == -1);
    assert(calls == 3);
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as folder:
            binary = pathlib.Path(folder) / 'message-box'
            subprocess.run(['clang', '-x', 'c', '-', '-std=c11', '-Wall', '-Werror',
                            '-fsanitize=address,undefined', '-I/opt/homebrew/include',
                            '-o', str(binary)], input=program, text=True, check=True,
                           capture_output=True)
            subprocess.run([str(binary)], check=True, capture_output=True)

    @unittest.skipUnless(sys.platform == 'darwin', 'Foundation and Apple dispatch are required')
    def test_uikit_waits_for_foreground_and_returns_the_selected_sparse_index(self):
        source = (ROOT / 'port/xbox/xg_ios.m').read_text()
        start = source.index('static void xg_present_message_box(')
        end = source.index('\n/* ---------- gamepads', start)
        # Replace UIKit's presentation edges only; execute the shipped helper,
        # guest-memory conversion and semaphore bridge on real dispatch queues.
        program = r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#include <stdatomic.h>
#include <stdint.h>
typedef NS_ENUM(NSInteger, UIApplicationState) {
    UIApplicationStateActive, UIApplicationStateInactive
};
enum { UIAlertControllerStyleAlert, UIAlertActionStyleDefault };
@class UIViewController;
@interface UIWindow : NSObject
@property(nonatomic, strong) UIViewController *rootViewController;
@end
@implementation UIWindow
@end
@interface UIView : NSObject
@property(nonatomic, strong) UIWindow *window;
@end
@implementation UIView
@end
@interface UIViewController : NSObject
@property(nonatomic, strong) UIView *view;
@property(nonatomic, strong) UIViewController *presentedViewController;
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion;
@end
@interface UIApplication : NSObject
@property(nonatomic) UIApplicationState applicationState;
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
@interface UIAlertAction : NSObject
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) void (^handler)(UIAlertAction *);
+ (instancetype)actionWithTitle:(NSString *)title style:(NSInteger)style handler:(void (^)(UIAlertAction *))handler;
@end
@implementation UIAlertAction
+ (instancetype)actionWithTitle:(NSString *)title style:(NSInteger)style handler:(void (^)(UIAlertAction *))handler {
    assert(NSThread.isMainThread);
    assert(style == UIAlertActionStyleDefault);
    UIAlertAction *action = [self new]; action.title = title; action.handler = handler;
    return action;
}
@end
@interface UIAlertController : UIViewController
@property(nonatomic, copy) NSString *heading;
@property(nonatomic, copy) NSString *body;
@property(nonatomic, strong) NSMutableArray<UIAlertAction *> *actions;
@property(nonatomic, strong) UIAlertAction *preferredAction;
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(NSInteger)style;
- (void)addAction:(UIAlertAction *)action;
@end
static UIAlertController *presented;
static int presentations;
@implementation UIViewController
- (void)presentViewController:(UIViewController *)controller animated:(BOOL)animated completion:(void (^)(void))completion {
    assert(NSThread.isMainThread && animated && self.view.window);
    assert(UIApplication.sharedApplication.applicationState == UIApplicationStateActive);
    presented = (UIAlertController *)controller; presentations++;
    if (completion) completion();
}
@end
@implementation UIAlertController
@synthesize preferredAction = _preferredAction;
+ (instancetype)alertControllerWithTitle:(NSString *)title message:(NSString *)message preferredStyle:(NSInteger)style {
    assert(NSThread.isMainThread && style == UIAlertControllerStyleAlert);
    UIAlertController *alert = [self new]; alert.heading = title; alert.body = message;
    alert.actions = [NSMutableArray new]; return alert;
}
- (void)addAction:(UIAlertAction *)action {
    assert(NSThread.isMainThread); [self.actions addObject:action];
}
- (void)setPreferredAction:(UIAlertAction *)action {
    assert(NSThread.isMainThread && [self.actions containsObject:action]);
    _preferredAction = action;
}
@end
static UIView *game_view;
static char memory[] = "\0Title\0Body\0First\0Third";
#define G(type, address) ((type)(memory + (address)))
''' + source[start:end] + r'''
static atomic_int completed, result;
static void pump(double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    do {
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    } while ([end timeIntervalSinceNow] > 0);
}
static void begin(int default_index, uint32_t title, uint32_t message, uint32_t first, uint32_t third) {
    presented = nil; atomic_store(&completed, 0); atomic_store(&result, -99);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            assert(!NSThread.isMainThread);
            atomic_store(&result, xh_host_sdl_show_message_box(0, title, message, default_index, first, 0, third));
            atomic_store(&completed, 1);
        }
    });
}
static void finish(int expected) {
    for (int attempt = 0; attempt < 100 && !atomic_load(&completed); attempt++) pump(0.01);
    assert(atomic_load(&completed) && atomic_load(&result) == expected);
}
int main(void) { @autoreleasepool {
    UIWindow *window = [UIWindow new];
    UIViewController *root = [UIViewController new], *top = [UIViewController new];
    root.view = [UIView new]; root.view.window = window;
    top.view = [UIView new]; top.view.window = window;
    root.presentedViewController = top; window.rootViewController = root;
    game_view = [UIView new]; game_view.window = window;
    UIApplication.sharedApplication.applicationState = UIApplicationStateInactive;
    assert(xh_host_sdl_show_message_box(0, 1, 7, 2, 12, 0, 18) == -1); // Never block UIKit's thread.
    begin(2, 1, 7, 12, 18);
    pump(0.25);
    assert(!presented && !presentations && !atomic_load(&completed)); // No fallback choice while inactive.
    UIApplication.sharedApplication.applicationState = UIApplicationStateActive;
    top.view.window = nil;
    pump(0.25);
    assert(!presented && !presentations && !atomic_load(&completed)); // Wait for attachment too.
    top.view.window = window;
    for (int attempt = 0; attempt < 100 && !presented; attempt++) pump(0.01);
    assert(presented && presentations == 1 && !atomic_load(&completed));
    assert([presented.heading isEqualToString:@"Title"] && [presented.body isEqualToString:@"Body"]);
    assert(presented.actions.count == 2);
    assert([presented.actions[0].title isEqualToString:@"First"]);
    assert([presented.actions[1].title isEqualToString:@"Third"]);
    assert(presented.preferredAction == presented.actions[1]);
    presented.actions[1].handler(presented.actions[1]);
    finish(2);
    pump(0.15); assert(presentations == 1); // No queued retry presents another alert.

    begin(1, 0, 0, 12, 18); // The absent middle button cannot become the default.
    for (int attempt = 0; attempt < 100 && !presented; attempt++) pump(0.01);
    assert(presented && presentations == 2 && !presented.preferredAction);
    assert([presented.heading isEqualToString:@""] && [presented.body isEqualToString:@""]);
    presented.actions[0].handler(presented.actions[0]);
    finish(0);
    begin(0, 1, 7, 0, 0);
    finish(-1); assert(!presented && presentations == 2);
} return 0; }
'''
        with tempfile.TemporaryDirectory(prefix='halopad-uikit-message-box-') as folder:
            path = pathlib.Path(folder)
            (path / 'message-box.m').write_text(program)
            subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra', '-Werror',
                            '-Wno-unused-parameter', '-fsanitize=address,undefined',
                            str(path / 'message-box.m'), '-framework', 'Foundation',
                            '-o', str(path / 'message-box')], check=True, capture_output=True)
            subprocess.run([str(path / 'message-box')], check=True, capture_output=True, timeout=10)


if __name__ == '__main__':
    unittest.main()
