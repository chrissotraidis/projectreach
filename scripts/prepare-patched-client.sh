#!/usr/bin/env bash
# Reproduce the Halo Custom Edition 1.10 client files from the supplied CE 1.00
# installer and Bungie's official CE 1.10 update, using a fresh throwaway Wine
# prefix (docs/INSTALL-WINE.md). Nothing is installed and no product key is involved.
#
# Usage: scripts/prepare-patched-client.sh [--keep-bottle]
# Prints the run directory (generated/patchwork/run-*) and writes evidence to
# docs/artifacts/<date>/G1a/prepare-<run>/.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PY="$ROOT/.venv/bin/python"
INSTALLER="$ROOT/ref/HaloCESetup.exe"
PATCH="$ROOT/ref/inputs/patches/haloce-patch-1.0.10.exe"
INSTALLER_SHA=150e430dc54ffb265cbe96605ef8909c9ba0065fa11bdbf170bfd88391cf98ba
PATCH_SHA=33818f3f56b7dddc8c61d654af6567c9c5b9220ca75d6ac23a52611038257508
TARGETS=(haloce.exe haloceded.exe Strings.dll binkw32.dll config.txt patchw32.dll msvcr71.dll)
TIMEOUT_S=${HALOPAD_PATCH_TIMEOUT:-240}
KEEP_BOTTLE=0
[[ "${1:-}" == "--keep-bottle" ]] && KEEP_BOTTLE=1

