/*
 * xg_ios.m: the Xbox engine's platform services on iOS and iPadOS, without
 * SDL: the host half of upstream's guest_sdl.c on UIKit, OpenGL ES (Apple by
 * default; opt-in preview ANGLE/Metal), GameController and Core Audio.
 *
 * The game runs on a thread of its own (xg_ios_start); the view is made on
 * the main thread by the app. EAGL maps framebuffer 0 to the layer-backed
 * colour buffer (xg_gl_framebuffer); EGL owns its own default framebuffer.
 */
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>
#if XG_USE_ANGLE
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES3/gl3.h>
#else
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#endif
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#include <TargetConditionals.h>
#include <SDL3/SDL_events.h>
#include <SDL3/SDL_gamepad.h>
#include <SDL3/SDL_audio.h>
#include <dlfcn.h>
#include <crt_externs.h>
#include <mach/mach_time.h>
#include <pthread.h>
#include <math.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include "xg_host.h"
#include "xg_ios.h"
#include "xg_scancode_names.h"
#if TARGET_OS_SIMULATOR
#include "xg_audio_capture.h"
static void audio_capture_flush(void);
#endif

void xg_gl_load(void);
void xg_gl_frame_dump(int width, int height);

struct xg_paths xg_paths;

/* ---------- the view */

@interface XGGameView : UIView
@end

@implementation XGGameView
+ (Class)layerClass {
#if XG_USE_ANGLE
    return [CAMetalLayer class];
#else
    return [CAEAGLLayer class];
#endif
}
@end

static XGGameView *game_view;
#if XG_USE_ANGLE
static CAMetalLayer *game_layer;
static EGLDisplay angle_display = EGL_NO_DISPLAY;
static EGLContext angle_context = EGL_NO_CONTEXT;
static EGLSurface angle_surface = EGL_NO_SURFACE;
#else
static CAEAGLLayer *game_layer;
static EAGLContext *context;
#endif
static GLuint drawable_framebuffer, drawable_color;
static GLint drawable_width, drawable_height;
static CGSize layer_pixels;
static pthread_mutex_t layer_lock = PTHREAD_MUTEX_INITIALIZER;

UIView *xg_ios_make_view(CGRect frame)
{
	game_view = [[XGGameView alloc] initWithFrame:frame];
	/* Apple's software renderer on the Simulator needs only point resolution.
	 * Physical devices retain their native pixel resolution. */
	game_view.contentScaleFactor = TARGET_OS_SIMULATOR ? 1 : UIScreen.mainScreen.nativeScale;
	game_view.multipleTouchEnabled = YES;
	game_view.backgroundColor = UIColor.blackColor;
	game_layer = (id)game_view.layer;
	game_layer.opaque = YES;
#if XG_USE_ANGLE
    game_layer.framebufferOnly = NO;
#else
	game_layer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking: @NO,
		kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8 };
#endif
	xg_ios_view_resized();
	return game_view;
}

/* the main thread: the view's size in pixels, for the game thread */
void xg_ios_view_resized(void)
{
	CGSize size = game_view.bounds.size;
	CGFloat scale = game_view.contentScaleFactor;
	pthread_mutex_lock(&layer_lock);
	layer_pixels = CGSizeMake(size.width * scale, size.height * scale);
#if XG_USE_ANGLE
    game_layer.drawableSize = layer_pixels;
#endif
	pthread_mutex_unlock(&layer_lock);
}

static void drawable_update(void)
{
	CGSize pixels;
	pthread_mutex_lock(&layer_lock);
	pixels = layer_pixels;
	pthread_mutex_unlock(&layer_lock);
#if XG_USE_ANGLE
    /* EGL owns the window's default framebuffer. Do not emulate it with an
     * EAGL renderbuffer or mix APIs from two different GL implementations. */
    drawable_width = (GLint)pixels.width; drawable_height = (GLint)pixels.height;
#else
	if (drawable_color && (GLint)pixels.width == drawable_width && (GLint)pixels.height == drawable_height)
		return;
	if (!drawable_framebuffer)
	{
		glGenFramebuffers(1, &drawable_framebuffer);
		glGenRenderbuffers(1, &drawable_color);
	}
	glBindFramebuffer(GL_FRAMEBUFFER, drawable_framebuffer);
	glBindRenderbuffer(GL_RENDERBUFFER, drawable_color);
	[context renderbufferStorage:GL_RENDERBUFFER fromDrawable:game_layer];
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, drawable_color);
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &drawable_width);
	glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &drawable_height);
	xg_log("drawable %dx%d", drawable_width, drawable_height);
#endif
}

/* Isolated driver test before the guest has any GL state. No game assets.
 * Compare transparent/opaque RGBA8 sources, filters and row reversal on a
 * texture target versus the actual drawable. Enabled only by XG_BLIT_PROBE. */
static void blit_probe(void)
{
	if (!getenv("XG_BLIT_PROBE")) return;
	GLuint textures[2], buffers[2];
	const int width = 640, height = 480;
	unsigned char *pixels = malloc(width * height * 4);
	if (!pixels) return;
	glGenTextures(2, textures);
	glGenFramebuffers(2, buffers);
	for (int i = 0; i < 2; i++) {
		glBindTexture(GL_TEXTURE_2D, textures[i]);
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, width, height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
		glBindFramebuffer(GL_FRAMEBUFFER, buffers[i]);
		glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, textures[i], 0);
	}
	for (int alpha = 0; alpha <= 255; alpha += 255) {
		for (int i = 0; i < width * height; i++) {
			pixels[i * 4] = 255; pixels[i * 4 + 1] = 32;
			pixels[i * 4 + 2] = 0; pixels[i * 4 + 3] = alpha;
		}
		glBindTexture(GL_TEXTURE_2D, textures[0]);
		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
		for (int target = 0; target < 2; target++)
		for (int cull = 0; cull < 2; cull++)
		for (int flip = 0; flip < 2; flip++)
		for (int linear = 0; linear < 2; linear++) {
			GLuint draw = target ? drawable_framebuffer : buffers[1];
			int w = target ? drawable_width : width, h = target ? drawable_height : height;
			unsigned char pixel[4] = { 0 };
			if (cull) glEnable(GL_CULL_FACE); else glDisable(GL_CULL_FACE);
			glFrontFace(GL_CW);
			glBindFramebuffer(GL_DRAW_FRAMEBUFFER, draw);
			glClearColor(0, 1, 0, 1);
			glClear(GL_COLOR_BUFFER_BIT);
			glBindFramebuffer(GL_READ_FRAMEBUFFER, buffers[0]);
			glBlitFramebuffer(0, 0, width, height, 0, flip ? h : 0, w, flip ? 0 : h,
				GL_COLOR_BUFFER_BIT, linear ? GL_LINEAR : GL_NEAREST);
			GLenum error = glGetError();
			glBindFramebuffer(GL_READ_FRAMEBUFFER, draw);
			glReadPixels(w / 2, h / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
			xg_log("blit probe: alpha %d target %s cull %d flip %d linear %d => %d %d %d %d, blit error 0x%x read error 0x%x",
				alpha, target ? "drawable" : "texture", cull, flip, linear,
				pixel[0], pixel[1], pixel[2], pixel[3], error, glGetError());
		}
	}
	glBindFramebuffer(GL_FRAMEBUFFER, drawable_framebuffer);
	glDisable(GL_CULL_FACE);
	glFrontFace(GL_CCW);
	glBindTexture(GL_TEXTURE_2D, 0);
	glClearColor(0, 0, 0, 0);
	glDeleteFramebuffers(2, buffers);
	glDeleteTextures(2, textures);
	free(pixels);
}

