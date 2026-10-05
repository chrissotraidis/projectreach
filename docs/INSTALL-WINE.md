# Install Wine for HaloPad on macOS

HaloPad uses Wine on your Mac to apply the official Halo CE 1.10 update and create
your installer-generated product ID. The finished app does not need Wine.

Homebrew [disabled its Wine cask on September 1, 2026](https://formulae.brew.sh/cask/wine-stable)
because it does not pass its Gatekeeper check. Retrying `brew install --cask wine-stable`
will fail. An existing working installation can still be used; check it with
`wine --version`, `command -v wineboot`, `command -v wineserver` and `command -v winepath`.

## Install the publisher's app

1. Download `wine-stable-11.0_1-osx64.tar.xz` from the
   [Wine macOS publisher's 11.0_1 release](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.0_1).
   Verify the checksum below, then expand it and move **Wine Stable.app** to **Applications**. Keep an existing working
   Wine app if you already have one; there is no need to replace it for this fix.
2. Install the **GStreamer runtime for macOS, universal** linked under Requirements
   on that same release page. Choose **Install for all users**. Wine expects
   `/Library/Frameworks/GStreamer.framework`; Homebrew's separate `gstreamer` formula
   is not a replacement for that framework.
3. Open **Wine Stable** once. On Apple silicon, allow macOS to install Rosetta if
   prompted. If macOS blocks Wine as an unidentified developer, review the source
   and use Apple's [Open Anyway instructions](https://support.apple.com/en-us/102445)
   in **System Settings > Privacy & Security** for this app. Keep Gatekeeper enabled.

The SHA-256 of the 11.0_1 archive is:

```text
b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388
```

Compare it with `shasum -a 256 ~/Downloads/wine-stable-11.0_1-osx64.tar.xz`
before opening the downloaded app.

## Let PadMint find Wine

Dragging Wine into Applications does not put its commands on your Terminal's path.
After installing Homebrew and the other tools listed by PadMint, paste this block
into Terminal. It links the four commands HaloPad needs into Homebrew's `bin`
directory, leaves existing files and links alone, and stops if Wine cannot run:

```sh
(
  set -eu
  wine_bin="/Applications/Wine Stable.app/Contents/Resources/wine/bin"
  brew_bin="$(brew --prefix)/bin"
  "$wine_bin/wine" --version
  for tool in wine wineboot wineserver winepath; do
    test -x "$wine_bin/$tool"
  done
  for tool in wine wineboot wineserver winepath; do
    if [ ! -e "$brew_bin/$tool" ] && [ ! -L "$brew_bin/$tool" ]; then
      ln -s "$wine_bin/$tool" "$brew_bin/$tool"
    fi
  done
  "$brew_bin/wine" --version
  "$brew_bin/wineserver" --version
)
```

Quit and reopen PadMint, choose HaloPad again, and retry. This also works with
PadMint 0.4.8: skip its old `brew install --cask wine-stable` line after completing
these steps. Your installer, product key and saved games do not need changing.

If Wine is still reported missing, run `command -v wine wineboot wineserver winepath`.
All four should resolve. An existing broken link is deliberately not replaced;
inspect it with `ls -l "$(brew --prefix)/bin/wine"` before changing your installation.
