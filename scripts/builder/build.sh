#!/usr/bin/env bash
# HaloPad's one-command personal build (PadMint's entry point; padmint.json).
#
#   scripts/builder/build.sh <folder or HaloCESetup.exe> --ipa HaloPad.ipa [--out DIR] [--product-key-file FILE]
#   scripts/builder/build.sh <folder or HaloCESetup.exe> --mac --zip HaloPad-mac.zip [...]
#
# --mac makes HaloPad.app for Apple silicon Macs instead (the same app, zipped; it runs
# as built, with no Apple account), with its own game package in <zip>.data/.
# --xbox-only (or an ISO/XISO input) builds Xbox without any PC inputs or tools.
# --xbox-release-record FILE reuses a saved xbox-release.json commit instead of latest.
# --app-version 0.3.8 --app-build 2 sets the app's update identity; defaults are 0.3/1.
# --xbox adds the Xbox edition: your Mac fetches the latest OpenCE release and
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
INPUT=""; OUT="$ROOT/generated/builder"; IPA=""; KEY_FILE=""; MAC=0; XBOX=0; PC=1
XBOX_RECORD=""; APP_VERSION=0.3; APP_BUILD=1
while [ $# -gt 0 ]; do
	case "$1" in
	--out) OUT=$2; shift ;;
	--ipa|--zip) IPA=$2; shift ;;                     # the output: an IPA, or the Mac app's zip
	--mac) MAC=1 ;;
	--xbox) XBOX=1 ;;
	--xbox-only) XBOX=1; PC=0 ;;
	--xbox-release-record) XBOX_RECORD=$2; shift ;;
	--app-version) APP_VERSION=$2; shift ;;
	--app-build) APP_BUILD=$2; shift ;;
	--product-key-file) KEY_FILE=$2; shift ;;
	--jobs) shift ;;                                  # accepted for PadMint; the steps size themselves
	-*) echo "unknown option $1" >&2; exit 2 ;;
	*) INPUT=$1 ;;
	esac
	shift
done
# The selected file chooses the edition without a second installer workflow.
case "$INPUT" in *.[iI][sS][oO]|*.[xX][iI][sS][oO])
	[ -f "$INPUT" ] || { echo "Xbox disc image not found: $INPUT" >&2; exit 2; }
	XBOX=1; PC=0 ;;
esac
python3 scripts/app_version.py --version "$APP_VERSION" --build "$APP_BUILD"
if [ -n "$XBOX_RECORD" ]; then
	[ $XBOX = 1 ] || { echo "--xbox-release-record requires the Xbox edition" >&2; exit 2; }
	[ "${HALOPAD_XBOX_PINNED:-0}" != 1 ] || { echo "Choose either --xbox-release-record or HALOPAD_XBOX_PINNED=1" >&2; exit 2; }
	# Validate and snapshot before tools/build work; later steps use these bytes.
	XBOX_RELEASE=$(python3 scripts/xbox/release.py --record "$XBOX_RECORD")
fi
if [ $PC = 0 ] && [ -n "$KEY_FILE" ]; then
	echo "An Xbox-only build does not use --product-key-file; omit it or choose the PC installer." >&2; exit 2
fi
if [ $PC = 1 ]; then
	[ -f "$INPUT" ] && INPUT=$(dirname "$INPUT")
	[ -d "$INPUT" ] || { echo "Select HaloCESetup.exe for PC, an Xbox ISO/XISO for Xbox, or use --xbox-only." >&2; exit 2; }
fi
[ -n "$IPA" ] || { [ $MAC = 1 ] && IPA="$OUT/HaloPad-mac.zip" || IPA="$OUT/HaloPad.ipa"; }
mkdir -p "$OUT"
mkdir -p "$(dirname "$IPA")"
IPA="$(cd "$(dirname "$IPA")" && pwd)/$(basename "$IPA")"
OUT="$(cd "$OUT" && pwd)"
# PadMint exports this sidecar automatically. Never hand over an old PC package
# beside a new Xbox-only app; retain it and ask for a separate output name.
if [ $PC = 0 ] && { [ -e "$IPA.data" ] || [ -L "$IPA.data" ]; }; then
	echo "Existing game data at $IPA.data is preserved. Choose a different Xbox-only output filename." >&2; exit 2
