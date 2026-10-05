#!/usr/bin/env bash
# HaloPad's one-command personal build (PadMint's entry point; padmint.json).
#
#   scripts/builder/build.sh <folder or HaloCESetup.exe> --ipa HaloPad.ipa [--out DIR] [--product-key-file FILE]
#   scripts/builder/build.sh <folder or HaloCESetup.exe> --mac --zip HaloPad-mac.zip [...]
#
# --mac makes HaloPad.app for Apple silicon Macs instead (the same app, zipped; it runs
# as built, with no Apple account), with its own game package in <zip>.data/.
# --xbox adds the Xbox edition: your Mac fetches the pinned OpenCE engine and
# ANGLE renderer from their own repositories and builds them into the same app (none of
# it is part of HaloPad). You add your Xbox disc image in the app.
#
# The folder (or the installer's own folder) holds your Halo Custom Edition installer
# (HaloCESetup.exe) and product-key.txt; the official 1.10 update (haloce-patch-1.0.10.exe)
# is used from there or downloaded. All are checked against the recorded hashes. It
# runs HaloPad's existing steps in order: tool build, 1.10 patch (Wine), translation of
# Halo and its four DLLs, the app, an unsigned IPA and its game package in <IPA>.data/
# (where PadMint picks it up). Install the IPA with your own signing, then choose the game
# package in HaloPad.
#
# Halo refuses to start without the product ID its installer writes. With
# product-key.txt beside the installer (or --product-key-file, or a hidden prompt when run
# in a terminal) your key goes through scripts/product-id.sh into your app only.
# Everything this makes contains translated game code and your game files: it is yours
# alone. Never share or upload it.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
PY=.venv/bin/python
export HALOPAD_BUILDER=1                              # steps leave tracked repository files unchanged
INPUT=""; OUT="$ROOT/generated/builder"; IPA=""; KEY_FILE=""; MAC=0; XBOX=0
while [ $# -gt 0 ]; do
	case "$1" in
	--out) OUT=$2; shift ;;
	--ipa|--zip) IPA=$2; shift ;;                     # the output: an IPA, or the Mac app's zip
	--mac) MAC=1 ;;
	--xbox) XBOX=1 ;;
	--product-key-file) KEY_FILE=$2; shift ;;
	--jobs) shift ;;                                  # accepted for PadMint; the steps size themselves
	-*) echo "unknown option $1" >&2; exit 2 ;;
	*) INPUT=$1 ;;
	esac
	shift
done
[ -f "$INPUT" ] && INPUT=$(dirname "$INPUT")          # PadMint passes the installer itself
[ -d "$INPUT" ] || { echo "usage: scripts/builder/build.sh <HaloCESetup.exe, beside haloce-patch-1.0.10.exe> --ipa FILE" >&2; exit 2; }
[ -n "$IPA" ] || { [ $MAC = 1 ] && IPA="$OUT/HaloPad-mac.zip" || IPA="$OUT/HaloPad.ipa"; }
mkdir -p "$OUT"
mkdir -p "$(dirname "$IPA")"
IPA="$(cd "$(dirname "$IPA")" && pwd)/$(basename "$IPA")"
OUT="$(cd "$OUT" && pwd)"
step() { printf '\n==> %s\n' "$*"; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

step "checking tools"
for tool in xcodebuild 7zz wine winetricks lld-link /opt/homebrew/opt/llvm/bin/clang; do
	command -v "$tool" >/dev/null || { echo "missing $tool: install Xcode, then brew install sevenzip winetricks llvm lld; for Wine see docs/INSTALL-WINE.md" >&2; exit 2; }
done
if [ $XBOX = 1 ]; then
	for tool in cmake ninja ld.lld git curl; do
		command -v "$tool" >/dev/null || { echo "missing $tool for the Xbox edition: brew install cmake ninja lld" >&2; exit 2; }
	done
fi
if ! "$PY" -c 'import pefile, capstone, SCons' 2>/dev/null; then   # a fresh checkout (PadMint's)
	step "setting up HaloPad's Python tools (.venv)"
	[ -x "$PY" ] || python3 -m venv .venv
	$PY -m pip install -q -r scripts/requirements-builder.txt
fi

step "finding your installer and the 1.10 update by hash"
INSTALLER_SHA=150e430dc54ffb265cbe96605ef8909c9ba0065fa11bdbf170bfd88391cf98ba
PATCH_SHA=33818f3f56b7dddc8c61d654af6567c9c5b9220ca75d6ac23a52611038257508
INSTALLER=""; PATCH=""
while IFS= read -r -d '' f; do
	case "$(sha "$f")" in
	"$INSTALLER_SHA") INSTALLER=$f ;;
	"$PATCH_SHA") PATCH=$f ;;
	esac
