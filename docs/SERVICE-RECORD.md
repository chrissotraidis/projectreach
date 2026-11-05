# Optional local Service Record

This contribution adds a native Service Record for the Xbox engine on iPhone,
iPad and Mac Catalyst. It is a source-only, opt-in feature. The existing engine
pin and ordinary builds retain their current behavior.

## Scope

The multiplayer-menu card opens a full-screen record with an overview, weapon,
map and game-mode breakdowns, a local rank ladder, a medal collection, and the
latest 100 recorded matches. The nameplate reads the selected saved player's
bounded name from `blam.sav`. Its emblem, panels, rank glyphs and medal icons are
drawn in native code using system fonts. There is no external rank-art bundle.

The bridge records locally observed kills, deaths, assists, streaks, authoritative
counter updates, match entry/end and 15 multikill/spree medals. It does not
reconstruct earlier matches, missing weapon attribution, campaign completion,
accuracy, opponents, skill ratings or server matchmaking history. A join baseline
excludes kills/deaths/assists accrued before observation. Authoritative counter
corrections can lower the tracked totals. If a correction makes source-event
counts exceed the corrected aggregate, source attribution is shown as unknown
with an explanation; the original event ledger remains intact.

Wins, losses and draws use the game's reported completed-match outcome. Unknown
outcomes and unfinished matches are excluded from win percentage. K/D does not
decide a match result. If a client never observes a completed result, the record
stays unfinished or unknown rather than inferring a win or loss.

All records stay beside the player's local saves. This change has no cloud
backup/sync, telemetry, account registration, game download or network-message
extension. Copying a save profile's `.halopad-profile-id` copies its local record
identity; profile names alone are not identity keys. Automatic cross-device
merging and duplicate-identity conflict resolution are outside this contribution.

## Local progression policy

One confirmed kill earns one local XP. Presentation groups the existing monthly
XP ledger into Gregorian calendar quarters in the device's local time zone.
Previous-quarter totals remain available; no XP rows are reset or deleted.
Career combat allocations use the quarter in which activity is observed. A match
spanning a boundary can appear in either quarter's history, while history combat
totals cover the recorded part of the whole match. A reported outcome is counted
in its stored completion quarter, once for lifetime totals. This distinction can
make a quarter's history list and that quarter's result counters differ.

The built-in ladder is a neutral example: Level 1–6 at 0, 100, 250, 500, 1,000 and
2,500 XP. These are local presentation levels, separate from server skill and
matchmaking. `HPHaloServiceRecordRanks.m` centralizes this policy. A build can
provide an optional bundle-root `HaloPadServiceRecordRanks.json`:

```json
{"tiers":[{"name":"Level 1","minXP":0},{"name":"Level 2","minXP":100}]}
```

Validation accepts 1–64 nonempty names (at most 80 characters) and strictly
increasing integer thresholds beginning at zero, within signed 64-bit storage.
Boolean, fractional, negative, duplicate and out-of-range thresholds are rejected.
An invalid optional catalog falls back to the built-in ladder. Badge identifiers
are derived from order and rendered as neutral geometric glyphs; the catalog
cannot point at external image paths. The personal 42-rank ladder and its artwork
are not included.

## Build selection

`config/xbox-engine.lock.json` currently pins build-125,
`13c14df95c63156429e96a9694bb9cecd0379228`. That file is unchanged. The Service
Record bridge requires an explicit, separately rebuilt OpenCE337 guest and native
library at revision `899219cc0a14b03bc12f0517a1e9ee4c37158af8`.

The feature flag is exactly `HALOPAD_SERVICE_RECORD=1`. Values other than `0` and
`1`, or enabling it against another revision, fail before source acquisition or
build preparation. For example, after satisfying the existing personal-engine
build prerequisites in [XBOX-ENGINE.md](XBOX-ENGINE.md):

```sh
HALOPAD_SERVICE_RECORD=1 \
XBOX_REV=899219cc0a14b03bc12f0517a1e9ee4c37158af8 \
scripts/xbox/build-ios.sh --device
```

Use `--mac` for the Mac Catalyst engine or omit the platform option for the
simulator engine. Each platform needs its matching rebuilt library, translated
guest and manifest; relinking an old engine does not add event tracking. The
manifest records the opt-in recipe identity and source hashes. The app packager
also needs the same flag and revision and checks that identity before including
the native UI. See its `--help` for platform and signing options. Existing signing
and private-engine distribution restrictions still apply; a successful build is
not permission to distribute a game executable or game content.

