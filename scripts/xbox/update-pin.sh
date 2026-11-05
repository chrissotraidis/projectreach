#!/bin/sh
# Moves the Xbox engine's pin to a newer upstream revision, safely
# (docs/XBOX-ENGINE.md, "Updating the engine").
#
#   scripts/xbox/update-pin.sh [--to REV] [--simulator UDID] [--device UDID] [--accept]
#
# 1. fetches upstream and lists what changed since the pin, flagging changes to
#    the parts HaloPad's host depends on (the Android guest and its imports);
# 2. backs up the Xbox saves: this Mac's test saves and, with --device, the
#    iPad/iPhone's Documents/Halo Xbox/save (upstream's saves are memory
#    snapshots that a changed engine may not load);
# 3. builds the candidate (scripts/xbox/build-mac.sh) and runs the Mac smoke
#    test (scripts/xbox/smoke-mac.py: menu, campaign, match);
# 4. writes the new revision into config/xbox-engine.lock.json only with
#    --accept and only if every check passed; otherwise the checkout goes back
#    to the pinned revision.
# After accepting, rebuild the apps (scripts/xbox/build-ios.sh, then
# scripts/build-ios-app.py) and install them over the existing app.
set -eu
if [ "${HALOPAD_XBOX_GUEST_ADAPTATION:-none}" != none ] || [ "${HALOPAD_SERVICE_RECORD:-0}" != 0 ]; then
    echo "Upstream pin updates require an unadapted guest; test HaloPad adaptations separately" >&2
    exit 2
fi
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
WORK="$ROOT/ref/xbox-build"
ENGINE="$WORK/vol/engine"
LOCK="$ROOT/config/xbox-engine.lock.json"
TO=origin/main
DEVICE=""
SIMULATOR=""
ACCEPT=0
while [ $# -gt 0 ]; do
	case "$1" in
	--to) TO=$2; shift ;;
	--device) DEVICE=$2; shift ;;
	--simulator) SIMULATOR=$2; shift ;;
	--accept) ACCEPT=1 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done
if [ "$ACCEPT" -eq 1 ] && [ -z "$SIMULATOR" ]; then
	echo "--accept requires --simulator UDID so an Apple runtime pass gates the update" >&2
	exit 2
fi
PINNED=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['revision'])" "$LOCK")
XBOX_REV="$PINNED" "$ROOT/scripts/xbox/prepare.sh" >/dev/null   # mounts the volume and checks out the pin
git -C "$ENGINE" fetch -q origin
TARGET=$(git -C "$ENGINE" rev-parse "$TO")
if [ "$TARGET" = "$PINNED" ]; then
	echo "already pinned at $PINNED"
	exit 0
fi
echo "==> upstream changes $PINNED..$TARGET"
git -C "$ENGINE" log --oneline "$PINNED..$TARGET"
echo "==> changes to what HaloPad's host depends on"
git -C "$ENGINE" diff --stat "$PINNED" "$TARGET" -- port/android port/include tools/android_build.py \
	tools/android_imports.py tools/android_gl_stubs.py tools/android_posix_stubs.py \
	tools/embed_assets.py port/linux/src port/linux/game/hud_hires_tags.c source/cache/cache_files.c | cat

STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$WORK/save-backups"
BACKUP=$(mktemp -d "$WORK/save-backups/$STAMP-from-$(echo "$PINNED" | cut -c1-8).XXXXXX")
echo "==> backing up saves to $BACKUP"
copy_saves() {
	ditto "$1" "$2"
	if ! diff -qr "$1" "$2"; then
		echo "save backup differs from its source; refusing the update: $2" >&2
		return 1
	fi
}
for folder in data/save save-ios; do
	if [ -d "$WORK/$folder" ]; then
		copy_saves "$WORK/$folder" "$BACKUP/mac-$(echo "$folder" | tr / -)"
	fi
done
if [ -n "$DEVICE" ]; then
	xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
		--domain-identifier dev.halopad.HaloPad --source "Documents/Halo Xbox/save" --destination "$BACKUP/device-save" >/dev/null
