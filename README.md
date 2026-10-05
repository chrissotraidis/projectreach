# HaloPad

<p align="center">
  <strong>Halo: Combat Evolved on iPhone, iPad and Mac.</strong><br>
  The Xbox edition with the original campaign and online matches of up to 128 players, plus Halo Custom
  Edition on its community servers. Touch, keyboard and mouse, controllers and real networking.
</p>

<p align="center">
  <img alt="Version 0.3" src="https://img.shields.io/badge/version-0.3-8E8E93">
  <img alt="iOS and iPadOS 17 or later" src="https://img.shields.io/badge/iOS%20%2F%20iPadOS-17%2B-0A84FF?logo=apple">
  <img alt="macOS 14 or later on Apple silicon" src="https://img.shields.io/badge/macOS-14%2B%20Apple%20silicon-0A84FF?logo=apple">
  <img alt="Online matches of up to 128 players" src="https://img.shields.io/badge/online-up%20to%20128%20players-30D158">
  <img alt="Game data not included" src="https://img.shields.io/badge/game%20data-not%20included-FF453A">
  <img alt="Status: preview" src="https://img.shields.io/badge/status-preview-FFD60A">
  <a href="https://discord.gg/xwHfUD2bxW"><img alt="Join the community on Discord" src="https://img.shields.io/badge/Discord-Join%20the%20community-5865F2?logo=discord&amp;logoColor=white"></a>
</p>