#if TARGET_OS_SIMULATOR
/* Asset-free depth control before guest GL state exists. The same invariant
 * position is linked with and without an active varying. This distinguishes a
 * basic EQUAL failure from the game's converted shaders/depth state. */
static void depth_probe(void)
{
	if (!getenv("XG_DEPTH_PROBE")) return;
	const char *sources[] = {
		"#version 300 es\nprecision highp float;\nlayout(location=0) in vec4 p; out vec2 v; invariant gl_Position;\nvoid main(){gl_Position=p;v=p.xy;}\n",
		"#version 300 es\nprecision highp float;\nuniform vec4 color;out vec4 c;void main(){c=color;}\n",
		"#version 300 es\nprecision highp float;\nin vec2 v;uniform vec4 color;out vec4 c;void main(){c=color+vec4(v.x*0.01,0,0,0);}\n"
	};
	GLuint shaders[3] = { 0 }, programs[2] = { 0 }, texture = 0, depth = 0, framebuffer = 0, vao = 0, buffer = 0;
	GLint viewport[4];
	glGetIntegerv(GL_VIEWPORT, viewport);
	for (int i = 0; i < 3; i++) {
		GLint okay = 0;
		shaders[i] = glCreateShader(i ? GL_FRAGMENT_SHADER : GL_VERTEX_SHADER);
		glShaderSource(shaders[i], 1, &sources[i], NULL);
		glCompileShader(shaders[i]);
		glGetShaderiv(shaders[i], GL_COMPILE_STATUS, &okay);
		if (!okay) { xg_log("depth probe: shader %d failed", i); goto cleanup; }
	}
	for (int i = 0; i < 2; i++) {
		GLint okay = 0;
		programs[i] = glCreateProgram();
		glAttachShader(programs[i], shaders[0]);
		glAttachShader(programs[i], shaders[i + 1]);
		glLinkProgram(programs[i]);
		glGetProgramiv(programs[i], GL_LINK_STATUS, &okay);
		if (!okay) { xg_log("depth probe: program %d failed", i); goto cleanup; }
	}
	glGenTextures(1, &texture);
	glBindTexture(GL_TEXTURE_2D, texture);
	glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 128, 128, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
	glGenRenderbuffers(1, &depth);
	glBindRenderbuffer(GL_RENDERBUFFER, depth);
	glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, 128, 128);
	glGenFramebuffers(1, &framebuffer);
	glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
	glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, texture, 0);
	glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, depth);
	GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
	if (status != GL_FRAMEBUFFER_COMPLETE) { xg_log("depth probe: framebuffer 0x%x", status); goto cleanup; }
	const GLfloat vertices[] = { -.9f,-.9f,-.7f,1, 1.8f,-1.8f,.8f,2, 0,3.6f,3.2f,4 };
	glGenVertexArrays(1, &vao);
	glBindVertexArray(vao);
	glGenBuffers(1, &buffer);
	glBindBuffer(GL_ARRAY_BUFFER, buffer);
	glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
	glEnableVertexAttribArray(0);
	glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, 0, NULL);
	glViewport(0, 0, 128, 128);
	glEnable(GL_DEPTH_TEST);
	unsigned char base[128 * 128 * 4], second[128 * 128 * 4];
	for (int i = 0; i < 2; i++) {
		glDepthMask(GL_TRUE);
		glClearColor(0, 0, 0, 1);
		glClearDepthf(1);
		glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
		glDepthFunc(GL_LEQUAL);
		glUseProgram(programs[0]);
		glUniform4f(glGetUniformLocation(programs[0], "color"), 1, .125f, 0, 1);
		glDrawArrays(GL_TRIANGLES, 0, 3);
		glReadPixels(0, 0, 128, 128, GL_RGBA, GL_UNSIGNED_BYTE, base);
		glDepthMask(GL_FALSE);
		glDepthFunc(GL_EQUAL);
		glUseProgram(programs[i]);
		glUniform4f(glGetUniformLocation(programs[i], "color"), 0, 0, 1, 1);
		glDrawArrays(GL_TRIANGLES, 0, 3);
		glReadPixels(0, 0, 128, 128, GL_RGBA, GL_UNSIGNED_BYTE, second);
		int covered = 0, failed = 0;
		for (int p = 0; p < 128 * 128; p++) if (base[p * 4] > 200) {
			covered++;
			if (second[p * 4 + 2] < 200) failed++;
		}
		xg_log("depth probe: %s covered %d failed %d error 0x%x", i ? "separate-program" : "same-program", covered, failed, glGetError());
	}
cleanup:
	glUseProgram(0);
	glBindVertexArray(0);
	glBindBuffer(GL_ARRAY_BUFFER, 0);
	glBindTexture(GL_TEXTURE_2D, 0);
	glBindRenderbuffer(GL_RENDERBUFFER, drawable_color);
	glBindFramebuffer(GL_FRAMEBUFFER, drawable_framebuffer);
	glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
	glDepthFunc(GL_LESS);
	glDepthMask(GL_TRUE);
	glDisable(GL_DEPTH_TEST);
	glClearColor(0, 0, 0, 0);
	glDeleteBuffers(1, &buffer);
	glDeleteVertexArrays(1, &vao);
	glDeleteFramebuffers(1, &framebuffer);
	glDeleteRenderbuffers(1, &depth);
	glDeleteTextures(1, &texture);
	for (int i = 0; i < 2; i++) if (programs[i]) glDeleteProgram(programs[i]);
	for (int i = 0; i < 3; i++) if (shaders[i]) glDeleteShader(shaders[i]);
}

/* Apple's software blitter is sensitive to texture-unit/sampler state, although ES
 * blits must ignore it. A campaign source was visible while the drawable was
 * black. Neutralizing unit 0 alone restores it; blend/cull/program A/Bs did not.
 * Only presentation needs this workaround. Restore the game's state afterward. */
