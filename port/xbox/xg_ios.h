/* xg_ios.h: the Xbox engine's entry points for the iOS app (xg_ios.m). */
#ifndef XG_IOS_H
#define XG_IOS_H
#import <UIKit/UIKit.h>
#include "xg_touch_input.h"

/* the view the game draws into; make it on the main thread before starting */
UIView *xg_ios_make_view(CGRect frame);
/* call from the main thread when the view's size changes */
void xg_ios_view_resized(void);
/* loads the game image and starts the game on its own thread; 0 on success */
int xg_ios_start(const char *image_path, const char *data_root, const char *save_root);
/* the verified network policy row for this engine (xg_network_policy.h); call
 * before xg_ios_start. Returns 0, and keeps upstream's exact rule, if invalid. */
int xg_ios_set_network_policy(unsigned int engine, unsigned int announce, unsigned int minimum, unsigned int maximum);

/* player 1's touch gamepad (xg_touch.m): axes in SDL order (left x, left y,
 * right x, right y, left trigger, right trigger; -1..1, y down), buttons as
 * bits numbered by SDL_GamepadButton */
void xg_ios_set_touch_pad(const struct xg_touch_pad *state);
void xg_ios_clear_touch_pad(void);
/* Relative touch look is delivered through upstream's SDL mouse path. */
void xg_ios_add_touch_look(float dx, float dy);
void xg_ios_scroll_scoreboard(float points);
/* A hardware keyboard and mouse (the Mac): an SDL scancode (the USB HID usage), an SDL mouse
 * button (1 left, 2 middle, 3 right) and wheel steps, as the engine's PC input reads them. */
void xg_ios_key(int scancode, int down);
void xg_ios_mouse_button(int button, int down);
void xg_ios_mouse_wheel(float steps);
/* nonzero while a game controller is player 1's */
int xg_ios_controller_connected(void);
/* frames presented since the game started (any thread) */
int xg_ios_frames_presented(void);

/* the Xbox-layout touch gamepad; add it above the game view */
@interface XGTouchPad : UIView
@end

#endif
