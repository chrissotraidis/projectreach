# Install HaloPad on iPhone or iPad

HaloPad currently produces a personal IPA, not a public app download. Build it
once with PadMint or the [source builder](../README.md#build-and-install), then
sign and install it. Do not run the source builder again after PadMint finishes.

The current source supports **Xbox only**, with no PC installer, product key or
prepared PC package. Released HaloPad 0.3.7 / PadMint 0.4.10 still build both
editions. The current source requires an Apple silicon Mac with Xcode 26 or
later (and a macOS version that supports it) to build; the device requires iOS/iPadOS 17.4+, Developer Mode and a development profile
covering that device with **Extended Virtual Addressing** and **Increased
Memory Limit**. A generated IPA still needs signing. Generic sideloading-tool
instructions are not evidence that those capabilities will be granted.

## Install your Xbox-only build (current source)

The following uses the existing signing and device-installation scripts. Have
your development identity and device-specific profile ready. If updating an
installed app, back up its Documents and accessible Library first; retain the
same app identity and do not uninstall it.

1. Connect and trust your iPhone/iPad. Check your personal IPA and signing
   profile without installing anything:

   ```sh
   scripts/install-device.sh \
     --identity <Apple-Development-certificate-SHA1> \
     --profile /private/path/HaloPad.mobileprovision \
     --device <actual-device-UDID> \
     --ipa /private/path/HaloPad-Xbox.ipa \
     --check-only
   ```

   The check validates the archive, device app and provisioning profile. It
   does not sign, install or prove the app will launch. Invalid archives stop
   before any device operation.
2. Run the same command without `--check-only` to sign and install. The
   installer unpacks the IPA into private temporary storage, signs a staged
   copy and removes the temporary files afterward. Your original IPA stays
   unchanged. Xbox-only builds need no `--package`; PC and combined builds
   still need their matching `.halopad.zip`. `--app /path/HaloPad.app` remains
   available for an already-unpacked app.
3. Put your own Xbox Halo ISO/XISO in Files. Open HaloPad, choose **Add Your
   Xbox Disc**, and select it. Wait for import, then choose Xbox to play.

The direct-IPA route has installed the Xbox-only candidate on a physical iPad
with the development profile and opened its edition picker, retaining the
checked save/profile/preference files. See [the validation record](STATUS.md#installation-delivery)
for the exact scope and outstanding gameplay checks. This is the current
developer-profile route, not a verified one-click consumer signing flow.

## PC and combined development installation

The procedure below covers the original PC package route. For combined builds,
include `--xbox` in the builder step and import your Xbox disc separately.

## Requirements

- macOS with Xcode 27, this repository and its ignored, accepted `ref/inputs`.
- iOS/iPadOS 17.4 or later, Developer Mode enabled, a trusted cable connection.
- An Apple Development identity and a development provisioning profile for
  `dev.halopad.HaloPad`, including the **specific device UDID**, Extended Virtual
  Addressing and Increased Memory Limit.
- A game-data package prepared for the **exact build** being installed.

Use a profile that includes the device being installed. The maintainer's iPad
development profile passed these checks for the private build-138 installation;
that profile does not authorize installation on other players' devices. Do not
treat a paired iPad record in Device Hub as a connected device.

## Install on the connected iPad

1. Connect the iPad by cable, unlock it, tap **Trust**, and confirm it is listed
   as connected by `xcrun devicectl list devices`. Record its actual UDID.
2. If HaloPad is already installed, copy its `Documents` and accessible `Library`
   contents to a private ignored backup. Do not uninstall the app or erase its
   container. An iOS-protected Library file may resist copying; record that
   limitation and preserve the accessible directories.
3. In Apple Developer, add the actual iPad UDID and create a development profile
   for the existing App ID with both memory capabilities. Download it into a
   private location. Validate the profile against the identity and iPad:

   ```sh
   .venv/bin/python scripts/device_profile.py \
     --profile /private/path/HaloPad.mobileprovision \
     --identity <Apple-Development-certificate-SHA1> \
     --device <actual-iPad-UDID>
   ```

4. Build the app and its game package with `scripts/builder/build.sh`. To sign
   it for your device directly instead of using the unsigned IPA, rebuild the app
   from the builder's translation with your identity and profile:

   ```sh
   .venv/bin/python scripts/build-ios-app.py --iphoneos \
     --identity <Apple-Development-certificate-SHA1> \
     --profile /private/path/HaloPad.mobileprovision \
     --product-id generated/product-id/product-id.txt
   ```

5. Install the signed `HaloPad.app` and its matching `.halopad.zip` to the exact
   device:

   ```sh
   scripts/install-device.sh \
     --identity <Apple-Development-certificate-SHA1> \
     --profile /private/path/HaloPad.mobileprovision \
     --device <actual-iPad-UDID> \
     --app /private/path/HaloPad.app \
     --package /private/path/matching.halopad.zip
   ```

   The script checks App ID, certificate, UDID, expiry and entitlements
   before installation. Keep the same bundle ID to preserve the existing app
   container. Read back the installed bundle and Documents after the copy.
6. Open HaloPad on the iPad. If the first-run picker appears, choose the
   matching package and wait for verification and import. Reach the Halo main
   menu before calling the install successful.

The current iPhone 14 development build is signed and installed. Its matching
package imported through the physical Files picker and reached the main menu.
A local LAN Battle Creek match, profile creation, and leave flow also worked.
The physical iPad imported its matching package, ran local matches, and passed
controller input after opening the app with the pad connected. A late-connect
fix has passed Simulator tests but is not yet installed on the iPad.

## First iPad test

Use a local LAN match only: Multiplayer → Create Game → LAN → Battle Creek →
Slayer → Start Game. Check touch movement, look, fire and pause. Then connect a
controller and check menu navigation, movement, aim, fire and touch-overlay
visibility. Check the three-dot menu, **Controls → Look Speed & Touch Settings**,
**Controller Guide**, **Keyboard & Chat → Show Keyboard**, and profile-name
**Enter / Accept**. **Open Leave Game Menu…** opens Halo's pause menu; choose
Halo's **Leave Game** there. Check lock/unlock recovery and sustained frame
times, heat and battery. A private server test can follow; public battles are
outside this test.

## Current display and performance limits

The verified internal mode is 800 × 600. Halo's own "30 FPS" Framerate Throttle
(the default for new profiles) made frames uneven on iOS, so HaloPad no longer
applies it; Halo's Video menu may still show it. The app's Original aspect
setting preserves 4:3 geometry with side bars on iPhone. Fill stretches the
image and distorts it. Halo's 1280 × 720 mode passed a short local match on the
physical iPhone 14. To retain it, accept Halo's video-test prompt, then press
**OK** on **Edit Profile Settings** so the profile saves. The mode remained
selected after an app relaunch. This short check does not establish sustained
performance; 800 × 600 remains the conservative option if the phone is slow.
The iPhone player reported slow loading and gameplay. A static Battle Creek
view showed about 30 FPS, but that does not establish sustained playability.
Physical finger feel, controller behavior and the iPad result remain open.

## Data and rights

Game files, prepared packages, provisioning profiles and backups belong in
ignored private paths, never Git. A build/IPA contains translated game code
and requires a rights review before any public distribution. See
[rights status](RIGHTS-STATUS.md) and [current status](STATUS.md).
