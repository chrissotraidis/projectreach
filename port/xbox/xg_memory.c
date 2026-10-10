/*
 * xg_memory.c: guest memory for the Xbox engine.
 *
 * One 4 GiB, 4 GiB-aligned host reservation holds everything the guest can
 * address. Guest address layout (upstream's Android contract):
 *   0x00000000-0x10000000  never mapped (null and small-integer pointers fault)
 *   0x10000000-0x80000000  pages the guest maps (malloc, thread stacks)
 *   0x80000000-0x88000000  the Xbox contiguous memory window, always mapped
 *   0x88000000-...         the game image (data only; its code is translated)
 *   image end-0xfff00000   more guest pages
 *
 * Apple platforms use 16 KiB pages and the game uses 4 KiB ones, so inside
 * the window and the image the guest's own mmap/mprotect are emulated
 * (fresh mappings are zeroed, protection changes ignored). Write tracking
 * for Direct3D resources (host_memory_watch_*) uses real protection at
 * 16 KiB granularity, which only makes it more conservative.
 */
#include "xg_host.h"
#include "xg_fault_frames.h"

#include <errno.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/ucontext.h>
#include <unistd.h>

uintptr_t xg_base;
const struct xg_guest_header *xg_header;

#define SPAN 0x100000000ull
#define PAGES (SPAN / XG_PAGE)
#define LOW_ALLOC 0x10000000u
#define HIGH_LIMIT 0xfff00000u

static uint8_t page_used[PAGES];
static uint32_t rover = LOW_ALLOC / XG_PAGE;
static pthread_mutex_t memory_lock = PTHREAD_MUTEX_INITIALIZER;
static uint32_t image_end = XG_IMAGE_BASE;

static uint32_t round_up(uint64_t value) { return (uint32_t)((value + XG_PAGE - 1) & ~(uint64_t)(XG_PAGE - 1)); }

static int in_fixed(uint64_t address, uint64_t size)
{
	return address >= XG_WINDOW_BASE && address + size <= image_end;
}

static void mark(uint32_t address, uint64_t size, uint8_t value)
{
	uint32_t first = address / XG_PAGE, index;
	uint64_t count = (size + XG_PAGE - 1) / XG_PAGE;
	for (index = 0; index < count; index++)
		page_used[first + index] = value;
}

int xg_memory_initialize(void)
{
	/* Ask the VM allocator for alignment directly. Reserving twice the span
	 * first unnecessarily needs 8 GiB of free virtual address space. */
	vm_address_t reservation = 0;
	if (vm_map(mach_task_self(), &reservation, SPAN, SPAN - 1,
		VM_FLAGS_ANYWHERE, MEMORY_OBJECT_NULL, 0, FALSE,
		VM_PROT_NONE, VM_PROT_READ | VM_PROT_WRITE, VM_INHERIT_NONE) != KERN_SUCCESS)
		return -1;
	xg_base = reservation;
	mark(0, LOW_ALLOC, 1);
	mark(XG_WINDOW_BASE, XG_WINDOW_SIZE, 1);
	mark(HIGH_LIMIT, SPAN - HIGH_LIMIT, 1);
	if (mmap(G(void *, XG_WINDOW_BASE), XG_WINDOW_SIZE, PROT_READ | PROT_WRITE,
		MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0) == MAP_FAILED)
	{
		vm_deallocate(mach_task_self(), reservation, SPAN);
		xg_base = 0;
		return -1;
	}
	xg_log("guest memory at %p (4 GiB), Xbox window at guest 0x%08x", (void *)xg_base, XG_WINDOW_BASE);
	return 0;
}

/* first fit from a rover over the free pages */
static uint32_t take(uint32_t pages)
{
	uint32_t start = rover, index, run = 0, pass;
	for (pass = 0; pass < 2; pass++)
	{
		for (index = start; index < PAGES; index++)
		{
			run = page_used[index] ? 0 : run + 1;
			if (run == pages)
			{
				uint32_t first = index + 1 - pages;
				memset(page_used + first, 1, pages);
				rover = index + 1;
				return first * XG_PAGE;
			}
		}
		start = LOW_ALLOC / XG_PAGE;
		run = 0;
	}
	return 0;
}