fi
step() { printf '\n==> %s\n' "$*"; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

step "checking tools"
command -v xcodebuild >/dev/null || { echo "Install Xcode before building HaloPad." >&2; exit 2; }
if [ $PC = 1 ]; then
for tool in 7zz wine winetricks lld-link /opt/homebrew/opt/llvm/bin/clang; do
	command -v "$tool" >/dev/null || { echo "missing $tool: install Xcode, then brew install sevenzip winetricks llvm lld; for Wine see docs/INSTALL-WINE.md" >&2; exit 2; }
done
fi
if [ $XBOX = 1 ]; then
	for tool in cmake ninja ld.lld git curl; do
		command -v "$tool" >/dev/null || { echo "missing $tool for the Xbox edition: brew install cmake ninja lld" >&2; exit 2; }
	done
fi
if [ $PC = 0 ]; then
	PY=python3
elif ! "$PY" -c 'import pefile, capstone, SCons' 2>/dev/null; then   # a fresh checkout (PadMint's)
	step "setting up HaloPad's Python tools (.venv)"
	[ -x "$PY" ] || python3 -m venv .venv
	$PY -m pip install -q -r scripts/requirements-builder.txt
fi


if [ $PC = 1 ]; then
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
[ -n "$INSTALLER" ] || {
	echo "HaloPad needs the original Halo Custom Edition 1.00 installer (HaloCESetup.exe). The 1.10 update patch is a different file and cannot replace it." >&2
	echo "In PadMint, select HaloCESetup.exe and keep product-key.txt beside it. HaloPad can download the patch for you." >&2
	echo "No original installer with the supported checksum was found in: $INPUT" >&2
	exit 3
}
# Halo refuses to start without the product ID, so ask for the key before the long steps
[ -n "$KEY_FILE" ] || [ ! -f "$INPUT/product-key.txt" ] || KEY_FILE="$INPUT/product-key.txt"
[ -n "$KEY_FILE" ] || [ -t 0 ] || { echo "put product-key.txt (your Halo PC product key) beside HaloCESetup.exe; Halo will not start without it" >&2; exit 3; }
fi
# Resolve once, before the expensive work. An update must never silently become
# an older build because GitHub is unavailable or the newest engine fails.
if [ $XBOX = 1 ]; then
	step "resolving the Xbox release"
	RELEASE_ARGS=(); [ "${HALOPAD_XBOX_PINNED:-0}" != 1 ] || RELEASE_ARGS=(--pinned)
	if [ -z "$XBOX_RECORD" ]; then
		XBOX_RELEASE=$($PY scripts/xbox/release.py ${RELEASE_ARGS[@]+"${RELEASE_ARGS[@]}"})
	fi
	XBOX_REV=$($PY -c 'import json,sys; print(json.loads(sys.argv[1])["revision"])' "$XBOX_RELEASE")
	export XBOX_REV
	XBOX_TAG=$($PY -c 'import json,sys; print(json.loads(sys.argv[1])["release"])' "$XBOX_RELEASE")
	export HALOPAD_XBOX_RELEASE="$XBOX_TAG"
	export HALOPAD_XBOX_LATEST=1
	if [ "${HALOPAD_XBOX_PINNED:-0}" = 1 ]; then
		export HALOPAD_XBOX_LATEST=0
		echo "Explicitly building tested $XBOX_TAG; it may not join current OpenCE games."
	elif [ -n "$XBOX_RECORD" ]; then
		echo "Rebuilding recorded OpenCE $XBOX_TAG ($XBOX_REV); acceptance is not implied."
	else
		echo "Building OpenCE $XBOX_TAG ($XBOX_REV); a failed update leaves your installed app unchanged."
	fi
fi

PRODUCT_ID=()
APP_OPTIONS=()
if [ $PC = 1 ]; then
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

if [ $ASSEMBLED = 1 ]; then
	step "reusing your assembled 1.10 game files"
else
	step "applying the 1.10 update and assembling the game files"
	PATCHED=$(scripts/prepare-patched-client.sh | sed -n 's/^RUN_DIR=//p')
	$PY scripts/assemble-custom-original.py --patched-run "$PATCHED"
fi
$PY scripts/extract-reference-components.py

runs() { { find generated/srw/custom-en-1.0.10.0621 -mindepth 1 -maxdepth 3 -type d -name 'run-*' -prune 2>/dev/null || true; } | sort; }
RUNS_BEFORE=$(runs)                                   # this build's translation runs are the new ones
WORK=$($PY scripts/builder/pc_cache.py lookup)
if [ -n "$WORK" ]; then
	step "reusing verified Custom Edition translation (only the Xbox engine and app need rebuilding)"
else
	step "fetching pinned sources and building the translator"
	scripts/bootstrap-sources.sh
	BUILD=$(scripts/build-lifter.sh | sed -n 's/^BUILT: //p')
	[ -n "$BUILD" ] || { echo "translator build failed" >&2; exit 4; }
	step "translating Halo and its DLLs"
	for module in haloce keystone ksimeui controls msxml4; do
		scripts/srw-pipeline.sh "$BUILD" --module "$module"
	done
	WORK=$(ls -dt generated/srw/custom-en-1.0.10.0621/run-*/ | head -n 1)
	WORK=${WORK%/}
	$PY scripts/va-model.py --work "$WORK" --llasm "$BUILD/llasm/llasm"
	# Retain completed PC work even if a later Xbox update fails.
	$PY scripts/builder/pc_cache.py record --work "$WORK"
fi

PRODUCT_ID=()
if [ -n "$KEY_FILE" ] || [ -t 0 ]; then
	step "your product ID (Halo's installer step)"
	if [ -n "$KEY_FILE" ]; then scripts/product-id.sh --installer "$INSTALLER" < "$KEY_FILE"
	else scripts/product-id.sh --installer "$INSTALLER"; fi
	PRODUCT_ID=(--product-id generated/product-id/product-id.txt)
else
	echo "warning: no product key given; Halo will stop with 'Your product key is invalid' until you add one" >&2
fi

else
	WORK="$OUT/xbox-only"
	APP_OPTIONS=(--xbox-only)
	echo "Xbox-only build: no PC installer, product key or Wine needed. Add your Xbox disc in HaloPad after installing."
fi

if [ $XBOX = 1 ]; then
	step "fetching and building the Xbox engine (OpenCE) for this app"
	export HALOPAD_XBOX_RENDERER=angle-metal HALOPAD_XBOX_GUEST_ADAPTATION=render-camera-v1   # the tested iPad build
	XSDK_FLAG=--device; [ $MAC = 0 ] || XSDK_FLAG=--mac
	# A failed engine build stops the update. No automatic downgrade.
	scripts/xbox/build-ios.sh $XSDK_FLAG
	XBOX_SETTING=on
else
	XBOX_SETTING=off                                  # the Windows edition alone
fi
if [ $MAC = 1 ]; then step "building HaloPad for your Mac"; TARGET=(--mac); else step "building HaloPad for iPhone and iPad"; TARGET=(--iphoneos); fi
APP_LOG="$OUT/build-app.log"
HALOPAD_XBOX=$XBOX_SETTING $PY scripts/build-ios-app.py "${TARGET[@]}" --work "$WORK" --app-version "$APP_VERSION" --app-build "$APP_BUILD" ${APP_OPTIONS[@]+"${APP_OPTIONS[@]}"} ${PRODUCT_ID[@]+"${PRODUCT_ID[@]}"} | tee "$APP_LOG"
[ $XBOX = 0 ] || hdiutil detach "$ROOT/ref/xbox-build/vol" -quiet 2>/dev/null || true   # the engine's volume (after its release tag is read)
APP=$(sed -n 's/^built //p' "$APP_LOG" | tail -n 1)
[ -d "$APP" ] || { echo "app build failed" >&2; exit 5; }

if [ $PC = 0 ]; then
	step "packaging your Xbox-only app"
	if [ -L "$IPA" ] || { [ -e "$IPA" ] && [ ! -f "$IPA" ]; }; then
		echo "output must be a regular file: $IPA" >&2; exit 5
	fi
	STAGE=$(mktemp -d "$(dirname "$IPA")/.halopad-xbox.XXXXXX")
	trap 'rm -rf "$STAGE"' EXIT
	if [ $MAC = 1 ]; then
		ditto -c -k --norsrc --noextattr --keepParent "$APP" "$STAGE/app.zip"
	else
		mkdir "$STAGE/Payload"
		cp -R "$APP" "$STAGE/Payload/"
		(cd "$STAGE" && zip -qry app.zip Payload)
	fi
	mv -f "$STAGE/app.zip" "$IPA"
	printf '%s\n' "$XBOX_RELEASE" > "$OUT/xbox-release.json"
	printf '\nDone.\n  App: %s\nInstall HaloPad, choose Xbox and add your ISO or XISO. No PC game package is needed.\nThis personal build is yours alone; never share it.\n' "$IPA"
	exit 0
fi

step "packaging your game files and the app"
PACKAGE="$IPA.data/Halo-CE.halopad.zip"               # PadMint copies <IPA>.data/ out to the player
for output in "$IPA" "$PACKAGE"; do
	if [ -L "$output" ] || { [ -e "$output" ] && [ ! -f "$output" ]; }; then
		echo "output must be a regular file: $output" >&2; exit 5
	fi
done
STAGE=$(mktemp -d "$(dirname "$IPA")/.halopad-package.XXXXXX")
finish_package() {
	status=$?
	# Renames record the state themselves, including interruption between commands.
	# Once app.zip has moved, both new outputs are committed.
	if [ -f "$STAGE/app.zip" ]; then
		if [ -f "$STAGE/previous-game.zip" ]; then
			mv -f "$STAGE/previous-game.zip" "$PACKAGE" || {
				echo "Could not restore the previous game package; it is preserved in $STAGE" >&2
				return "$status"
			}
		elif [ ! -f "$STAGE/game.zip" ]; then
			rm -f "$PACKAGE"
		fi
	fi
	rm -rf "$STAGE"
	return "$status"
}
trap finish_package EXIT
mkdir -p "$IPA.data"
if [ $MAC = 1 ]; then
	$PY scripts/prepare-game-data.py --app-data "$APP/Contents/Resources/data" --game ref/inputs/custom-original --output "$STAGE/game.zip"
	ditto -c -k --norsrc --noextattr --keepParent "$APP" "$STAGE/app.zip"
else
	$PY scripts/prepare-game-data.py --app-data "$APP/data" --game ref/inputs/custom-original --output "$STAGE/game.zip"
	mkdir "$STAGE/Payload"
	cp -R "$APP" "$STAGE/Payload/"
	(cd "$STAGE" && zip -qry app.zip Payload)
fi
# Publish outputs only after both packages have been created successfully.
# Retain the previous game package until the app replacement succeeds as well.
[ ! -f "$PACKAGE" ] || mv "$PACKAGE" "$STAGE/previous-game.zip"
mv -f "$STAGE/game.zip" "$PACKAGE"
mv -f "$STAGE/app.zip" "$IPA"
# keep this build's finished translation (adding the Xbox edition reuses it) and drop its
# intermediate runs and the previous builder's translation (gigabytes each); other runs stay
NEW_RUNS=$(comm -13 <(printf '%s\n' "$RUNS_BEFORE") <(runs))
for run in $RUNS_BEFORE; do [ "$run" = "$WORK" ] || [ ! -f "$run/.builder" ] || rm -rf "$run"; done
for run in $NEW_RUNS; do
	if ls "$run"/*.ll >/dev/null 2>&1; then touch "$run/.builder"; else rm -rf "$run"; fi
done
# Include this target's compiled PC objects in subsequent cache verification.
$PY scripts/builder/pc_cache.py record --work "$WORK"
if [ $XBOX = 1 ]; then
	printf '%s\n' "$XBOX_RELEASE" > "$OUT/xbox-release.json"
	echo "Xbox engine packaged: $XBOX_TAG ($XBOX_REV)"
fi
if [ $MAC = 1 ]; then
	printf '\nDone.\n  App:          %s\n  Game package: %s\nUnzip HaloPad, open it and choose the game package.\nBoth are yours alone: never share them.\n' "$IPA" "$PACKAGE"
else
	printf '\nDone.\n  App (unsigned): %s\n  Game package:   %s\nInstall the IPA with your own signing, open HaloPad and choose the game package.\nBoth are yours alone: never share them.\n' "$IPA" "$PACKAGE"
fi