#if !XG_USE_ANGLE
static void presentation_blit(GLint x0, GLint y0, GLint x1, GLint y1,
	GLint x2, GLint y2, GLint x3, GLint y3, GLbitfield mask, GLenum filter)
{
	GLint draw = 0;
	glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &draw);
	GLint active = 0, sampler = 0;
	BOOL presenting = (GLuint)draw == drawable_framebuffer;
	if (presenting) {
		glGetIntegerv(GL_ACTIVE_TEXTURE, &active);
		glActiveTexture(GL_TEXTURE0);
		glGetIntegerv(GL_SAMPLER_BINDING, &sampler);
		glBindSampler(0, 0);
	}
	glBlitFramebuffer(x0, y0, x1, y1, x2, y2, x3, y3, mask, filter);
	if (presenting) {
		glBindSampler(0, (GLuint)sampler);
		glActiveTexture((GLenum)active);
	}
}
#endif
#endif

#if TARGET_OS_SIMULATOR
/* Isolated A/B only: distinguish failed equal-depth passes from sampling.
 * Never a normal player workaround; relaxed comparisons alter occlusion. */
static int diagnostic_depth_mode = -1;
static GLenum diagnostic_requested_depth = GL_LESS;
static void diagnostic_depth_func(GLenum function)
{
	static int reported;
	diagnostic_requested_depth = function;
	if (diagnostic_depth_mode < 0) {
		const char *value = getenv("XG_DEPTH_COMPARE");
		diagnostic_depth_mode = value && !strcmp(value, "paired") ? 0 :
			value && !strcmp(value, "always") ? 2 : 1;
		xg_log("depth comparison diagnostic: %s", diagnostic_depth_mode == 0 ? "paired, native EQUAL" :
			diagnostic_depth_mode == 2 ? "EQUAL to ALWAYS" : "EQUAL to LEQUAL");
	}
	if (function == GL_EQUAL && diagnostic_depth_mode) {
		if (!reported++) xg_log("depth comparison diagnostic: replaced an EQUAL call");
		function = diagnostic_depth_mode == 2 ? GL_ALWAYS : GL_LEQUAL;
	}
	glDepthFunc(function);
}

/* Switch only between complete frames, reapplying the guest's requested state
 * even if its renderer caches GL_EQUAL and does not issue it again. The runner
 * owns this private control file; normal runs never read it. */
static void diagnostic_depth_tick(void)
{
	const char *mode = getenv("XG_DEPTH_COMPARE"), *prefix = getenv("XG_GL_TRACE");
	static CFTimeInterval next;
	if (!mode || strcmp(mode, "paired") || !prefix || !*prefix || diagnostic_depth_mode < 0) return;
	CFTimeInterval now = CACurrentMediaTime();
	if (now < next) return;
	next = now + 1;
	char path[1024], value[32] = { 0 };
	snprintf(path, sizeof(path), "%s.depth-mode", prefix);
	FILE *file = fopen(path, "r");
	if (!file) return;
	fscanf(file, "%31s", value);
	fclose(file);
	if (strcmp(value, "equal") && strcmp(value, "always")) return;
	int wanted = !strcmp(value, "always") ? 2 : 0;
	if (wanted != diagnostic_depth_mode) {
		diagnostic_depth_mode = wanted;
		xg_log("paired depth mode: %s", value);
		diagnostic_depth_func(diagnostic_requested_depth);
	}
}
#endif

void *xg_gl_proc(const char *name)
{
#if TARGET_OS_SIMULATOR
	void *xg_draw_capture_proc(const char *);
	void *capture = xg_draw_capture_proc(name);
	if (capture) return capture;
	const char *comparison = getenv("XG_DEPTH_COMPARE");
	if (comparison && (!strcmp(comparison, "lequal") || !strcmp(comparison, "always") || !strcmp(comparison, "paired")) &&
		!strcmp(name, "glDepthFunc"))
		return diagnostic_depth_func;
	/* Raw path is retained only for isolated diagnostic A/Bs. */
#if !XG_USE_ANGLE
	if (!getenv("XG_PRESENT_RAW_BLIT") && !strcmp(name, "glBlitFramebuffer"))
		return presentation_blit;
#endif
#endif
#if XG_USE_ANGLE
    return (void *)eglGetProcAddress(name);
#else
	return dlsym(RTLD_DEFAULT, name);
#endif
}
GLuint xg_gl_framebuffer(GLuint framebuffer) { return framebuffer ? framebuffer : drawable_framebuffer; }

/* ---------- SDL services */

static char last_error[256];
static uint64_t start_ticks;

static void copy_out(uint32_t buffer, uint32_t size, const char *text)
{
	if (!size)
		return;
	strlcpy(G(char *, buffer), text ? text : "", size);
}

int xh_host_sdl_init(uint32_t flags) { (void)flags; return 1; }
int xh_host_sdl_set_hint(uint32_t name, uint32_t value) { (void)name; (void)value; return 1; }
void xh_host_sdl_get_error(uint32_t buffer, uint32_t size) { copy_out(buffer, size, last_error); }

long long xh_host_sdl_ticks(void)
{
	static mach_timebase_info_data_t timebase;
	if (!timebase.denom)
		mach_timebase_info(&timebase);
	return (long long)((mach_absolute_time() - start_ticks) * timebase.numer / timebase.denom / 1000000ull);
}

long long xh_host_sdl_thread_id(void)
{
	uint64_t id;
	pthread_threadid_np(NULL, &id);
	return (long long)id;
}

uint32_t xh_host_sdl_create_window(uint32_t title, int width, int height, long long flags)
{
	(void)title; (void)width; (void)height; (void)flags;
	return game_view ? 1 : 0;
}

void xh_host_sdl_window_size_in_pixels(uint32_t window, uint32_t width, uint32_t height)
{
	(void)window;
	if (width) *G(int *, width) = drawable_width;
	if (height) *G(int *, height) = drawable_height;
}

int xh_host_sdl_set_relative_mouse(uint32_t window, int enabled) { (void)window; (void)enabled; return 1; }
int xh_host_sdl_gl_set_attribute(int attribute, int value) { (void)attribute; (void)value; return 1; }