uint32_t xg_map(size_t size, int protection)
{
	uint32_t length = round_up(size), address;
	if (!length)
		return 0;
	pthread_mutex_lock(&memory_lock);
	address = take(length / XG_PAGE);
	pthread_mutex_unlock(&memory_lock);
	if (!address)
		return 0;
	if (mmap(G(void *, address), length, protection, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0) == MAP_FAILED)
	{
		xg_unmap(address, length);
		return 0;
	}
	return address;
}

void xg_unmap(uint32_t address, size_t size)
{
	uint32_t start = address & ~(XG_PAGE - 1), length = round_up((uint64_t)address + size - start);
	mmap(G(void *, start), length, PROT_NONE, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0);
	pthread_mutex_lock(&memory_lock);
	mark(start, length, 0);
	pthread_mutex_unlock(&memory_lock);
}

/* ---------- the image (an ELF file from upstream's Android build) */

struct elf64_header { uint8_t ident[16]; uint16_t type, machine; uint32_t version; uint64_t entry, phoff, shoff;
	uint32_t flags; uint16_t ehsize, phentsize, phnum, shentsize, shnum, shstrndx; };
struct elf64_program { uint32_t type, flags; uint64_t offset, vaddr, paddr, filesz, memsz, align; };

int xg_load_image(const void *elf, size_t size)
{
	const struct elf64_header *header = elf;
	uint32_t low = 0xffffffffu, high = 0, index;
	if (size < sizeof(*header) || memcmp(header->ident, "\177ELF", 4) || header->machine != 183)
		return -1;
	for (index = 0; index < header->phnum; index++)
	{
		const struct elf64_program *p = (const void *)((const uint8_t *)elf + header->phoff + index * header->phentsize);
		if (p->type != 1)
			continue;
		if (p->vaddr < low) low = (uint32_t)p->vaddr;
		if (p->vaddr + p->memsz > high) high = (uint32_t)(p->vaddr + p->memsz);
	}
	if (low != XG_IMAGE_BASE || high <= low)
		return -1;
	image_end = round_up(high);
	mark(low, image_end - low, 1);
	if (mmap(G(void *, low), image_end - low, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0) == MAP_FAILED)
		return -1;
	for (index = 0; index < header->phnum; index++)
	{
		const struct elf64_program *p = (const void *)((const uint8_t *)elf + header->phoff + index * header->phentsize);
		if (p->type != 1)
			continue;
		if (p->offset + p->filesz > size)
			return -1;
		memcpy(G(void *, p->vaddr), (const uint8_t *)elf + p->offset, p->filesz);
	}
	xg_header = G(const struct xg_guest_header *, XG_IMAGE_BASE);
	if (xg_header->magic != 0x4f4c4148u)
		return -1;
	xg_log("image 0x%08x-0x%08x", low, image_end);
	return 0;
}

/* ---------- the guest's mmap, munmap and mprotect (Linux flags) */

#define L_MAP_SHARED 0x01
#define L_MAP_FIXED 0x10
#define L_MAP_ANON 0x20
#define L_MAP_FIXED_NOREPLACE 0x100000

long xg_guest_mmap(uint32_t address, uint32_t size, int protection, int flags, int fd, int64_t offset)
{
	uint32_t length = round_up(size), result;
	int anonymous = (flags & L_MAP_ANON) != 0;
	if (!length)
		return -EINVAL;
	if (flags & (L_MAP_FIXED | L_MAP_FIXED_NOREPLACE))
	{
		if ((uint64_t)address + size > SPAN || address < LOW_ALLOC)
			return -ENOMEM;
		if (in_fixed(address, size))
		{
			if (!anonymous)
				return -EINVAL;
			if (protection)
				memset(G(void *, address), 0, size);
			return address;
		}
		if (address & (XG_PAGE - 1))
			return -EINVAL;
		pthread_mutex_lock(&memory_lock);
		mark(address, length, 1);
		pthread_mutex_unlock(&memory_lock);
		result = address;
	}
	else
	{
		pthread_mutex_lock(&memory_lock);
		result = take(length / XG_PAGE);
		pthread_mutex_unlock(&memory_lock);
		if (!result)
			return -ENOMEM;
	}
	if (anonymous)
	{
		if (mmap(G(void *, result), length, protection, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0) == MAP_FAILED)
			goto failed;
	}
	else if ((offset & (XG_PAGE - 1)) == 0 && !(flags & L_MAP_SHARED))
	{
		if (mmap(G(void *, result), length, protection, MAP_PRIVATE | MAP_FIXED, fd, offset) == MAP_FAILED)
			goto failed;
	}
	else
	{
		/* a file offset that is not a host page multiple: read it in */
		if (mmap(G(void *, result), length, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_FIXED, -1, 0) == MAP_FAILED)
			goto failed;
		if (pread(fd, G(void *, result), size, offset) < 0)
			goto failed;
		mprotect(G(void *, result), length, protection);
	}
	return result;
failed:
	{
		int error = errno;
		xg_unmap(result, length);
		return -xg_linux_errno(error);
	}
}

