/* HaloPad Apple host, shared between the Metal core (halopad_metal.m) and the platform hosts
 * (halopad_host_macos.m: AppKit; halopad_host_ios.m: UIKit). */
#ifndef HALOPAD_HOST_H
#define HALOPAD_HOST_H
#include <TargetConditionals.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#include <stdint.h>
#if TARGET_OS_OSX
@class NSWindow;
typedef NSWindow *hp_platform_window;
#else
@class UIView;
typedef UIView *hp_platform_window;         /* the view an app shell attached, or nil (headless) */
#endif

/* ---- host windows: one per shown Windows top-level window (USER32 owns them) ----
 * Each has a Metal layer. Before Direct3D attaches, GDI output (StretchBlt to the window)
 * goes to a CPU surface of the client size that is presented directly; once a device
 * attaches, Present shows its back buffer. Every presentation passes through the window's
 * gamma table (SetDeviceGammaRamp, IDirect3DDevice9::SetGammaRamp), as a display's
 * hardware ramp would apply. A window whose layer is not on screen presents nothing. */
typedef struct hp_window {
    hp_platform_window window;
    CAMetalLayer *layer;
    uint32_t w, h, refs;
    uint32_t *gdi;                           /* GDI surface, BGRA, client size */
    id<MTLTexture> gdi_tex;
    float lut[768];                          /* gamma, per channel, 256 entries each */
    int has_target;
    int on_screen;                           /* the layer is in a window or view */
} hp_window;

id<MTLDevice> halopad_metal_gpu(void);       /* halopad_metal.m: the device, created on first use */
void halopad_host_app(void);                 /* the platform's application set-up (before any window) */
void halopad_host_window_unref(hp_window *w);
void halopad_host_screen_size(int32_t *w, int32_t *h);   /* Halo's desktop in pixels */
#if !TARGET_OS_OSX
/* iOS app shell, main thread: the game window's desktop size (halopad_desktop_pixels). */
void halopad_host_set_screen_size(int32_t w, int32_t h);
#endif
void halopad_host_pump(void);                /* pending host events, without blocking */
#endif