uint32_t xh_host_sdl_gl_create_context(uint32_t window)
{
	(void)window;
#if XG_USE_ANGLE
    if (angle_context == EGL_NO_CONTEXT) {
#if TARGET_OS_SIMULATOR
        /* ANGLE disables sampling swizzles on Simulator by default. Its native
         * path passes the asset-free probe on this Mac/iPadOS 26.5; without it
         * the guest's BGRA textures display with red/blue reversed. This remains
         * an opt-in Simulator candidate, never a physical-device override. */
        const char *features[] = {"hasTextureSwizzle", NULL};
        const EGLAttrib attributes[] = {EGL_PLATFORM_ANGLE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE,
            EGL_FEATURE_OVERRIDES_ENABLED_ANGLE, (EGLAttrib)features, EGL_NONE};
#else
        /* Hardware feature support is detected by pinned ANGLE, not inferred
         * from a Simulator probe or overridden before device validation. */
        const EGLAttrib attributes[] = {EGL_PLATFORM_ANGLE_TYPE_ANGLE, EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE,
            EGL_NONE};
#endif
        angle_display = eglGetPlatformDisplay(EGL_PLATFORM_ANGLE_ANGLE, NULL, attributes);
        EGLint major = 0, minor = 0, count = 0;
        EGLConfig config;
        const EGLint config_attributes[] = {EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
            EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE};
        const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE};
        if (!eglInitialize(angle_display, &major, &minor) ||
            !eglChooseConfig(angle_display, config_attributes, &config, 1, &count) || count != 1) goto angle_failure;
        angle_surface = eglCreateWindowSurface(angle_display, config, (__bridge void *)game_layer, NULL);
        angle_context = eglCreateContext(angle_display, config, EGL_NO_CONTEXT, context_attributes);
        if (angle_surface == EGL_NO_SURFACE || angle_context == EGL_NO_CONTEXT ||
            !eglMakeCurrent(angle_display, angle_surface, angle_surface, angle_context)) goto angle_failure;
#if TARGET_OS_SIMULATOR
        xg_log("ANGLE/Metal Simulator candidate: native texture swizzle enabled");
#else
        xg_log("ANGLE/Metal device candidate: automatic native feature detection");
#endif
        drawable_update(); blit_probe();
#if TARGET_OS_SIMULATOR
        depth_probe();
        void xg_draw_replay(void); xg_draw_replay();
#endif
        xg_gl_load();
    }
    return 2;
angle_failure:
    snprintf(last_error, sizeof(last_error), "ANGLE/Metal context failed: EGL 0x%x", eglGetError());
    xg_log("%s", last_error);
    if (angle_context != EGL_NO_CONTEXT) eglDestroyContext(angle_display, angle_context);
    if (angle_surface != EGL_NO_SURFACE) eglDestroySurface(angle_display, angle_surface);
    eglTerminate(angle_display); angle_context = EGL_NO_CONTEXT; angle_surface = EGL_NO_SURFACE;
    return 0;
#else
	if (!context)
	{
		context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
		if (!context)
		{
			strlcpy(last_error, "OpenGL ES 3 is not available", sizeof(last_error));
			return 0;
		}
		[EAGLContext setCurrentContext:context];
		drawable_update();
		blit_probe();
#if TARGET_OS_SIMULATOR
		depth_probe();
		void xg_draw_replay(void);
		xg_draw_replay();
#endif
		xg_gl_load();
	}
	return 2;
#endif
}

int xh_host_sdl_gl_make_current(uint32_t window, uint32_t handle)
{
	(void)window;
#if XG_USE_ANGLE
    return eglMakeCurrent(angle_display, handle ? angle_surface : EGL_NO_SURFACE,
        handle ? angle_surface : EGL_NO_SURFACE, handle ? angle_context : EGL_NO_CONTEXT);
#else
	return [EAGLContext setCurrentContext:handle ? context : nil];
#endif
}

int xh_host_sdl_gl_set_swap_interval(int interval) {
#if XG_USE_ANGLE
    return eglSwapInterval(angle_display, interval);
#else
    (void)interval; return 1;
#endif
}

/* Renderer health for the shareable log: GL errors (the first twenty, then
 * counted), frames slower than a quarter second, and a summary every thirty
 * seconds. Main-thread presentation only; costs one glGetError per frame. */
static atomic_int presented_frames;

int xg_ios_frames_presented(void) { return atomic_load(&presented_frames); }

static void render_health(int frame)
{
	static double window_start, last, worst;
	static int window_frames, slow, errors, reported_errors, hitches;
	static struct xg_gl_cost frame_start[4], window_base[4];
	struct xg_gl_cost in_frame[4];
	double now = CACurrentMediaTime();
	GLenum error;
	for (int kind = 0; kind < 4; kind++)
	{
		in_frame[kind].count = xg_gl_costs[kind].count - frame_start[kind].count;
		in_frame[kind].seconds = xg_gl_costs[kind].seconds - frame_start[kind].seconds;
		frame_start[kind] = xg_gl_costs[kind];
	}
	for (int guard = 0; guard < 8 && (error = glGetError()) != GL_NO_ERROR; guard++)
	{
		errors++;
		if (reported_errors < 20 && ++reported_errors)
			xg_log("render: GL error 0x%x before frame %d%s", error, frame,
				reported_errors == 20 ? " (later errors are only counted)" : "");
	}
	if (last > 0)
	{
		double ms = (now - last) * 1000;
		if (ms > worst) worst = ms;
		if (ms > 50) slow++;
		/* what a slow frame spent in GL calls that can stall (shaders, textures, buffers) */
		if (ms > 50 && hitches < 60 && ++hitches)
			xg_log("render: frame %d took %.0f ms; %u draws (%.0f ms), %u shader compiles/links (%.0f ms), "
				"%u texture uploads (%.0f ms), %u buffer uploads (%.0f ms)%s", frame, ms,
				in_frame[3].count, in_frame[3].seconds * 1000, in_frame[0].count, in_frame[0].seconds * 1000,
				in_frame[1].count, in_frame[1].seconds * 1000, in_frame[2].count, in_frame[2].seconds * 1000,
				hitches == 60 ? " (later slow frames are only counted)" : "");
	}
	if (window_start == 0) window_start = now;
	window_frames++;
	last = now;
	if (now - window_start >= 30)
	{
		xg_log("render: %.1f fps over %.0f s, worst frame %.0f ms, %d frames over 50 ms, %d GL errors, drawable %dx%d; "
			"%u shader compiles/links (%.0f ms), %u texture uploads (%.0f ms), %u buffer uploads (%.0f ms)",
			window_frames / (now - window_start), now - window_start, worst, slow, errors, drawable_width, drawable_height,
			xg_gl_costs[0].count - window_base[0].count, (xg_gl_costs[0].seconds - window_base[0].seconds) * 1000,
			xg_gl_costs[1].count - window_base[1].count, (xg_gl_costs[1].seconds - window_base[1].seconds) * 1000,
			xg_gl_costs[2].count - window_base[2].count, (xg_gl_costs[2].seconds - window_base[2].seconds) * 1000);
		for (int kind = 0; kind < 4; kind++) window_base[kind] = xg_gl_costs[kind];
		window_start = now;
		window_frames = slow = errors = 0;
		worst = 0;
	}
}

