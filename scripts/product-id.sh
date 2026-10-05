#!/bin/sh
# Halo Custom Edition's product ID for your personal HaloPad build, from your own
# product key and your own installer's PIDGen.dll, called exactly as Halo's
# installer calls it (scripts/product-id/pid.c). Halo refuses to start without it.
#
#   scripts/product-id.sh --installer "ref/Halo CE/HaloCESetup.exe" [--out FILE]
#
# The key is read from a hidden prompt (or standard input) and never written to
# disk. The output holds only the two registry values Halo's installer writes;
# it stays in generated/ (ignored) and goes into your own app with
# build-ios-app.py --product-id. Never share it or an app built with it.
# Needs Wine (docs/INSTALL-WINE.md), winetricks (for Microsoft's MFC42 runtime), sevenzip (7zz) and llvm.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
INSTALLER=""
OUT="$ROOT/generated/product-id/product-id.txt"
while [ $# -gt 0 ]; do
	case "$1" in
	--installer) INSTALLER=$2; shift ;;
	--out) OUT=$2; shift ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done
[ -f "$INSTALLER" ] || { echo "--installer: your HaloCESetup.exe is required" >&2; exit 2; }
LLVM=/opt/homebrew/opt/llvm/bin
LLD=$(command -v lld-link || echo "$LLVM/lld-link")
for tool in wine winetricks 7zz "$LLVM/clang" "$LLD" "$LLVM/llvm-dlltool"; do
	command -v "$tool" >/dev/null || { echo "missing $tool (brew install winetricks sevenzip llvm lld; for Wine see docs/INSTALL-WINE.md)" >&2; exit 2; }
done
WORK=$(mktemp -d "$ROOT/generated/product-id-work.XXXXXX")
# winedbg disabled: a crash fails at once instead of waiting in Wine's debugger
export WINEPREFIX="$WORK/prefix" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=;winedbg=d"
cleanup() { wineserver -k >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

7zz e -y -o"$WORK" "$INSTALLER" PidGen.dll >/dev/null || { echo "PidGen.dll is not in that installer" >&2; exit 3; }
printf 'LIBRARY kernel32.dll\nEXPORTS\nLoadLibraryA@4\nGetProcAddress@8\nGetStdHandle@4\nReadFile@20\nWriteFile@20\nExitProcess@4\n' > "$WORK/kernel32.def"
# -k: import the plain names (GetStdHandle), as kernel32 exports them, not GetStdHandle@4
"$LLVM/llvm-dlltool" -k -m i386 -d "$WORK/kernel32.def" -l "$WORK/kernel32.lib"
"$LLVM/clang" --target=i686-pc-windows-msvc -O1 -ffreestanding -fno-builtin -c "$ROOT/scripts/product-id/pid.c" -o "$WORK/pid.obj"
"$LLD" /nologo /entry:start /subsystem:console /nodefaultlib "$WORK/pid.obj" "$WORK/kernel32.lib" /out:"$WORK/pidtool.exe"
echo "Preparing a temporary Windows runtime (MFC42, downloaded from Microsoft by winetricks)..." >&2
winetricks -q mfc42 > "$WORK/winetricks.log" 2>&1 || { echo "winetricks mfc42 failed; see output above" >&2; tail -5 "$WORK/winetricks.log" >&2; exit 4; }

if [ -t 0 ]; then
	printf 'Your Halo PC product key (XXXXX-XXXXX-XXXXX-XXXXX-XXXXX): ' >&2
	stty -echo; read -r KEY; stty echo; echo >&2
else
	read -r KEY
fi
RESULT=$(printf '%s\n' "$KEY" | (cd "$WORK" && wine pidtool.exe 2>/dev/null) | tr -d '\r') || true
KEY=""
PID=$(printf '%s\n' "$RESULT" | sed -n 's/^PID //p')
DPID=$(printf '%s\n' "$RESULT" | sed -n 's/^DPID //p')
if [ -z "$PID" ] || [ -z "$DPID" ]; then
	printf '%s\n' "$RESULT" | grep '^ERROR' >&2 || echo "PIDGen produced no product ID" >&2
	exit 5
fi
mkdir -p "$(dirname "$OUT")"
KEYPATH='HKLM\Software\Microsoft\Microsoft Games\Halo CE'
{
	echo "# Halo CE product ID for one player's personal HaloPad build. Private: never share."
	echo "value $KEYPATH 1 $(printf PID | xxd -p) $(printf '%s' "$PID" | xxd -p | tr -d '\n')00"
	echo "value $KEYPATH 3 $(printf DigitalProductID | xxd -p | tr -d '\n') $DPID"
} > "$OUT"
chmod 600 "$OUT"
echo "wrote $OUT" >&2
