# Xbox engine (second HaloPad engine)

**Current build policy, 2026-10-09:** normal builds replay
`config/xbox-release.json` (OpenCE 168, network version 24) with the
`network-policy-v1` adaptation: the installed app follows compatible OpenCE network
raises through a signed policy ([UPDATE-STRATEGY.md](UPDATE-STRATEGY.md#network-compatibility-policy)).
`--xbox-latest` explicitly selects upstream; the prepared hosted app-update
workflow handles that selection separately. Public app delivery is not enabled.
See [UPDATE-STRATEGY.md](UPDATE-STRATEGY.md) and [STATUS.md](STATUS.md) for current
candidate and acceptance evidence. The dated engine investigations below are
historical and do not change the current default.

Status, 2026-10-03: **HaloPad offers Windows Custom Edition or Xbox Combat Evolved at launch.**
The accepted **experimental development pin** in `config/xbox-engine.lock.json`
is upstream OpenCE (formerly halo-ce-universal) **build 125, `13c14df9`**, network version 16
(accepted 2026-10-05 with `scripts/xbox/update-pin.sh`: Mac and Simulator menu/a10/match pass;
build 119 `a38ede07`, build 85 `c3adcfe5` and build 74 `80d30410` before). The pin is an
**explicit tested option** (`HALOPAD_XBOX_PINNED=1`), separate from the bundled
release record and explicit latest mode (see "Updating the engine"). Build 64 expanded the high-resolution HUD/scopes and fixed meter
alpha and flat menu fills; the following paragraphs retain that earlier evidence.
Save-backed candidate and acceptance Mac/ANGLE iPad Simulator menu/a10/scripted-match
gates pass. A copied build-61 a30 checkpoint loads through normal menus; actual
fire, pistol swap, 2x Zoom, Save and Quit and fresh-process pod reload work.
An isolated build-64 normal-menu pass now advances outside the pod using actual
touch gestures and restores that newly reached checkpoint after Save and Quit
and a cold launch (one grenade retained). This is bounded early progression,
not sustained multi-touch, campaign completion or physical graphics acceptance.
ANGLE/Metal remains an independently pinned opt-in PREVIEW, not the default.
The current-source iPhoneOS ANGLE preview is now provisioned and installed in
place on the authorized M2 iPad after complete backup/readback. Ordinary picker,
Xbox menus and a fresh isolated a10 cryo-bay run are observed. Hardware guest
allocation and non-silent stereo capture work; direct controls, speaker quality,
sustained performance and matched rendering acceptance remain open. Default
Apple rendering is unchanged; this installed build is still an opt-in preview.
The earlier build-59 real touch pass verified
navigation, cryo-bay training, tube exit, Save and Quit, and a same-build cold checkpoint
reload with isolated saves. A copied build-59 checkpoint also loads through the
normal build-60 menus; a copy of that fixture also reloads the cryo-bay in build 61.
This is not general snapshot compatibility or full gameplay acceptance:
geometry/texture artifacts, full campaign progression, split-screen, human system link,
audio quality and physical performance remain open.
The Apple-GLES presentation workaround remains narrow: temporarily neutralize texture unit/
sampler 0 during final presentation, then restore it. ANGLE builds (Simulator and device) do not use it.
Since 2026-10-04 device builds use the same cumulative `render-present-v1` fixes and counted
ANGLE backend as the Simulator (`angle-counted-iphoneos`); installed and observed on Chris' iPad
(Silent Cartographer, 0 GL errors). Engine, renderer, GL-error and frame-timing lines are in
HaloPad Logs/HaloPad.log.
See [XBOX-SIMULATOR-PASSES.md](XBOX-SIMULATOR-PASSES.md).

Latest Simulator candidate: build74 `80d30410`, executable `4e42dc6d…11175`,
guest `8fb0112f…0a5e`, cumulative **render-present-v1**. Reviewed revision-aware
renderer identity preserves historical66/73 manifests and all source guards.
206 Xbox tests, cold menu/a10/match smoke, copied73 Green Thumb shared controls,
Save and Quit and cold checkpoint reload pass. First frame read1/draw0/error0;
real saves/preferences/PC registry preserved. Subsequent four100s a10/b30
captures retain water/shadow/display fixes at Original640x480/1x and UI-selected
Sharper1280x960/4x. The real update-helper workflow now accepts74 after fresh
unadapted Mac/Simulator gates; this exact adapted preview is restored in place.
Normal New001/Green Thumb System Link profile/lobby progression also reaches
Battle Creek/Slayer and returns to the menu using shared controls. The second
machine is a local stand-in, not full peer-gameplay compatibility. Same-revision
desktop reference agrees on22 usable stepped Battle Creek material views, but
the longer Simulator run exposes a stale looping-sound crash at about184s.
A stationary240s control passes; trigger unresolved. Next sound-lifecycle
reproduction and safe crash reporting. Broad-fidelity/stability gates remain open.
[Installed evidence](XBOX-SIMULATOR-PASSES.md#adapted74-controls-and-save-regression-2026-10-03).
[Quality regression](XBOX-SIMULATOR-PASSES.md#build74-both-quality-material-regression-2026-10-03).
[Accepted update](XBOX-SIMULATOR-PASSES.md#build74-accepted-update-workflow-2026-10-03).
[Normal multiplayer route](XBOX-SIMULATOR-PASSES.md#build74-normal-multiplayer-menu-route-2026-10-03).
[Reference and sound fault](XBOX-SIMULATOR-PASSES.md#build74-battle-creek-reference-and-late-sound-fault-2026-10-03).

Previous Simulator candidate: build73 `d1c7243c`, executable `ed257ad5…af30b`,
guest `4ac7e842…b60`, cumulative **render-present-v1**. Resolving the read
framebuffer before selecting/clearing the presentation destination fixes the
confirmed cold-cache ordering defect. Cold menu, a10 campaign and scripted local
match all report frame0 read1/draw0/error0. Normal shared controls, Save and Quit
and cold checkpoint reload pass on copied state;202 Xbox tests pass. Subsequent
four bounded a10/b30 captures retain water/border fixes at Original640x480/1x
and Sharper1280x960/4x, without startup0x502. Next investigate a different
unresolved material/effect against desktop. No accepted pin promotion,
hardware or broad-fidelity claim.
[Installed evidence](XBOX-SIMULATOR-PASSES.md#first-blit-fixed-build-validation-2026-10-03).

Previous Simulator candidate: build73 `d1c7243c`, executable `48f118f3…213e`,
guest `652fbebb…de17`, opt-in `shared-input-v1`. A guarded scalar guest import
publishes resolved button/stick mappings and active-menu state before polling
input. HaloPad normalizes its touch pad only; physical pad routing and saved
profiles are unchanged. Context transitions clear queued pad input and suppress
held controls until release. Menus retain raw A/B navigation. This adaptation
includes the preceding border/water fixes, but exact-new-build broad graphics
regression remains open. 198 Xbox tests, 153 native overlay assertions and 39
launch/save/quality checks pass. Actual copied Southpaw Fire/Throw, normal menus,
Save and Quit and cold checkpoint reload pass. Other presets have unit coverage,
not equivalent runtime acceptance; legacy stick diagonal response remains guest
behavior. Real saves/preferences/PC registry preserved, Original picker restored.
[Input bridge evidence](XBOX-SIMULATOR-PASSES.md#southpaw-touch-mapping-bridge-2026-10-03).

Earlier source-only diagnosis (now built above): opt-in **render-present-v1** resolves
the read framebuffer before selecting/clearing the presentation destination.
A cold-cache runtime trace and one-process debugger correction confirm the
startup blit ordering defect.202 Xbox tests and40 native launch/save/quality
checks pass; this cumulative adaptation retains all shared-input/graphics fixes
and old recipe identities. At that checkpoint it was not built or installed:
only1.2GiB free disk remained. Outgoing artifacts are now preserved and the
new candidate installed; see current evidence above. No accepted pin promotion.
[Evidence](XBOX-SIMULATOR-PASSES.md#first-blit-ordering-confirmed-2026-10-03).

Previous Simulator candidate: build73 `d1c7243c`, executable `dc469db1…5997d`,
guest `2d03ab18…b6b6`, opt-in `render-border-v1`. It includes the water correction
and emulates border-color sampling for eligible single-level 2D textures. Matched
bridge views lose the long black shadow bands while retaining character shadows;
water and exterior engine glow remain visible. 194 Xbox tests, 38 native
launch/save/quality checks, a10 cinematic, menu and local-match checks pass.
Exact-candidate normal-menu copied checkpoint, shared Fire/Look/Swap/Zoom/Pause,
Save and Quit and cold reload now pass. UI-selected Sharper persists at1280x960/
4x into fresh water/bridge captures: water detail remains and shadow bands stay
absent. This is bounded regression evidence; non-default profiles, sustained
human multi-touch, broad fidelity and hardware remain open.
No physical-device work is authorized until Chris makes the iPad available again.
[Border fix evidence](XBOX-SIMULATOR-PASSES.md#bridge-border-sampling-fix-2026-10-03).
[Regression evidence](XBOX-SIMULATOR-PASSES.md#border-candidate-controls-saves-and-sharper-2026-10-03).

Earlier non-default profile repro on that candidate: copied Southpaw buttons
swap the actual shared Fire/Throw actions. No profile reset is acceptable as the
fix. Next paired guest/host bridge must expose authoritative mapping/menu context
and normalize only touch, preserving raw menu navigation and hardware settings.
That planned boundary is implemented in the newer candidate above.
[Evidence and bridge gates](XBOX-SIMULATOR-PASSES.md#southpaw-touch-mismatch-reproduced-2026-10-03).

Previous Simulator candidate: build 73 `d1c7243c`, executable `39f06f77…7198e`,
adds held Scoreboard drag to paired Page Up/Down inputs. 185 Xbox tests and
141 native overlay assertions pass; actual Simulator drag emits paired inputs
without moving the camera, and Fire still works. Visible scoreboard response
and overflow paging are not accepted. See the
[input bridge pass](XBOX-SIMULATOR-PASSES.md#build-73-scoreboard-touch-bridge-2026-10-02).

Previous Simulator candidate: build 73 `d1c7243c`, executable `59764ae4…ac8c`,
with `render-visibility-v1` and ANGLE/Metal. Menu/a10/scripted-match smoke and
copied build-66 normal-menu save/quit/cold reload pass. Accepted lock stays 66;
unadapted acceptance, new scoreboard touch pagination and graphics fidelity
remain open. Prior app/output/data are backed up. See the
[candidate pass](XBOX-SIMULATOR-PASSES.md#build-73-candidate-upgrade-2026-10-02).

Earlier local integration: executable `3a933fea…95e8a` was rebuilt and installed
in place on the dedicated iPad Simulator, with outgoing apps/data backed up.
The touch-owner follow-up keeps RT/A held until the last owning finger releases;
24 actual-handler checks pass after two reproduced failures. Normal-menu copied
outdoor checkpoint and single RT 60→59 verify after rebuilding/installing. Real
saves remain untouched; final ordinary picker PID 74408. Simultaneous OS gestures
and physical controls still require acceptance. The device preview was rebuilt
from `68cb779` and is now installed as signed candidate `90437ca6…06362e`.
See the [physical pass](XBOX-SIMULATOR-PASSES.md#physical-ipad-angle-preview-2026-10-02).
Earlier integration evidence:
The post-device-SDK source follow-up verifies picker/About/Done, a copied outdoor
a30 checkpoint, finite touch look, weapon swap, 2x scope and Save and Quit.
Normal Windows startup reaches its still-unaccepted EULA. A retained 62-second
video is not sustained-input or visual-fidelity acceptance. Earlier evidence:
The picker and isolated outdoor Xbox continuation/fire/pistol/scope/Save and Quit
work. Actual Home/resume retains the process and fresh controls work afterward.
Xbox touch input now clears on focus loss and activation; 16 actual UIKit-handler
checks cover held/unread cancellation, hidden input and normal short taps.
This is not OS-held multi-touch or physical-controller interruption proof.
The normal PC Files import verifies all 78 stock files and reaches its original
EULA, left unaccepted pending user confirmation; this is not normal PC gameplay
proof. Real Xbox data/saves are unchanged. Reported physical-iPad shading/focus
problems remain unresolved; the bounded hardware pass does not promote upstream
beyond frozen build 64 or establish PC visual fidelity.

HaloPad now opens with a choice:

| | Halo PC | Halo Xbox |
|---|---|---|
| Engine | Custom Edition 1.10, translated from the player's own `haloce.exe` | [cybersecurity/halo-ce-universal](https://github.com/cybersecurity/halo-ce-universal), a port of the Xbox decompilation |
| Game files | Custom Edition package | The player's own Xbox disc image (maps copied into Documents/Halo Xbox) |
| Online | Custom Edition servers | Other copies of that port: system link and internet games (up to 128 players, same upstream build) |
| Campaign | Not yet | Original Xbox campaign; experimental. Split-screen is upstream functionality, unverified in HaloPad |

The two cannot play online together. One engine runs per launch (both use the same guest memory), so
switching means closing HaloPad and opening it again (**⋯ › Switch Edition…** does the closing); the
picker appears at every launch.

## Personal-build boundary (Chris's decision, 2026-09-30)

Historical design record: current source can create a personal Xbox-only IPA
with `scripts/builder/build.sh --xbox-only --ipa HaloPad-Xbox.ipa`; normal builds
replay the bundled release record. The older no-IPA/pinned-only statements
below describe September 30, not today's builder. Public app distribution remains
under review; see [installation delivery](STATUS.md#installation-delivery).

- The upstream engine is **fetched and built on the player's own Mac** at the revision in
  [config/xbox-engine.lock.json](../config/xbox-engine.lock.json). Its sources, its guest image, the
  translation and the engine library live only under the ignored `ref/xbox-build/`.
- HaloPad's repository holds only HaloPad's own code: the translator, the host runtime, the picker and
  scripts. A HaloPad build made without the local engine has no picker and behaves as before.
- A device build containing the engine stops at the signed `HaloPad.app`; the app builder
  **does not create an IPA** for Xbox personal builds. The app contains translated upstream
  code: **it is the builder's alone and is never shared or published.** PC-only packaging is unchanged.
- Updates stay **pinned**: moving the pin is a deliberate, tested step (below); saves are backed up first.
- Upstream's documentation says parts of the decompilation were reconstructed with help from leaked
  Bungie material ([REVIEW-HALO1-DECOMP.md](REVIEW-HALO1-DECOMP.md)). That is why the engine stays a
  personal build, and why this document is not a rights clearance.

## Ideas from other ports (reviewed 2026-10-03)

Read-only review of the most-starred forks of the upstream engine. All trail upstream
(build 74 was then the latest release; HaloPad now pins build 85), so none is a newer engine. No code was copied;
each idea needs its own design and test in HaloPad's shared overlay.

| Idea | Seen in | HaloPad today | Worth doing |
| --- | --- | --- | --- |
| Optional gyroscope aim, off by default, using look sensitivity, paused in menus | [theLlamaNet/halo-ce-android](https://github.com/theLlamaNet/halo-ce-android) | Not present | Yes, a strong fit for iPad and iPhone |
| Phone haptics for the game's rumble when no controller is connected | theLlamaNet/halo-ce-android | Not present | Yes, small and contained |
| Export and import of a touch layout file; per-button size and duplicate buttons | theLlamaNet/halo-ce-android | Move and resize exist | Export/import yes; duplicates later |
| Drop a disc image into the app's Files folder and import it automatically | [NicholasDominici/halo-ce-ios](https://github.com/NicholasDominici/halo-ce-ios) | Import from the Files picker | Yes, alongside the existing safe staged importer |
| Native-resolution rendering on iPad | NicholasDominici/halo-ce-ios | Original and Sharper choices | Only after real-iPad performance is measured |
| Profile-guided optimisation | Upstream | Already used: the guest build applies upstream's `pgo/halo_linux.profdata` | No action |
| Cheats menu | theLlamaNet/halo-ce-android | Not present | No: changes gameplay, low priority |

## Opt-in renderer preview

Apple OpenGL ES remains the default; ANGLE is installed only as the personal
hardware-test preview described above, not promoted to the default.
`HALOPAD_XBOX_RENDERER=angle-metal` builds a **preview** from the
separately pinned [WebKit ANGLE source](https://github.com/WebKit/WebKit/tree/a1fb7ce122d0cd99f7d6cc82775f02565e266ece/Source/ThirdParty/ANGLE).
[config/xbox-angle.lock.json](../config/xbox-angle.lock.json) records both source
revisions and the tested Simulator feature override. This is independent of the
Xbox guest pin. Device builds use ANGLE's automatic feature detection, not that
override. Do not retag libraries between macOS, Simulator and iPhoneOS.

Without `XBOX_ANGLE_SOURCE`, `scripts/xbox/build-ios.sh` fetches this pinned source itself into the
ignored `generated/xbox-angle/` (as `scripts/builder/build.sh --xbox` and PadMint do). To use your own
checkout, fetch it into scratch, not another project checkout in `GitHub`:

```sh
angle_work=$(mktemp -d /tmp/halopad-angle.XXXXXX)
git clone --filter=blob:none --depth=1 --no-checkout https://github.com/WebKit/WebKit.git "$angle_work/WebKit"
git -C "$angle_work/WebKit" fetch --depth=1 origin a1fb7ce122d0cd99f7d6cc82775f02565e266ece
git -C "$angle_work/WebKit" sparse-checkout init --cone
git -C "$angle_work/WebKit" sparse-checkout set Source/ThirdParty/ANGLE
git -C "$angle_work/WebKit" checkout --detach a1fb7ce122d0cd99f7d6cc82775f02565e266ece
export XBOX_ANGLE_SOURCE="$angle_work/WebKit/Source/ThirdParty/ANGLE"
HALOPAD_XBOX_RENDERER=angle-metal scripts/xbox/build-ios.sh
```

The small CMake wrapper reuses upstream source lists and builds with the actual
selected iOS SDK. Source revision/dirty-tree guards run before guest preparation.
Separate archives/manifests live under ignored `ref/xbox-build/out/iphonesimulator-angle/`
and `iphoneos-angle/`, leaving the default libraries untouched. Package with the
same renderer setting using the normal `scripts/build-ios-app.py` workflow;
it refuses missing candidate libraries, missing/mismatched SDK identity,
mismatched renderer/source/features or stale hashes. Older manifests require
a real rebuild, not metadata retrofitting.
The picker identifies this renderer build as PREVIEW even with the accepted guest
pin. Preserve the previous app and actual saves before an in-place installation.

For a build-only iPhoneOS preview:

```sh
HALOPAD_XBOX_RENDERER=angle-metal scripts/xbox/build-ios.sh --device
HALOPAD_XBOX_RENDERER=angle-metal .venv/bin/python scripts/build-ios-app.py --iphoneos
```

This produces an ad-hoc signed personal `.app`, no Xbox IPA. It is not installed
or device-installable merely because signature verification passes: proper
provisioning with both memory entitlements and a coordinated device window are
still required. The standalone host and combined apps containing Xbox require iOS/iPadOS 17.4
or macOS 14.4. The futex bridge uses Apple’s `os_sync_*` APIs, introduced in those
versions; compile targets and package minimums match. Custom Edition-only builds
retain iOS 17/macOS 14 support.
`--launch` remains Simulator-only. Simulator depth/replay diagnostics are not
enabled on hardware. No physical graphics/audio/controller claim follows from
compilation; the reported shading/focus issue is still open.

Run the asset-free probe before accepting this backend on another Simulator:

```sh
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.4-simulator \
  -fobjc-arc -I"$XBOX_ANGLE_SOURCE/include" tests/xbox_angle_probe.m \
  ref/xbox-build/out/angle-simulator/libhalopad-angle.a -lc++ -lz \
  -framework Foundation -framework CoreGraphics -framework IOSurface \
  -framework QuartzCore -framework Metal -o "$angle_work/angle-probe"
SIMCTL_CHILD_HALOPAD_ANGLE_NATIVE_SWIZZLE=1 xcrun simctl spawn SIMULATOR_UDID "$angle_work/angle-probe"
```

It tests equal-depth coverage, swizzle-independent blitting and swizzled texture
sampling. The unmodified ANGLE Simulator default fails the last test here:
it deliberately disables `hasTextureSwizzle` in
[DisplayMtl](https://github.com/WebKit/WebKit/blob/a1fb7ce122d0cd99f7d6cc82775f02565e266ece/Source/ThirdParty/ANGLE/src/libANGLE/renderer/metal/DisplayMtl.mm).
The native-feature override passes on this Mac/iPadOS 26.5 and is confined to this
opt-in candidate; it is not a general driver fix or a physical-device override.
The smoke runner verifies the logged renderer against its manifest, allows a
30-second cold ANGLE menu capture, and retains image/progression gates. Neither
probe nor smoke results establish correct lighting, full gameplay or hardware
acceptance. See the pass ledger for actual scene review and remaining defects.

The bounded campaign smoke defaults to Pillar of Autumn/a10 without scripted
input. For later assets, `--case campaign --campaign-map a30` selects Halo;
`--campaign-map a50` selects Truth and Reconciliation for night/sniper coverage.
For a moving-camera diagnostic only:

```sh
.venv/bin/python scripts/xbox/smoke-simulator.py --device SIMULATOR_UDID \
  --case campaign --campaign-map a30 --scripted-campaign \
  --render-diagnostics --seconds 90
```

This uses upstream's `bot:7` for movement/look/fire and fresh isolated saves.
The result records the requested map and `scripted-render-diagnostic` input
mode; the load gate checks that actual map, not merely any campaign request.
It is not normal-menu checkpoint, human-control or campaign-completion proof.
Scripted campaign input requires both explicit diagnostic flags. Ordinary
menu/campaign runs override inherited bot/network-test settings with empty
values. Review the images separately; a lit frame is not visual acceptance.

For output-signal diagnostics, add `--audio-diagnostics` to a Simulator smoke
run (allow at least 14 seconds after the audio unit starts). This explicitly
enables Simulator-only `XG_AUDIO_CAPTURE=1`: skip ten seconds of callback frames,
then copy four seconds of interleaved float32 output, including any zero-filled
starvation. Allocation occurs at setup; the callback does no file I/O. After a
release/acquire completion handoff, the game thread writes `audio-output.f32le`
and rate/channel/frame/underrun metadata in the isolated evidence folder. The
runner rejects missing, truncated, invalid, nonfinite or silent captures and
reports RMS, peak and samples outside ±1. Range excursions/underruns are reported,
not hidden by the signal gate. Ordinary runs explicitly clear this diagnostic.
This is delivery to the output callback, not audible quality, deadline timing,
audio/video sync or physical-device acceptance. Keep captured game audio private.

## How it works

Upstream's Android build compiles the game as **arm64_32** (AArch64 instructions, 32-bit pointers,
because the game's data files hold 32-bit pointers) and links one static image at guest address
`0x88000000`, with the Xbox memory window at `0x80000000`. Apple platforms reserve the low 4 GiB of every
process, so that image cannot run where it was linked. HaloPad therefore:

1. **Builds upstream's own Android guest** with two extra compiler flags
   ([scripts/xbox/guest-cc.sh](../scripts/xbox/guest-cc.sh)): x27 and x28 are reserved, and there are no
   jump tables.
2. **Translates the linked image** ([scripts/xbox/translate.py](../scripts/xbox/translate.py)) into
   ordinary ARM64. Guest memory is one **4 GiB-aligned** host reservation whose base is in x28, so guest
   address *g* is at x28 + *g* and the low 32 bits of any host address inside it are the guest address.
   Loads and stores add the base (`add x27, x28, wN, uxtw`); adrp/adr become constants; direct branches
   go to translated labels; blr/br go through one dispatch table (an entry per guest instruction); calls
   to upstream's import stubs become direct calls into the host. The stack pointer is a real host address
   inside guest memory, and any copy of it into a register is cut back to 32 bits. No JIT.
3. **Runs it on a Darwin host** ([port/xbox](../port/xbox)): guest memory and the game's mmap; Linux
   system calls converted to Darwin (flags, structures, errno, futexes on `os_sync_wait_on_address`);
   threads with stacks in guest memory; OpenGL ES wrappers generated from upstream's own list
   ([scripts/xbox/gen-host-gl.py](../scripts/xbox/gen-host-gl.py)), with the real functions declared with
   their original argument types (upstream widens stack arguments to 8-byte slots on the guest side only);
   and upstream's `port/linux/src/posix_*.c` compiled for the host from the pinned checkout.
   - **Mac** ([xg_sdl.c](../port/xbox/xg_sdl.c), [xg_main_macos.c](../port/xbox/xg_main_macos.c)): SDL3,
     OpenGL ES through ANGLE's Metal back end.
   - **iOS** ([xg_ios.m](../port/xbox/xg_ios.m)): no SDL. Apple's OpenGL ES 3.0 on a layer-backed
     framebuffer that stands in for framebuffer 0, the GameController framework, Remote I/O audio, the
     game on its own thread. The standalone test app's [xg_touch.m](../port/xbox/xg_touch.m) is an Xbox-layout touch gamepad merged
     into player 1 (floating move stick, drag to look, RT/LT, A/B/X/Y, RB/LB, crouch, zoom, Start, Back);
     it hides while a controller is connected. [xg_xiso.c](../port/xbox/xg_xiso.c) copies maps/ out of
     the player's disc image.
   - **HaloPad** ([port/ios/HaloPadXbox.m](../port/ios/HaloPadXbox.m)): the launch picker and the Xbox
     screen (disc import, then the game). Both combined-app editions use
     [HPOverlay](../port/ios/HaloPadOverlay.m), including layout and touch settings.
     [xg_overlay_input.h](../port/xbox/xg_overlay_input.h) maps its actions into
     the default Xbox pad layout; relative look uses the upstream mouse-motion
     import. This adapter and overlay belong to HaloPad, not the upstream source
     tree, so a guest update cannot replace the touch UI. Non-default Xbox profile
     bindings and menu-aware A/B labels still need handling.
     [HaloPadApp.m](../port/ios/HaloPadApp.m) uses the picker through a weak reference.

Apple devices use 16 KiB pages and the game 4 KiB ones: inside the Xbox window and the image the game's
own mapping calls are emulated, and Direct3D write tracking protects whole 16 KiB pages. The game's
start-up invite link is kept off the player's clipboard.

## Build, run and install

```sh
scripts/xbox/extract-maps.py "ref/Halo - Combat Evolved (USA).xiso.iso" ref/xbox-build/data
scripts/xbox/build-mac.sh                 # the Mac program (also prepares everything below)
scripts/xbox/smoke-mac.py                 # Mac checks: menu, campaign, match
scripts/xbox/build-ios.sh                 # engine library for the Simulator (+ a stand-alone test app)
scripts/xbox/build-ios.sh --device        # engine library for devices
.venv/bin/python scripts/build-ios-app.py [--iphoneos --identity ... --profile ... --scene tests/halo_app_scene.c]
```

Needs Homebrew `llvm`, `lld`, `ninja` and `sdl3` (Mac only). The checkout lives on a case-sensitive
disk image (upstream has a header that includes itself on a case-insensitive disk). On the Mac, OpenGL ES
comes from ANGLE: any Chromium/Electron app's `libEGL.dylib` and `libGLESv2.dylib` work for a local
test (`--angle`). Development switches: `XG_FRAME_DUMP=<file.ppm>` saves the game's own frames
(`XG_FRAME_DUMP_DOCUMENTS=1` on a device), `XG_GL_CHECK=1` names failing OpenGL calls, `HALOPAD_ENGINE` or
`HALOPAD_CHOOSE` (`pc`/`xbox`) skip or press a picker card, `HALOPAD_XBOX_IMPORT=<image>` imports a disc image,
`XG_TOUCH_SHOW=1` keeps the touch gamepad up, and upstream's `HALO_*` settings pass through (for example
its `HALO_NETWORK_TEST` scripted matches). `init.txt` in the data folder holds console commands.

`XG_TOUCH_TRACE=1` also records touch clearing and inactive/active lifecycle
callbacks. `scripts/test-xbox-touch.py --device <booted-Simulator-UDID>` runs
asset-free UIKit handlers plus the shared native input buffer without installing,
opening a window or operating the game. It is not synthetic OS touch routing.
Unset `XG_DATA` and `XG_SAVE` for the ordinary app. Empty values now behave like
unset values; only nonempty paths override the installation. A nonempty
`XG_SAVE` isolates development saves and skips the real revision marker/backup.
`scripts/test-xbox-launch.py --device <booted-Simulator-UDID>` exercises the
actual launch/save helpers against synthetic folders and isolated preferences,
including failed-copy refusal. It neither opens the game nor installs an app.
Upstream build 64 deliberately unlocks all levels and
difficulties in new profiles, which explains The Maw/Legendary in their summary;
that summary does not prove completion or describe the current checkpoint.

On a device, back up HaloPad's Documents and Library first, install over the existing app, then either
pick the disc image in the app (Files) or copy an extracted `maps` folder to Documents/Halo Xbox/maps.

The native Files importer validates bounded XDVDFS entries and common version-5
map headers before writing. It uses a unique `maps.import-*` stage and publishes
with an exclusive rename: existing `maps`, old partial copies and saves are kept.
Failed stages remain for inspection; no automatic cleanup or replacement. This
is not authentication of the XBE/map contents or proof that every required map
is present. The Python reference extractor has not inherited these native
safety checks; use it only with the identified trusted personal input.

The Xbox library manifest also records local `port/xbox` source and relevant
build/generator hashes. A main-app rebuild refuses older or changed local-source
archives, even when the upstream pin and binary hashes still match. After local
runtime edits, run `scripts/xbox/build-ios.sh` for the intended renderer/SDK,
then rebuild the main app. Do not retrofit hashes into an old manifest. Retained
outgoing apps remain available as rollback artifacts without repackaging.

## Small HaloPad guest adaptations

Upstream source stays a clean, private pinned dependency. Shared touch controls
live in HaloPad's overlay/adapter, not guest patches. A narrowly scoped guest
experiment can be selected with `HALOPAD_XBOX_GUEST_ADAPTATION=render-scale-v1`
for **both** `scripts/xbox/build-ios.sh` and `scripts/build-ios-app.py` (alongside
the existing ANGLE options). Default is `none`. This adaptation only enables
`HALO_TEST_RENDER_SCALE=2` at runtime; without that runtime switch it remains 1x.
Use copied `XG_SAVE` data for experiments. It is tested on Simulator ANGLE ES3.0,
not accepted for physical-device performance or all visibility/effects paths.

`guest_adaptation.py` checks the complete renderer input against the reviewed
revision-specific hash (shared66/73 bytes, distinct74 bytes) before temporarily
applying the selected recipe. Ninja runs under an exclusive guest
build lock; normal completion, failures and handled interrupts restore the
original source. Concurrent edits are preserved and stop the build. A hard kill
may leave edits: inspect/preserve them manually; never reset as a recovery shortcut.
Run complete build/update workflows serially because their output directory is
shared. The lock protects the guest operation, not all packaging/update stages.

Manifests record upstream revision, guest hash and adaptation identity separately.
The packager requires the exact requested identity and current local sources;
adapted packages are previews. Pin updates reject adaptations so upstream
acceptance cannot accidentally promote a patched guest. When upstream's renderer
changes, review the new code and repeat focused graphics tests before changing
the input hash/recipe. Unsetting the option and rebuilding both guest and app
returns to the original guest; that round-trip is hash-verified on build 66.

The separately opt-in `render-quality-v1` uses the same source checks and scale
switch, plus `HALO_TEST_ANISOTROPY=4` or `16` for world filtering. Choose the same
adaptation in guest and app build commands. Other/unset anisotropy values keep
original filtering; point, non-mipmapped and high-resolution HUD paths are
excluded, unsupported GPUs are unchanged, and requests clamp to the GPU limit.
It follows the reviewed policy of [Tyberious's PR35](https://github.com/cybersecurity/halo-ce-universal/pull/35)
without importing that unmerged patch/configuration or changing the upstream pin.
Same-view Simulator a30 comparisons show more ground detail, not full material,
visibility or physical-device performance acceptance. The adaptation is still
opt-in at build time. Combined quality-adapted apps expose a pre-launch **Xbox
graphics** choice: Original (default, 1x resolution/original filtering) or
Sharper (Preview, 2x resolution/4x world filtering). Selection persists across
launches and does not alter Windows settings. The control is absent for other
guest variants. Explicit nonempty development quality environment values override
the saved choice; ordinary launches need no environment flags. Reopen HaloPad
to change the choice before starting Xbox. Sharper is not full graphics or
physical-performance acceptance.

`render-water-v1` additionally preserves read/draw framebuffer bindings and
scissor enable through the ES mip-copy fallback. It includes the counted
visibility/quality recipe and currently requires the paired counted ANGLE
**Simulator** backend, like `render-visibility-v1`.

`render-border-v1` inherits those fixes and restores border-color behavior when
ANGLE cannot provide native border clamp. The bounded policy covers single-level
2D textures with matching point/linear min and mag filters, excluding high-res
replacements. It preserves half-texel/corner blending and the actual border color,
not merely a UV discard. Mipmapped, anisotropic, mixed-filter, cube and 3D paths
remain unchanged. A second strict source hash guards the pixel-shader generator;
both temporary source edits are restored after a build. Upstream changes require
review of both sources, not blind hash updates. Set the same adaptation on both
build commands; leave the accepted pin and default build unchanged:

```sh
XBOX_REV=d1c7243cb20eab4488efa1266e259b1f4d5240f6 \
HALOPAD_XBOX_GUEST_ADAPTATION=render-border-v1 \
HALOPAD_XBOX_RENDERER=angle-metal scripts/xbox/build-ios.sh
```

Supply the pinned `XBOX_ANGLE_SOURCE` as above, preserve the prior app/output and
save data first, then package with those same variables using the normal app
builder. The source guard currently supports reviewed builds66/73/74; never substitute a new
upstream digest without reviewing the copy/draw ordering and border policy, then
rerunning the water/shadow comparisons. Evidence is linked above.

## Updating the engine

**Normal builds are reproducible; latest is explicit.** OpenCE frequently changes
its network version (which online players must share). `scripts/builder/build.sh`
uses `config/xbox-release.json` by default. With `--xbox-latest`, it resolves
OpenCE's latest release once, before expensive build steps, and builds it with `XBOX_REV=<its commit>` and
`HALOPAD_XBOX_LATEST=1`: HaloPad's edits must still find every anchor exactly once (only the
reviewed file hashes are waived, and the identity records `"reviewed": false`). If that guest or
library does not build, or release lookup fails, the builder stops without an automatic downgrade.
`HALOPAD_XBOX_PINNED=1` explicitly chooses the tested pin without contacting the release API. This
is not necessarily compatible with current online players. The pin is still moved with the reviewed
workflow below. `scripts/xbox/release.py` handles lightweight and annotated Git tags and records the
selected release/commit in the builder's `xbox-release.json`; the app retains that release label even
if upstream later deletes the tag.

`scripts/builder/pc_cache.py` records the completed PC translation under ignored `generated/builder/`.
Repeat builds verify PC source/configuration, accepted input hashes, toolchain, generated IR/images
and any compiled objects before reuse. Xbox-only changes leave that cache valid. A damaged or stale
cache triggers normal translation. The receipt stays with the checkout; it is not a portable cache
or an executable updater. Packages are staged before replacing prior output archives. The installed
app and player containers are never modified by the builder.

The ordinary picker remains the default regardless of the last-played edition. Its **Update Xbox…**
action opens the PadMint update instructions, and its notice distinguishes a newer compatible build
from a different network version. Unknown/offline metadata is never presented as proof of compatibility.

Check upstream releases on a regular maintenance pass (weekly is the proposed cadence), then
freeze an exact commit for validation. Do not chase changing HEAD during a pass. This is a
local build/update workflow, not an in-app executable updater or a scheduled job already installed.

```sh
scripts/xbox/update-pin.sh --to f2ba71d9af4c6fc65d7419cc22e8f4899b16da88 --simulator <dedicated-simulator-UDID>
# Only after all checks and visual review pass:
scripts/xbox/update-pin.sh --to f2ba71d9af4c6fc65d7419cc22e8f4899b16da88 --simulator <dedicated-simulator-UDID> --accept
```

The script lists upstream changes, backs up Mac and selected Simulator Xbox saves, builds the
candidate, and runs isolated Mac and Simulator menu/campaign/match tests. `--accept` requires an
explicit Simulator and all checks passing. `--device UDID` additionally backs up physical-device
Xbox saves; it does not establish physical gameplay acceptance. On rejection/interruption the
checkout and Mac build return to the accepted pin. A candidate installed in the Simulator remains
an explicitly labeled preview; revision/hash checks reject stale libraries during ordinary builds.
Rebuild and install in place after accepting. Screenshots require human/agent visual review, not
just a nonblack-pixel check. An accepted pin is the repeatable development baseline,
not full progression/fidelity or physical-device acceptance. The Xbox card continues to
say **EXPERIMENTAL** even after a candidate's regression gates pass.

The update gate retains the normal PC entry point (no development `--scene`)
and launches with `--device-data`, without redirecting the PC edition to Mac
development state. It requires the existing private PC runtime work. Preserve
the old full app/data first, use the intended renderer setting, and exercise the
ordinary picker plus a copied checkpoint. Check shared control routing after
every guest update; upstream gamepad/profile defaults can change even though
our overlay source is untouched. Build74 unadapted Mac/ANGLE Simulator smoke
passes; its adapted Simulator preview also passes smoke and copied73 Green Thumb
controls/save/reload and exact74 Original/Sharper water/shadow regression.
Actual update-helper acceptance advances the development pin to74, with the
adapted preview restored and real state preserved. Upstream network protocol is
now10 (was9 at66); do not promise interoperability with older Xbox-port peers.
See [update evidence](XBOX-SIMULATOR-PASSES.md#upstream74-unadapted-update-gates-2026-10-03).

Keep three independently reviewable layers: the guest commit in
`config/xbox-engine.lock.json`, the ANGLE renderer pin, and HaloPad's shell/input
adapter. Unmerged renderer experiments use an explicit `XBOX_REV` and isolated
outputs/saves; they are not silently folded into the accepted release pin.

Each attempt now uses a unique save-backup directory. Mac and Simulator copies
must compare byte-for-byte with their source folders, and checksum creation and
readback must succeed before the candidate build starts. Failed or empty
Simulator container lookup refuses the update; install HaloPad on the selected
dedicated Simulator before using this maintenance command. An inspected app
with no saves is valid. Stop games before maintenance: directory comparison is
not an atomic snapshot of a concurrently writing game. The optional physical
copy has destination checksums, not independent source/readback or compatibility
proof; use it only in a coordinated device window.
`python3 -m unittest discover -s tests -p 'test_xbox_update_pin.py'` exercises
the real shell control flow with inert Git/build/device boundaries and synthetic
save copies, not an actual upstream promotion.

The app also copies nonempty Xbox saves to `Documents/Halo Xbox/Save Backups/<previous-identity>-<time>`
before a changed guest opens them. Identity includes upstream revision and guest
SHA256, so a same-pin adaptation and rollback both trigger backups. A legacy
revision-only marker triggers one backup. A failed backup or missing guest
identity blocks startup. This preserves recovery data,
**not save-format compatibility**; upstream saves are snapshots. PC saves are not migrated into Xbox
saves. The **About these builds** panel shows the bundled revision and preview status.

Optional original-Xbox texture-byte diagnostics are revision-specific: builds 61
and 64 change the cache layout, so the runner rejects that diagnostic until its ABI is
adapted/reviewed. Normal builds, updates and gameplay do not use that reader.

## Evidence (2026-09-30)

| Check | Result |
|---|---|
| Disc | `Halo - Combat Evolved (USA).xiso.iso`: all 24 maps build `01.10.12.2276` (NTSC, upstream's reference speed); `default.xbe` SHA-256 `ed3a8e96…e3a3ac`; 1.7 GB of maps. The in-app extractor's copy is byte-identical to the Mac extraction |
| Pin | `b47f237d` |
| Guest image | 7.0 MB ELF; .text 2.6 MB, 657,553 instructions, no use of x27/x28, 191 import stubs, all resolved by the host |
| Mac (M3 Max, ANGLE Metal) | Menu; `map_name levels\a10\a10` loads The Pillar of Autumn; Blood Gulch Slayer with a stand-in machine: 2,100+ ticks, kills, respawns, shield damage, no corrections; in-match first-person frame with HUD. `smoke-mac.py` passes all three |
| iPad Simulator (iPadOS 26.5) | HaloPad's own app: picker, the Halo Xbox card, disc import into Documents/Halo Xbox (24 maps), menu, touch gamepad drawn. The Halo PC card still starts Custom Edition (its license dialog on a fresh install) |
| iPad Simulator match | HaloPad (the iOS host) hosts Blood Gulch; a stand-in machine joins from the Mac: 1,469 ticks, 8 hits, in-match first-person frame with the Link button. A white triangle in that frame is not yet explained (the Simulator draws with Apple's software renderer) |
| Physical iPad Pro 12.9" (6th gen, M2) | Signed with the existing profile (both memory entitlements). Guest memory reserved at `0x7000000000`; OpenGL ES 3.0 on the M2 GPU; 48 kHz audio; menu; The Pillar of Autumn's opening. Backups before each in-place install: `generated/device-backups/ipad-20260930-192030-before-xbox` (Documents + Library, SHA-256 list) and `…-193829-before-xbox-2` |
| Update routine | Upstream `c68db561` (10 commits newer, including changes to its Android build) builds through the translator and passes the smoke test; the pin was left at `b47f237d` so the installed iPad build matches it |

## Open items

- **iPad match (separate physical gate):** iOS allows broadcast only with Apple's restricted multicast
  entitlement, so the Xbox screen's **Link** button lists the other devices' addresses (and shows this
  device's own), which the game searches instead of broadcasting. Even so, an iPad joining a Mac-hosted
  game found nothing: a plain listener on the Mac's game port received **no packets** from the iPad,
  while the Mac copy's own search reached it through the same host code. An iOS permission block
  was a hypothesis, not a demonstrated root cause. Local Network authorization,
  route/address selection and socket diagnostics still need checking on the physical iPad. The
  builds declare Local Network usage. Do not infer hardware results from the Simulator host match.
- **Human play on the device:** touch gamepad feel and a Bluetooth controller on the iPad are untested
  by a player.
- **Visual fidelity:** corrected Mac drawable capture shows a properly letterboxed cinematic.
  The earlier lower-left picture was an invalid test capture, not a presentation defect.
  Simulator geometry/texture artifacts remain, including pale triangles in the match frame.
  The Mac program is a test tool, not a product.
- **Internet play:** the game starts internet hosting and asks public STUN servers for its address at
  start-up; it should be opt-in in the app. UPnP and Discord are stubbed.
- **Missing on OpenGL ES 3.0:** `glCopyImageSubData` and `glDrawElementsBaseVertex` (upstream falls back);
  Bink movies are skipped, as upstream does.