int xh_host_sdl_gl_swap_window(uint32_t window)
{
	static int frames;
	(void)window;
	if (frames == 0)
		xg_log("renderer: %s | %s | %s", (const char *)glGetString(GL_VENDOR), (const char *)glGetString(GL_RENDERER),
			(const char *)glGetString(GL_VERSION));
	if (frames < 3 || frames == 120)
	{
		GLint read = 0, draw = 0;
		unsigned char pixel[4] = { 0 };
		glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read);
		glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &draw);
		glBindFramebuffer(GL_READ_FRAMEBUFFER, drawable_framebuffer);
		glReadPixels(drawable_width / 2, drawable_height / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
		xg_log("frame %d: error 0x%x, status 0x%x, read %d draw %d (drawable %u), centre %d %d %d", frames,
			glGetError(), glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER), read, draw, drawable_framebuffer,
			pixel[0], pixel[1], pixel[2]);
	}
	render_health(frames);
	frames++;
	atomic_store(&presented_frames, frames);
#if TARGET_OS_SIMULATOR
	void xg_draw_capture_present(void);
	xg_draw_capture_present();
	audio_capture_flush();
#endif
	glBindFramebuffer(GL_READ_FRAMEBUFFER, drawable_framebuffer);
	xg_gl_frame_dump(drawable_width, drawable_height);
#if XG_USE_ANGLE
    if (!eglSwapBuffers(angle_display, angle_surface)) return 0;
#else
	glBindRenderbuffer(GL_RENDERBUFFER, drawable_color);
	[context presentRenderbuffer:GL_RENDERBUFFER];
#endif
	drawable_update();
#if TARGET_OS_SIMULATOR
	diagnostic_depth_tick();
#endif
	return 1;
}

int xh_host_sdl_set_clipboard_text(uint32_t text) { (void)text; return 1; }
void xh_host_sdl_get_clipboard_text(uint32_t buffer, uint32_t size) { copy_out(buffer, size, ""); }

/* keyboard binding names (upstream build 85, xinput_sdl.c) */
void xh_host_sdl_scancode_name(int scancode, uint32_t buffer, uint32_t size)
{
	copy_out(buffer, size, xg_scancode_name(scancode));
}
int xh_host_sdl_scancode_from_name(uint32_t name) { return xg_scancode_from_name(name ? G(const char *, name) : NULL); }

int xh_host_sdl_show_toast(uint32_t message, int duration, int gravity, int x, int y)
{
	(void)duration; (void)gravity; (void)x; (void)y;
	xg_log("%s", G(const char *, message));
	return 1;
}

int xh_host_sdl_show_simple_message_box(uint32_t flags, uint32_t title, uint32_t message)
{
	(void)flags;
	xg_log("message: %s: %s", G(const char *, title), G(const char *, message));
	return 1;
}

/* ---------- gamepads
 * Slot 1 is always connected: it is the touch gamepad (xg_touch.m) merged with
 * the first game controller, so player 1 can use either. More controllers
 * take slots 2 to 8 (split screen). Slots are the gamepads' ids and handles. */

#define PADS 8
static __strong GCController *pads[PADS + 1];
static uint8_t pad_announced[PADS + 1];
static pthread_mutex_t pad_lock = PTHREAD_MUTEX_INITIALIZER;
static struct xg_touch_input touch_input;
#include "xg_profile_input.h"
static struct xg_profile_input touch_profile;
static float touch_look_x, touch_look_y;
#include "xg_scoreboard_input.h"
static struct xg_scoreboard_input touch_scoreboard;

void xh_host_halopad_input_context_v1(uint32_t menu, uint32_t low, uint32_t high, uint32_t sticks)
{
	pthread_mutex_lock(&pad_lock);
	if (xg_profile_context(&touch_profile, &touch_input, menu, low, high, sticks)) {
		touch_look_x = touch_look_y = 0;
		xg_scoreboard_clear(&touch_scoreboard);
		fprintf(stderr, "[xbox] touch context v1 menu=%u mapping=%08x:%04x sticks=%u valid=%d\n",
			menu, low, high, sticks, touch_profile.valid);
	}
	pthread_mutex_unlock(&pad_lock);
}

/* ---------- HaloPad network policy v1 (scripts/xbox/network_bridge.py) */

#include "xg_network_policy.h"
static struct xg_network_policy network_policy;
static atomic_int network_policy_logged;

int xg_ios_set_network_policy(unsigned int engine, unsigned int announce, unsigned int minimum, unsigned int maximum)
{
	return xg_network_policy_set(&network_policy, engine, announce, minimum, maximum);
}

uint32_t xh_host_halopad_network_announce_v1(uint32_t built_in)
{
	uint32_t announced = xg_network_policy_announce(&network_policy, built_in);
	if (announced != built_in && !atomic_exchange(&network_policy_logged, 1))
		xg_log("network policy: network version %u announces compatible version %u", built_in, announced);
	return announced;
}

uint32_t xh_host_halopad_network_accepts_v1(uint32_t built_in, uint32_t theirs)
{
	return (uint32_t)xg_network_policy_accepts(&network_policy, built_in, theirs);
}

void xg_ios_scroll_scoreboard(float points)
{
	pthread_mutex_lock(&pad_lock);
	if (touch_input.current.buttons & (1u << SDL_GAMEPAD_BUTTON_BACK))
		xg_scoreboard_drag(&touch_scoreboard, points);
	pthread_mutex_unlock(&pad_lock);
}

void xg_ios_add_touch_look(float dx, float dy)
{
	pthread_mutex_lock(&pad_lock);
	if (isfinite(dx) && isfinite(dy)) { touch_look_x += dx; touch_look_y += dy; }
	pthread_mutex_unlock(&pad_lock);
}

/* ---------- a hardware keyboard and mouse, queued as SDL events for poll_event */

#define HW_EVENTS 128
static SDL_Event hw_events[HW_EVENTS];
static unsigned hw_head, hw_tail;

static void hw_push(const SDL_Event *e)
{
	pthread_mutex_lock(&pad_lock);
	if (hw_tail - hw_head < HW_EVENTS) hw_events[hw_tail++ % HW_EVENTS] = *e;
	pthread_mutex_unlock(&pad_lock);
}

static SDL_Keycode hw_keycode(int scancode)
{
	if (scancode >= SDL_SCANCODE_A && scancode <= SDL_SCANCODE_Z) return 'a' + (scancode - SDL_SCANCODE_A);
	if (scancode >= SDL_SCANCODE_1 && scancode <= SDL_SCANCODE_9) return '1' + (scancode - SDL_SCANCODE_1);
	switch (scancode)
	{
	case SDL_SCANCODE_0: return '0';
	case SDL_SCANCODE_RETURN: return SDLK_RETURN;
	case SDL_SCANCODE_ESCAPE: return SDLK_ESCAPE;
	case SDL_SCANCODE_BACKSPACE: return SDLK_BACKSPACE;
	case SDL_SCANCODE_TAB: return SDLK_TAB;
	case SDL_SCANCODE_SPACE: return SDLK_SPACE;
	case SDL_SCANCODE_MINUS: return SDLK_MINUS;
	case SDL_SCANCODE_EQUALS: return SDLK_EQUALS;
	case SDL_SCANCODE_PERIOD: return SDLK_PERIOD;
	case SDL_SCANCODE_COMMA: return SDLK_COMMA;
	case SDL_SCANCODE_SLASH: return SDLK_SLASH;
	default: return SDL_SCANCODE_TO_KEYCODE(scancode);
	}
}