No game assets, engine binaries, upstream game-source fixtures, saved databases
or personal configuration belong in this contribution. The commands above are
build instructions; the focused tests do not fetch or build the game.

## Native integration

The optional sources are the `HPCareer*` and `HPHalo*` modules under `port/ios`.
They link against Foundation, UIKit, QuartzCore, CoreText and SQLite. No new
third-party dependency is required.

- Call `HPHaloProgressConfigure(saveRoot)` before starting the guest. It creates
  the progression store, supplies its validated UUID resolver, and configures the
  companion career store on UIKit platforms.
- Attach `HPHaloProgressControllerMakeWithDismissal(before, after)` as a child of
  the game controller. `before` clears touch state and acquires a native input
  suspension; `after` releases it after the complete native navigation flow ends.
  The navigation controller releases that lease at most once through Done,
  interactive dismissal, a profile change, or failed presentation.
- Bind `HPHaloMedalOverlayAttach(controller, eligibility)` on the main queue. Its
  weak controller binding uses the existing game view, never an extra window.
  Eligibility must exclude menus, keyboards, native modals and inactive gameplay.
- The native engine calls `xg_progress_frame_presented()` after frame presentation.
  Menu visibility comes from copied guest/input context.
  `xg_ios_set_native_modal_active()` combines modal suspension with actual app
  activation; `xg_ios_game_menu_visible()` reads the copied menu snapshot.

The guest imports are `host_halopad_progress_kill_v1`,
`host_halopad_progress_menu_v1` and `host_halopad_career_event_v1`. Their host
implementations are `xh_host_*`. The progress event is 24 bytes; the career event
is 320 bytes (`HPCareerStatsEvent.h` has a static size assertion). Weak standalone
engine fallbacks do not persist data. The app supplies strong implementations.

## Storage and failure behavior

`.halopad-progression.sqlite3` retains schema-1 monthly XP and deduplicates kills
using profile UUID plus session/game/map/victim identity. `.halopad-career.sqlite3`
retains schema 4 with event, match, quarter and medal tables. Migrations add or
derive companion tables transactionally; an unsupported/corrupt database is not
deleted or silently replaced. Both use WAL and full synchronous commits.

The progression serial queue owns its database and retry state. The render loop
reads immutable cached menu snapshots and never waits for a database query.
Career operations are serialized by their lock; the progression profile resolver
is called before taking that lock. This order avoids acquiring the stores in
opposite directions. Guest pointers are bounded and copied through checked Mach
reads rather than retained. Profile paths are constrained to existing named
profiles under the configured save root. The UUID sidecar is atomically published;
invalid existing identity files are preserved and rejected.

Storage errors return a retryable result to the guest and show an unavailable or
retrying state, retaining existing files. Retry identity and first-observed XP
dates stay stable within the active process. A force quit during a storage failure
can lose uncommitted in-memory events. The guest's queues and local database
cannot reconstruct activity never observed by this app.

History queries are read-only and capped at 100 rows. They run off the main queue;
generation tokens reject stale filter completions, and profile checks reject
results for a different saved identity. Native views keep the input suspension
until the whole modal closes. Medal preview/retry delivery is deduplicated and
separate from committed medal storage; old awards are not replayed as fresh HUD
animations.

The save root is app-controlled. Path checks reject symlink/database-link inputs
and ambiguous case matches; they are not a general defense against a separate
hostile process concurrently replacing parent directories. Career overview
aggregation currently runs synchronously during a once-per-second UI refresh.
Very large histories may need asynchronous snapshots or query optimization after
profiling. Offline operation is supported, but multiplayer observation naturally
depends on the game session supplying events.

## Verification and acceptance boundaries

`tests/service_record/` uses synthetic events, temporary saves and an isolated
UIKit fixture. It contains no game-source fixture, real player data or engine
binary. Choose explicit output directories on the developer's build volume and
reuse an existing simulator from `xcrun simctl list devices available`:

```sh
python3 tests/service_record/run.py native --work-dir /path/to/test-output/Native
python3 tests/service_record/run.py ui --work-dir /path/to/test-output/UIKit \
  --derived-data /path/to/build-output/ServiceRecord --device EXISTING_SIMULATOR_UDID
```

Native source syntax checks cover iOS compilation; sanitized host store/model
tests exercise persistence and presentation contracts independently of the game.

These checks do not establish a working OpenCE337 game build, real multiplayer
event delivery, physical controller/modal focus, audio/rendering, long-history
performance, or iCloud delivery. The opt-in guest and library must be rebuilt as a
pair and tested on the intended device/platform before enabling this in a release.