done < <(find "$INPUT" -maxdepth 2 -iname '*.exe' -print0)
[ -n "$INSTALLER" ] || { echo "no Halo Custom Edition 1.00 installer (HaloCESetup.exe) with the expected hash in $INPUT" >&2; exit 3; }
# Halo refuses to start without the product ID, so ask for the key before the long steps
[ -n "$KEY_FILE" ] || [ ! -f "$INPUT/product-key.txt" ] || KEY_FILE="$INPUT/product-key.txt"
[ -n "$KEY_FILE" ] || [ -t 0 ] || { echo "put product-key.txt (your Halo PC product key) beside HaloCESetup.exe; Halo will not start without it" >&2; exit 3; }
# 1.10 files assembled by an earlier build are reused; the update is needed only the first time
ACCEPTED=$($PY -c "import json;print(json.load(open('config/profiles/custom-en-1.0.10.0621.json'))['accepted_sha256'])")
ASSEMBLED=0
[ -f ref/inputs/custom-original/haloce.exe ] && [ "$(sha ref/inputs/custom-original/haloce.exe)" = "$ACCEPTED" ] && ASSEMBLED=1
# the steps read them from these ignored paths
mkdir -p ref/inputs/patches
[ -f ref/HaloCESetup.exe ] && [ "$(sha ref/HaloCESetup.exe)" = "$INSTALLER_SHA" ] || cp "$INSTALLER" ref/HaloCESetup.exe
SAVED_PATCH=ref/inputs/patches/haloce-patch-1.0.10.exe
if [ $ASSEMBLED = 0 ] && ! { [ -f "$SAVED_PATCH" ] && [ "$(sha "$SAVED_PATCH")" = "$PATCH_SHA" ]; }; then
	if [ -n "$PATCH" ]; then cp "$PATCH" "$SAVED_PATCH"
	else
		step "downloading Bungie's free 1.10 update"           # checked by hash below
		curl -fsSL --retry 2 -o "$SAVED_PATCH" https://ftp.zx.net.nz/pub/Game-Files/Halo/Patches/haloce-patch-1.0.10.exe || true
		[ -f "$SAVED_PATCH" ] && [ "$(sha "$SAVED_PATCH")" = "$PATCH_SHA" ] \
			|| { echo "could not download haloce-patch-1.0.10.exe; put it beside HaloCESetup.exe" >&2; exit 3; }
	fi
fi

step "fetching pinned sources and building the translator"
scripts/bootstrap-sources.sh
BUILD=$(scripts/build-lifter.sh | sed -n 's/^BUILT: //p')
[ -n "$BUILD" ] || { echo "translator build failed" >&2; exit 4; }

if [ $ASSEMBLED = 1 ]; then
	step "reusing your assembled 1.10 game files"
else
	step "applying the 1.10 update and assembling the game files"
	PATCHED=$(scripts/prepare-patched-client.sh | sed -n 's/^RUN_DIR=//p')
	$PY scripts/assemble-custom-original.py --patched-run "$PATCHED"
fi
$PY scripts/extract-reference-components.py

step "translating Halo and its DLLs"
runs() { { find generated/srw/custom-en-1.0.10.0621 -mindepth 1 -maxdepth 3 -type d -name 'run-*' -prune 2>/dev/null || true; } | sort; }
RUNS_BEFORE=$(runs)                                   # this build's translation runs are the new ones
for module in haloce keystone ksimeui controls msxml4; do
	scripts/srw-pipeline.sh "$BUILD" --module "$module"
done
WORK=$(ls -dt generated/srw/custom-en-1.0.10.0621/run-*/ | head -n 1)
$PY scripts/va-model.py --work "$WORK" --llasm "$BUILD/llasm/llasm"

PRODUCT_ID=()
if [ -n "$KEY_FILE" ] || [ -t 0 ]; then
	step "your product ID (Halo's installer step)"
	if [ -n "$KEY_FILE" ]; then scripts/product-id.sh --installer "$INSTALLER" < "$KEY_FILE"
	else scripts/product-id.sh --installer "$INSTALLER"; fi
	PRODUCT_ID=(--product-id generated/product-id/product-id.txt)
else
	echo "warning: no product key given; Halo will stop with 'Your product key is invalid' until you add one" >&2
fi