long xg_guest_munmap(uint32_t address, uint32_t size)
{
	if ((uint64_t)address + size > SPAN || address < LOW_ALLOC)
		return -EINVAL;
	if (in_fixed(address, size))
		return 0;
	if (address & (XG_PAGE - 1))
		return -EINVAL;
	xg_unmap(address, size);
	return 0;
}

long xg_guest_mprotect(uint32_t address, uint32_t size, int protection)
{
	uint32_t start, end;
	if ((uint64_t)address + size > SPAN)
		return -EINVAL;
	if (in_fixed(address, size))
		return 0;
	start = address & ~(XG_PAGE - 1);
	end = round_up((uint64_t)address + size);
	return mprotect(G(void *, start), end - start, protection) ? -xg_linux_errno(errno) : 0;
}

/* ---------- write tracking (port/linux/src/memory_watch.c's host half) */

#define WATCH_SMALL 0x1000u
#define WATCH_PER (XG_PAGE / WATCH_SMALL)
#define WATCH_COUNT (XG_WINDOW_SIZE / WATCH_SMALL)
static uint8_t watch_protected[WATCH_COUNT];
static uint32_t watch_generation[WATCH_COUNT];
static volatile uint32_t watch_current = 1;
static int watch_active;

static uint32_t watch_range(uint32_t address, uint32_t size, uint32_t *first, uint32_t *last)
{
	uint64_t start = address, end = (uint64_t)address + size;
	if (!size || end <= XG_WINDOW_BASE || start >= (uint64_t)XG_WINDOW_BASE + XG_WINDOW_SIZE)
		return 0;
	if (start < XG_WINDOW_BASE) start = XG_WINDOW_BASE;
	if (end > (uint64_t)XG_WINDOW_BASE + XG_WINDOW_SIZE) end = (uint64_t)XG_WINDOW_BASE + XG_WINDOW_SIZE;
	*first = (uint32_t)(start - XG_WINDOW_BASE) / WATCH_SMALL;
	*last = (uint32_t)(end - 1 - XG_WINDOW_BASE) / WATCH_SMALL;
	return 1;
}

/* a write reached the host page holding this small page: unprotect the
 * whole host page and count each small page in it as written */
static void watch_written(uint32_t page)
{
	uint32_t first = page / WATCH_PER * WATCH_PER, index;
	for (index = first; index < first + WATCH_PER; index++)
	{
		watch_generation[index] = __sync_add_and_fetch(&watch_current, 1);
		watch_protected[index] = 0;
	}
	mprotect(G(void *, XG_WINDOW_BASE + first * WATCH_SMALL), XG_PAGE, PROT_READ | PROT_WRITE);
}

void xh_host_memory_watch_initialize(void) { watch_active = 1; }

/* OpenCE 162+: a frame boundary for hash-based watching. HaloPad watches by
 * page protection, which needs nothing per frame (as upstream's protection mode). */
void xh_host_memory_watch_begin_frame(void) {}

void xh_host_memory_watch_protect(uint32_t address, uint32_t size)
{
	uint32_t first, last, page;
	if (!watch_active || !watch_range(address, size, &first, &last))
		return;
	/* whole host pages: their other small pages fault once and count as
	 * written (watch_written) */
	first = first / WATCH_PER * WATCH_PER;
	last = last / WATCH_PER * WATCH_PER + WATCH_PER - 1;
	for (page = first; page <= last; page++)
		watch_protected[page] = 1;
	mprotect(G(void *, XG_WINDOW_BASE + first * WATCH_SMALL), (last + 1 - first) * WATCH_SMALL, PROT_READ);
}

uint32_t xh_host_memory_watch_serial(void) { return watch_current; }

