#!/bin/sh
# Builds the Xbox engine as a macOS program (the Mac proof):
#   scripts/xbox/build-mac.sh     -> ref/xbox-build/out/halopad-xbox
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# Scheduled and manual builds must not rewrite the shared engine concurrently.
if ! python3 "$ROOT/scripts/xbox/build_lock.py" --check; then
    exec python3 "$ROOT/scripts/xbox/build_lock.py" -- /bin/sh "$0" "$@"
fi
"$ROOT/scripts/xbox/prepare.sh"
WORK="$ROOT/ref/xbox-build"
ENGINE="$WORK/vol/engine"
OUT="$WORK/out"
INC="$WORK/ndk/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include"

# ---------- the macOS program
CFLAGS="-O2 -g -Wall -Wno-unused-function -I$ROOT/port/xbox -I$OUT -I$INC -I/opt/homebrew/include -mmacosx-version-min=14.4"
OBJ="$OUT/obj-macos"
mkdir -p "$OBJ"
for f in xg_memory xg_thread xg_syscall xg_gl xg_sdl xg_posix xg_main_macos; do
	clang $CFLAGS -c "$ROOT/port/xbox/$f.c" -o "$OBJ/$f.o"
done
clang $CFLAGS -c "$OUT/xg_gl_gen.c" -o "$OBJ/xg_gl_gen.o"
for f in posix_files posix_net; do
	clang -O2 -w -include "$ROOT/port/xbox/xg_darwin_compat.h" -I"$ENGINE/port/linux/src" \
		-c "$ENGINE/port/linux/src/$f.c" -o "$OBJ/upstream_$f.o"
done
clang -c "$ROOT/port/xbox/xg_runtime.s" -o "$OBJ/xg_runtime.o"
clang -c "$OUT/guest.s" -o "$OBJ/guest.o"
clang -o "$OUT/halopad-xbox" "$OBJ"/*.o -L/opt/homebrew/lib -lSDL3 -mmacosx-version-min=14.4
# The translated executable and loaded guest must come from the same build.
python3 - "$ENGINE" "$OUT" <<'PY'
import datetime, hashlib, json, pathlib, subprocess, sys
engine, out = sys.argv[1], pathlib.Path(sys.argv[2])
manifest = {
    'revision': subprocess.check_output(['git', '-C', engine, 'rev-parse', 'HEAD'], text=True).strip(),
    'built': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d'),
    'guest_sha256': hashlib.sha256((out / 'halo_guest.elf').read_bytes()).hexdigest(),
    'guest_adaptation': json.loads((out / 'guest-adaptation.json').read_text()),
    'executable_sha256': hashlib.sha256((out / 'halopad-xbox').read_bytes()).hexdigest(),
}
(out / 'build-mac.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
echo "built $OUT/halopad-xbox"