void xg_ios_key(int scancode, int down)
{
	if (scancode <= 0 || scancode >= SDL_SCANCODE_COUNT) return;
	SDL_Event e;
	memset(&e, 0, sizeof(e));
	e.key.type = down ? SDL_EVENT_KEY_DOWN : SDL_EVENT_KEY_UP;
	e.key.windowID = 1;
	e.key.scancode = (SDL_Scancode)scancode;
	e.key.key = hw_keycode(scancode);
	e.key.down = down;
	hw_push(&e);
}

void xg_ios_mouse_button(int button, int down)
{
	SDL_Event e;
	memset(&e, 0, sizeof(e));
	e.button.type = down ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
	e.button.windowID = 1;
	e.button.button = (Uint8)button;
	e.button.down = down;
	e.button.clicks = 1;
	hw_push(&e);
}

void xg_ios_mouse_wheel(float steps)
{
	if (!steps || !isfinite(steps)) return;
	SDL_Event e;
	memset(&e, 0, sizeof(e));
	e.wheel.type = SDL_EVENT_MOUSE_WHEEL;
	e.wheel.windowID = 1;
	e.wheel.y = steps;
	e.wheel.integer_y = steps > 0 ? 1 : -1;
	hw_push(&e);
}

/* Opt-in touch diagnostics: input values only, no player/profile data. */
static int touch_trace;

void xg_ios_set_touch_pad(const struct xg_touch_pad *state)
{
	pthread_mutex_lock(&pad_lock);
	if (touch_trace && (state->buttons != touch_input.current.buttons ||
		fabsf(state->axes[0] - touch_input.current.axes[0]) > 0.1f ||
		fabsf(state->axes[1] - touch_input.current.axes[1]) > 0.1f ||
		fabsf(state->axes[2] - touch_input.current.axes[2]) > 0.1f ||
		fabsf(state->axes[3] - touch_input.current.axes[3]) > 0.1f))
		fprintf(stderr, "[xbox] touch publish buttons=%x move=%.2f,%.2f look=%.2f,%.2f\n",
			state->buttons, state->axes[0], state->axes[1], state->axes[2], state->axes[3]);
	xg_profile_publish(&touch_profile, &touch_input, state);
	if (!(state->buttons & (1u << SDL_GAMEPAD_BUTTON_BACK))) xg_scoreboard_clear(&touch_scoreboard);
	pthread_mutex_unlock(&pad_lock);
}

void xg_ios_clear_touch_pad(void)
{
	pthread_mutex_lock(&pad_lock);
	if (touch_trace) fprintf(stderr, "[xbox] touch clear live-buttons=%x pending-buttons=%x\n",
		touch_input.current.buttons, touch_input.pending.buttons);
	xg_profile_cancel(&touch_profile, &touch_input);
	touch_look_x = touch_look_y = 0;
	xg_scoreboard_clear(&touch_scoreboard);
	pthread_mutex_unlock(&pad_lock);
}

int xg_ios_controller_connected(void)
{
	return pads[1] != nil;
}

static void pads_refresh(void)
{
	NSArray<GCController *> *controllers = GCController.controllers;
	int index;
	pthread_mutex_lock(&pad_lock);
	for (index = 1; index <= PADS; index++)
		if (pads[index] && ![controllers containsObject:pads[index]])
		{
			pads[index] = nil;
			if (index > 1)
				pad_announced[index] = 0;
		}
	for (GCController *controller in controllers)
	{
		int free_slot = 0, known = 0;
		if (!controller.extendedGamepad)
			continue;
		for (index = 1; index <= PADS; index++)
		{
			if (pads[index] == controller) known = 1;
			if (!pads[index] && !free_slot) free_slot = index;
		}
		if (!known && free_slot)
			pads[free_slot] = controller;
	}
	pthread_mutex_unlock(&pad_lock);
}

static int pad_connected(uint32_t id) { return id == 1 || (id <= PADS && pads[id]); }

int xh_host_sdl_get_gamepads(uint32_t ids, int capacity)
{
	int count = 0, index;
	pads_refresh();
	for (index = 1; index <= PADS && count < capacity; index++)
		if (pad_connected((uint32_t)index))
		{
			G(uint32_t *, ids)[count++] = (uint32_t)index;
			pad_announced[index] = 1;
		}
	return count;
}

uint32_t xh_host_sdl_open_gamepad(uint32_t id) { return pad_connected(id) ? id : 0; }
uint32_t xh_host_sdl_gamepad_from_id(uint32_t id) { return xh_host_sdl_open_gamepad(id); }

static int16_t axis_value(float value)
{
	float scaled = value * 32767.0f;
	return (int16_t)(scaled < -32768.0f ? -32768.0f : scaled > 32767.0f ? 32767.0f : scaled);
}

static float stronger(float a, float b) { return xg_touch_stronger(a, b); }

int xh_host_sdl_gamepad_axis(uint32_t pad, int axis)
{
	static float traced[6];
	GCExtendedGamepad *g = pad <= PADS ? pads[pad].extendedGamepad : nil;
	float values[6] = { 0 };
	if (g)
	{
		values[SDL_GAMEPAD_AXIS_LEFTX] = g.leftThumbstick.xAxis.value;
		values[SDL_GAMEPAD_AXIS_LEFTY] = -g.leftThumbstick.yAxis.value;
		values[SDL_GAMEPAD_AXIS_RIGHTX] = g.rightThumbstick.xAxis.value;
		values[SDL_GAMEPAD_AXIS_RIGHTY] = -g.rightThumbstick.yAxis.value;
		values[SDL_GAMEPAD_AXIS_LEFT_TRIGGER] = g.leftTrigger.value;
		values[SDL_GAMEPAD_AXIS_RIGHT_TRIGGER] = g.rightTrigger.value;
	}
	if (pad == 1)
	{
		pthread_mutex_lock(&pad_lock);
		if (axis >= 0 && axis < 6)
			values[axis] = stronger(values[axis], xg_touch_axis(&touch_input, axis));
		pthread_mutex_unlock(&pad_lock);
		if (touch_trace && axis >= 0 && axis < 6 && fabsf(values[axis] - traced[axis]) > 0.1f)
		{
			fprintf(stderr, "[xbox] touch poll axis=%d value=%.2f\n", axis, values[axis]);
			traced[axis] = values[axis];
		}
	}
	return axis >= 0 && axis < 6 ? axis_value(values[axis]) : 0;
}

