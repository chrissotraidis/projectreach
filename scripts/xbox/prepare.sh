#!/bin/sh
# Prepares the Xbox engine for a platform build (scripts/xbox/build-mac.sh,
# scripts/xbox/build-ios.sh): the pinned checkout, upstream's guest image,
# its translation and the generated host sources, in ref/xbox-build/out.
#
# Everything upstream-derived stays under the ignored ref/xbox-build/:
#   engine.sparsebundle   a case-sensitive volume (upstream's headers need one)
#   vol/engine            the pinned checkout (config/xbox-engine.lock.json)
#   ndk/                  the few Android NDK pieces the guest build asks for
#   out/                  the guest image, its translation and the program
set -eu
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
# Scheduled and manual builds must not rewrite the shared engine concurrently.
if ! python3 "$ROOT/scripts/xbox/build_lock.py" --check; then
    exec python3 "$ROOT/scripts/xbox/build_lock.py" -- /bin/sh "$0" "$@"
fi
WORK="$ROOT/ref/xbox-build"
LLVM=${XBOX_LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
LOCK="$ROOT/config/xbox-engine.lock.json"
REV=${XBOX_REV:-}; [ -n "$REV" ] || REV=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['revision'])" "$LOCK")
URL=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['url'])" "$LOCK")
mkdir -p "$WORK/out" "$WORK/vol"

# ---------- the case-sensitive volume and the pinned checkout
if [ ! -d "$WORK/engine.sparsebundle" ]; then
	hdiutil create -quiet -type SPARSEBUNDLE -fs 'Case-sensitive APFS' -volname HaloXboxEngine -size 40g "$WORK/engine.sparsebundle"
fi
if ! mount | grep -q " on $WORK/vol "; then
	hdiutil attach -quiet -nobrowse -mountpoint "$WORK/vol" "$WORK/engine.sparsebundle"
fi
ENGINE="$WORK/vol/engine"
if [ ! -d "$ENGINE/.git" ]; then
	git clone -q "$URL" "$ENGINE"
fi
if [ -n "$(git -C "$ENGINE" status --porcelain --untracked-files=no)" ]; then
	echo "Xbox upstream checkout has local edits; preserve them before rebuilding" >&2
	exit 1
fi
if [ "$(git -C "$ENGINE" rev-parse HEAD)" != "$REV" ]; then
	git -C "$ENGINE" fetch -q origin
	git -C "$ENGINE" checkout -q "$REV"
fi

# ---------- the NDK pieces: upstream's guest build only needs lld, llvm-ar
# and the Khronos OpenGL ES headers
NDK="$WORK/ndk"
BIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
INC="$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include"
mkdir -p "$BIN" "$INC/GLES3" "$INC/GLES2" "$INC/KHR"
ln -sf "$(command -v ld.lld)" "$BIN/ld.lld"
ln -sf "$LLVM/llvm-ar" "$BIN/llvm-ar"
ln -sf "$LLVM/clang" "$BIN/clang"
KHRONOS=https://raw.githubusercontent.com/KhronosGroup
for f in GLES3/gl32.h GLES3/gl31.h GLES3/gl3.h GLES3/gl3platform.h GLES2/gl2ext.h GLES2/gl2.h GLES2/gl2platform.h; do
	[ -f "$INC/$f" ] || curl -fsSL "$KHRONOS/OpenGL-Registry/main/api/$f" -o "$INC/$f"
done
[ -f "$INC/KHR/khrplatform.h" ] || curl -fsSL "$KHRONOS/EGL-Registry/main/api/KHR/khrplatform.h" -o "$INC/KHR/khrplatform.h"

# ---------- the guest image (upstream's Android guest, our compiler flags)
python3 "$ROOT/scripts/xbox/guest_adaptation.py" --engine "$ENGINE" --ndk "$NDK" \
	--compiler "$ROOT/scripts/xbox/guest-cc.sh" --out "$WORK/out"
GUEST="$ENGINE/build/android"
OUT="$WORK/out"

# ---------- translation and generated host sources
python3 "$ROOT/scripts/xbox/translate.py" "$OUT/halo_guest.elf" "$OUT/guest.s" \
	--imports "$ENGINE/port/android/host_imports.list" "$ROOT/port/xbox/guest_imports.list" "$GUEST/guest/gen/gl_imports.list" "$GUEST/guest/gen/posix_imports.list"
sed -n 's/^#define __NR_\([a-z0-9_]*\)[[:space:]]*\([0-9]*\)$/#define LX_NR_\1 \2/p' \
	"$GUEST/guest/libc_include/bits/syscall.h" > "$OUT/xg_linux_nr.h"
python3 "$ROOT/scripts/xbox/gen-host-gl.py" "$GUEST/guest/gen/guest_gl.c" "$OUT/xg_gl_gen.c"
# The pin predates upstream's extra UPnP argument. Keep rollback builds ABI-safe.
python3 - "$ENGINE/port/linux/src/posix.h" "$OUT/xg_engine_compat.h" <<'PY'
import pathlib, re, sys
source = pathlib.Path(sys.argv[1]).read_text()
signature = re.search(r'int posix_upnp_forward_udp\((.*?)\);', source, re.S).group(1)
pathlib.Path(sys.argv[2]).write_text(
    '#define XG_UPNP_PREFERRED_PORT ' + str(int('preferred_port' in signature)) + '\n')
PY