if [ $XBOX = 1 ]; then
	step "fetching and building the Xbox engine (OpenCE) for this app"
	export HALOPAD_XBOX_RENDERER=angle-metal HALOPAD_XBOX_GUEST_ADAPTATION=render-camera-v1   # the tested iPad build
	XSDK_FLAG=--device; [ $MAC = 0 ] || XSDK_FLAG=--mac
	# Online play needs the same network version as everyone else, and OpenCE moves it often:
	# try its newest release first, and fall back to HaloPad's tested pin if that does not apply
	# or build. HALOPAD_XBOX_PINNED=1 skips the attempt.
	PIN_REV=$($PY -c "import json;print(json.load(open('config/xbox-engine.lock.json'))['revision'])")
	LATEST_TAG=$(curl -fsSL --max-time 20 https://api.github.com/repos/OpenCommunityEdition/OpenCE/releases/latest 2>/dev/null |
		$PY -c "import json,sys;print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || true)
	LATEST_REV=""
	[ -z "$LATEST_TAG" ] || LATEST_REV=$(git ls-remote https://github.com/OpenCommunityEdition/OpenCE.git "refs/tags/$LATEST_TAG^{}" "refs/tags/$LATEST_TAG" 2>/dev/null | head -n 1 | cut -f1 || true)
	if [ "${HALOPAD_XBOX_PINNED:-0}" != 1 ] && [ -n "$LATEST_REV" ] && [ "$LATEST_REV" != "$PIN_REV" ]; then
		echo "trying OpenCE's newest release, $LATEST_TAG ($LATEST_REV); HaloPad's tested pin is the fallback"
		if XBOX_REV=$LATEST_REV HALOPAD_XBOX_LATEST=1 scripts/xbox/build-ios.sh $XSDK_FLAG; then
			export XBOX_REV=$LATEST_REV HALOPAD_XBOX_LATEST=1
		else
			echo "warning: OpenCE $LATEST_TAG did not build with HaloPad's changes; using the tested pin" >&2
			scripts/xbox/build-ios.sh $XSDK_FLAG
		fi
	else
		scripts/xbox/build-ios.sh $XSDK_FLAG
	fi
	XBOX_SETTING=on
else
	XBOX_SETTING=off                                  # the Windows edition alone
fi
if [ $MAC = 1 ]; then step "building HaloPad for your Mac"; TARGET=(--mac); else step "building HaloPad for iPhone and iPad"; TARGET=(--iphoneos); fi
APP_LOG="$OUT/build-app.log"
HALOPAD_XBOX=$XBOX_SETTING $PY scripts/build-ios-app.py "${TARGET[@]}" --work "$WORK" ${PRODUCT_ID[@]+"${PRODUCT_ID[@]}"} | tee "$APP_LOG"
[ $XBOX = 0 ] || hdiutil detach "$ROOT/ref/xbox-build/vol" -quiet 2>/dev/null || true   # the engine's volume (after its release tag is read)
APP=$(sed -n 's/^built //p' "$APP_LOG" | tail -n 1)
[ -d "$APP" ] || { echo "app build failed" >&2; exit 5; }

step "packaging your game files and the app"
PACKAGE="$IPA.data/Halo-CE.halopad.zip"               # PadMint copies <IPA>.data/ out to the player
rm -f "$PACKAGE" "$IPA"                               # this builder's own earlier outputs
mkdir -p "$IPA.data"
if [ $MAC = 1 ]; then
	$PY scripts/prepare-game-data.py --app-data "$APP/Contents/Resources/data" --game ref/inputs/custom-original --output "$PACKAGE"
	ditto -c -k --keepParent "$APP" "$IPA"
else
	$PY scripts/prepare-game-data.py --app-data "$APP/data" --game ref/inputs/custom-original --output "$PACKAGE"
	STAGE=$(mktemp -d "$OUT/ipa.XXXXXX")
	trap 'rm -rf "$STAGE"' EXIT
	mkdir "$STAGE/Payload"
	cp -R "$APP" "$STAGE/Payload/"
	(cd "$STAGE" && zip -qry "$IPA" Payload)
fi
# keep this build's finished translation (adding the Xbox edition reuses it) and drop its
# intermediate runs and the previous builder's translation (gigabytes each); other runs stay
NEW_RUNS=$(comm -13 <(printf '%s\n' "$RUNS_BEFORE") <(runs))
for run in $RUNS_BEFORE; do [ ! -f "$run/.builder" ] || rm -rf "$run"; done
for run in $NEW_RUNS; do
	if ls "$run"/*.ll >/dev/null 2>&1; then touch "$run/.builder"; else rm -rf "$run"; fi
done
if [ $MAC = 1 ]; then
	printf '\nDone.\n  App:          %s\n  Game package: %s\nUnzip HaloPad, open it and choose the game package.\nBoth are yours alone: never share them.\n' "$IPA" "$PACKAGE"
else
	printf '\nDone.\n  App (unsigned): %s\n  Game package:   %s\nInstall the IPA with your own signing, open HaloPad and choose the game package.\nBoth are yours alone: never share them.\n' "$IPA" "$PACKAGE"
fi