![HaloPad at Halo's main menu in the iPad Simulator, with the HaloPad three-dot menu button in the corner](docs/images/halopad-menu.jpg)

*HaloPad at Halo's own main menu. iPhone 14, iPad Pro and Apple silicon Mac builds play local and online.*

**[What is it](#what-is-halopad) · [Status](#current-status) · [Get it](#build-and-install) ·
[Playing](#playing) · [FAQ](#frequently-asked-questions) · [Discord](https://discord.gg/xwHfUD2bxW)**

> [!IMPORTANT]
> **Bring your own game.** You need your own Halo: Custom Edition 1.10 for PC and, for the Xbox
> edition, your own Halo: Combat Evolved Xbox disc image. This repository contains no Halo files,
> product key, engine source or translated game code.
>
> **Built on your Mac.** There is no prebuilt download. You build HaloPad from your own game with
> [PadMint](https://github.com/chrissotraidis/padmint) or one command: a Mac app you open right away,
> or an IPA you sign with your own Apple profile. It is a preview: playable on real hardware, with
> frame pacing and some Xbox graphics still being tuned.
>
> **AI disclosure:** HaloPad is developed with substantial AI assistance. The
> [status log](docs/STATUS.md) records what has actually been checked, and on which device.

## What's new

- **0.3.4: the server browser finds games.** The Xbox edition now ships OpenCE's list of public
  matchmaking servers (`brokers.txt`), which it was missing, so **Multiplayer › Server Browser**
  lists everyone's public games and joining them works. Rebuild with PadMint and install over your app.
- **0.3.3: online with current OpenCE players.** The Xbox edition moves to OpenCE build 119
  (network version 13, with online co-op), so HaloPad joins the same games as everyone else again.
  HaloPad now tells you on the edition picker when OpenCE ships a build that can no longer play with
  yours; rebuild with PadMint and install over your app to catch up. Saves stay.
- **0.3.2: both editions from PadMint.** PadMint (and `build.sh --xbox`) now builds the Xbox edition
  into HaloPad too, on iPhone, iPad and Mac, by fetching the engine from upstream on your Mac. Mac
  players get **⋯ › Controls › Mouse Speed**.
- **0.3: HaloPad for Mac.** The same app, edition picker, ⋯ menu and icon on Apple silicon Macs, with
  keyboard and mouse, and no Apple account needed.
- **0.2.1:** build HaloPad with [PadMint](https://github.com/chrissotraidis/padmint) in a few clicks.
  Bungie's 1.10 update is downloaded for you and CrossOver is no longer needed
  ([notes](https://github.com/chrissotraidis/projectreach/releases/tag/v0.2.1)).
- **0.2:** the Xbox edition, with the original campaign and online play of up to 128 players; an
  edition picker and one shared ⋯ menu; smoother Custom Edition frames; normal startup with the
  product ID from your own key ([notes](https://github.com/chrissotraidis/projectreach/releases/tag/v0.2.0)).

## What is HaloPad?

HaloPad (the codebase is Project Reach) brings two versions of Halo: Combat Evolved to iPhone, iPad and
Apple silicon Macs.
When your build includes both, it asks which one to open at launch.

| | Halo Custom Edition (PC) | Halo: Combat Evolved (Xbox) |
| --- | --- | --- |
| How it runs | Your own `haloce.exe` 1.10, translated from x86 to native ARM64 ahead of time | [OpenCE](https://github.com/OpenCommunityEdition/OpenCE), the port of the Xbox decompilation, built on your Mac |
| Your files | Your Custom Edition installer and product key | Your own Xbox disc image, imported in the app |
| Online | Community-run Custom Edition servers and LAN, alongside PC players | Internet and system link games of up to 128 players with PC, Linux and Android players on the same build |
| Campaign | No | The original Xbox campaign |
| Runs on | iPhone, iPad and Mac | iPhone, iPad and Mac |
| Build with | PadMint or one command | A few extra commands ([below](#adding-the-xbox-edition)) |

For Custom Edition, HaloPad supplies the Windows services the game expects: Direct3D 9 rendered through
Metal, DirectInput mapped to touch and controllers, audio, files, the registry and Winsock networking.
Nothing is compiled on the device, so it needs no JIT. The Xbox edition draws with Metal through ANGLE.
Both editions share the touch controls and the ⋯ menu, and keep their own saves.

## Current status

| Area | Where it stands |
| --- | --- |
| **iPad** | iPad Pro 12.9" (6th gen) plays both editions, local and online |
| **iPhone** | iPhone 14 plays local matches, including 1280 × 720 widescreen; slower in loading and busy scenes. Online play not fully tested |
| **Mac** | Both editions run on Apple silicon Macs (macOS 14+) with keyboard and mouse: Custom Edition lists public servers; the Xbox edition imports your disc and plays the campaign |
| **Online** | Custom Edition joins public PC servers; the Xbox edition joins internet games through the decompilation's game browser |
| **Controls** | Movable, resizable touch overlay, look-speed settings, iOS keyboard for chat and names, Xbox-style controllers, trackpad and mouse in menus |
| **Custom maps** | `.map` files import from the ⋯ menu. DLL mods (Chimera, OpenSauce, HAC2) do not load |
| **Xbox edition** | Preview: campaign and multiplayer run on a physical iPad; some textures and effects differ from the original |

**Known issues:** the first time a map, weapon or effect appears, play can hitch for up to a second.
Some Xbox textures look softer or different from the original. A few players have seen a controller
stop responding after reconnecting it; if that happens, please share the diagnostic log. Changing
Halo's resolution is tested on iPhone, not yet on iPad, so 800 × 600 is the safest choice there.
Measurements and open checks are in [docs/STATUS.md](docs/STATUS.md).

## Build and install

You need:

- a Mac with Apple silicon and Xcode
- your own Halo: Custom Edition installer (`HaloCESetup.exe`) and its product key
- for iPhone or iPad: iOS/iPadOS 17 or later with Developer Mode on, and an Apple development profile
  that allows **Extended Virtual Addressing** and **Increased Memory Limit** (the Mac app needs neither)

Put `HaloCESetup.exe` and a `product-key.txt` holding your Halo PC key in one folder. Then either:

- **PadMint (easiest):** download [PadMint](https://github.com/chrissotraidis/padmint#quick-start) 0.4.8
  or later, choose **HaloPad**, then **iPhone / iPad** or **This Mac**, then your installer. It lists the tools
  to install, builds HaloPad with both editions and gives you the app plus a **HaloPad game data** folder.
- **Terminal:** install the tools once, then run the builder:

  ```sh
  brew install sevenzip winetricks llvm lld && brew install --cask wine-stable
  scripts/builder/build.sh /path/to/that/folder --ipa HaloPad.ipa        # iPhone and iPad
  scripts/builder/build.sh /path/to/that/folder --mac --zip HaloPad.zip  # Mac
  ```

Both download Bungie's free 1.10 update, check every file by hash, translate Halo and make your product
ID on your Mac, then write the app and `Halo-CE.halopad.zip`. On a Mac, unzip HaloPad, move it to
Applications and open it. On iPhone or iPad, install the IPA with your own signing
([install guide](docs/INSTALL-IPHONE.md)). Then open HaloPad, choose **Choose Prepared Package…** and
pick the zip. Your game files, key and translated code never leave your Mac.

**An app you build contains code translated from your game: it is yours alone. Never share or upload it.**

To update, install over the existing app. Deleting HaloPad deletes your profiles and imported files.

### Adding the Xbox edition

PadMint and the `--xbox` builder option add the Xbox edition to the same app, so HaloPad opens to the
edition picker. Your Mac downloads the pinned [OpenCE](https://github.com/OpenCommunityEdition/OpenCE)
engine and the ANGLE renderer from their own repositories and builds them; none of that code is part of
HaloPad. You add your own Xbox disc image in the app (**Add Your Xbox Disc** on the picker).

```sh
brew install cmake ninja                                          # once, on top of the tools above
scripts/builder/build.sh /path/to/that/folder --xbox --ipa HaloPad.ipa        # iPhone and iPad
scripts/builder/build.sh /path/to/that/folder --mac --xbox --zip HaloPad.zip  # Mac
```

The first Xbox build takes longer and needs about 35 GB free. [Xbox engine](docs/XBOX-ENGINE.md) covers
updating to newer upstream builds, the tested disc (NTSC-US, maps build `01.10.12.2276`) and the
lower-level `scripts/xbox/build-ios.sh` steps.

## Playing

Create a Halo profile, then use the game's own **Multiplayer** menus to host or join.

- **⋯ menu:** the same in both editions: touch settings, controller guide, display options,
  **Report a Problem**, **Share Diagnostic Log** and **Switch Edition**. Custom Edition adds keyboard
  and chat, join by address and custom maps; Xbox adds System Link
- **Touch:** move and resize the overlay; tune look speed in **Controls › Look Speed & Touch Settings**
- **Mac:** keyboard and mouse as on a PC. The pointer locks while you play. In Custom Edition **Esc**
  opens Halo's menu and frees it; in the Xbox edition **F12** frees or recaptures it, as on PC. Then
  click ⋯ for the menu, including **Switch Edition**. Aim too fast or slow? **⋯ › Controls › Mouse
  Speed** (both editions); Custom Edition's own **Settings › Controls** sensitivity applies on top
- **Controllers:** connect before opening HaloPad for the most reliable result. In menus the D-pad
  moves, **A** selects, **B** goes back and **Menu** pauses. Halo's "Button 6" pickup is **RB**
- **Leaving a match:** **⋯ › Open Leave Game Menu…**, then **Leave Game**
- **Resolution:** 800 × 600 (4:3) by default. Halo's **Settings › Video** goes up to the screen's own
  size; 1280 × 720 is true widescreen, or use **Fill** to stretch 4:3
- **Recording:** play a warm-up match on the same map first, so new effects don't hitch on camera

## Frequently asked questions

<details>
<summary><strong>Can I download an IPA?</strong></summary>

No, and that is deliberate. A working HaloPad contains code translated from your copy of Halo, and the
Xbox edition contains an engine built from a decompilation, so neither can be handed out. You build your
own in a few clicks with [PadMint](https://github.com/chrissotraidis/padmint), or with one command.

</details>

<details>
<summary><strong>Can I play online with people on PC?</strong></summary>

Yes. Custom Edition joins the community-run PC servers in Halo's own lobby. The Xbox edition plays with
other OpenCE players on PC, Linux and Android, up to 128 per match. The two editions cannot
play each other.

</details>

<details>
<summary><strong>Why can't I join someone's Xbox game?</strong></summary>

Everyone in a match needs the same OpenCE network version. HaloPad shows its build on the Xbox card and
in **⋯ › About** (for example *build 119*), and the picker tells you when OpenCE has moved past it.
When that happens, rebuild HaloPad with PadMint (it always uses the latest HaloPad release) and install
over your app; saves stay. The game browser finds games through public relay servers, as upstream does;
there is no HaloPad server.

</details>

<details>
<summary><strong>Which version of Halo works?</strong></summary>

Halo: Custom Edition 1.10 for the PC edition (the builder starts from the original installer and
applies the official update). An original Xbox Halo: Combat Evolved disc image for the Xbox edition;
NTSC-US is the tested one. The retail PC `halo.exe` and the Master Chief Collection are not supported.

</details>

<details>
<summary><strong>Does it run on iPhone?</strong></summary>

Yes. An iPhone 14 has imported the game and played local matches, including in widescreen. Loading and
busy scenes are slower than on iPad for now.

</details>

<details>
<summary><strong>Does it run on Mac?</strong></summary>

Yes, on Apple silicon Macs with macOS 14 or later. It is the same app as on iPad, built for the Mac, with
the same edition picker and ⋯ menu, and it needs no Apple account. PadMint builds it with both
editions.

</details>

<details>
<summary><strong>Do I need a paid Apple developer account?</strong></summary>

Not for the Mac app. On iPhone and iPad, HaloPad needs the **Extended Virtual Addressing** and
**Increased Memory Limit** capabilities, because it reserves Halo's full 32-bit address space. Sign with
an Apple development profile that allows both. Free signing through AltStore, SideStore or Sideloadly
has not been tested.

</details>

<details>
<summary><strong>Is this an emulator?</strong></summary>

Not in the usual sense. Custom Edition's x86 code is translated to ARM64 ahead of time and runs
natively, with no JIT; HaloPad provides the Windows, Direct3D 9, input, audio and network pieces it
calls into. The Xbox edition is a native port of the decompiled game.

</details>

<details>
<summary><strong>Can I use mods and custom maps?</strong></summary>

Custom `.map` files, yes: **⋯ › Add Custom Maps…**. Windows DLL mods such as Chimera, OpenSauce and HAC2
cannot load into a translated game.

</details>

<details>
<summary><strong>Will updates keep my profile and saves?</strong></summary>

Yes, when you install over the existing app with the same signing. Never delete HaloPad to update.

</details>

## Help and community

- **Discord:** [discord.gg/xwHfUD2bxW](https://discord.gg/xwHfUD2bxW) for setup help, testing and news,
  shared with HaloPad's sibling projects such as KartPad, BlueWake and MeleePad
- **Bugs:** **⋯ › Report a Problem** or [open an issue](https://github.com/chrissotraidis/projectreach/issues/new/choose)
  with your device, iOS version, build and what you did. Never attach game files, maps or app packages
- **Diagnostic log:** **⋯ › Help › Share Diagnostic Log…**, or **Files › HaloPad › HaloPad Logs**. It
  records controller, display, stall and crash events, never typed text, names, chat or server addresses

## Documentation

[Install guide](docs/INSTALL-IPHONE.md) · [Xbox engine](docs/XBOX-ENGINE.md) ·
[Status](docs/STATUS.md) · [Journal](docs/JOURNAL.md) · [Execution model](docs/EXECUTION-MODEL.md) ·
[Graphics contract](docs/GRAPHICS-CONTRACT.md) · [D3D9 inventory](docs/D3D9-INVENTORY.md) ·
[Runtime and networking](docs/G3-RUNTIME.md) · [Rights status](docs/RIGHTS-STATUS.md)

## Credits

HaloPad stands on a lot of other people's work. Thank you to:

- [SR](https://github.com/M-HT/SR) by M-HT, the static x86 recompiler at the heart of the translation pipeline
- [OpenCE](https://github.com/OpenCommunityEdition/OpenCE) (formerly halo-ce-universal) by cybersecurity and its
  contributors, the Xbox engine port, built on the decompilations [bnunu/halo-1](https://github.com/bnunu/halo-1)
  and [punpckhdq/halo](https://github.com/punpckhdq/halo)
- [ANGLE](https://chromium.googlesource.com/angle/angle), whose Metal backend draws the Xbox edition
- [xboxrecomp](https://github.com/sp00nznet/xboxrecomp) by sp00nznet, used for runtime research
- [SunPad](https://github.com/chrissotraidis/sunpad), whose touch overlay and three-dot menu HaloPad adapts
- Xiph.Org contributors for Ogg and Vorbis, and udis86 for disassembly
- The Halo Custom Edition community, who have kept servers, maps and the master server running for over twenty years

Each project keeps its own license and notices. This repository does not claim a blanket license over
upstream work or Halo content.

## Legal

HaloPad is an independent fan project. It is not affiliated with or endorsed by Microsoft, Xbox or
Halo Studios. Halo and Halo: Custom Edition are trademarks of their respective owners. HaloPad grants
no rights to Halo content: you need your own legitimate copy and are responsible for the laws that apply
to it. Upstream notes that parts of the Xbox decompilation were reconstructed with help from leaked
Bungie material, which is why the Xbox edition is only ever a personal build. No project-wide license
has been chosen yet; see [rights status](docs/RIGHTS-STATUS.md).
