# HaloPad updates without daily maintainer work

## Current decision, 2026-10-08

Chris removed the local Codex maintenance schedule. Do not recreate it or capture
his keyboard/mouse. Work through commands and APIs without disrupting his computer.
The verification passes recorded here did not change the installed iPad app.
The current goal is a product/release mechanism, not an agent repeatedly rebuilding
on Chris's computer. The notes below this section retain earlier research evidence.

There are two separate problems:

1. **An old HaloPad recipe changes underneath new players.** Fixed now in source:
   normal PadMint builds read `config/xbox-release.json`, not OpenCE's latest API.
   This development branch records build 150. `--xbox-latest` is an explicit
   experiment, and immutable candidate records remain supported. A broken/missing
   record is an error, never permission to substitute a moving release.
2. **Installed players need new code when multiplayer changes.** Pinning does not
   solve this. Deliver whole app updates from a hosted build pipeline. Daily
   upstream commits must not require Chris to edit a pin, compile on his Mac, or
   have every player run PadMint. Offline play and compatible peers continue;
   exact latest-upstream cross-play requires the matching implementation.

The native engine is compiled into HaloPad. Downloading a compatibility number
cannot implement new packet handling. Ordinary iOS code-signing constraints also
prevent treating a replacement native engine as an unsigned data download. A web
runtime or interpreter is a different port with unproven performance and storage;
that migration is not the smallest solution to this release problem.

### Delivery choice

Evaluate **TestFlight as the preferred iPad beta delivery route**: Chris's paid
membership signs the distributed app, and testers can enable automatic app updates.
This avoids making each tester provision the memory entitlements. It still requires
actual distribution-profile validation and Apple's external-beta review; neither is
established. Apple documents review of the first build of a version; subsequent
builds may not need a full review. Routine engine updates can therefore increment
the app build number without unnecessarily changing the marketing version. This
is not a promise of immediate processing or review exemption. TestFlight supports up to 10,000 external testers and each build expires
after 90 days, so it is not a permanent unsupported release channel. App Store
acceptance would be a separate long-term decision. Apple approval must not be assumed.

Keep a **versioned IPA plus AltStore source** as the fallback. This is a working
format, but HaloPad's actual consumer signing/upgrade remains blocked by Apple's
pending agreement and must be tested. AltStore certificate refresh is not automatic
app upgrading. Free-account/lower-memory compatibility is still unproven.