die() { echo "FAIL: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

command -v wine >/dev/null || die "wine is required; see docs/INSTALL-WINE.md"
command -v 7zz >/dev/null || die "7zz (7-Zip) is required"
[[ -f "$INSTALLER" ]] || die "missing $INSTALLER"
[[ -f "$PATCH" ]] || die "missing $PATCH"
[[ "$(sha "$INSTALLER")" == "$INSTALLER_SHA" ]] || die "installer hash differs from the recorded supplied installer"
[[ "$(sha "$PATCH")" == "$PATCH_SHA" ]] || die "patch hash differs from the recorded official CE 1.10 update"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
WORK="$ROOT/generated/patchwork/run-$RUN_ID"
EVID="$ROOT/docs/artifacts/$(date +%Y-%m-%d)/G1a/prepare-$RUN_ID"
BOTTLE_DIR="$WORK/prefix"
UPDATER_PID=""
mkdir -p "$WORK/files" "$WORK/patch" "$EVID"

for f in "${TARGETS[@]}"; do
  7zz e -y -so "$INSTALLER" "$f" > "$WORK/files/$f" 2>/dev/null
  [[ -s "$WORK/files/$f" ]] || die "installer does not contain $f"
done
(cd "$WORK/files" && shasum -a 256 "${TARGETS[@]}") > "$EVID/before.sha256"

7zz e -y -o"$WORK/patch" "$PATCH" >/dev/null
# 7-Zip normally opens the cabinet embedded in the patch executable directly;
# fall back to extracting the raw resource cabinet if it did not.
if [[ ! -s "$WORK/patch/patch.rtp" && -s "$WORK/patch/CABINET" ]]; then
  7zz e -y -o"$WORK/patch" "$WORK/patch/CABINET" >/dev/null
fi
for f in haloupdate.exe patch.rtp; do
  [[ -s "$WORK/patch/$f" ]] || die "patch cabinet does not contain $f"
  cp "$WORK/patch/$f" "$WORK/files/$f"
done
(cd "$WORK/patch" && shasum -a 256 haloupdate.exe patch.rtp) > "$EVID/patch-contents.sha256"

export WINEPREFIX="$BOTTLE_DIR" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=;winedbg=d"
stop_bottle() {
  if [[ -d "$BOTTLE_DIR" ]]; then
    wineserver -k >/dev/null 2>&1 || true
  fi
  if [[ -n "$UPDATER_PID" ]]; then
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$UPDATER_PID" 2>/dev/null || break
      sleep 1
    done
    if kill -0 "$UPDATER_PID" 2>/dev/null; then
      pkill -9 -P "$UPDATER_PID" 2>/dev/null || true
      kill -9 "$UPDATER_PID" 2>/dev/null || true
    fi
    wait "$UPDATER_PID" 2>/dev/null || true
    UPDATER_PID=""
  fi
}

cleanup() {
  stop_bottle
  if [[ $KEEP_BOTTLE -eq 0 && -d "$BOTTLE_DIR" ]]; then
    rm -rf "$BOTTLE_DIR"
  fi
}
trap cleanup EXIT

wineboot -i > "$EVID/wineboot.log" 2>&1 || die "could not create the Wine prefix (see $EVID/wineboot.log)"

(cd "$WORK/files" && wine \
  haloupdate.exe processrtp=patch.rtp updateversion=01.00.10.0621 > "$EVID/haloupdate.log" 2>&1) &
UPDATER_PID=$!

version() { "$PY" -c 'import sys,pefile
p=pefile.PE(sys.argv[1],fast_load=True); p.parse_data_directories([2]); f=p.VS_FIXEDFILEINFO[0]
print("%d.%d.%d.%d"%(f.FileVersionMS>>16,f.FileVersionMS&0xffff,f.FileVersionLS>>16,f.FileVersionLS&0xffff))' "$1" 2>/dev/null || echo none; }
snapshot() { (cd "$WORK/files" && ls -l haloce.exe haloceded.exe [Ss]trings.dll 2>/dev/null | awk '{print $5, $6, $7, $8, $9}'); }

start=$SECONDS; stable=0; last=""
while true; do
  (( SECONDS - start > TIMEOUT_S )) && die "updater did not produce a stable 1.0.10.621 haloce.exe within ${TIMEOUT_S}s"
  sleep 3
  if [[ "$(version "$WORK/files/haloce.exe")" == "1.0.10.621" && "$(version "$WORK/files/haloceded.exe")" == "1.0.10.621" ]]; then
    now=$(snapshot)
    if [[ "$now" == "$last" ]]; then stable=$((stable + 1)); else stable=0; last="$now"; fi
    (( stable >= 3 )) && break
  elif ! kill -0 $UPDATER_PID 2>/dev/null; then
    die "updater exited before patching completed (see $EVID/haloupdate.log)"
  fi
done
echo "patched after $((SECONDS - start))s" > "$EVID/timing.txt"
stop_bottle
pgrep -f "haloupdate.exe processrtp" >/dev/null && die "updater still running after stop"

(cd "$WORK/files" && find . -type f ! -name haloupdate.exe ! -name patch.rtp | sed 's|^\./||' | sort -f \
  | while IFS= read -r f; do shasum -a 256 "$f"; done) > "$EVID/after.sha256"
"$PY" - "$WORK/files" "$EVID" "$RUN_ID" "$INSTALLER_SHA" "$PATCH_SHA" <<'EOF'
import hashlib, json, pathlib, subprocess, sys
files, evid, run, inst, patch = sys.argv[1:]
files = pathlib.Path(files); before = {}
for line in (pathlib.Path(evid) / 'before.sha256').read_text().split('\n'):
    if line.strip():
        h, n = line.split(None, 1); before[n.strip().lower()] = h
out = []
for p in sorted((q for q in files.rglob('*') if q.is_file()), key=lambda q: str(q).lower()):
    rel = p.relative_to(files).as_posix()
    if rel in ('haloupdate.exe', 'patch.rtp'):
        continue
    h = hashlib.sha256(p.read_bytes()).hexdigest()
    out.append({'path': rel, 'size': p.stat().st_size, 'sha256': h,
                'origin': 'installer' if before.get(rel.lower()) == h else 'patch'})
wine = subprocess.run(['wine', '--version'], capture_output=True, text=True).stdout.strip()
manifest = {'schema': 1, 'run': run, 'installer_sha256': inst, 'patch_sha256': patch,
            'method': 'haloupdate.exe processrtp=patch.rtp updateversion=01.00.10.0621',
            'wine_version': wine, 'files': out}
(pathlib.Path(evid) / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
for f in out:
    print(f"{f['origin']:9} {f['sha256']}  {f['path']}")
EOF
echo "RUN_DIR=$WORK"
echo "EVIDENCE=$EVID"
