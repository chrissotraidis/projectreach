/*
 * xg_sdl.c: SDL3 and OpenGL ES services for the Xbox engine's guest
 * (the host half of upstream's port/android/guest/runtime/guest_sdl.c).
 *
 * SDL objects are pointers here, so the guest sees small integer handles.
 * SDL_Event has the same 128-byte layout on both sides for every event the
 * platform layer reads, so events are written straight into guest memory.
 */
#include "xg_host.h"

#include <GLES3/gl32.h>
#include <SDL3/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

void xg_gl_load(void);

#define HANDLES 256
static void *handles[HANDLES];

static uint32_t handle_new(void *object)
{
	uint32_t index;
	if (!object)
		return 0;
	for (index = 1; index < HANDLES; index++)
		if (handles[index] == object)
			return index;
	for (index = 1; index < HANDLES; index++)
		if (!handles[index])
		{
			handles[index] = object;
			return index;
		}
	return 0;
}

static void *handle_get(uint32_t handle) { return handle < HANDLES ? handles[handle] : NULL; }

static void copy_out(uint32_t buffer, uint32_t size, const char *text)
{
	if (!size)
		return;
	strncpy(G(char *, buffer), text ? text : "", size - 1);
	G(char *, buffer)[size - 1] = 0;
}

int xh_host_sdl_init(uint32_t flags) { return SDL_Init(flags); }
int xh_host_sdl_set_hint(uint32_t name, uint32_t value) { return SDL_SetHint(G(const char *, name), GP(value)); }
void xh_host_sdl_get_error(uint32_t buffer, uint32_t size) { copy_out(buffer, size, SDL_GetError()); }
long long xh_host_sdl_ticks(void) { return (long long)SDL_GetTicks(); }
long long xh_host_sdl_thread_id(void) { return (long long)SDL_GetCurrentThreadID(); }

uint32_t xh_host_sdl_create_window(uint32_t title, int width, int height, long long flags)
{
	SDL_Window *window = SDL_CreateWindow(G(const char *, title), width, height, (SDL_WindowFlags)flags);
	int w = 0, h = 0;
	SDL_GetWindowSizeInPixels(window, &w, &h);
	xg_log("window %dx%d (flags 0x%llx): %dx%d pixels", width, height, flags, w, h);
	return handle_new(window);
}

void xh_host_sdl_window_size_in_pixels(uint32_t window, uint32_t width, uint32_t height)
{
	int w = 0, h = 0;
	SDL_GetWindowSizeInPixels(handle_get(window), &w, &h);
	if (width) *G(int *, width) = w;
	if (height) *G(int *, height) = h;
}

int xh_host_sdl_set_relative_mouse(uint32_t window, int enabled)
{
	return SDL_SetWindowRelativeMouseMode(handle_get(window), enabled != 0);
}

int xh_host_sdl_gl_set_attribute(int attribute, int value) { return SDL_GL_SetAttribute((SDL_GLAttr)attribute, value); }

uint32_t xh_host_sdl_gl_create_context(uint32_t window)
{
	SDL_GLContext context = SDL_GL_CreateContext(handle_get(window));
	if (!context)
	{
		xg_log("cannot create the OpenGL ES context: %s", SDL_GetError());
		return 0;
	}
	xg_gl_load();
	return handle_new(context);
}

int xh_host_sdl_gl_make_current(uint32_t window, uint32_t context)
{
	return SDL_GL_MakeCurrent(handle_get(window), handle_get(context));
}

int xh_host_sdl_gl_set_swap_interval(int interval) { return SDL_GL_SetSwapInterval(interval); }
void xg_gl_frame_dump(int width, int height);

int xh_host_sdl_gl_swap_window(uint32_t window)
{
	int width = 0, height = 0;
	SDL_GetWindowSizeInPixels(handle_get(window), &width, &height);
	xg_gl_frame_dump(width, height);
	return SDL_GL_SwapWindow(handle_get(window));
}
int xh_host_sdl_poll_event(uint32_t event) { return SDL_PollEvent(G(SDL_Event *, event)); }
/* the game puts its internet invite link on the clipboard at start-up and
 * joins any link it finds there; HaloPad keeps the player's clipboard out of
 * it until invites have a proper place in the app */
int xh_host_sdl_set_clipboard_text(uint32_t text) { (void)text; return 1; }

void xh_host_sdl_get_clipboard_text(uint32_t buffer, uint32_t size)
{
	copy_out(buffer, size, "");
}

