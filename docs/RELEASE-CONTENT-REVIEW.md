# Build 22 package contents, 2026-10-09

This review covers the actual private 0.3.8/build 22 archives, OpenCE 157 at
`73dc01d09a21875f14c77b4430f20518d1f5ad09`. It does not approve publication or
replace the installer/gameplay checks.

| Package | SHA-256 | Files |
| --- | --- | --- |
| iOS | `238e90e1d4d500a01ace596028dd9a559a63b5122535b4241d0d240188d7290b` | 12 |
| Mac | `3af17d9cf27298d046ff29f226dfc01b22fc8fee3464d03d82800f80a8dc928e` | 11 |

Both contain the native executable, app metadata/signature, app icon catalog,
edition-picker background, notices, and exactly three files under `data/xbox`:
the guest engine, engine build record, and broker list. No disc/maps, player saves,
PC runtime or personal provisioning profile are archive members. This statement
alone does not describe assets compiled into the executable/guest.

The two archived guest images match each other. Against the exact upstream
checkout mounted read-only under the build lock, all **313** resources selected
by upstream's embedding lists were located byte-for-byte in that guest:

| Embedded group | Count | Source evidence |
| --- | --- | --- |
| HUD replacement PNGs | 69 | `tools/hud_assets.py` describes rendering hand-drawn SVGs; map data supplies layout/matching information. |
| Title replacement PNGs | 35 | `tools/title_assets.py` renders replacement font text; some generation paths retain processed map backgrounds. See the unresolved item below. |
| Font files | 2 | Overpass 750/900; upstream's `fonts/README.md` describes the Google Fonts source and SIL OFL. The notice is packaged. |
| Menu XML/PNG resources | 207 | `menus.json` names the embedded files; upstream documents redraws/placeholders and runtime references to pictures in the player's own map. |

Upstream's [license at this revision](https://github.com/OpenCommunityEdition/OpenCE/blob/73dc01d09a21875f14c77b4430f20518d1f5ad09/LICENSE.md)
is CC0. The bundled notice inventory separately records dependency and font
notices. Source provenance is established here; the upstream license is not an
independent determination of ownership of every input.
The older [decompilation-origin review](REVIEW-HALO1-DECOMP.md) also records
upstream source-origin concerns. This asset inventory does not re-audit or resolve
those historical findings; do not treat removal of title PNGs alone as complete
distribution clearance.

The compiled Apple catalogs contain only `AppIcon` renditions. Both picker
backgrounds match the checked-in image exactly; its origin is recorded in
`port/ios/assets/README.md`. No artwork or gameplay behavior was changed by this review.

## Specific item still requiring a distribution decision

The [upstream title generator](https://github.com/OpenCommunityEdition/OpenCE/blob/73dc01d09a21875f14c77b4430f20518d1f5ad09/tools/title_assets.py)
has three background paths: a supplied SVG redraw, a regenerated glow, or a
processed background from the game-map bitmap. The title list does not record
which path generated each PNG. All 35 PNGs are confirmed inside build 22; we
cannot describe all of them as independently drawn replacements on this evidence.

This is a concrete provenance question, not a finding that a license was violated.
Before public delivery, resolve acceptance of these assets or prepare a shared
package that omits the optional title replacements and verify the game's original
map-texture fallback. Disabling a display setting alone would leave their bytes
in the package. Existing personal packages remain untouched.

## Reproducible private evidence

`generated/release-content-audit-20261009/` contains:

- `package-inventory.json`: every archive member, size and hash.
- `embedded-asset-proof.json`: the 313 source paths, hashes, sizes and matching
  offsets in the actual packaged guest.
- `asset-inventory.json`: the upstream asset-tree inventory.
- `app-art-proof.json` and `*-asset-catalog.json`: background equality and Apple's
  compiled-catalog inspection.
- `inspect_engine.py` and `upstream/`: the read-only collection script and exact
  source documentation inspected. The volume was detached after collection.

These generated files remain private and ignored. This review neither changes the
candidate counter nor installs, launches, publishes or uploads a package.
