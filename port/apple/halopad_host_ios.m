/* HaloPad Apple host, iOS and iPadOS: windows as Metal layers, for an app shell to show.
 *
 * A Windows top-level window gets a CAMetalLayer. Until an app shell attaches it to a view
 * (halopad_host_attach_view), the layer is off screen: Direct3D still renders into its back
 * buffer (readable by tests), and Present shows nothing, as for a window no one can see.
 * Input comes from the shell's UIKit callbacks through halopad_input_event; this file has no
 * event source of its own: the shell queues events (halopad_host_post_input) and
 * halopad_host_pump delivers them on the thread that pumps, which is Halo's. */
#include <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#import "halopad_host.h"
#include "halopad_display_geometry.h"
#include "../runtime/halopad_input.h"
#include <stdatomic.h>

int halopad_host_input_off;                        /* tests drive input themselves */
static int pointer_captured, cursor_visible = 1;

void halopad_host_app(void) {}                     /* UIApplication belongs to the app shell */

/* Halo's desktop: the game window in pixels, landscape, as the app shell measured it on the
   main thread (Halo asks from its own thread). Before a shell has measured a window, as in the
   headless host tests, fall back to the device's main screen. */
static _Atomic int32_t desktop_w, desktop_h;
void halopad_host_set_screen_size(int32_t w, int32_t h)
{
    if (w <= 0 || h <= 0) return;
    atomic_store(&desktop_h, h);
    atomic_store(&desktop_w, w);
}
void halopad_host_screen_size(int32_t *w, int32_t *h)
{
    int32_t width = atomic_load(&desktop_w), height = atomic_load(&desktop_h);
    if (width > 0 && height > 0) { *w = width; *h = height; return; }
    CGRect b = UIScreen.mainScreen.nativeBounds;
    halopad_desktop_pixels(b.size.width, b.size.height, 1, w, h);
}

/* Events from the shell (UIKit's main thread) wait here until Halo's thread pumps. */
#include <pthread.h>
#define QSIZE 1024u
static hp_input queue_ev[QSIZE];
static uint32_t q_head, q_tail;
static int cancel_touch_pending;
/* Absolute axes need only their latest value. A separate lane guarantees release
   even with a full key queue; cancel is delivered first and erases older axes. */
static int touch_move_pending;
static hp_input touch_move_event;
static pthread_mutex_t q_lock = PTHREAD_MUTEX_INITIALIZER;

void halopad_host_post_input(const hp_input *e)
{
    static int trace = -1;
    if (trace < 0) trace = getenv("HALOPAD_TRACE_INPUT") != NULL;
    if (trace && e->kind == HPI_BUTTON) fprintf(stderr, "HALOPAD INPUT: %.3f posted button %d %s (queue %u)\n", CFAbsoluteTimeGetCurrent(), e->button, e->down ? "down" : "up", q_tail - q_head);
    pthread_mutex_lock(&q_lock);
    if (trace && e->kind == HPI_KEY && e->scan == 0x29)
        fprintf(stderr, "HALOPAD INPUT: %.3f posted console key %s (queue %u)\n", CFAbsoluteTimeGetCurrent(), e->down ? "down" : "up", q_tail - q_head);
    if (e->kind == HPI_CANCEL_TOUCH) {
        /* Native UI takes ownership now. Discard queued virtual controls and look, and
           deliver cancellation before ordinary events, even behind a key barrier. */
        uint32_t write = q_head;
        for (uint32_t read = q_head; read != q_tail; read++) {
            hp_input queued = queue_ev[read % QSIZE];
            if (!(queued.flags & HPI_TOUCH)) queue_ev[write++ % QSIZE] = queued;
        }
        q_tail = write;
        touch_move_pending = 0;
        cancel_touch_pending = 1;
    } else if (e->kind == HPI_TOUCH_MOVE) {
        touch_move_event = *e;
        touch_move_pending = 1;
    } else if (q_tail - q_head < QSIZE) queue_ev[q_tail++ % QSIZE] = *e;   /* a full queue drops, as a stalled Windows queue would */
    pthread_mutex_unlock(&q_lock);
}

