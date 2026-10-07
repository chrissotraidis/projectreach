#!/usr/bin/env bash
# One command for a connected iPhone/iPad: build, sign, install, and put your game package
# in HaloPad's Documents so the first launch can import it (docs/INSTALL-IPHONE.md).
#
#   scripts/install-device.sh --identity "Apple Development: Name (TEAMID)" \
#       --profile ~/Downloads/HaloPad.mobileprovision --game "/path/to/Halo Custom Edition"
#
# On another Mac, without the build tree, install a prebuilt app and its matching package
# (the handoff folder made on the build Mac) instead:
#
#   scripts/install-device.sh --identity "..." --profile X.mobileprovision \\
#       --app HaloPad.app --package Halo-CE.halopad.zip
# Xbox-only apps need only --app; import the Xbox disc in HaloPad after installation.
# Use --ipa HaloPad.ipa instead of --app to stage the IPA automatically.
# Add --check-only to check the app/profile/device without signing or installing.
#
# Options: --device ID (default: the only connected device), --work RUN_DIR.
# Development builds use the menu scene (tests/halo_app_scene.c, the scene the physical iPad and
# iPhone builds are tested with) until Halo's normal start-up can find the product ID its
# original installer writes.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PY="$ROOT/.venv/bin/python"; [[ -x "$PY" ]] || PY=python3
IDENTITY="" PROFILE="" GAME="" DEVICE="" WORK="" PREBUILT="" PACKAGE="" IPA="" CHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity) IDENTITY=$2; shift 2 ;;
    --profile) PROFILE=$2; shift 2 ;;
    --game) GAME=$2; shift 2 ;;
    --device) DEVICE=$2; shift 2 ;;
    --work) WORK=$2; shift 2 ;;
    --app) PREBUILT=$2; shift 2 ;;
    --ipa) IPA=$2; shift 2 ;;
    --check-only) CHECK=1; shift ;;
    --package) PACKAGE=$2; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
die() { echo "error: $*" >&2; exit 1; }
[[ -n "$IDENTITY" ]] || die "--identity is required (security find-identity -v -p codesigning)"
[[ -f "$PROFILE" ]] || die "--profile must name a .mobileprovision for dev.halopad.HaloPad"
[[ -z "$IPA" || ( -z "$PREBUILT" && -z "$GAME" ) ]] || die "use --ipa without --app or --game"
[[ "$CHECK" == 0 || -n "$IPA" || -n "$PREBUILT" ]] || die "--check-only needs --ipa or --app"
WORK_TMP=$(mktemp -d)
trap 'rm -rf "$WORK_TMP"' EXIT
if [[ -n "$IPA" ]]; then
  [[ -f "$IPA" ]] || die "--ipa must name your HaloPad IPA"
  echo "==> Checking and unpacking your IPA"
  PREBUILT=$("$PY" "$ROOT/scripts/extract-ipa.py" "$IPA" "$WORK_TMP/unpacked")
fi
if [[ -n "$PREBUILT" ]]; then
  [[ -d "$PREBUILT" ]] || die "--app needs a HaloPad.app folder"
  if [[ -n "$PACKAGE" ]]; then
    [[ -f "$PACKAGE" ]] || die "--package must name the matching .halopad.zip"
  else
    [[ ! -f "$PREBUILT/data/core-identity.json" &&
       -f "$PREBUILT/data/xbox/build.json" &&
       -f "$PREBUILT/data/xbox/halo_guest.elf" &&
       -f "$PREBUILT/data/xbox/brokers.txt" ]] || die "PC and combined apps need --package with their matching .halopad.zip; only Xbox-only apps can omit it"
  fi
else
  [[ -d "$GAME" ]] || die "--game must name your Halo Custom Edition 1.10 folder"
fi

if [[ -z "$DEVICE" ]]; then
  JSON="$WORK_TMP/devices.json"
  xcrun devicectl list devices --json-output "$JSON" >/dev/null
  DEVICE=$("$PY" "$ROOT/scripts/device-id.py" "$JSON")
  [[ -n "$DEVICE" ]] || die "connect and trust exactly one iPhone/iPad, or pass --device (xcrun devicectl list devices)"
fi

"$PY" "$ROOT/scripts/device_profile.py" --profile "$PROFILE" --identity "$IDENTITY" --device "$DEVICE"

if [[ "$CHECK" == 1 ]]; then
  "$PY" "$ROOT/scripts/sign-app.py" "$PREBUILT" --identity "$IDENTITY" --profile "$PROFILE" --check-only
  echo "Preflight passed. Nothing signed or installed; device launch remains untested."
  exit 0
fi

if [[ -n "$PREBUILT" ]]; then
  echo "==> Signing the prebuilt app for your team"
  STAGE="$WORK_TMP/signed"
  mkdir "$STAGE"
  ditto "$PREBUILT" "$STAGE/HaloPad.app"
  APP="$STAGE/HaloPad.app"
  "$PY" "$ROOT/scripts/sign-app.py" "$APP" --identity "$IDENTITY" --profile "$PROFILE"
  PKG="$PACKAGE"
else
  echo "==> Building for the device"
  WORKARG=()
  [[ -n "$WORK" ]] && WORKARG=(--work "$WORK")
  BUILD_LOG="$WORK_TMP/build.log"
  "$PY" "$ROOT/scripts/build-ios-app.py" --iphoneos --identity "$IDENTITY" --profile "$PROFILE" \
    --scene "$ROOT/tests/halo_app_scene.c" ${WORKARG[@]+"${WORKARG[@]}"} | tee "$BUILD_LOG"
  APP=$("$PY" - "$ROOT" "$BUILD_LOG" <<'PY'
import pathlib, plistlib, sys
paths = [line[6:] for line in pathlib.Path(sys.argv[2]).read_text().splitlines()
         if line.startswith('built ')]
if not paths:
    sys.exit('error: build did not report a HaloPad app')
app = pathlib.Path(sys.argv[1]) / paths[-1]
info = app / 'Info.plist'
if not info.is_file() or plistlib.loads(info.read_bytes()).get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
    sys.exit(f'error: {app} is not a device build')
print(app)
PY
  )

  echo "==> Preparing your game package for this build"
  PKG="$ROOT/generated/prepared/device-$(date +%Y%m%d-%H%M%S).halopad.zip"
  "$PY" "$ROOT/scripts/prepare-game-data.py" --app-data "$APP/data" --game "$GAME" --output "$PKG"
fi

echo "==> Installing on $DEVICE"
xcrun devicectl device install app --device "$DEVICE" "$APP"
if [[ -n "$PKG" ]]; then
  xcrun devicectl device copy to --device "$DEVICE" --domain-type appDataContainer \
    --domain-identifier dev.halopad.HaloPad --source "$PKG" --destination "Documents/$(basename "$PKG")"
  echo "Done. Open HaloPad, choose Custom Edition, tap Choose Prepared Package, and pick $(basename "$PKG")."
else
  echo "Done. Open HaloPad, choose Add Your Xbox Disc, and select your Xbox ISO/XISO in Files."
fi
