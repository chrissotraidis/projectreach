# HaloPad Xbox on Apple TV (experimental)

The Xbox edition runs on an Apple TV 4K with a game controller. Like every HaloPad build, it is a
personal build: you build it on your own Mac, sign it with your own Apple account and add your own
Halo: Combat Evolved Xbox disc. Never share the app you build.

Checked on an Apple TV 4K (3rd generation) with tvOS 27.2. Earlier Apple TV models are untested.

## What you need

- A Mac with Apple silicon and **Xcode** 26 or later.
- An Apple account signed in to Xcode (Xcode › Settings › Accounts). A free account is expected to
  work, but has not been tried yet. Apps signed with one stop opening after 7 days and must be
  built and installed again.
- An Apple TV 4K on tvOS 17.4 or later, on the same network as the Mac.
- A game controller paired with the Apple TV: one tvOS supports, such as an Xbox or PlayStation
  controller.
- Homebrew's `llvm` and `lld` (`brew install llvm lld`). OpenCE's newer engines are too large for
  Apple's linker, so Apple TV builds link with LLVM's.
- Your Halo: Combat Evolved Xbox disc image (`.iso` or `.xiso`).

## Pair the Apple TV with Xcode

1. On the Apple TV: Settings › Remotes and Devices › Remote App and Devices.
2. On the Mac: Xcode › Window › Devices and Simulators. Choose the Apple TV, then **Pair**, and type
   the code the Apple TV shows.

## Signing

Xcode makes the signing profile the first time it runs an app on your Apple TV. Do this once:

1. In Xcode: File › New › Project › tvOS › App. Name it anything.
2. Under Signing & Capabilities, choose your team and give it a bundle identifier of your own,
   such as `com.yourname.halopad`.
3. Choose your Apple TV as the run destination and press Run. Once the empty app opens on the TV,
   you can delete it there and close the project.

The build finds that profile and its signing identity by itself
(`scripts/xbox/tvos-signing.py`). If you have more than one, it lists them; choose one with
`--team TEAM --bundle-id ID`.

## Build and install

```sh
scripts/xbox/build-ios.sh --tvos
xcrun devicectl list devices                       # your Apple TV's identifier
xcrun devicectl device install app --device <identifier> ref/xbox-build/out/appletvos/HaloPadXbox.app
```

The first build fetches and translates OpenCE and takes a while; see
[XBOX-ENGINE.md](XBOX-ENGINE.md) for the engine checkout it uses.

## Add your game

Extract the maps from your disc on the Mac (the same script HaloPad's other builds use), then copy
them into the app's data folder on the Apple TV:

```sh
python3 scripts/xbox/extract-maps.py <your disc image> ref/xbox-build/data   # writes data/maps
xcrun devicectl device copy to --device <identifier> --domain-type appDataContainer \
    --domain-identifier <bundle identifier> --source ref/xbox-build/data/maps \
    --destination Library/Caches/data/maps
```

The bundle identifier is the one you chose under "Signing" (the build prints it after
`signing:`). Then open **HaloPad Xbox** on the Apple TV.

## Limits

- tvOS may delete an app's cached files when the Apple TV runs low on storage. The maps and saves
  live there (tvOS apps may write nowhere else), so copy the maps again if that happens.
- Play with a controller: the Siri Remote does not navigate the menus.
- Steam Workshop needs an OpenCE engine newer than HaloPad's pinned 359.