void halopad_host_pump(void)
{
    /* the thread that pumps is Halo's: the app's game thread, or the main thread of a test binary */
    if ([NSThread isMainThread]) [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantPast]];
    /* A press and its release in one pump would never be seen by a game that reads key and button
       state once a frame (Halo does: a long frame left a touch's FIRE visible for one tick). The
       release of something pressed in this pump waits for the next one; order is kept.
       Virtual mouse buttons instead retain edges until DirectInput reads them. */
    uint32_t pressed[32];
    int npressed = 0;
    static int trace = -1;
    if (trace < 0) trace = getenv("HALOPAD_TRACE_INPUT") != NULL;
    if (trace) {
        pthread_mutex_lock(&q_lock);
        int waiting = 0;
        for (uint32_t i = q_head; i != q_tail; i++) waiting |= queue_ev[i % QSIZE].kind == HPI_BUTTON;
        pthread_mutex_unlock(&q_lock);
        if (waiting) fprintf(stderr, "HALOPAD INPUT: %.3f pump with a button waiting (%u events)\n", CFAbsoluteTimeGetCurrent(), q_tail - q_head);
    }
    for (;;) {
        hp_input e;
        pthread_mutex_lock(&q_lock);
        int have = cancel_touch_pending || touch_move_pending || q_head != q_tail;
        if (cancel_touch_pending) {
            e = (hp_input){.kind = HPI_CANCEL_TOUCH};
            cancel_touch_pending = 0;
        } else if (touch_move_pending) {
            e = touch_move_event;
            touch_move_pending = 0;
        } else if (have) {
            e = queue_ev[q_head % QSIZE];
            uint32_t id = e.kind == HPI_KEY ? 0x10000u | (e.scan & 0xFF) | (e.extended ? 0x100u : 0) : e.kind == HPI_BUTTON && !(e.flags & HPI_TOUCH) ? 0x20000u | (uint32_t)e.button : 0;
            int held_back = 0;
            if (id && !e.down) for (int i = 0; i < npressed; i++) held_back |= pressed[i] == id;
            if (held_back) have = 0;
            else {
                q_head++;
                if (id && e.down && npressed < 32) pressed[npressed++] = id;
            }
        }
        pthread_mutex_unlock(&q_lock);
        if (!have) return;
        if (trace && e.kind == HPI_KEY && e.scan == 0x29)
            fprintf(stderr, "HALOPAD INPUT: %.3f pumped console key %s\n", CFAbsoluteTimeGetCurrent(), e.down ? "down" : "up");
        if (e.kind == HPI_BUTTON && getenv("HALOPAD_TRACE_INPUT")) fprintf(stderr, "HALOPAD INPUT: %.3f pumped button %d %s\n", CFAbsoluteTimeGetCurrent(), e.button, e.down ? "down" : "up");
        if (!halopad_host_input_off) {
            if (e.kind == HPI_ACTIVATE && getenv("HALOPAD_TRACE_LIFECYCLE"))
                fprintf(stderr, "HALOPAD LIFECYCLE: %.3f pump activation %d\n", CFAbsoluteTimeGetCurrent(), e.down);
            halopad_input_event(&e);
        }
    }
}

/* For the shell's pointer mapping: a window's client size in pixels. */
void halopad_host_window_size(void *p, uint32_t *w, uint32_t *h) { hp_window *win = p; *w = win->w; *h = win->h; }

/* DirectInput's exclusive mouse and Windows' cursor display: recorded for the shell, which
   applies them with UIKit's pointer lock and pointer hiding. */
void halopad_host_mouse_capture(int on) { pointer_captured = on; }
void halopad_host_cursor(int visible) { cursor_visible = visible; }
int halopad_host_pointer_captured(void) { return pointer_captured; }
int halopad_host_cursor_visible(void) { return cursor_visible; }

/* The app shell's handler for new windows (it attaches their layers to its view). */
static void (*window_handler)(void *window);
void halopad_host_set_window_handler(void (*handler)(void *window)) { window_handler = handler; }

void *halopad_host_window_create(uint32_t width, uint32_t height, const char *title, int visible)
{
    (void)title;
    id<MTLDevice> gpu = halopad_metal_gpu();
    hp_window *w = calloc(1, sizeof *w);
    w->refs = 1;
    for (int c = 0; c < 3; c++) for (int i = 0; i < 256; i++) w->lut[256 * c + i] = i / 255.0f;
    @autoreleasepool {
        w->layer = [CAMetalLayer layer];
        w->layer.device = gpu;
        w->layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        w->layer.framebufferOnly = YES;
        w->layer.drawableSize = CGSizeMake(width, height);
        w->layer.contentsGravity = kCAGravityResizeAspect;   /* letterboxed in the shell's view */
        w->layer.hidden = !visible;
        [CATransaction flush];                           /* Halo's thread has no run loop to commit it */
    }
    w->w = width; w->h = height;
    if (window_handler) {
        w->refs++;                                       /* held until the shell has seen it */
        void (*h)(void *) = window_handler;
        dispatch_async(dispatch_get_main_queue(), ^{ h(w); halopad_host_window_unref(w); });
    }
    return w;
}

/* For the app shell: show a window's layer in a view (filling it), or detach it (nil). */
void halopad_host_attach_view(void *p, UIView *view)
{
    hp_window *w = p;
    @autoreleasepool {
        [w->layer removeFromSuperlayer];
        w->window = view;
        w->on_screen = view != nil;
        if (view) {
            w->layer.frame = view.layer.bounds;
            w->layer.contentsScale = view.contentScaleFactor;
            [view.layer addSublayer:w->layer];
        }
    }
}

void halopad_host_window_destroy(void *p)
{
    hp_window *w = p;
    @autoreleasepool { [w->layer removeFromSuperlayer]; }
    w->window = nil;
    w->on_screen = 0;
    halopad_host_window_unref(w);
}

void halopad_host_window_show(void *p, int visible)
{
    hp_window *w = p;
    @autoreleasepool { w->layer.hidden = !visible; [CATransaction flush]; }
}

void halopad_host_window_title(void *p, const char *title) { (void)p; (void)title; }   /* iOS windows have no title bar */

/* The client area in pixels (GDI's surface follows it). */
void halopad_host_window_resize(void *p, uint32_t width, uint32_t height)
{
    hp_window *w = p;
    if (!width || !height || (width == w->w && height == w->h)) return;
    w->w = width; w->h = height;
    free(w->gdi);
    w->gdi = NULL;
    w->gdi_tex = nil;
}

/* The pasteboard's text in Windows-1252 (for CF_TEXT); its length, 0 if none. */
int halopad_host_clipboard_text(char *out, size_t size)
{
    @autoreleasepool {
        NSString *s = UIPasteboard.generalPasteboard.string;
        if (!s.length) return 0;
        NSData *d = [s dataUsingEncoding:NSWindowsCP1252StringEncoding allowLossyConversion:YES];
        size_t n = d.length < size - 1 ? d.length : size - 1;
        memcpy(out, d.bytes, n);
        out[n] = 0;
        return (int)n;
    }
}
#endif