fi
if [ -n "$SIMULATOR" ]; then
	xcrun simctl boot "$SIMULATOR" 2>/dev/null || true
	xcrun simctl bootstatus "$SIMULATOR" -b >/dev/null
	xcrun simctl terminate "$SIMULATOR" dev.halopad.HaloPad 2>/dev/null || true
	# Updates require an inspectable existing app, not an assumed empty save set.
	CONTAINER=$(xcrun simctl get_app_container "$SIMULATOR" dev.halopad.HaloPad data)
	if [ -z "$CONTAINER" ] || [ ! -d "$CONTAINER" ]; then
		echo "Simulator app container is unreadable; refusing the update" >&2
		exit 1
	fi
	if [ -d "$CONTAINER/Documents/Halo Xbox/save" ]; then
		copy_saves "$CONTAINER/Documents/Halo Xbox/save" "$BACKUP/simulator-save"
	fi
fi
if ! find "$BACKUP" -type f -exec shasum -a 256 {} + > "$BACKUP.sha256"; then
	echo "save backup checksum failed; refusing the update: $BACKUP" >&2
	exit 1
fi
if [ -s "$BACKUP.sha256" ]; then
	shasum -a 256 -c "$BACKUP.sha256"
fi

# Interrupted or rejected candidates return to the pin. Libraries built for
# a rejected candidate are caught by the app packager's revision check.
RESTORE=1
restore_pin() {
	if [ "$RESTORE" -eq 1 ]; then
		git -C "$ENGINE" checkout -q "$PINNED"
		XBOX_REV="$PINNED" "$ROOT/scripts/xbox/build-mac.sh" > "$WORK/update-restore.log" 2>&1 || \
			echo "rebuilding the pinned engine failed; see $WORK/update-restore.log"
	fi
}
trap restore_pin 0
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

echo "==> building and testing $TARGET"
git -C "$ENGINE" checkout -q "$TARGET"
RESULT=1
if XBOX_REV="$TARGET" "$ROOT/scripts/xbox/build-mac.sh" > "$WORK/update-build.log" 2>&1; then
	if python3 "$ROOT/scripts/xbox/smoke-mac.py" --out "$WORK/smoke-results/$STAMP-$(echo "$TARGET" | cut -c1-8)"; then
		RESULT=0
	fi
else
	echo "build failed; see $WORK/update-build.log"
fi
if [ $RESULT -eq 0 ] && [ -n "$SIMULATOR" ]; then
	RESULT=1
	if XBOX_REV="$TARGET" "$ROOT/scripts/xbox/build-ios.sh" > "$WORK/update-simulator-build.log" 2>&1 && \
		XBOX_REV="$TARGET" "$ROOT/.venv/bin/python" "$ROOT/scripts/build-ios-app.py" \
		--device "$SIMULATOR" --device-data --launch --wait 3 >> "$WORK/update-simulator-build.log" 2>&1 && \
		python3 "$ROOT/scripts/xbox/smoke-simulator.py" --device "$SIMULATOR" \
		--out "$WORK/simulator-results/$STAMP-$(echo "$TARGET" | cut -c1-8)"; then
		RESULT=0
	fi
fi
if [ $RESULT -eq 0 ] && [ $ACCEPT -eq 1 ]; then
	# upstream later deletes old release tags: keep this one's name with the pin
	RELEASE=$(git -C "$ENGINE" tag --points-at "$TARGET" 2>/dev/null | grep '^build-' | head -n 1 || true)
	python3 - "$LOCK" "$TARGET" "$RELEASE" <<'EOF'
import datetime, json, sys
path, revision, release = sys.argv[1], sys.argv[2], sys.argv[3]
lock = json.load(open(path))
lock["revision"] = revision
if release:
    lock["release"] = release
else:
    lock.pop("release", None)
lock["pinned"] = datetime.date.today().isoformat()
open(path, "w").write(json.dumps(lock, indent=2) + "\n")
EOF
	RESTORE=0
	echo "==> pinned $TARGET; rebuild the apps and install over the existing app"
	exit 0
fi
restore_pin
RESTORE=0
if [ $RESULT -eq 0 ]; then
	echo "==> $TARGET passed; run again with --accept to pin it (the checkout is back at $PINNED)"
	exit 0
fi
echo "==> $TARGET did not pass; the pin stays at $PINNED"
exit 1
