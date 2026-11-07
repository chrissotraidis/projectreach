/*
 * xg_gl.c: the guest's OpenGL ES helper imports (upstream's host_gl.c) and a
 * frame dump for testing, on any platform (xg_gl_proc resolves functions).
 */
#include "xg_host.h"
#include "xg_query_trace.h"
#include "xg_query_rect_trace.h"

#include <GLES3/gl32.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

void *xg_gl_proc(const char *name);
GLuint xg_gl_framebuffer(GLuint framebuffer);

/* GL calls that can stall a frame (xg_gl_gen.c), read by the renderer health
 * log: 0 shader compiles and links, 1 texture uploads, 2 buffer uploads,
 * 3 draws. Only the game's render thread makes GL calls. */
struct xg_gl_cost xg_gl_costs[4];

double xg_gl_cost_begin(void)
{
	struct timespec now;
	clock_gettime(CLOCK_MONOTONIC, &now);
	return now.tv_sec + now.tv_nsec / 1e9;
}

void xg_gl_cost_end(int kind, double started)
{
	xg_gl_costs[kind].count++;
	xg_gl_costs[kind].seconds += xg_gl_cost_begin() - started;
}

/* Private guest bridge, not a GL query pname exposed to other clients. */
void xg_gl_query_samples(GLuint id, GLuint *result)
{
#ifdef XG_COUNTED_VISIBILITY
	extern int halopad_angle_query_samples(unsigned, unsigned *);
	if (!result || !halopad_angle_query_samples(id, result))
		xg_fatal("Counted visibility bridge failed for query %u", id);
	/* The rectangle observer now reports a count for this explicit bridge;
	 * ordinary query reads still report GL booleans. */
	xg_query_rect_result(id, 0x8866, *result);
#else
	(void)result;
	xg_fatal("Counted visibility guest requires its paired backend (query %u)", id);
#endif
}

static const GLubyte *(*p_glGetString)(GLenum);
static const GLubyte *(*p_glGetStringi)(GLenum, GLuint);
static void (*p_glGetIntegerv)(GLenum, GLint *);
static void (*p_glBindBuffer)(GLenum, GLuint);
static void (*p_glBindFramebuffer)(GLenum, GLuint);
static void *(*p_glMapBufferRange)(GLenum, GLintptr, GLsizeiptr, GLbitfield);
static GLboolean (*p_glUnmapBuffer)(GLenum);
static void (*p_glBufferSubData)(GLenum, GLintptr, GLsizeiptr, const void *);
static GLsync (*p_glFenceSync)(GLenum, GLbitfield);
static void (*p_glDeleteSync)(GLsync);
static GLenum (*p_glClientWaitSync)(GLsync, GLbitfield, GLuint64);
static void (*p_glReadPixels)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void *);
static void helpers_load(void);

void xg_gl_trace_query(int begin, GLuint id, GLenum name, GLuint value)
{
	xg_query_trace(begin, id, name, value);
	if (begin) xg_query_rect_begin(name, id);
	else xg_query_rect_result(id, name, value);
}

void xg_gl_trace_query_end(GLenum target) { xg_query_rect_end(target); }
void xg_gl_trace_query_draw(GLenum mode, GLint first, GLsizei count)
{ xg_query_rect_draw(mode, first, count); }

/* XG_GL_TRACE=<private path prefix>: inspect presentation on an isolated
 * diagnostic run. Never enabled by normal builds. Capture at most every ten
 * seconds, preserving all framebuffer and pixel-pack state. */
