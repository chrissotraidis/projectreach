/* Display sizes the iOS hosts hand their engines (port/apple/halopad_display_geometry.h). */
#include <stdio.h>
#include "../port/apple/halopad_display_geometry.h"

static int failures;
static void expect(int ok, const char *what) { if (!ok) { fprintf(stderr, "display geometry: %s\n", what); failures++; } }

int main(void)
{
    int32_t w, h;
    /* A full-screen landscape iPad window at its screen's native scale: the panel's pixels. */
    halopad_desktop_pixels(1194, 834, 2, &w, &h);
    expect(w == 2388 && h == 1668, "iPad window");
    /* Measured before the first landscape layout: still a landscape desktop. */
    halopad_desktop_pixels(402, 874, 3, &w, &h);
    expect(w == 2622 && h == 1206, "portrait-measured phone window");
    /* A resized window, or one on a 1x external display, gives that window's pixels. */
    halopad_desktop_pixels(900, 700, 2, &w, &h);
    expect(w == 1800 && h == 1400, "resized window");
    halopad_desktop_pixels(1920, 1080, 1, &w, &h);
    expect(w == 1920 && h == 1080, "1x display");
    /* Xbox: 480 lines at the window's shape, even width; presentation size is separate. */
    expect(halopad_xbox_display_width(1194, 834) == 686, "iPad aspect");
    expect(halopad_xbox_display_width(874, 402) == 1042, "phone aspect");
    expect(halopad_xbox_display_width(800, 600) == 640, "4:3 window");
    expect(halopad_xbox_display_width(0, 0) == 640, "unmeasured window");
    if (failures) return 1;
    puts("display geometry tests passed");
    return 0;
}
