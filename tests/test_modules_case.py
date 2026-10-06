import os
from pathlib import Path
import resource
import shutil
import signal
import struct
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'port/runtime'


class ResourceModulePathTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which('clang')
        if not compiler:
            raise unittest.SkipTest('clang is required')
        parent = ROOT / 'generated'
        parent.mkdir(exist_ok=True)
        cls.temp = tempfile.TemporaryDirectory(prefix='modules-case-', dir=parent)
        cls.addClassCleanup(cls.temp.cleanup)
        cls.directory = Path(cls.temp.name)
        modules = (RUNTIME / 'halopad_modules.c').read_text()
        start = modules.index('static void map_datafile(module *m)')
        loader = modules[start:modules.index('/* ---- translated DLLs:', start)]
        kernel = (RUNTIME / 'halopad_kernel32.c').read_text()
        start = kernel.index('static char game_root[1024], state_root[1024];')
        filesystem = kernel[start:kernel.index('/* Make n->upper usable for writing:', start)]
        start = kernel.index('int halopad_host_path(')
        resolver = kernel[start:kernel.index('/* ---- time conversion ---- */', start)]
        harness = '''
#include "halopad_win32.h"
#include <dirent.h>
#include <errno.h>
#include <pthread.h>
#include <strings.h>
#include <sys/stat.h>
#define INSTALL HP_INSTALL_DIR
typedef struct { const char *name; uint32_t handle; int state; uint32_t refs; int translated; const char *dir; int datafile_only; } module;
static uint32_t mapped[8], nmapped;
static unsigned char guest[8192];
void *halopad_guest_ptr(uint32_t address) { return guest + (address - 0x3F800000u); }
void halopad_trace_guest_stack(void) {}
void halopad_log(const char *fmt, ...) {}
uint32_t halopad_vm_reserve(uint32_t address, uint32_t size, int commit_now) { return address; }
uint32_t VirtualProtect_c(uint32_t address, uint32_t size, uint32_t prot, uint32_t old) { return 1; }
''' + filesystem + resolver + loader + '''
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    module item = {.name = "strings.dll", .handle = 0x3F800000u};
    if (!strcmp(argv[1], "reference")) {
        item.name = "msxml4r.dll";
        item.dir = "system32";
    }
    map_datafile(&item);
    return guest[511] == (unsigned char)atoi(argv[2]) ? 0 : 3;
}
'''
        source = cls.directory / 'loader.c'
        source.write_text(harness)
        cls.binary = cls.directory / 'loader-test'
        result = subprocess.run([compiler, '-std=c11', '-D_POSIX_C_SOURCE=200809L',
                                 '-O2', '-pthread', '-I', str(RUNTIME), str(source),
                                 '-o', str(cls.binary)], capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError(result.stderr)

    def setUp(self):
        self.temp_case = tempfile.TemporaryDirectory(prefix='case-', dir=self.directory)
        self.addCleanup(self.temp_case.cleanup)
        self.base = Path(self.temp_case.name)
        self.game = self.base / 'game'
        self.state = self.base / 'state'
        self.reference = self.base / 'reference'
        for path in (self.game, self.state, self.reference):
            path.mkdir()
        self.env = dict(os.environ, HALOPAD_GAME_ROOT=str(self.game),
                        HALOPAD_STATE_ROOT=str(self.state),
                        HALOPAD_REFERENCE_ROOT=str(self.reference))

    def fixture(self, path, marker=1):
        data = bytearray(512)
        data[:2] = b'MZ'
        struct.pack_into('<I', data, 0x3c, 0x80)
        data[0x80:0x84] = b'PE\0\0'
        struct.pack_into('<H', data, 0x80 + 0x14, 224)
        struct.pack_into('<II', data, 0x80 + 0x50, 4096, 512)
        data[511] = marker
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def run_loader(self, mode='game', marker=1):
        def no_core():
            resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
        return subprocess.run([str(self.binary), mode, str(marker)], env=self.env,
                              capture_output=True, text=True, timeout=10, preexec_fn=no_core)

    def require_case_sensitive(self):
        probe = self.base / 'CaseProbe'
        probe.touch()
        if (self.base / 'caseprobe').exists():
            self.skipTest('requires a case-sensitive filesystem')

    def test_uppercase_resource_on_case_sensitive_filesystem(self):
        self.require_case_sensitive()
        self.fixture(self.game / 'Strings.dll')
        result = self.run_loader()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_lowercase_resource(self):
        self.fixture(self.game / 'strings.dll')
        result = self.run_loader()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_windows_writable_layer_takes_precedence(self):
        self.fixture(self.game / 'strings.dll', marker=1)
        self.fixture(self.state / 'install/STRINGS.DLL', marker=2)
        result = self.run_loader(marker=2)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_missing_resource_still_aborts(self):
        result = self.run_loader()
        self.assertEqual(result.returncode, -signal.SIGABRT, result.stderr)
        self.assertIn('LoadLibraryA', result.stderr)

    def test_reference_resource(self):
        self.fixture(self.reference / 'system32/msxml4r.dll')
        result = self.run_loader(mode='reference')
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == '__main__':
    unittest.main()