void xg_gl_trace_blit(int after, int x0, int y0, int x1, int y1)
{
	static const char *prefix;
	static int checked, capture;
	static time_t next;
	static void (*bind_framebuffer)(GLenum, GLuint);
	static void (*pixel_store)(GLenum, GLint);
	static GLenum (*framebuffer_status)(GLenum);
	static GLenum (*get_error)(void);
	static GLboolean (*is_enabled)(GLenum);
	GLenum prior_error, read_error;
	GLint read, draw, viewport[4], pack[5];
	const GLenum pack_names[] = { GL_PIXEL_PACK_BUFFER_BINDING, GL_PACK_ALIGNMENT,
		GL_PACK_ROW_LENGTH, GL_PACK_SKIP_ROWS, GL_PACK_SKIP_PIXELS };
	int width = abs(x1 - x0), height = abs(y1 - y0), row, i;
	size_t lit = 0, alpha = 0, count;
	unsigned char *pixels;
	char path[1024];
	FILE *file;
	if (!checked) { checked = 1; prefix = getenv("XG_GL_TRACE"); }
	if (!prefix || !*prefix) return;
	helpers_load();
	if (!bind_framebuffer)
	{
		bind_framebuffer = xg_gl_proc("glBindFramebuffer");
		pixel_store = xg_gl_proc("glPixelStorei");
		framebuffer_status = xg_gl_proc("glCheckFramebufferStatus");
		get_error = xg_gl_proc("glGetError");
		is_enabled = xg_gl_proc("glIsEnabled");
	}
	p_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read);
	p_glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &draw);
	if (!after)
	{
		capture = (GLuint)draw == xg_gl_framebuffer(0) && time(NULL) >= next;
		if (capture) next = time(NULL) + 10;
	}
	if (!capture || width <= 0 || height <= 0 || width > 4096 || height > 4096) return;
	count = (size_t)width * height;
	pixels = calloc(count, 4);
	if (!pixels) return;
	for (i = 0; i < 5; i++) p_glGetIntegerv(pack_names[i], &pack[i]);
	p_glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
	pixel_store(GL_PACK_ALIGNMENT, 1);
	for (i = 2; i < 5; i++) pixel_store(pack_names[i], 0);
	if (after) bind_framebuffer(GL_READ_FRAMEBUFFER, (GLuint)draw);
	p_glGetIntegerv(GL_VIEWPORT, viewport);
	prior_error = get_error();
	p_glReadPixels(x0 < x1 ? x0 : x1, y0 < y1 ? y0 : y1,
		width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
	read_error = get_error();
	for (i = 0; (size_t)i < count; i++) {
		if (pixels[i * 4] + pixels[i * 4 + 1] + pixels[i * 4 + 2] > 45) lit++;
		if (pixels[i * 4 + 3]) alpha++;
	}
	xg_log("presentation %s: read %d draw %d, rect %d %d %d %d, viewport %d %d %d %d, status 0x%x, prior error 0x%x read error 0x%x, lit %.4f alpha %.4f",
		after ? "destination" : "source", read, draw, x0, y0, x1, y1,
		viewport[0], viewport[1], viewport[2], viewport[3], framebuffer_status(GL_READ_FRAMEBUFFER),
		prior_error, read_error, (double)lit / count, (double)alpha / count);
	if (!after) {
		GLint active = 0, program = 0;
		p_glGetIntegerv(GL_ACTIVE_TEXTURE, &active);
		p_glGetIntegerv(GL_CURRENT_PROGRAM, &program);
		xg_log("presentation state: blend %d cull %d depth %d stencil %d scissor %d, active texture 0x%x program %d",
			is_enabled(GL_BLEND), is_enabled(GL_CULL_FACE), is_enabled(GL_DEPTH_TEST),
			is_enabled(GL_STENCIL_TEST), is_enabled(GL_SCISSOR_TEST), active, program);
	}
	snprintf(path, sizeof(path), "%s.%s.ppm", prefix, after ? "destination" : "source");
	file = fopen(path, "wb");
	if (file)
	{
		fprintf(file, "P6\n%d %d\n255\n", width, height);
		for (row = height - 1; row >= 0; row--)
			for (i = 0; i < width; i++) fwrite(pixels + ((size_t)row * width + i) * 4, 1, 3, file);
		fclose(file);
	}
	bind_framebuffer(GL_READ_FRAMEBUFFER, (GLuint)read);
	p_glBindBuffer(GL_PIXEL_PACK_BUFFER, (GLuint)pack[0]);
	for (i = 1; i < 5; i++) pixel_store(pack_names[i], pack[i]);
	free(pixels);
	if (after) capture = 0;
}

static void helpers_load(void)
{
	if (p_glGetString)
		return;
	p_glGetString = xg_gl_proc("glGetString");
	p_glGetStringi = xg_gl_proc("glGetStringi");
	p_glGetIntegerv = xg_gl_proc("glGetIntegerv");
	p_glBindBuffer = xg_gl_proc("glBindBuffer");
	p_glBindFramebuffer = xg_gl_proc("glBindFramebuffer");
	p_glMapBufferRange = xg_gl_proc("glMapBufferRange");
	p_glUnmapBuffer = xg_gl_proc("glUnmapBuffer");
	p_glBufferSubData = xg_gl_proc("glBufferSubData");
	p_glFenceSync = xg_gl_proc("glFenceSync");
	p_glDeleteSync = xg_gl_proc("glDeleteSync");
	p_glClientWaitSync = xg_gl_proc("glClientWaitSync");
	p_glReadPixels = xg_gl_proc("glReadPixels");
}

static void copy_out(uint32_t buffer, uint32_t size, const char *text)
{
	if (!size)
		return;
	strncpy(G(char *, buffer), text ? text : "", size - 1);
	G(char *, buffer)[size - 1] = 0;
}

void xh_host_gl_get_string(uint32_t name, int index, uint32_t buffer, uint32_t size)
{
	helpers_load();
	copy_out(buffer, size, (const char *)(index >= 0 ? p_glGetStringi(name, (GLuint)index) : p_glGetString(name)));
}