uint32_t xh_host_memory_watch_generation(uint32_t address, uint32_t size)
{
	uint32_t first, last, page, newest = 0;
	if (!watch_range(address, size, &first, &last))
		return 0;
	for (page = first; page <= last; page++)
		if (watch_generation[page] > newest)
			newest = watch_generation[page];
	return newest;
}

void xh_host_memory_watch_prepare_write(uint32_t address, uint32_t size)
{
	uint32_t first, last, page;
	if (!watch_active || !watch_range(address, size, &first, &last))
		return;
	for (page = first; page <= last; page++)
		if (watch_protected[page])
			watch_written(page);
}

void xh_host_memory_watch_forget(uint32_t address, uint32_t size)
{
	uint32_t first, last, page;
	if (!watch_range(address, size, &first, &last))
		return;
	for (page = first; page <= last; page++)
		if (watch_protected[page])
			watch_written(page);
	for (page = first; page <= last; page++)
		watch_generation[page] = __sync_add_and_fetch(&watch_current, 1);
}

/* ---------- faults */

extern char xg_text[] __asm__("_xg_text");

static void name_of(const char *label, uint64_t address)
{
	Dl_info info;
	if (dladdr((void *)address, &info) && info.dli_sname)
		xg_log("  %s %p = %s+0x%llx (%s)", label, (void *)address, info.dli_sname,
			(unsigned long long)(address - (uint64_t)info.dli_saddr), info.dli_fname);
	else
		xg_log("  %s %p", label, (void *)address);
}

static void report(int number, siginfo_t *information, void *context)
{
	ucontext_t *uc = context;
	uint64_t *x = (uint64_t *)uc->uc_mcontext->__ss.__x;
	uint64_t pc = uc->uc_mcontext->__ss.__pc, address = (uint64_t)information->si_addr;
	int index;
	xg_log("signal %d at %p (guest 0x%08llx): pc %p (translated +0x%llx) lr %p sp %p", number,
		information->si_addr, (unsigned long long)(address - xg_base), (void *)pc,
		(unsigned long long)(pc - (uint64_t)xg_text), (void *)uc->uc_mcontext->__ss.__lr,
		(void *)uc->uc_mcontext->__ss.__sp);
	for (index = 0; index < 29; index += 4)
		xg_log("  x%-2d %016llx %016llx %016llx %016llx", index, x[index], x[index + 1],
			index + 2 < 29 ? x[index + 2] : 0, index + 3 < 29 ? x[index + 3] : 0);
	name_of("pc", pc);
	name_of("lr", uc->uc_mcontext->__ss.__lr);
	{
		/* guest and host frame records, to find the callers */
		uint64_t returns[24];
		int count = xg_walk_frames(uc->uc_mcontext->__ss.__fp, xg_base, returns, 24,
			xg_read_frame_record);
		for (index = 0; index < count; index++)
			name_of("frame", returns[index]);
	}
}

static void fault(int number, siginfo_t *information, void *context)
{
	static volatile sig_atomic_t reporting;
	uint64_t address = (uint64_t)information->si_addr - xg_base;
	if (watch_active && address - XG_WINDOW_BASE < XG_WINDOW_SIZE)
	{
		uint32_t page = (uint32_t)(address - XG_WINDOW_BASE) / WATCH_SMALL;
		if (watch_protected[page])
		{
			watch_written(page);
			return;
		}
	}
	if (reporting)
	{
		/* the reporter itself faulted: never recurse; the default action ends it */
		signal(number, SIG_DFL);
		return;
	}
	reporting = 1;
	report(number, information, context);
	/* returning re-runs the original instruction under the default action,
	   so the system's crash report names the first fault, not the reporter */
	signal(number, SIG_DFL);
}

void xg_install_signal_handlers(void)
{
	struct sigaction action;
	memset(&action, 0, sizeof(action));
	action.sa_flags = SA_SIGINFO | SA_NODEFER | SA_ONSTACK;
	action.sa_sigaction = fault;
	sigaction(SIGSEGV, &action, NULL);
	sigaction(SIGBUS, &action, NULL);
	sigaction(SIGILL, &action, NULL);
	sigaction(SIGTRAP, &action, NULL);
}

void xg_bad_transfer(uint32_t target)
{
	xg_fatal("guest code jumped to 0x%08x, which is not translated code", target);
}