static int hardware_button(GCExtendedGamepad *g, int button)
{
	if (!g)
		return 0;
	switch (button)
	{
	case SDL_GAMEPAD_BUTTON_SOUTH: return g.buttonA.pressed;
	case SDL_GAMEPAD_BUTTON_EAST: return g.buttonB.pressed;
	case SDL_GAMEPAD_BUTTON_WEST: return g.buttonX.pressed;
	case SDL_GAMEPAD_BUTTON_NORTH: return g.buttonY.pressed;
	case SDL_GAMEPAD_BUTTON_BACK: return g.buttonOptions.pressed;
	case SDL_GAMEPAD_BUTTON_START: return g.buttonMenu.pressed;
	case SDL_GAMEPAD_BUTTON_LEFT_STICK: return g.leftThumbstickButton.pressed;
	case SDL_GAMEPAD_BUTTON_RIGHT_STICK: return g.rightThumbstickButton.pressed;
	case SDL_GAMEPAD_BUTTON_LEFT_SHOULDER: return g.leftShoulder.pressed;
	case SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER: return g.rightShoulder.pressed;
	case SDL_GAMEPAD_BUTTON_DPAD_UP: return g.dpad.up.pressed;
	case SDL_GAMEPAD_BUTTON_DPAD_DOWN: return g.dpad.down.pressed;
	case SDL_GAMEPAD_BUTTON_DPAD_LEFT: return g.dpad.left.pressed;
	case SDL_GAMEPAD_BUTTON_DPAD_RIGHT: return g.dpad.right.pressed;
	default: return 0;
	}
}

int xh_host_sdl_gamepad_button(uint32_t pad, int button)
{
	int pressed = hardware_button(pad <= PADS ? pads[pad].extendedGamepad : nil, button);
	if (pad == 1 && button >= 0 && button < 32)
	{
		pthread_mutex_lock(&pad_lock);
		pressed |= xg_touch_button(&touch_input, button);
		pthread_mutex_unlock(&pad_lock);
	}
	return pressed;
}


int xh_host_sdl_gamepad_type(uint32_t pad) { (void)pad; return SDL_GAMEPAD_TYPE_XBOXONE; }

int xh_host_sdl_rumble_gamepad(uint32_t pad, uint32_t low, uint32_t high, uint32_t milliseconds)
{
	(void)pad; (void)low; (void)high; (void)milliseconds;
	return 0;
}

/* ---------- events: controllers that appeared since the last poll */

int xh_host_sdl_poll_event(uint32_t event)
{
	SDL_Event *out = G(SDL_Event *, event);
	int index;
	pthread_mutex_lock(&pad_lock);
	if (hw_head != hw_tail)
	{
		*out = hw_events[hw_head++ % HW_EVENTS];
		out->common.timestamp = (Uint64)xh_host_sdl_ticks() * 1000000ull;
		pthread_mutex_unlock(&pad_lock);
		return 1;
	}
	int down = 0;
	int page = xg_scoreboard_next(&touch_scoreboard, &down);
	if (page)
	{
		memset(out, 0, sizeof(*out));
		/* Unlike wheel events, these cannot become weapon switching when the
		 * guest has not yet opened (or has just closed) its scoreboard. */
		out->key.type = down ? SDL_EVENT_KEY_DOWN : SDL_EVENT_KEY_UP;
		out->key.timestamp = (Uint64)xh_host_sdl_ticks() * 1000000ull;
		out->key.windowID = 1;
		out->key.scancode = page > 0 ? SDL_SCANCODE_PAGEDOWN : SDL_SCANCODE_PAGEUP;
		out->key.key = page > 0 ? SDLK_PAGEDOWN : SDLK_PAGEUP;
		out->key.down = down;
		if (touch_trace) fprintf(stderr, "[xbox] scoreboard page=%d down=%d\n", page, down);
		pthread_mutex_unlock(&pad_lock);
		return 1;
	}
	if (touch_look_x != 0 || touch_look_y != 0)
	{
		memset(out, 0, sizeof(*out));
		out->motion.type = SDL_EVENT_MOUSE_MOTION;
		out->motion.timestamp = (Uint64)xh_host_sdl_ticks() * 1000000ull;
		out->motion.windowID = 1;
		out->motion.xrel = touch_look_x;
		out->motion.yrel = touch_look_y;
		touch_look_x = touch_look_y = 0;
		pthread_mutex_unlock(&pad_lock);
		return 1;
	}
	pthread_mutex_unlock(&pad_lock);
	pads_refresh();
	for (index = 1; index <= PADS; index++)
		if (pads[index] && !pad_announced[index])
		{
			pad_announced[index] = 1;
			memset(out, 0, sizeof(*out));
			out->gdevice.type = SDL_EVENT_GAMEPAD_ADDED;
			out->gdevice.timestamp = (Uint64)xh_host_sdl_ticks() * 1000000ull;
			out->gdevice.which = (SDL_JoystickID)index;
			return 1;
		}
	return 0;
}

/* ---------- audio: a Remote I/O unit pulls from the guest's callback */

static AudioComponentInstance audio_unit;
static uint32_t audio_callback, audio_userdata;
static uint8_t *audio_buffer;
static uint32_t audio_length, audio_capacity, audio_frame_bytes;
#if TARGET_OS_SIMULATOR
static struct xg_audio_capture audio_capture;
static uint32_t audio_capture_rate;
static int audio_capture_written;

/* The producer freezes its sample buffer before publishing ready. File I/O
 * runs on the game thread, never Remote I/O's real-time callback. */
static void audio_capture_flush(void)
{
	if (audio_capture_written || !atomic_load_explicit(&audio_capture.ready, memory_order_acquire)) return;
	audio_capture_written = 1;
	char path[1200];
	snprintf(path, sizeof(path), "%s/audio-output.f32le", xg_paths.data_root);
	FILE *file = fopen(path, "wb");
	size_t samples = (size_t)audio_capture.frames * audio_capture.channels;
	int okay = file && fwrite(audio_capture.samples, sizeof(float), samples, file) == samples;
	if (file && fclose(file)) okay = 0;
	if (!okay) { xg_log("audio capture: cannot write output samples"); return; }
	snprintf(path, sizeof(path), "%s/audio-output.json", xg_paths.data_root);
	file = fopen(path, "w");
	if (!file) { xg_log("audio capture: cannot write metadata"); return; }
	int result = fprintf(file, "{\"rate\":%u,\"channels\":%u,\"frames\":%u,\"underrun_frames\":%u}\n",
		audio_capture_rate, audio_capture.channels, audio_capture.frames, audio_capture.underrun_frames);
	int closed = fclose(file);
	xg_log("audio capture: %s, %u frames, %u underrun frames",
		result > 0 && !closed ? "complete" : "metadata failed", audio_capture.frames, audio_capture.underrun_frames);
}
#endif