int xh_host_gl_has_extension(uint32_t name)
{
	GLint count = 0, index;
	helpers_load();
	/* XG_NO_EXTENSION=<substring>: hide matching extensions (to test the
	 * renderer's fallbacks, for example the CPU decoding of S3TC textures) */
	if (getenv("XG_NO_EXTENSION") && strstr(G(const char *, name), getenv("XG_NO_EXTENSION")))
		return 0;
	p_glGetIntegerv(GL_NUM_EXTENSIONS, &count);
	for (index = 0; index < count; index++)
	{
		const char *extension = (const char *)p_glGetStringi(GL_EXTENSIONS, (GLuint)index);
		if (extension && !strcmp(extension, G(const char *, name)))
			return 1;
	}
	return 0;
}

uint32_t xh_host_gl_read_buffer_word(uint32_t buffer, uint32_t offset)
{
	uint32_t value = 0;
	GLint previous = 0;
	const void *mapping;
	helpers_load();
	p_glGetIntegerv(GL_ATOMIC_COUNTER_BUFFER_BINDING, &previous);
	p_glBindBuffer(GL_ATOMIC_COUNTER_BUFFER, buffer);
	mapping = p_glMapBufferRange(GL_ATOMIC_COUNTER_BUFFER, offset, sizeof(value), GL_MAP_READ_BIT);
	if (mapping)
	{
		memcpy(&value, mapping, sizeof(value));
		p_glUnmapBuffer(GL_ATOMIC_COUNTER_BUFFER);
	}
	p_glBindBuffer(GL_ATOMIC_COUNTER_BUFFER, (GLuint)previous);
	return value;
}

void xh_host_gl_buffer_write(uint32_t target, uint32_t offset, uint32_t size, uint32_t data)
{
	void *mapping;
	xg_query_rect_upload(target, size, G(const void *, data));
	helpers_load();
	mapping = p_glMapBufferRange(target, offset, size, GL_MAP_WRITE_BIT | GL_MAP_UNSYNCHRONIZED_BIT);
	if (!mapping)
	{
		p_glBufferSubData(target, offset, size, G(const void *, data));
		return;
	}
	memcpy(mapping, G(const void *, data), size);
	p_glUnmapBuffer(target);
}

#define FENCES 8
static GLsync fences[FENCES];

void xh_host_gl_fence_frame(uint32_t slot)
{
	helpers_load();
	if (slot >= FENCES)
		return;
	if (fences[slot])
		p_glDeleteSync(fences[slot]);
	fences[slot] = p_glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
}

void xh_host_gl_wait_frame(uint32_t slot)
{
	helpers_load();
	if (slot >= FENCES || !fences[slot])
		return;
	p_glClientWaitSync(fences[slot], GL_SYNC_FLUSH_COMMANDS_BIT, 1000000000ull);
	p_glDeleteSync(fences[slot]);
	fences[slot] = NULL;
}

void xh_host_android_path(int which, uint32_t buffer, uint32_t size)
{
	copy_out(buffer, size, which ? xg_paths.save_root : xg_paths.data_root);
}

/* OpenCE 343's SoC classification is Android-specific. Unknown (0) retains
 * the geometry and Custom Edition texture compatibility paths that this
 * translated guest used before chip-specific selection was introduced. */
int xh_host_android_chip_family(void) { return 0; }

/* XG_FRAME_DUMP=<path>: every XG_FRAME_DUMP_SECONDS (default 5), the frame
 * about to be shown (the platform drawable) is written to <path> as a PPM
 * image, for testing without capturing anything else on screen */
void xg_gl_frame_dump(int width, int height)
{
	static const char *path;
	static int checked;
	static time_t next;
	unsigned char *pixels;
	FILE *file;
	int row;
	GLint read = 0;
	if (!checked)
	{
		checked = 1;
		path = getenv("XG_FRAME_DUMP");
	}
	if (!path || time(NULL) < next || width <= 0 || height <= 0)
		return;
	next = time(NULL) + (getenv("XG_FRAME_DUMP_SECONDS") ? atoi(getenv("XG_FRAME_DUMP_SECONDS")) : 5);
	helpers_load();
	pixels = malloc((size_t)width * height * 4);
	if (!pixels)
		return;
	/* The guest leaves its back-buffer texture bound for reading after its
	 * final blit. Capture the drawable, not a 640x480 source read at the
	 * window's larger dimensions (which fabricated a small-picture result). */
	p_glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &read);
	p_glBindFramebuffer(GL_READ_FRAMEBUFFER, xg_gl_framebuffer(0));
	p_glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
	p_glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)read);
	file = fopen(path, "wb");
	if (file)
	{
		fprintf(file, "P6\n%d %d\n255\n", width, height);
		/* OpenGL rows run bottom to top */
		for (row = height - 1; row >= 0; row--)
		{
			int column;
			for (column = 0; column < width; column++)
				fwrite(pixels + ((size_t)row * width + column) * 4, 1, 3, file);
		}
		fclose(file);
	}
	free(pixels);
}
