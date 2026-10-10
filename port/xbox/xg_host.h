/*
 * xg_host.h: HaloPad's host for the Xbox engine (docs/XBOX-ENGINE.md).
 *
 * The engine is upstream's arm64_32 Android guest image, translated to
 * base-relative ARM64 by scripts/xbox/translate.py. Guest memory is one
 * 4 GiB-aligned host reservation starting at xg_base; guest address g is the
 * host address xg_base + g. Host functions the guest imports are named
 * xh_<import name> and take guest pointers as uint32_t.
 */
#ifndef XG_HOST_H
#define XG_HOST_H

#include <stddef.h>
#include <stdint.h>

extern uintptr_t xg_base;

#define G(type, address) ((type)(xg_base + (uint32_t)(address)))
#define GP(address) ((address) ? G(void *, address) : NULL)
#define GA(pointer) ((uint32_t)((uintptr_t)(pointer) - xg_base))

/* the upstream image layout (port/android/include/halo_android_abi.h).
 * HaloPad reads the header only up to thread_attach, which ABI versions 1
 * and 2 share; ABI 2 (OpenCE 170) adds thread_detach after it. */
#define XG_WINDOW_BASE 0x80000000u
#define XG_WINDOW_SIZE 0x08000000u
#define XG_IMAGE_BASE 0x88000000u
#define XG_PAGE 0x4000u

struct xg_guest_header
{
	uint32_t magic, abi_version, image_end, import_table, import_names, import_count;
	uint32_t start, thread_start, thread_attach;
};
extern const struct xg_guest_header *xg_header;

/* xg_runtime.s: calls guest code at fn with x28 = xg_base (the caller must
 * already be on a stack inside guest memory) */
uint64_t xg_call(uint32_t fn, uint64_t a, uint64_t b, uint64_t c, uint64_t d, uint64_t e, uint64_t f);
/* the same, first switching sp to stack_top (a host address in guest memory) */
uint64_t xg_call_on(uintptr_t stack_top, uint32_t fn, uint64_t a, uint64_t b, uint64_t c, uint64_t d);

/* xg_thread.c: calls guest code from any host thread, giving the thread a
 * guest stack and a guest struct pthread the first time */
uint32_t xg_enter(uint32_t fn, uint32_t a, uint32_t b, uint32_t c, uint32_t d);
int xg_start_game(uint32_t boot);
/* argv and the environment copied into guest memory: the struct
 * halo_guest_boot that __guest_start takes */
uint32_t xg_make_boot(const char **environment, int count, int argc, char **argv);

/* xg_memory.c */
int xg_memory_initialize(void);
uint32_t xg_map(size_t size, int protection);
void xg_unmap(uint32_t address, size_t size);
int xg_load_image(const void *elf, size_t size);
long xg_guest_mmap(uint32_t address, uint32_t size, int protection, int flags, int fd, int64_t offset);
long xg_guest_munmap(uint32_t address, uint32_t size);
long xg_guest_mprotect(uint32_t address, uint32_t size, int protection);
void xg_install_signal_handlers(void);

/* xg_syscall.c */
int xg_linux_errno(int darwin_errno);
extern __thread int xg_errno;

/* logging */
void xg_log(const char *format, ...) __attribute__((format(printf, 1, 2)));
void xg_fatal(const char *format, ...) __attribute__((format(printf, 1, 2), noreturn));
/* Optional host sink for finished log lines (HaloPad's shareable diagnostic
 * log). Set once before the game starts; called from any thread. */
extern void (*xg_log_sink)(const char *line);
/* time spent in GL calls that can stall a frame (xg_gl.c) */
struct xg_gl_cost { unsigned count; double seconds; };
extern struct xg_gl_cost xg_gl_costs[4];   /* compiles/links, textures, buffers, draws */

/* the platform (xg_main_*.c): data and save folders, display width */
struct xg_paths
{
	char data_root[1024];
	char save_root[1024];
};
extern struct xg_paths xg_paths;

#endif