static OSStatus audio_render(void *reference, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time,
	UInt32 bus, UInt32 frames, AudioBufferList *io)
{
	uint32_t needed = frames * audio_frame_bytes, copied;
	(void)reference; (void)flags; (void)time; (void)bus;
	if (audio_length < needed && audio_callback)
		xg_enter(audio_callback, audio_userdata, 1, needed - audio_length, needed);
	copied = audio_length < needed ? audio_length : needed;
	memcpy(io->mBuffers[0].mData, audio_buffer, copied);
	memset((uint8_t *)io->mBuffers[0].mData + copied, 0, needed - copied);
#if TARGET_OS_SIMULATOR
	xg_audio_capture_append(&audio_capture, io->mBuffers[0].mData, frames, copied / audio_frame_bytes);
#endif
	memmove(audio_buffer, audio_buffer + copied, audio_length - copied);
	audio_length -= copied;
	return noErr;
}

uint32_t xh_host_sdl_open_audio_stream(uint32_t device, uint32_t spec_address, uint32_t callback, uint32_t userdata)
{
	const SDL_AudioSpec *spec = G(const SDL_AudioSpec *, spec_address);
	AudioComponentDescription description = { kAudioUnitType_Output, kAudioUnitSubType_RemoteIO,
		kAudioUnitManufacturer_Apple, 0, 0 };
	AudioStreamBasicDescription format;
	AURenderCallbackStruct render = { audio_render, NULL };
	AudioComponent component;
	(void)device;
	if (spec->format != SDL_AUDIO_F32)
	{
		xg_log("audio format 0x%x is not supported", spec->format);
		return 0;
	}
	[[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient error:nil];
	[[AVAudioSession sharedInstance] setActive:YES error:nil];
	audio_callback = callback;
	audio_userdata = userdata;
	audio_frame_bytes = 4u * (uint32_t)spec->channels;
	audio_capacity = 1u << 20;
	audio_buffer = malloc(audio_capacity);
#if TARGET_OS_SIMULATOR
	const char *capture = getenv("XG_AUDIO_CAPTURE");
	if (capture && !strcmp(capture, "1")) {
		audio_capture_rate = (uint32_t)spec->freq;
		if (!xg_audio_capture_init(&audio_capture, audio_capture_rate, (uint32_t)spec->channels))
			xg_log("audio capture: unsupported format or allocation failed");
	}
#endif
	memset(&format, 0, sizeof(format));
	format.mSampleRate = spec->freq;
	format.mFormatID = kAudioFormatLinearPCM;
	format.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
	format.mBytesPerPacket = format.mBytesPerFrame = audio_frame_bytes;
	format.mFramesPerPacket = 1;
	format.mChannelsPerFrame = (UInt32)spec->channels;
	format.mBitsPerChannel = 32;
	component = AudioComponentFindNext(NULL, &description);
	if (!component || AudioComponentInstanceNew(component, &audio_unit) ||
		AudioUnitSetProperty(audio_unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format)) ||
		AudioUnitSetProperty(audio_unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &render, sizeof(render)) ||
		AudioUnitInitialize(audio_unit))
	{
		xg_log("cannot open audio output");
		return 0;
	}
	xg_log("audio %d Hz, %d channels", spec->freq, spec->channels);
	return 1;
}

int xh_host_sdl_put_audio_stream_data(uint32_t stream, uint32_t data, int length)
{
	(void)stream;
	if (length <= 0)
		return 1;
	if (audio_length + (uint32_t)length > audio_capacity)
		length = (int)(audio_capacity - audio_length);
	memcpy(audio_buffer + audio_length, G(const void *, data), (size_t)length);
	audio_length += (uint32_t)length;
	return 1;
}

int xh_host_sdl_resume_audio_stream_device(uint32_t stream)
{
	(void)stream;
	return audio_unit && AudioOutputUnitStart(audio_unit) == noErr;
}

/* ---------- start-up */

int xg_ios_start(const char *image_path, const char *data_root, const char *save_root)
{
	NSData *image;
	char buffers[5][1100];
	const char *environment[48];
	int count = 5;
	CGSize screen = UIScreen.mainScreen.bounds.size;
	CGFloat longer = MAX(screen.width, screen.height), shorter = MIN(screen.width, screen.height);
	uint32_t boot;
	start_ticks = mach_absolute_time();
	touch_trace = getenv("XG_TOUCH_TRACE") != NULL;
	strlcpy(xg_paths.data_root, data_root, sizeof(xg_paths.data_root));
	strlcpy(xg_paths.save_root, save_root, sizeof(xg_paths.save_root));
	mkdir(save_root, 0755);
	xg_install_signal_handlers();
	if (xg_memory_initialize())
	{
		xg_log("cannot reserve guest memory (the app needs the extended virtual addressing entitlement)");
		return -1;
	}
	image = [NSData dataWithContentsOfFile:@(image_path)];
	if (!image || xg_load_image(image.bytes, image.length))
	{
		xg_log("cannot load the game image %s", image_path);
		return -1;
	}
	snprintf(buffers[0], sizeof(buffers[0]), "HOME=%s", save_root);
	snprintf(buffers[1], sizeof(buffers[1]), "HALO_DATA_ROOT=%s", data_root);
	snprintf(buffers[2], sizeof(buffers[2]), "HALO_SAVE_ROOT=%s", save_root);
	/* the game draws 480 lines at the screen's shape (upstream's d3d8_gl.c) */
	snprintf(buffers[3], sizeof(buffers[3]), "HALO_DISPLAY_WIDTH=%d", (int)(480.0 * longer / shorter) & ~1);
	{
		NSInteger offset = -NSTimeZone.localTimeZone.secondsFromGMT;
		snprintf(buffers[4], sizeof(buffers[4]), "TZ=<L>%s%ld:%02ld", offset < 0 ? "-" : "",
			labs((long)offset) / 3600, (labs((long)offset) / 60) % 60);
	}
	for (int index = 0; index < 5; index++)
		environment[index] = buffers[index];
	/* upstream's settings as HALO_* variables (development and tests) */
	for (char **entry = *_NSGetEnviron(); *entry && count < 47; entry++)
		if (!strncmp(*entry, "HALO_", 5) && strncmp(*entry, "HALO_DATA_ROOT=", 15) && strncmp(*entry, "HALO_SAVE_ROOT=", 15))
			environment[count++] = *entry;
	boot = xg_make_boot(environment, count, 1, (char *[]){ "halo" });
	if (!boot || xg_start_game(boot))
	{
		xg_log("cannot start the game thread");
		return -1;
	}
	xg_log("started: data %s, saves %s", data_root, save_root);
	return 0;
}
