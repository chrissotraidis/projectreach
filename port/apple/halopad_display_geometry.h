/* Display sizes both iOS hosts hand their engines, from the game window that shows them.
 * Pure arithmetic, shared by port/apple/halopad_host_ios.m, port/ios/HaloPadApp.m and
 * port/xbox/xg_ios.m, and checked by tests/halo_display_geometry_test.c. */
#ifndef HALOPAD_DISPLAY_GEOMETRY_H
#define HALOPAD_DISPLAY_GEOMETRY_H
#include <math.h>
#include <stdint.h>

/* Custom Edition: Halo's Windows desktop in pixels, landscape, from the game window's size in
   points and its screen's native scale (a full-screen window gives the panel's native pixels). */
static inline void halopad_desktop_pixels(double width, double height, double scale, int32_t *w, int32_t *h)
{
    int32_t a = (int32_t)lround(width * scale), c = (int32_t)lround(height * scale);
    *w = a > c ? a : c;
    *h = a > c ? c : a;
}

/* Xbox: the 480-line render's width for the game window's aspect, landscape, even. The render
   resolution stays separate from the presentation size; the drawable follows the view. */
static inline int halopad_xbox_display_width(double width, double height)
{
    double longer = fmax(width, height), shorter = fmin(width, height);
    return shorter > 0 ? (int)(480.0 * longer / shorter) & ~1 : 640;
}
#endif
