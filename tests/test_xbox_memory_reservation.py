"""Exercise the production guest allocator, including its address contract."""
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class MemoryReservationTests(unittest.TestCase):
    def test_real_aligned_reservation_mapping_and_unmapping(self):
        source = r'''
#include "xg_host.h"
#include <assert.h>
#include <mach/mach.h>
#include <stdlib.h>
#include <sys/mman.h>
char xg_text[1];
void xg_log(const char *format, ...) { (void)format; }
void xg_fatal(const char *format, ...) { (void)format; abort(); }
int xg_linux_errno(int error) { return error; }
int main(void) {
    assert(xg_memory_initialize() == 0);
    assert(xg_base && !(xg_base & 0xffffffffULL));
    volatile unsigned char *window = G(volatile unsigned char *, XG_WINDOW_BASE);
    window[0] = 17; window[XG_WINDOW_SIZE - 1] = 29;
    assert(window[0] == 17 && window[XG_WINDOW_SIZE - 1] == 29);
    uint32_t guest = xg_map(XG_PAGE, PROT_READ | PROT_WRITE);
    assert(guest >= 0x10000000 && guest < XG_WINDOW_BASE);
    unsigned char *host = G(unsigned char *, guest);
    assert(GA(host) == guest && !host[0] && !host[XG_PAGE - 1]);
    host[0] = 43; host[XG_PAGE - 1] = 71;
    assert(host[0] == 43 && host[XG_PAGE - 1] == 71);
    xg_unmap(guest, XG_PAGE);
    unsigned char byte = 0; vm_size_t read = 0;
    assert(vm_read_overwrite(mach_task_self(), (vm_address_t)host, 1,
        (vm_address_t)&byte, &read) != KERN_SUCCESS);
    assert(xg_guest_mmap(0xffe00000, XG_PAGE, PROT_READ | PROT_WRITE,
        0x10 | 0x20, -1, 0) == 0xffe00000L);
    host = G(unsigned char *, 0xffe00000);
    host[0] = 113; assert(host[0] == 113);
    assert(vm_deallocate(mach_task_self(), xg_base, 0x100000000ULL) == KERN_SUCCESS);
    return 0;
}
'''
        with tempfile.TemporaryDirectory() as folder:
            binary = pathlib.Path(folder) / 'memory-test'
            subprocess.run(['xcrun', 'clang', '-O2', '-Wall', '-Werror',
                            '-I', str(ROOT / 'port/xbox'), '-x', 'c', '-',
                            str(ROOT / 'port/xbox/xg_memory.c'), '-o', str(binary)],
                           input=source, text=True, capture_output=True, check=True)
            subprocess.run([str(binary)], capture_output=True, check=True, timeout=15)