/* keyboard binding names (upstream build 85, xinput_sdl.c) */
void xh_host_sdl_scancode_name(int scancode, uint32_t buffer, uint32_t size)
{
	copy_out(buffer, size, SDL_GetScancodeName((SDL_Scancode)scancode));
}
int xh_host_sdl_scancode_from_name(uint32_t name)
{
	return name ? (int)SDL_GetScancodeFromName(G(const char *, name)) : 0;
}

int xh_host_sdl_show_toast(uint32_t message, int duration, int gravity, int x, int y)
{
	(void)duration; (void)gravity; (void)x; (void)y;
	xg_log("%s", G(const char *, message));
	return 1;
}

int xh_host_sdl_show_simple_message_box(uint32_t flags, uint32_t title, uint32_t message)
{
	xg_log("message: %s: %s", G(const char *, title), G(const char *, message));
	return SDL_ShowSimpleMessageBox(flags, G(const char *, title), G(const char *, message), NULL);
}

int xh_host_sdl_get_gamepads(uint32_t ids, int capacity)
{
	int count = 0, index;
	SDL_JoystickID *list = SDL_GetGamepads(&count);
	for (index = 0; index < count && index < capacity; index++)
		G(uint32_t *, ids)[index] = list[index];
	SDL_free(list);
	return index;
}

uint32_t xh_host_sdl_open_gamepad(uint32_t id) { return handle_new(SDL_OpenGamepad(id)); }
uint32_t xh_host_sdl_gamepad_from_id(uint32_t id) { return handle_new(SDL_GetGamepadFromID(id)); }
int xh_host_sdl_gamepad_axis(uint32_t pad, int axis) { return SDL_GetGamepadAxis(handle_get(pad), (SDL_GamepadAxis)axis); }
int xh_host_sdl_gamepad_button(uint32_t pad, int button) { return SDL_GetGamepadButton(handle_get(pad), (SDL_GamepadButton)button); }

/* Desktop has no HaloPad touch surface; hardware retains upstream bindings. */
void xh_host_halopad_input_context_v1(uint32_t menu, uint32_t low, uint32_t high, uint32_t sticks)
{
    (void)menu; (void)low; (void)high; (void)sticks;
}

/* Desktop test host: upstream's exact network rule (no HaloPad policy). */
uint32_t xh_host_halopad_network_announce_v1(uint32_t built_in) { return built_in; }
uint32_t xh_host_halopad_network_accepts_v1(uint32_t built_in, uint32_t theirs) { return theirs == built_in; }
int xh_host_sdl_gamepad_type(uint32_t pad) { return SDL_GetGamepadType(handle_get(pad)); }

int xh_host_sdl_rumble_gamepad(uint32_t pad, uint32_t low, uint32_t high, uint32_t milliseconds)
{
	return SDL_RumbleGamepad(handle_get(pad), (Uint16)low, (Uint16)high, milliseconds);
}

/* ---------- audio: SDL's callback runs the guest's on SDL's audio thread,
 * switched to a guest stack by xg_enter; SDL's stream lock is recursive, so
 * the guest may put data into the stream from inside the callback */

struct audio { uint32_t callback, userdata, handle; };

static void SDLCALL audio_callback(void *context, SDL_AudioStream *stream, int additional, int total)
{
	struct audio *audio = context;
	(void)stream;
	xg_enter(audio->callback, audio->userdata, audio->handle, (uint32_t)additional, (uint32_t)total);
}

uint32_t xh_host_sdl_open_audio_stream(uint32_t device, uint32_t spec, uint32_t callback, uint32_t userdata)
{
	struct audio *audio = SDL_calloc(1, sizeof(*audio));
	SDL_AudioStream *stream;
	audio->callback = callback;
	audio->userdata = userdata;
	stream = SDL_OpenAudioDeviceStream(device, G(const SDL_AudioSpec *, spec), callback ? audio_callback : NULL, audio);
	if (!stream)
	{
		xg_log("cannot open audio: %s", SDL_GetError());
		return 0;
	}
	audio->handle = handle_new(stream);
	return audio->handle;
}

int xh_host_sdl_put_audio_stream_data(uint32_t stream, uint32_t data, int length)
{
	return SDL_PutAudioStreamData(handle_get(stream), G(const void *, data), length);
}

int xh_host_sdl_resume_audio_stream_device(uint32_t stream) { return SDL_ResumeAudioStreamDevice(handle_get(stream)); }

/* ---------- OpenGL ES functions for xg_gl.c and the generated wrappers */

void *xg_gl_proc(const char *name) { return (void *)SDL_GL_GetProcAddress(name); }
GLuint xg_gl_framebuffer(GLuint framebuffer) { return framebuffer; }
