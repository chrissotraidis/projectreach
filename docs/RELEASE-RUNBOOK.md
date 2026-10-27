# Preparing the next HaloPad update

The aim is to have a reviewed candidate and a clear list of remaining checks ready
before release day. A new OpenCE build is not by itself a reason to release HaloPad.
The public product remains a source and PadMint recipe release.

## What triggers work

| Change | Action |
| --- | --- |
| Same OpenCE commit | Skip the automatic candidate. |
| New commit, same network version | Batch into a weekly maintenance review; skip if nothing warrants a release. |
| New network version | Prepare a private candidate promptly. Review adaptations and validate before releasing. |
| Important fix with the same network version | Manually run **HaloPad release build**, choosing `engine=upstream`. |
| HaloPad source changes | Validate the engine pinned in `config/xbox-release.json`. |

Weekly review is a maintenance policy, not another scheduled build or announcement.
If OpenCE changes the protocol daily, keeping up with newer servers can still
require daily app updates. Existing campaign play does not expire. Advertising a
new network number cannot upgrade the engine.

## Candidate preparation

The hourly GitHub check and `opence-release` repository dispatch use
`HALOPAD_CANDIDATES_ENABLED=true` as their opt-in. They compare the network versions
of the exact bundled and latest upstream commits, then allocate a Mac runner only
when a new protocol needs a candidate. The policy's historical rows are not used
as a release trigger.

Activation is a repository setting: set `HALOPAD_CANDIDATES_ENABLED` to `true`
after this workflow is on `main`; delete it or set it to `false` to pause private
scheduled/dispatch builds. This does not enable public delivery. Existing
`HALOPAD_IPA_PUBLISH_ENABLED` and TestFlight settings stay separate. Checks are
scheduled at minute 17 each hour; [GitHub scheduling and runner queues](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
can add delay, so this is not an instant-update guarantee.

The selector records its reason and exact engine in `selection.json` and the
Actions summary. It reuses an intact retained candidate and suppresses repeat
builds of the same failed source/engine combination. A source or engine change
permits another attempt. Manual `engine=upstream` remains the explicit retry and
same-protocol maintenance route. Failed lookups and malformed version headers
stop selection; they do not silently substitute an engine.

Successful main-branch builds retain audited Mac/iOS packages in an unpublished
draft for repository writers. These are engineering candidates, not accepted
player releases. Automatic IPA delivery has a separate opt-in; public IPA and
TestFlight delivery are not prerequisites for private candidate preparation.

To inspect a candidate without rebuilding it:

```sh
python3 scripts/xbox/draft_release.py \
  --download halopad-candidate-VERSION-BUILD \
  --out generated/retrieved-candidate-VERSION-BUILD
```

Use a fresh output directory. Retrieval verifies the archive and preserves its
acceptance state. The candidate's source commit, engine revision, app version and
build number must remain attached to every test result. A package built before a
source or version change cannot stand in for the final release package.

## Check and stage a source release

After choosing the next version and updating the recipe/workflow fields, run:

```sh
# Example next version; this does not edit or bump any version for you.
RELEASE_VERSION=0.3.14
/usr/bin/python3 scripts/xbox/prepare_release.py --version "$RELEASE_VERSION"
```

This read-only check works on a development tree. It checks the two recipe
commands, active workflow versions/cache key/staging tag, the player workflow's
actual build arguments, the engine-record format and the recipe's source-only
publication setting. It runs before the hosted candidate selector too. A mismatch
stops before allocating a Mac build. It does not review engine adaptations or run
any acceptance tests.

After committing the final source and completing the pre-publication checks:

```sh
RELEASE_COMMIT=$(git rev-parse HEAD)
/usr/bin/python3 scripts/xbox/prepare_release.py \
  --version "$RELEASE_VERSION" --source "$RELEASE_COMMIT" \
  --out "generated/release-$RELEASE_VERSION-prep"
```

Staging requires a clean checkout, compares the release inputs with the commit,
and refuses to overwrite an existing output directory. The fresh ignored output
contains `public-assets/HaloPad-vVERSION-padmint.json` and `public-assets/SHA256SUMS`.
Only those two files are intended as public release assets. A separate
`preparation.json` records their hashes, source identity and pre/post-check command
arguments. Its acceptance fields remain `not_checked`: staging is not a release
approval, and the command does not publish, tag, install or bump versions.

## Release work that remains

1. Review upstream changes against the actual shipped engine, particularly host
   imports, renderer/shaders, network messages and guest adaptations. Fix and test
   any adaptation failures. An automatic build cannot do this review for us.
2. Set the intended app version and exact engine pin. Check recipe and workflow
   versions together using the preparation helper below. Commit the final source.
3. Run the required clean PadMint checks for **both iOS and macOS**, using current
   PadMint `main`, Apple's Python 3.9 and an empty PadMint folder. Before tagging,
   pass the clean final game checkout. Keep its commit, PadMint commit, logs,
   packages and build records. A cached candidate build does not replace this.
4. Audit the final packages and test the relevant physical-device paths. Back up
   and read back player data before an in-place update. Cover graphics modes,
   campaign load, matching Mac/iPad multiplayer, fresh map/resource transfer,
   cached rejoin and public-server access as relevant. Record anything untested;
   a successful build does not resolve a reporter-only crash.
5. Stage the recipe and checksum from the same clean source, inspect the release
   notes, and complete the authorized source-only publication. Do not upload
   private candidate packages or the preparation receipt as release assets.
6. After publication, rerun PadMint's checks **without a checkout argument** so
   they select the public release. Verify the selected tag/commit, package
   identity and anonymous recipe/checksum downloads. Any failed player check
   blocks a release announcement.

Run these from a clean checkout of current **PadMint main**, replacing `GAME_FILE`
with the private Xbox ISO/XISO and `HALOPAD_CHECKOUT` with the clean release source:

```sh
# Before tagging. Each invocation creates its own empty PadMint folder.
scripts/player-check.sh projectreach ios "$GAME_FILE" "$HALOPAD_CHECKOUT"
scripts/player-check.sh projectreach macos "$GAME_FILE" "$HALOPAD_CHECKOUT"

# After publication. No local checkout argument.
scripts/player-check.sh projectreach ios "$GAME_FILE"
scripts/player-check.sh projectreach macos "$GAME_FILE"
```

The two platform checks can run concurrently in their separate folders if this
Mac has enough resources. Preserve results before cleaning temporary folders.
Do not switch or reset a PadMint checkout being used by another task; reuse a
suitable clean checkout or isolate it under `$CODEX_HOME/worktrees`.

## What should get faster

The 0.3.13 final pre-publication player builds took about 216–218 seconds each;
post-publication builds took about 217 seconds each. Run in pairs, those four
required checks accounted for roughly seven minutes of build time. These figures
exclude upstream adaptation, hardware testing and GitHub runner queues, and are
not a promise about future builds.

The immediate savings come from skipping irrelevant builds, retaining candidates,
avoiding unintended IPA preparation, checking version drift early and staging
release files consistently. A broader reusable package auditor and automated
evidence collection are subsequent work. Device acceptance and an unfamiliar
upstream adaptation still need investigation. Routine compatibility releases can
use short notes; Discord announcements and new artwork can be batched separately.