Sources: [Apple TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/),
[TestFlight automatic updates](https://testflight.apple.com/),
[TestFlight review](https://developer.apple.com/help/glossary/testflight-app-review/),
[iOS runtime protections](https://support.apple.com/guide/security/sec15bfe098e/web).

### Implemented background-only work

- Normal builds use one fixed engine record; upstream experiments are explicit.
- New self-contained upstream GL helpers are reused through generated guest-pointer
  bridges. Existing HaloPad overrides remain; unsupported signatures, state and
  dependencies fail early. This avoids copying each portable helper added upstream.
- The picker checks HaloPad's own release metadata. Source-only releases, failed
  requests, older/equal versions, missing platform assets, malformed metadata and
  unsupported OS versions produce no update prompt. Raw OpenCE bumps produce none.
- `scripts/xbox/update_source.py` re-audits both delivered packages, verifies their
  hashes and the IPA's actual memory entitlements, then stages the exact packages,
  `altstore.json`, `halopad-update.json`, icon and checksums. It does not upload,
  publish, overwrite previous staging or invent acceptance results.
- `.github/workflows/halopad-build.yml` builds on a GitHub-hosted Apple-silicon Mac
  when source changes or the workflow is manually dispatched. Manual dispatch can
  choose the fixed release or an upstream candidate. An authenticated
  `repository_dispatch: opence-release` entry point also selects upstream, but no
  sender is configured and it only becomes usable on the default branch. A
  six-hour GitHub release check is prepared behind `HALOPAD_PREVIEW_ENABLED=true`;
  that opt-in is not enabled. It resolves once before allocating a Mac runner and
  skips an exact engine/product-source pair already retained. Staged asset URLs include the unique app build.
  It needs no private
  disc, player data or signing secret. On the default branch, successful builds
  retain the exact audited packages in an unpublished draft for repository writers.
  Branch verification uploads reports only. Public binary promotion remains off.
  This is normal CI, not a restored Codex schedule.

### Retain the built package instead of rebuilding for delivery

`scripts/xbox/draft_release.py` provides the private handoff from build to signing.
It audits the candidate again, requires its exact source checkout, and stores a
deterministic archive containing only the two packages and their candidate record.
It verifies the uploaded bytes by downloading them. Repeated uploads of identical
content are safe; different existing content or a published release stops the
command without overwriting anything. The command has no publish operation.

```sh
python3 scripts/xbox/draft_release.py \
  --candidate generated/xbox-candidates/latest-built.json \
  --out generated/private-handoff

python3 scripts/xbox/draft_release.py \
  --download halopad-candidate-0.3.8-BUILD_NUMBER \
  --out generated/retrieved-candidate
```

The downloaded `result.json` is accepted by `export_archive.py`; retrieval restores
local paths, audits both actual packages and preserves every acceptance flag.
Use a fresh output directory each time. No disc, save, provisioning profile or
signing key is included. These are unpublished drafts, not player update sources.
GitHub [documents draft visibility](https://docs.github.com/en/rest/releases/releases)
as limited to users with push access. A live inert-file probe also verified
authenticated byte retrieval and anonymous 404 responses for the draft, asset API
and download URL, then removed the probe. The current workflow limits retention
to the default branch because GitHub's built-in token cannot create a release
targeting a branch's unmerged workflow changes.

Real verification: **build 17/OpenCE 154**, following **279 Xbox and 23 builder
tests**, was retained as `halopad-candidate-0.3.8-17`, downloaded to a fresh
directory, re-audited and prepared as a development-signed xcarchive. Both original
package hashes and all acceptance flags were preserved. A repeated upload returned
the same draft ID and identical archive checksum. Anonymous requests to the actual
candidate's draft, asset API and download URL all returned 404. No public release
or signing secret was uploaded. This change is still on PR #20; default-branch
automation awaits integration. Hosted run 37739072112 passed; final selection/
receipt changes are undergoing their next verification pass.

The handoff now also uploads a small `handoff.json` receipt after verifying the
candidate archive. `check_update.py` compares the selected engine, product-source
fingerprint, app version and GitHub's archive digest against that receipt. A match
skips the Mac build. A changed engine/source/version builds a new candidate; a
partial, malformed or mismatched handoff cannot suppress it. API access failure
stops the check instead of starting repeated builds. Already promoted matching
packages also count as completed work. Scheduled checks remain disabled until
delivery is accepted and the one-time repository variable is enabled. This is a
small hosted CI check, not the deleted Codex agent maintenance loop.

Build **18/OpenCE 154** passed **284 Xbox and 23 builder tests**, both archive
audits and a real receipt-backed retention/retrieval. Against the live GitHub
receipt, the exact engine/source/version skipped; a changed engine or app version
required a build. The real upstream CLI check resolved build 154 and returned
`build: false`. The opt-in repository variable was verified absent. Final hosted
verification is run 37740472342; its selection job already passed.

### Evidence from this implementation

Local candidate 0.3.8/build 13 packages OpenCE 150/network 24 on Mac and iOS.
263 Xbox tests and 23 builder tests passed. Both delivered archives passed strict
signature, identity, guest digest and data-content checks, and exact-archive feed
staging passed. No device was controlled, installed or launched. The first hosted
runs caught missing SDL3 test headers and a runner defaulting to Xcode 16.4 while
the picker uses an iOS 26 API. SDL3 and Xcode 26.3 are now explicit; [clean hosted run 37718404061](https://github.com/chrissotraidis/projectreach/actions/runs/37718404061)
passed. It built and audited Mac and iOS 0.3.8/build 1003, passed all 286 tests,
and staged the exact-archive update metadata. Its product-source tree hash matches
local build 13 and the implementation at commit 398b884. The report and staged metadata agree on
both archive hashes, sizes, minimum OS and network 24. Only reports were retained;
no binary was published. These results do not establish consumer delivery.

The subsequent [hosted run 37732244804](https://github.com/chrissotraidis/projectreach/actions/runs/37732244804)
passed all 290 tests and both build-1005 package audits, including the iOS platform
metadata fix and exporter tests. Its product-source fingerprint matches commit
cbe7135; the report and staged update metadata agree.
The saved-account distribution export remains a separate local verification.

A real upstream-mode [run 37733000100](https://github.com/chrissotraidis/projectreach/actions/runs/37733000100)
then exposed a new OpenCE 154 import, `host_gl_read_buffer`, missing from HaloPad's
manually maintained host helpers. `gen-host-gl-helpers.py` now extracts only missing
self-contained upstream helper bodies and generates their guest-pointer ABI bridges
and GL procedure resolution. It preserves existing overrides and rejects unsupported
signatures, stateful helpers and undeclared dependencies. It does not claim arbitrary
future host changes can be accepted automatically.

Local **0.3.8/build 16**, OpenCE **154** (`544ee497b6c1da195fa4dd9363851074edc63cbb`),
network **24**, passed **271 Xbox and 23 builder tests** and both platform archive
audits. Tests compile and execute the new wrapper for copied bytes, pointer conversion,
mapping failure and buffer cleanup. Its recorded product-source fingerprint matches
the implementation committed as `6ebedbd`; it was built just before that commit.
The fixed recipe stays at 150. Hosted [fixed-release verification](https://github.com/chrissotraidis/projectreach/actions/runs/37735761338)
and [upstream verification](https://github.com/chrissotraidis/projectreach/actions/runs/37735860129)
both passed: build 1007/OpenCE 150 and build 1008/OpenCE 154 each passed all 294
tests, both archive audits and update metadata staging. Their independently
downloaded reports match the current product-source fingerprint and staged archive
hashes, sizes, minimum OS and network 24. Exact-archive update metadata staging and development-signed
xcarchive preparation also passed for build 16, preserving the original IPA.
This does not establish distribution signing. No new candidate has been installed
or gameplay-tested.

### Existing Apple account path and the current delivery gate

The initial conclusion that absent distribution certificates/upload keys prevented
any further signing work was too broad. Xcode already has Chris's developer
account configured. Its `-exportArchive -allowProvisioningUpdates` path can create
profiles and managed signing certificates using that saved account. A real local
export authenticated far enough to reach Apple's membership checks without any
keyboard, mouse or device interaction.

The first attempt also exposed missing `DTPlatformName` in HaloPad's hand-built
Info.plist: Xcode attempted a Mac installer path for the iOS app. Adding the
correct iPhoneOS platform metadata removed that error. The production packager
now emits the correct platform for device, simulator and Mac bundles.

The repeatable command is `scripts/xbox/export_archive.py`. It checks the exact
candidate's identity, hash and signature, validates an existing development
profile, signs a private copy, writes an xcarchive and asks Xcode for a **local**
App Store Connect export. It never uploads or submits a build and leaves the
original IPA and device data unchanged. Use a fresh ignored output directory:

```sh
python3 scripts/xbox/export_archive.py \
  --candidate generated/xbox-candidates/latest-built.json \
  --out generated/distribution-export-attempt \
  --profile /path/to/HaloPad-development.mobileprovision \
  --identity 'Apple Development: YOUR NAME (TEAM)' --export
```

On 2026-10-08 the corrected live export returned `PLA Update available`: Apple
requires the account holder to accept its updated Program License Agreement.
The missing App Store profile was reported alongside that membership denial;
do not treat it as proof that Xcode cannot create the profile after acceptance.
No agreement was accepted by the agent. Chris has been asked to confirm it.

The production exporter was exercised against newly built 0.3.8/build 14 after
267 Xbox and 23 builder tests passed and both platform archives passed their
checks. It prepared a certificate-signed iOS archive, preserved the source IPA's
hash, and reached the same live Apple agreement denial. The minimal metadata fix
removed the Mac-installer error. Export success and external delivery remain
unproven; this result is a validated route to retry after account acceptance.

After acceptance, rerun the same exporter, validate the distribution profile's
actual memory entitlements and Apple's acceptance of the archive, and establish
external TestFlight delivery. The hosted publisher still needs unattended upload
authentication configured; saved local Xcode login is not a credential on a GitHub
runner. Prove the first consumer upgrade before enabling automatic promotion.

### Complete the product loop in this order

1. Prove the hosted clean build and feed staging. Keep the prior downloadable app
   untouched on any failure. Build identifiers for hosted releases start at 1001;
   use that single workflow's counter once public distribution starts.
2. After Apple's updated agreement is accepted, prove distribution signing and
   one real in-place upgrade without capturing Chris's keyboard, with independent
   data readback and campaign/save/resume. TestFlight approval, actual entitlement
   support and installation identity must be measured, not inferred from a local
   development install. Finish exact-artifact notices/distribution review.
3. Once the first delivery route works, enable the prepared **hosted preview release
   check** through its repository variable, or connect upstream release events.
   Resolve once, skip unchanged input, build/test, then distribute complete
   accepted packages and update the feed last. This requires no daily source-pin
   changes. The prepared check is not yet enabled; public distribution is not wired.
4. Keep the normal release channel deliberate and reproducible. Preview can follow
   upstream for players who prioritize public-lobby compatibility. Promote stable
   releases for meaningful fixes, rather than for every upstream commit. Develop a
   private-data automated gameplay regression before unattended binary promotion;
   public build checks alone cannot substitute for that acceptance.
5. Reduce exceptional repair work by upstreaming the narrow Apple host hooks and
   correctness fixes. Do not weaken protocol checks or promise that automation can
   repair arbitrary future upstream changes without engineering work.

**Completion boundary:** fixed source selection, hosted compilation and metadata
are necessary, but the daily-maintenance problem is not fully closed until a
changed upstream engine reaches an already-installed iPad through the chosen
consumer route without Chris rebuilding or editing code. The current goal must
not be marked complete merely because CI passes.

**Remaining work:** verify the private-handoff changes in hosted CI, complete
distribution export after Apple's agreement condition changes, then validate the
distribution entitlements and consumer delivery. A fresh export attempt against
build 16 still returned the agreement denial. The downloaded build-17 archive is
prepared for signing. Device acceptance is still unproven; use commands/APIs where
possible and preserve player data instead of assuming keyboard control is needed.
Verify the gated upstream check and establish unattended upload authentication;
private package retention does not establish automatic player delivery. Keep
working through those implementation gaps without restarting upstream builds
merely because another release appears or recreating the deleted Codex schedule.

## Earlier research and implementation snapshots

## Decision

Second-pass decision: keep the current native engine and edition picker, and
make whole-app updates the primary path. Build the Xbox-only IPA centrally and
deliver it through an existing iOS signing/installation client, subject to proving
that ordinary players can actually sign and run it. Do not build a compatibility
service as part of the first release. Reconsider one only after measuring a real
problem that whole-app updates fail to solve.

The current private build-3 IPA is 19,853,117 bytes, about 20 MB. The large disc/maps stay
in the player's data container. Replacing this app is a much smaller engineering
commitment than maintaining protocol translations, compatibility approvals and a
signed policy service. A compatibility table cannot add engine fixes or new
message handlers; an IPA can. Preserving the app identity/container avoids another
disc import, although engine-specific checkpoint compatibility still needs testing.

New OpenCE builds do not make an installed HaloPad expire. Offline campaign and
compatible peers remain available. The current pressure comes from strict
multiplayer version checks, fragile source adaptations, and making each player
build the replacement engine. Signing expiration is a separate iOS constraint.

The target experience is: set up installation once, import the owned disc once,
play, and accept app updates on the iPad. A build machine handles compilation.
Keep an installed build playable when an update fails. Do not promise silent
executable replacement inside HaloPad or permanent compatibility with unknown
future protocols. Zero routine maintainer work is the target; zero maintenance
despite arbitrary upstream/platform changes is not a credible guarantee.

The durable way to reduce code maintenance is to make the Apple platform boundary
boring: a small set of supported host hooks and automated Apple build checks,
ideally accepted upstream. A downstream updater cannot repair source/API changes.
Propose those hooks/checks without requiring adoption of our picker or PadMint,
and do not make an upstream merge a prerequisite for the first usable download.

## What the other projects actually do

Inspected ChupathingyCE at
[`61eb5615`](https://github.com/ChupathingyCE/chupathingyce/tree/61eb5615d5703df7a971be7f75c3d1434d716b7e).

- Its [platform list](https://github.com/ChupathingyCE/chupathingyce/blob/61eb5615d5703df7a971be7f75c3d1434d716b7e/README.md)
  offers Windows, Mac, Linux and Android, not an iOS IPA. Mac self-updating is
  explicitly not implemented. It nevertheless has the right first-run model:
  download the app and import a disc.
- Its [network constants](https://github.com/ChupathingyCE/chupathingyce/blob/61eb5615d5703df7a971be7f75c3d1434d716b7e/port/linux/include/halo_port_limits.h)
  announce network 20 and accept hosts from 11 through 20. This is broader than
  upstream's exact-version rule. It does not establish HaloPad compatibility or
  support for current OpenCE network 21.
- Its [Delta implementation](https://github.com/ChupathingyCE/chupathingyce/blob/61eb5615d5703df7a971be7f75c3d1434d716b7e/port/linux/src/delta.c)
  loads a signed compatibility table, keyed by an engine wire ID, with cached
  offline defaults. This is a concrete example of updating compatibility as data.
- The [Delta design](https://github.com/ChupathingyCE/chupathingyce/blob/61eb5615d5703df7a971be7f75c3d1434d716b7e/docs/delta.md)
  also says the cross-play test is not built and CI publishing after cross-play
  is next. Some status text is inconsistent about keys being ready. Its separate
  command repository returned 404 to this account, so the claimed watch/release
  automation was not independently inspected. Treat these as design/source
  evidence, not proof of an end-to-end production service.

OpenCE's [network-21 change](https://github.com/OpenCommunityEdition/OpenCE/commit/07302a866f8b36c162203fe58dcf632d4708d65c)
documents reliable killing blows, repeated resting-object messages and changed
co-op BSP behavior. The number-raising commit alone does not contain all those
changes: review the complete interval from the accepted engine. Identical packet
sizes or an apparently additive enum are insufficient proof of safe cross-play.

The native Apple work in [OpenCE PR 64](https://github.com/OpenCommunityEdition/OpenCE/pull/64)
is open and unmerged. The API says `draft: false`, although its description still
starts with "Draft"; its described rebase is network 11. It is useful upstream
integration work, not a currently verified route to network 21.

The [browser port](https://github.com/fqlx/halo-ce-universal/blob/fqlx/browser-webgl-stream-batching/port/web/README.md)
supports a home-screen web app and downloaded WebAssembly. Its own documentation
leaves physical-iPhone acceptance open. Its [native invitation route](https://github.com/fqlx/halo-ce-universal/blob/fqlx/browser-webgl-stream-batching/BROWSER_NATIVE_INVITES.md)
requires a relay, describes testing against network 4/build 33, and leaves the
public relay unset. Moving HaloPad there would introduce a renderer/runtime,
storage and networking migration. Keep it as a fallback experiment only if the
native distribution route proves unusable; do not start a rewrite now.

## Work in order

The immediate critical path is consumer installation, one reliable multiplayer
build, then the smallest automated whole-IPA pipeline. The adaptation cleanup
below supports that path. Cross-version compatibility is explicitly deferred.

### 1. Remove demonstrated build fragility

The recent 144 build failure came from optional anisotropic filtering, not a
network change. The replacement patch originally selected the new sampler layout
using one complete source-file hash. Another edit anywhere in that file would
select the old patch again.

Implemented locally: latest-mode builds recognize the required cache field
meanings, ordering and unique insertion sites while retaining the exact source
hash and recipe identity. Missing/ambiguous/changed layouts stop the build.
Historical recipes and the accepted 144 output must remain byte-identical.
This is a bounded reduction in maintenance, not a general C compatibility parser.

Next, reduce source edits by purpose:

| Adaptation | Proposed treatment |
| --- | --- |
| Optional render scale and anisotropy | Separate from correctness fixes; prefer an upstream setting/hook. A quality option should not be able to break the entire shipping build. Do not silently remove a selected option. |
| Water framebuffer restoration and presentation ordering | Prepare small upstream fixes with focused repros; delete local patches only after equivalent upstream behavior is verified. |
| Counted visibility and border sampling | Keep until an ANGLE-compatible path reproduces the same rendering. These are correctness work, not cosmetic extras. |
| Profile input context | Retain the existing scalar, versioned host callback; propose the minimal platform hook upstream. |
| Direct camera | Prefer a platform capability rather than editing an Android-only guard. |

Do not switch the whole engine to another fork just to borrow its updater. That
would add its game changes and integration obligations to ours. Proposed upstream
contributions are preparation work; none has been posted by this investigation.

### 2. Prove an ordinary on-device upgrade

Use SideStore/AltStore's existing source format and signing machinery. Do not
build an Apple-account client into PadMint. [SideStore documents](https://docs.sidestore.io/docs/faq)
on-device signing, periodic certificate refresh and an explicit Update button.
[AltStore documents](https://faq.altstore.io/developers/updating-apps) versioned
source entries and update notifications. Certificate refresh is not the same as
installing a new HaloPad version; background upgrade behavior is not promised.

First experiment: install two private Xbox-only packages with the same engine
and different app build numbers through the selected consumer signing route.
Verify the actual increased-memory/virtual-address entitlements, cold launch,
picker, import, campaign save/resume, and in-place upgrade with independently
verified data backups. Repeat with a genuinely newer engine only after that
passes. The maintainer development-profile test is not a substitute for this.

Pass: update offered on iPad, installation succeeds without a local game build,
maps/profiles survive, and saved gameplay resumes. Fail: determine whether the
account/device entitlement is unsupported before building a release service. Keep
the current Mac-assisted signing route as the honest fallback. Never uninstall
the existing app to test an upgrade.

The second pass found a prerequisite for this experiment:
[Apple's capability matrix](https://developer.apple.com/help/account/reference/supported-capabilities-ios)
marks Extended Virtual Addressing for paid Developer Program and Enterprise
memberships, but not the free Apple Developer column. The rendered HTML's check
icons were inspected because plain-text extraction drops those marks. HaloPad's
packager, signer and profile validation currently require that entitlement.
AltStore's support for Increased Memory Limit does not establish support for this
different capability or for free-account HaloPad installation.

The bounded experiment identified an avoidable constraint: the old allocator
reserved **8 GiB of virtual address space** to keep an aligned 4 GiB region.
On the physical M2 iPad, that allocation failed without either extra memory
entitlement. A direct aligned 4 GiB `vm_map` reservation succeeded. The production
allocator now uses that smaller reservation and retains the translator's address
contract. This concerns virtual address space, not 8 GiB of physical RAM.

Two fresh diagnostic launches exercised the production allocator and verified
read/write access. A separate full HaloPad test app, signed without Extended
Virtual Addressing or Increased Memory Limit, then opened the picker and rendered
OpenCE 144's main menu. A native allocator test also covers mapping, unmapping,
zero-filled allocation, pointer round-trips and high guest addresses.

This is one M2 iPad on iPadOS 27.0.1, still signed with a paid development identity.
The no-extra-entitlement build subsequently failed during the opening Normal
campaign cinematic: GL out-of-memory errors preceded SIGABRT from an allocation
failure on an ANGLE shader-link worker. It was not a jetsam report. This does not
isolate physical-memory pressure from virtual-address exhaustion. Menu startup
alone therefore cannot justify removing the shipping entitlement requirements.

A second private variant (0.3.8/build 5) requests Increased Memory Limit only. It
was installed over the main app after two independent full data reads matched;
119 save/profile/preference files matched again before launch, excluding changed
OS-managed SplashBoard snapshots. Its opening cinematics ran farther, with no GL
errors in the captured segment. Another task used the shared iPad before gameplay
acceptance finished; no new HaloPad crash report was found. Treat this as an
interrupted test, not a campaign pass or a demonstrated second crash. A signed
build-6 variant with both entitlements is prepared but not installed.

Free-account provisioning, sustained campaign/save/resume, lower-memory devices
and consumer upgrades remain unproven. Shipping packaging/signing/profile
requirements are unchanged. Apple refused new profile creation pending the
account holder's Program License Agreement; an existing paid development profile
allowed the private variants. Finish the controlled gameplay comparison and actual
consumer signing route before relaxing requirements.

### 3. Build the smallest whole-app release pipeline

**Implemented 2026-10-08:** `scripts/xbox/candidate.py` now performs one complete
private candidate cycle. Run the same command again to pick up the newest release
or skip unchanged successful/failed work:

```sh
python3 scripts/xbox/candidate.py --app-version 0.3.8 --first-build 9
```

`--first-build` seeds a persistent counter in `generated/xbox-candidates/`; retain
that directory and the initial argument on this worker. A fresh worker/output
folder must start above every previously distributed build number. Do not use
multiple independent counters for one distributed app. The script stops at 9999
instead of reusing a number. `--record FILE` replays an exact record; use
`--retry-failed` deliberately after investigating an unchanged failed/interrupted
attempt. A new upstream revision or build-relevant source/toolchain change gets a
new attempt automatically. Documentation-only commits do not rebuild the engine.

Each cycle resolves once, runs Xbox and builder tests, sequentially builds Mac and
iOS packages, then inspects the actual archives: app version/build/platform,
engine commit/release/protocol, guest digest, nonempty broker configuration,
Xbox-only data inventory and strict code signature. It rejects embedded profiles,
unsafe paths and unexpected data. These are engineering checks, not a complete
publication/provenance audit. Private artifacts remain under ignored `generated/`.

Successful metadata is atomically written to `latest-built.json` only after both
packages pass. Failure leaves that pointer and previous packages intact. Retrying
allocates a new build number/directory. Candidate and manual builder/prepare/platform entry points now share an inherited
lock over the engine cache. A competing build stops before changing it; nested
build stages retain the same lock. Tests time out after ten minutes and builds
after four hours. The local Codex heartbeat was briefly created and then removed by Chris.
Do not recreate it; the current decision above supersedes that approach.

Validation: 257 Xbox tests and 21 builder tests passed under the candidate lock.
Four lock tests exercise real nested/competing processes, stale inherited state
and child failure. During a real OpenCE 150 build, both another candidate runner
and the direct device builder were refused, with the counter and previous
candidate pointer unchanged. The temporary private LAN feed server was stopped
after the account-blocked AltStore test; its files remain available locally.

The real first attempt stopped on macOS AppleDouble metadata files. Mac packaging
now omits resource forks/extended attributes, and archive verification succeeded
on the extracted package. The second attempt produced private **0.3.8/build 10**,
OpenCE **148/network 23**, for both platforms. The IPA is **21,899,393 bytes**.
253 Xbox tests (including ten candidate-loop tests) and 21 builder tests passed.
Real unchanged-success and unchanged-failure reruns skipped work. CLI concurrency
and invalid-record checks preserved the counter and candidate pointer. The new Mac
app reached the Halo menu in an isolated test container; a captured 30-second
render interval had zero GL errors. This is not campaign or multiplayer acceptance.

`latest-built.json` explicitly records gameplay, consumer-upgrade and publication
acceptance as false. It is **not** an AltStore source or a player-facing feed.
Do not expose it as one. The next step remains a proven AltStore in-place upgrade,
then promotion of the exact accepted package.

On 2026-10-08, AltStore 2.3 on the physical M2 iPad accepted a private LAN source
and displayed the 21.9 MB 0.3.8/build-10 test app and permissions. Its signed-in
account is Developer, also confirmed by Chris. Installation reached Apple but
failed with `Apple.APIError 403: Unable to process request - PLA Update available`.
Chris must accept the updated Apple Developer Program License Agreement before
new consumer signing can proceed. The source was not publicly hosted and no
AltStore installation or upgrade is claimed.

The existing valid paid development profile did allow an in-place main-app
upgrade from build 5 to build 10 with both shipping memory entitlements. Two
independent pre-install reads matched 608 files / 9,962,453,249 bytes. A complete
post-install read found no changed retained files and only four replaced
OS-managed SplashBoard snapshots. The themed picker showed existing maps ready;
Play Xbox started the engine and menu rendering. Campaign, save/resume and a
matching Mac-iPad session remain unverified.

Chris subsequently prohibited keyboard/mouse/device control until he explicitly
resumes it. The deleted schedule must not be restored. Continue background
code/package work only; do not resume device interaction merely because it is
connected. Evidence is in `generated/device-update-20261008/`.
Private evidence: `generated/update-loop-20261008/` and
`generated/xbox-candidates/runs/10-build-148/`.


Use one promoted HaloPad release record for the IPA, app update notice and PadMint
recipe. The normal path should describe the same accepted engine everywhere.
Offer raw upstream latest only as an explicit experimental choice. This policy is
proposed, not yet applied: today's builder still resolves OpenCE latest by default,
so new users can encounter an upstream failure before HaloPad has tested it.

Two release foundations are implemented and exercised by real private IPA builds:

1. `--xbox-release-record FILE` rebuilds the full commit in a saved
   `xbox-release.json`, without resolving a moving tag. Invalid records stop before
   build work. The record is an identity, not gameplay acceptance, and cannot
   redirect the configured upstream repository.
2. `--app-version` and `--app-build` reach the packaged plist. Private version
   `0.3.8`, builds `2` and `3`, contain OpenCE 144/network 21. The pipeline still
   needs to allocate increasing build numbers and derive feed entries from the
   actual artifact. Defaults remain `0.3`/`1` for existing development commands.

Example for a previously saved candidate record (private build only):

```sh
/bin/bash scripts/builder/build.sh --xbox-only \
  --xbox-release-record /absolute/path/to/xbox-release.json \
  --app-version 0.3.8 --app-build 3 \
  --out generated/recorded-candidate \
  --ipa generated/HaloPad-candidate.ipa
```

The normal builder still selects upstream latest. Once the downloadable route is
proven, add the promoted HaloPad record/feed and make it the normal selection.
HaloPad's current notice also checks OpenCE latest and points back to a Mac build;
then change it to the promoted app update. Do not present an unbuilt upstream
commit as an available HaloPad app update. No feed or scheduled workflow exists yet. The native picker now suppresses notices for same-protocol upstream builds and unknown protocol metadata; known mismatches remain visible with explicit PadMint rebuild wording.

Build and test exact revisions, then publish the IPA and update the installer
feed last. Retain the prior downloadable artifact and player backups; downgrading
an engine is not automatically safe for newer saves. Supersede queued work with
the newest candidate rather than requiring a person to process every upstream
commit. Keep the last accepted app available while a candidate fails.

Run adaptation/host and package checks on every candidate. First prove an actual
same-version multiplayer match, then automate a useful gameplay regression with
owned inputs on a private runner. Qualify the consumer install/upgrade route
separately. Initial candidates need acceptance; once these checks are trustworthy,
routine green candidates can publish automatically and notify only for actionable
failures. Do not add permanent per-release manual pin edits or universal human
checklists and call that automation. No scheduler is enabled by this plan.

The first public artifact still needs complete dependency notices and the existing
compiled-engine distribution review. Keep source/PadMint delivery independent.
PadMint remains useful for optional personal Custom Edition combined builds and
building from source; it should not be the everyday Xbox update mechanism.

### 4. Deferred experiment: compatibility independent of the engine

Only start this if measured update/signing friction remains a material problem
after whole-IPA updates work. Reusing an established, tested upstream compatibility
contract is preferable to operating another HaloPad-specific protocol service.

Start with one frozen native engine and one newer OpenCE host. First establish
same-version multiplayer on HaloPad; it is not yet accepted. Then run a private
mixed-version experiment. Do not widen public join checks on the basis of source
inspection alone.

Exercise both host/client directions, LAN and internet discovery, lobby settings,
join-in-progress, movement, damage/death, scoring, respawn, disconnect/rejoin and
match completion. Check password-protected listings separately. Co-op needs its
own acceptance, including loading zones and recovery; versus success must not
authorize co-op. Retain actual engine hashes and logs with every result.

If the engine needs new behavior to pass, ship an IPA. If the unchanged engine
passes, prototype a minimal compatibility policy containing the exact engine/wire
identity, explicit tested peer versions, host/client role, transport and game mode.
Avoid assuming every integer between two tested versions works. Advertised
versions, server-browser filtering, join checks and discovery/listing formats must
agree; changing one comparison or only the picker's warning cannot establish it.

The policy is signed data with bounded parsing, cached offline defaults and a
monotonic revision. Apply it between sessions. Permit a newer policy to revoke a
bad compatibility entry; always keep the built-in same-version behavior available.
Do not remotely patch packets, download native code, overwrite saves, or let an
unknown policy/schema prevent offline play. Do not share ChupathingyCE's wire ID
or automatically trust its approvals: its engine differs from ours.

Pass: the same installed HaloPad executable joins the newly approved peer after
only a policy refresh. Fail: preserve the strict existing rule and use IPA updates.
This experiment determines whether the extra policy mechanism earns its complexity.

## Current evidence and next gate

Latest private candidate: **0.3.8/build 10**, OpenCE **148/network 23**,
commit `ff47e47ad6f54bc533cee2a0fe57232c8f63d614`. Both platform archives audited;
Mac picker/menu smoke passed. iPad still runs the earlier build described below.
IPA SHA-256: `4de7f741e73ecdabcef4dc871f084714a477fe8ed82c7ec4ea6cc016e055939a`.
The candidate loop is working; consumer delivery and automatic publishing are not.

OpenCE published build 145/network 22 after the 144 candidate was built. The
picker correctly showed an incompatible-multiplayer update notice during design
QA. Existing 144 artifacts remain reproducible evidence, not the latest network
release. This intermediate observation is superseded by the 148 candidate above; a same-protocol real match is still required before advertising current-server compatibility.

- Main iPad installation: private 0.3.8/build 5, OpenCE 144/network 21,
  Increased Memory Limit only. In-place installation, data preservation and picker
  passed; interrupted cinematic run is not campaign/save acceptance. Engine-138
  data remains in verified local backups; no uninstall was performed.
- Separate diagnostic installation: 0.3.8/build 4, same engine, neither extra
  memory entitlement. Picker/menu passed, campaign cinematic crashed with an
  allocation failure. Its data was backed up independently.
- Mac: the exact release record builds 0.3.8/build 3; strict code signature
  verification passed. An isolated app identity imported the owned disc, created
  a profile and reached a Battle Creek/Slayer LAN lobby. Same-version two-peer
  gameplay and public Mac installation/notarization remain open. A bounded
  two-peer same-Mac discovery/join attempt did not complete a match; both isolated
  configs were restored afterward. Direct-link paste also remains unsupported by
  the host clipboard bridge and needs a deliberate user-controlled handoff.
- Private Mac build 7 adds the selected space-themed native picker. Wide/narrow
  layout and setup controls were checked; this UI has not replaced the physical
  iPad installation. Evidence: `generated/picker-design-20261007/`, `design-qa.md`.
- Private build-3 IPA: 19,853,117 bytes, strict signature verification passed;
  SHA-256 `efb2cea37e0575e43562ce3ea12faf3b5dcbf1067d917900940296f4b3d04884`.
  No maps/discs, PC product ID or provisioning profile included. Compiled engine
  distribution review and complete dependency notices remain pending; 16 notice
  files have been collected privately, not bundled into this archive.
- Validation: 242 Xbox tests passed before the final record-error diagnostic test;
  the final 10-test release suite and all 26 installer/signing/profile tests also
  passed. All 21 builder tests passed, plus real versioned builds and independent
  archive inspection. These do not substitute for the physical acceptance above.
- Next gate: exclusive iPad time for campaign/save/resume and a real Mac–iPad
  multiplayer match; consumer signing and upgrade with the actual account and
  entitlements. Only then promote a downloadable build and automate its feed.
- No compatibility override, shipping entitlement relaxation, public binary or
  automatic publishing was performed. Public HaloPad remains v0.3.7.

Local evidence is excluded from source control:
`generated/update-research-20261007/` holds adaptation tests and memory diagnostics;
`generated/ipa-update-pipeline-20261007/` holds builds and archive audits;
`generated/release-acceptance-20261007/` holds physical crash/campaign logs,
independent backups/readbacks, signature variants, Mac builds and component notices.

The scheduled command was exercised again after the shared-lock change. It
resolved OpenCE **150** (`d0b9049e2de2be55864bf77dc4f54a9b65ef9d78`) without
manual pin edits and produced **0.3.8/build 12**, network **24**, for Mac and iOS.
Both archives passed the delivered-package audit. The IPA is 21,889,496 bytes
(SHA-256 `bf27b4dddf27c1f7470ee997881423a703757702cc1d3ce3300c4fb76d250cd6`).
Build 10 remains intact. This demonstrates another complete automatic build
cycle, not a consumer upgrade, gameplay pass, or public release.
