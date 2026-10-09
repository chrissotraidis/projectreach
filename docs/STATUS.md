# HaloPad status

## Current release candidate: 0.3.8 Xbox-only beta

**Latest background candidate, 2026-10-08 14:15 UTC:** private **0.3.8/build 21**
uses OpenCE **157**, revision `73dc01d09a21875f14c77b4430f20518d1f5ad09`,
network **24** on both platforms. All 346 Python tests passed; Mac and iOS package
audits passed, followed by independent notice/signature/hash and source-identity
verification. Build 20 retains its original hashes, and the persistent next-build
counter is 22. Evidence: `generated/xbox-candidates/runs/21-build-157/result.json`.
No device install, gameplay test or publication was performed.

**Update repair loop, 2026-10-09:** the three integration-audit defects are now
repaired in source and remain under verification. Main-branch app builds follow
upstream while pinned recipe checks stay separate; publication rejects engine
regressions and retagged revisions, even after a recipe-only release. Retained
candidates carry their original identity into delivery retries, and complete
uploads skip another Mac runner. Both app feeds move together on the dedicated
`halopad-updates` branch only after verified public assets exist. Source/recipe
releases cannot change that endpoint. Interrupted feed commits preserve the old
feed, and retries finish an already published package without republishing it.
All 359 Python tests passed locally, including disposable real-Git feed transaction
tests. Final package and hosted verification are pending. The channel branch has
not been created; publishing and device control remain off. The earlier audit
reproductions remain in `generated/update-plan-audit-20261008/` as historical evidence.

**Direct IPA publisher implemented, 2026-10-08:** the new main-branch delivery
workflow retrieves an existing candidate, verifies both packages and prepares a
private draft with the IPA, Mac app, update feeds, icon and checksums. All assets
must pass download/hash readback before the optional final public release update.
Retries preserve identical assets; changed bytes and downgrades stop. No Apple
service is used. Public promotion stays off while `HALOPAD_IPA_PUBLISH_ENABLED`
is unset; the upstream check also remains off. Local verification passes all 322
Xbox tests. Real build 20's six draft assets passed readback, while public latest
remained v0.3.7. Consumer installation/upgrade and public distribution are unproven.
See [UPDATE-STRATEGY.md](UPDATE-STRATEGY.md#direct-ipa-publishing).

Clean hosted private-delivery verification
[37766384899](https://github.com/chrissotraidis/projectreach/actions/runs/37766384899)
passed using the workflow token: retrieve retained build 19, upload all six
release assets, verify download hashes, retry without rebuilding, and compare
the repeated receipt plus GitHub asset digests. The release stayed private.
The temporary probe was removed. A focused follow-up also checks that historical
two-component versions cannot evade the downgrade guard.

Final full build [37767010361](https://github.com/chrissotraidis/projectreach/actions/runs/37767010361)
passed 346 Python tests and both build-1018/OpenCE-150 package audits at 65b9ca5.
Downloaded reports match the current product-source fingerprint and both staged
package identities, hashes, sizes, minimum OS versions and network versions.
The publisher also rejected the actual personal, profile-bearing build-20 IPA
before staging or any release request. Public latest and publishing variables
remain unchanged. PadMint v0.4.11 retains the recipe-lookup fallback needed for
app-only releases; companion input-validation PR #133 is still an open draft.

**Direct IPA clarification, 2026-10-08:** TestFlight is optional and disabled.
It is not required for HaloPad builds, IPA packaging or existing local signing.
Private **0.3.8/build 20, OpenCE 155, network 24** has now been signed using the
existing paid development profile, without a new Apple provisioning request.
Its final IPA passes archive, Apple-rooted signature, identity, component-notice
and memory-entitlement checks; the original candidate is unchanged. The profile
expires September 29, 2027 and is limited to its registered devices. Evidence:
`generated/direct-ipa-20261008T101049Z/personal-signing-proof.json`.
It has not been installed or gameplay-tested. Public IPA/feed promotion and a
consumer upgrade remain unfinished; the Apple agreement denial below concerns
the optional App Store Connect export, not this successful local signing.

**2026-10-08, fixed release recipe and hosted-build work implemented. Not released.** Public HaloPad
remains v0.3.7 (source/recipe assets, no public IPA). New Mac/iOS candidate
**0.3.8/build 19** uses OpenCE **154**, commit
`544ee497b6c1da195fa4dd9363851074edc63cbb`, network **24**. It was produced by
`scripts/xbox/candidate.py`, which resolves once, tests, builds and audits both
platforms, skips unchanged work and retains previous packages on failure.
Chris removed the local maintenance heartbeat. No public player update feed
is live. Normal source builds now use a bundled engine record; upstream latest is
explicitly experimental. The fixed recipe remains OpenCE 150. Hosted build/feed
verification passed on GitHub for both engine selections: build 1007/OpenCE 150
and build 1008/OpenCE 154 use the same HaloPad product-source fingerprint.
No upstream event sender or publisher is enabled. The physical iPad has private build 10/OpenCE 148/network 23, installed
with both required memory entitlements. Build 19 passed package checks on both
platforms; it has not been installed or gameplay-tested.

The intended player-facing description is: install HaloPad, choose Xbox Halo,
import your own Xbox disc once, and play with touch controls or a controller.
This Xbox-only package does not require the Custom Edition PC installer or key.
The picker explains that Custom Edition is not included; personal combined builds
remain separate. The small app update preserves the data container, avoiding a
repeat disc import. Hosted TestFlight signing/submission now has an opt-in workflow;
it is disabled, and ordinary consumer signing and automatic upgrades remain unproven.

**TestFlight implementation, 2026-10-08:** the new delivery workflow retrieves the
exact successful main-branch candidate, prepares credentials on a disposable
runner, exports with a team API key, verifies the resulting profile/signature and
memory capabilities, and uses pinned Fastlane to submit the exact version/build
to an existing internal or external group. External mode requests Beta App Review;
it does not infer approval. Configuration, export and archive failures stop before
upload; explicit resume supports a previously uploaded build without recompilation.
The workflow remains off until the channel and scoped credentials are configured.
No Apple credentials were exported from this Mac, no repository secrets or variables
were set, and no upload or review request was made. See the setup and remaining
real-service gates in [UPDATE-STRATEGY.md](UPDATE-STRATEGY.md#hosted-testflight-delivery-implementation).
Clean hosted run [37755072408](https://github.com/chrissotraidis/projectreach/actions/runs/37755072408)
passed 330 Python tests, seven Fastlane tests (42 assertions), the real Mac
keychain setup/cleanup fixture, both build-1014 archives and feed staging at
0d5c98c. Downloaded reports match the source fingerprint and staged package
identities. The latest saved-account export retry, at 18:05 JST, still received
Apple's agreement denial; no success proof or TestFlight submission was produced.

The delivery handoff now skips a deliberately unchanged build before allocating
a signing runner. Missing artifacts from a successful build still fail visibly.
All 313 Xbox tests, workflow lint and repository safety checks passed locally
after this repair; it does not change the disabled delivery or device-acceptance gates.

A real hosted-token check exposed a second handoff issue: read-only release
listing hid every private candidate. Build selection and delivery now have the
job-scoped permission needed to see drafts. The download-only confirmation
[37759064649](https://github.com/chrissotraidis/projectreach/actions/runs/37759064649)
retrieved build 20 with matching receipt and GitHub archive hashes. This verifies
private package access, not Apple signing or delivery. The temporary probe was
removed; existing private releases were preserved.

Final full run [37758513718](https://github.com/chrissotraidis/projectreach/actions/runs/37758513718)
passed 336 Python tests, seven Fastlane tests (42 assertions), real keychain
setup/cleanup, both build-1015/OpenCE-150 package audits and feed staging.
Downloaded reports match the current product-source fingerprint and staged
package identities. The later permission-only change passed the independent
hosted download probe above; its duplicate queued build was canceled before
starting. Automatic delivery, Apple acceptance and a consumer upgrade remain
unverified. Both HaloPad PR #20 and companion PadMint PR #133 remain open drafts.

| Acceptance check | Current evidence |
| --- | --- |
| Reproducible candidate | Real iOS and Mac build-19 archives replay OpenCE 154, pass identity/digest/data/signature checks, and share network 24. 295 Xbox and 23 builder tests passed. Both packages contain 27 source-linked notice entries and were privately retained, downloaded and re-audited. A real build-17 upload retry retained the same release and bytes. Concurrent local builders share a tested cache lock. Build 10 remains retained; gameplay, consumer upgrade and publication acceptance remain false. |
| Hosted build | Latest clean run [37758513718](https://github.com/chrissotraidis/projectreach/actions/runs/37758513718) passed all 336 Python tests, seven Fastlane tests, the real keychain fixture, both build-1015/OpenCE-150 archive audits and metadata staging at 4eb61fb. Downloaded reports match the current product-source fingerprint and both staged package identities. Branch runs upload reports only; consumer delivery and gameplay remain unproven. |
| iPad upgrade and picker | Main app upgraded in place from build 5 to 0.3.8/build 10, engine 148, using the existing paid development profile with both shipping memory entitlements. The themed picker and existing maps were observed; Play Xbox started menu rendering. This is not consumer signing or campaign acceptance. |
| Player data preservation | Fresh pre-install Documents/Library backup and independent readback matched 608 files (9,962,453,249 bytes). Full post-install readback found no changed retained files; only four OS-managed SplashBoard snapshots were replaced. This proves file preservation, not checkpoint compatibility. |
| Memory without extra entitlements | Build 4 reached the menu but crashed in the Normal campaign opening cinematic. GL out-of-memory errors preceded an ANGLE shader-link worker allocation failure (SIGABRT). No free-account gameplay claim is supported. |
| Increased Memory Limit only | Build 5's actual signature requests Increased Memory Limit, without Extended Virtual Addressing. Opening cinematics progressed farther with zero GL errors in the captured segment. Shared-iPad testing interrupted the run; campaign/save acceptance remains open. Paid development signing was used. |
| New Mac candidate | Build 10 picker and Halo main menu observed in an isolated test container with independent map copies. Captured render interval: zero GL errors. Campaign/multiplayer not accepted. Same-protocol releases no longer trigger picker update warnings. |
| Earlier Mac host | Fresh disc import, profile creation and a one-player Battle Creek/Slayer LAN lobby observed on engine 144. Two isolated same-Mac peers did not discover/join in the bounded test. A completed match remains unverified; a real Mac–iPad test is still required. |
| Themed picker | Private Mac build 7 implements the selected two-card layout over original space artwork. Wide/narrow visual checks, setup/back navigation, graphics selection and informational dialogs passed. Five packaging/minimum-OS tests passed. Build 10 now displays the themed picker on the physical iPad. See `design-qa.md`. |
| Distribution | Private IPA passes strict signature/archive checks. Build 19 bundles 27 known notice entries with source hashes; compiled-in asset provenance, complete transitive notices and exact-artifact publication decision remain open. Mac notarization is untested. |

**Distribution export, 2026-10-08:** the saved Xcode developer account provides an
existing provisioning path. A missing local distribution certificate does not
establish that automatic export is unavailable. Build 14 includes the iOS platform
metadata Xcode needs; the reusable `scripts/xbox/export_archive.py` prepared its
signed archive and reached Apple's live membership check. Apple returned
`PLA Update available` and could not obtain an App Store profile. The original IPA
remains unchanged. No upload, account agreement acceptance or device action occurred.
The exporter now also validates the final exported IPA's identity, signature,
App Store profile and both memory entitlements. Six focused tests passed; a real
development-signed build-18 IPA was correctly rejected as a distribution result.
A successful App Store export remains unproven behind the same agreement response.
Hosted run [37743259579](https://github.com/chrissotraidis/projectreach/actions/runs/37743259579)
passed all 313 tests, both build-1011 archive audits and metadata staging at b390fdb.
The downloaded report matches b390fdb's product-source fingerprint and staged
package identities. That clean build verifies the export-check implementation,
not an Apple-approved distribution export.

**Notice audit follow-up:** the earlier 16-file inventory omitted the Chromium
notice explicitly referenced by ANGLE's compiled `compression_utils_portable.cc`
and notices in the Khronos headers used by the host bridge. Source references and
exact notice extracts are retained under
`generated/distribution-export-20261008/notice-audit/`. OpenCE 154's build script
places miniupnpc in its Android host objects, not the guest reused by HaloPad;
repository presence alone does not establish a shipped dependency. Package-time
notice collection is now implemented: build 19 packages 27 notice entries from
its actual engine, renderer and header inputs in both apps. Both archives contain
identical verified notice bytes; the inventory records source hashes and engine/
renderer revisions. Five new tests cover complete license text, source mismatches,
missing licenses and corrupted/incomplete archives. All 295 Xbox and 23 builder
tests passed, as did both real package audits. The broader embedded-asset
provenance review remains open. No publication clearance is inferred.

**Upstream maintenance, 2026-10-08:** a real hosted upstream build of OpenCE 154
failed because it added `host_gl_read_buffer`. The build now generates guest-pointer
bridges around new self-contained upstream GL helpers instead of requiring a copied
Apple implementation for each addition. Existing HaloPad overrides stay in place;
unsupported signatures and dependent/stateful helpers fail before expensive builds.
Tests execute the generated readback wrapper, including mapping failure and buffer
cleanup. Build 16 verifies both archives with this final implementation. This removes
one source of routine port edits, not the need to engineer arbitrary future host APIs.

**Private delivery handoff, 2026-10-08:** `draft_release.py` now retains audited
packages in unpublished GitHub drafts, verifies remote bytes, and retrieves them
for signing without rebuilding. Build 17 completed that real round trip. Anonymous
access to its draft, asset API and download URL returned 404; no player feed was
published. The workflow enables retention on the default branch after merge;
branch builds retain reports only. Clean hosted run 37739072112 passed. The final
build-18 handoff adds a small receipt: a live upstream check correctly returned
`build: false` for the already retained OpenCE 154/product-source pair. Real
changed-engine and changed-version probes required a build. The prepared six-hour
GitHub check remains disabled; `HALOPAD_PREVIEW_ENABLED` is unset. A fresh build-16
distribution export still returned Apple's agreement denial; the downloaded build-19 export confirmed the same live denial at 17:00 JST. Both package hashes and acceptance flags survived retention/retrieval; the signing archive contains the verified notice inventory. A live receipt check skips this exact engine/source pair and requires a build for a changed engine.

Read-only USB queries reconfirmed the iPad is connected with HaloPad 0.3.8/build 10
installed and a HaloPad process running. No process was stopped, app installed or
input sent. Existing backups remain preserved; no new point-in-time save snapshot
or gameplay acceptance is claimed from those queries.

**Next acceptance session:** Chris has stopped keyboard control. Do not disrupt
his computer. These passes used commands/APIs and read-only device queries; they
did not install or launch a new app. Campaign/save/resume and a matching Mac-iPad
match remain unverified; use methods that preserve keyboard availability and data.
AltStore 2.3 accepted the private source and recognized build 10, but new signing
failed with `Apple.APIError 403: PLA Update available`. The signed-in account is
Developer; a paid account does not bypass the pending Program License Agreement.
Chris was asked to accept that agreement. Consumer install/upgrade and its actual
entitlements remain unverified; the successful development-profile install above
is separate evidence.

Private evidence: `generated/device-update-20261008/`, `generated/update-loop-20261008/`, `generated/xbox-candidates/`, and `generated/release-acceptance-20261007/`, including backup/readback
audits, the build-4 crash report, build-5 signature and campaign logs, and Mac
artifact audit. The release plan and exact private IPA identity are in
[UPDATE-STRATEGY.md](UPDATE-STRATEGY.md). Shipping entitlement requirements remain
unchanged. No public binary, update feed or automatic publisher exists.

## Earlier investigation log

The entries below are chronological investigation snapshots. Statements about
what was installed or untested describe their own step; the current table above
supersedes them.

## Reducing update maintenance

**2026-10-07: implementation and physical memory test supersede the planning notes below.**
The builder now accepts `--xbox-release-record`, `--app-version` and `--app-build`.
Real private builds 2 and 3 replayed the same OpenCE 144 commit and packaged the
requested version/build identity. Invalid inputs stop before expensive work.
The saved record does not imply gameplay acceptance; default latest selection and
the existing app update notice are unchanged. No publishing workflow/feed exists.

The Xbox allocator now directly reserves an aligned 4 GiB region with `vm_map`,
avoiding the temporary 8 GiB reservation. On the connected M2 iPad, the old
allocation failed without extra memory entitlements while the new one succeeded.
Two fresh diagnostic launches exercised the production allocator. A separate full
HaloPad test app with neither Extended Virtual Addressing nor Increased Memory
Limit then reached the edition picker and the actual Halo main menu. Its log
confirms OpenCE 144 and the aligned guest region. This used a paid development
identity; free-account signing, campaign memory pressure and multiplayer remain
unverified. Shipping entitlement/profile requirements were not relaxed.

The main HaloPad build-138 installation and player data remain preserved. The
separate `dev.halopad.MemoryProbe` app, displayed as HaloPad Test, has its own map
copies. Evidence and the private 0.3.8/build-3 IPA are under
`generated/ipa-update-pipeline-20261007/`; memory diagnostics are under
`generated/update-research-20261007/memory-probe/`. The build-3 archive passed
strict signature verification and contains no maps/discs, PC identity or profile.
See [UPDATE-STRATEGY.md](UPDATE-STRATEGY.md) for exact artifact identity, tests,
remaining consumer-install/upgrade/gameplay gates and the whole-IPA release plan.
No public binary was published.

**2026-10-07: second-pass decision simplifies delivery.**
Whole-IPA updates are the primary plan; a custom compatibility-policy service is
deferred until there is evidence it is needed. The private IPA is about 20 MB;
maps stay in the app's data container. Source inspection found two concrete
release-pipeline gaps: the top-level builder re-resolves latest instead of accepting
an immutable candidate input, and packaging hardcodes app version `0.3`, build `1`
(also confirmed inside the private IPA). Neither gap was changed in this planning
pass. A promoted HaloPad release should eventually drive both app updates and
normal PadMint builds, with raw upstream latest an explicit experiment.

Consumer installation comes first: Apple's current capability table marks Extended
Virtual Addressing for paid memberships, not free accounts, and HaloPad currently
requires it. The Xbox allocator temporarily reserves 8 GiB of virtual address
space to retain an aligned 4 GiB region. Investigate that constraint with a bounded
diagnostic before promising free-account SideStore installation; no allocator or
profile check was weakened. See the revised [plan](UPDATE-STRATEGY.md) and local
`generated/update-research-20261007/second-pass-evidence.json`. No runtime code,
signing account, installed app or release changed during this second pass.

**2026-10-07: deeper update plan and a bounded build fix, local changes.**
See [UPDATE-STRATEGY.md](UPDATE-STRATEGY.md) for the source-backed decision:
keep the native engine and prove an on-device IPA upgrade through an existing
signing client. The initial compatibility-data proposal below is now deferred
by the second-pass decision. ChupathingyCE implements a useful
compatibility-table design, but its documented cross-play automation is incomplete;
its published network range is not evidence that HaloPad can join those peers.
No network-version override or update service has been enabled.

The latest-mode sampler adapter now recognizes the required cache layout after
an unrelated source edit instead of relying solely on build 144's complete file
hash. It retains exact input/recipe identities and rejects missing, duplicate,
reordered or changed required fields. All 238 Xbox tests pass. An additional
comparison against the previous adapter confirms unchanged historical recipe
identities and byte-identical renderer output for the real build-144 source;
that real source also passes the unrelated-edit probe and rejects changed fields.
Evidence: `generated/update-research-20261007/`. The existing private IPA and
physical iPad installation have not changed. Consumer signing and actual
multiplayer remain the next acceptance gates, not completed work.

## Installation delivery

**2026-10-07: current network candidate built, public IPA still pending.**
The live GitHub API reports OpenCE **build 144**, revision
`76b1898ee14e6fb58e0412acc183da509c10e001`, with **network version 21**.
The physically tested build 138 uses network 20 and cannot join network-21
hosts. Matching the protocol number is necessary but does not establish
successful HaloPad multiplayer.

The first build-144 attempt exposed an outdated HaloPad anisotropic-filtering
insertion: upstream now caches immutable samplers and the old insertion referred
to variables outside their scope. The compatibility fix applies the same optional
filtering to the sampler input key before cache lookup. HUD, point-filtered and
non-mipmapped textures retain their exclusions; an explicit stronger game setting
is retained. Historic renderer recipes keep their original identity. Compiled
regressions exercise exclusions, GPU limits and repeated cache keys.

The rebuilt private iOS candidate packages build 144/network 21, requires iOS
17.4+, and passes strict code-signature verification. It is 19,853,004 bytes;
SHA-256 `b2a8ae7010b31cfcaeb80d7059cd007ccbde718c41b315adfe37704cb5e184d6`.
No disc/maps, PC identity/modules or provisioning profile are packaged. The
compiled Xbox engine is included. This candidate has not replaced the physical
iPad's tested build 138. Evidence: `generated/release-candidate-20261007/`.
Validation: all 236 Xbox tests and 26 archive/installer/signing/profile tests pass;
Bash syntax and whitespace checks pass. The exact IPA also passes the real
non-mutating signing/device preflight against the iPad's development profile.

The intended first public app download is an **Xbox-only beta IPA**, with the
edition picker, disc importer, touch/controller support and a tested OpenCE
engine; players import their own Xbox disc after signing/installing. PC Custom
Edition remains an optional personal combined build. Accompany the IPA with
checksums, complete component notices, exact engine/network versions and tested
installation/upgrade instructions. A Mac download needs its own acceptance and
signing/notarization checks. The source/PadMint recipe updates are a separate
deliverable; latest public PadMint 0.4.11 still lacks the draft conditional-tool
flow in PadMint PR #133.

Before promoting an IPA: test this exact candidate on hardware, including a
real matching-version multiplayer match; reproduce an ordinary player's signing
route with its actual memory entitlements; verify upgrade/save behavior and clear
recovery guidance for incompatible old checkpoints; finish notices and the exact
compiled-engine distribution decision. Installing with the maintainer's development
profile alone does not establish a broadly usable sideloading route. No public
binary or claim of release readiness follows from the successful build.

**2026-10-07: direct-download delivery plan, implementation started.**
Keep the existing Xbox engine, picker and disc importer. The intended release
is an Xbox-only app; Custom Edition remains an optional personal combined build.
Work through four separate acceptance steps:

1. **Package and install handoff:** the existing device installer now accepts
   `--ipa` directly and offers `--check-only`. Validate archive paths and app
   identity before extracting, retain profile/device checks, sign a temporary
   copy, and preserve the input IPA. This removes manual unzipping from the
   developer-profile route; it is not yet a consumer signing application.
2. **Physical device:** use one frozen candidate for signing, picker, gameplay
   and update preservation checks. Back up and independently read back the
   existing iPad data before replacement. The private build-138 IPA is the
   candidate; record the exact hash and results rather than chasing a moving
   upstream release during acceptance.
3. **Distribution contents:** inventory the compiled engine and dependencies,
   bundle required notices and review distribution treatment. Inspection of
   the candidate found no bundled dependency notices. The guest build includes
   musl, tomlc17, Expat, KCP, Monocypher and zlib; the host includes ANGLE and
   xxHash. The component/license inventory still needs completion. Absence of
   ISO/map files is not a complete review of compiled-in assets or engine rights.
4. **Player delivery and updates:** after the first three steps, prepare a
   stable platform-specific download, tested signing instructions, exact engine
   and network versions, and an in-place upgrade path preserving player data.
   Verify Mac signing/notarization separately. Keep a tested prior release and
   promote tested builds rather than promise every daily upstream update works.

Public binary publication remains pending. Source-only HaloPad/PadMint fixes
can proceed independently of deciding how to distribute the compiled engine.

Installer validation: 26 focused archive, device-wrapper, signing and profile
tests pass, including invalid archive paths, non-device apps, failed signing,
PC package requirements and non-mutating preflight. The real private IPA also
passed preflight with the connected iPad's development profile. Before the
in-place device install, two independent reads of Documents/Library matched
all 459 files (7,422,708,827 bytes). Installation through `--ipa` succeeded;
98 save/profile/preference files read back unchanged before first launch.
QuickTime showed the physical iPad opening to the edition picker with build
138 and the existing Xbox maps ready, plus the expected different-network
warning for build 144.

Physical interaction through Apple's Device Hub then verified touch menu navigation,
a new test profile, Pillar of Autumn on Normal, swipe-to-look, the X action to leave
the cryo tube, and Save and Quit followed by Continue back into the checkpoint.
The original profile's Continue stayed in the menu and logged `checksum failed on
persistent storage`; its pre-install save bytes are retained in the verified backup.
This does not establish whether the old checkpoint was already invalid or became
incompatible with this engine. Do not bypass the checksum or overwrite the backup.
A one-player local Battle Creek lobby was created but did not start during this
test; multiplayer remains unverified. Sustained movement, combat, controller input,
audio and frame-rate acceptance remain open. Short remote stick gestures are not
enough to diagnose a physical-touch defect.

The iPad currently retains the private Xbox-only build 138, paused in the test
campaign. Custom Edition is temporarily unavailable in this candidate. A signed
combined build 125 is retained locally, but it is older and is not an exact backup
of the original app; validate save compatibility before returning to that build.
Private logs and backup audits: `generated/ipa-install-check-20261007/`.

**2026-10-06: player reports identify a distribution problem as well as setup bugs.**
Players want Xbox Halo on an iPhone/iPad, but encounter PC installer/key requirements,
Mac/Xcode builds, unclear signing instructions and confusion over whether both Halo
editions are required. Several stop before reaching the game. The Xbox-only builder
removes the PC dependency; it does not remove local compilation or signing.

The intended simpler flow is **download app → sign/install → import owned disc → play**,
with the edition picker retained and Custom Edition optional. PadMint remains useful
for personal builds and the PC translation. This is a delivery proposal, not a shipped
download or a change to the current publication policy.

Comparison checked against published artifacts and source:

- [ChupathingyCE v0.6.7b](https://github.com/ChupathingyCE/chupathingyce/releases/tag/v0.6.7b)
  has desktop/Android releases, including Mac, but no IPA in that release.
- [NicholasDominici's iOS v0.1.2](https://github.com/NicholasDominici/halo-ce-ios/releases/tag/v0.1.2-ios)
  does publish an unsigned IPA: 5,663,938 bytes, published SHA-256 verified as
  `8340cc94f21429e398c668f5d4313f20917fdd6f8c202d51b934a7bfc7194530`.
  ZIP inventory contains the app executable, icons, metadata and notices, with no disc
  or map files. Its [release build script](https://github.com/NicholasDominici/halo-ce-ios/blob/ff9d86bf65730b780b65fb4b4d3a7d87044623ed/tools/ios_build.py)
  embeds the compiled guest engine. The package was inspected, not run; its release
  notes leave multiplayer and physical-iPad validation open.
- [OpenCE PR #64](https://github.com/OpenCommunityEdition/OpenCE/pull/64) is a separate
  Apple port with IPA workflow artifacts and a Mac test download. At reviewed head
  `6702fb72efd8d97a780939d9b4bc04ab78d05aaf`, its
  [distribution record](https://github.com/AttilaTheFun/halo-ce-universal/blob/6702fb72efd8d97a780939d9b4bc04ab78d05aaf/port/apple/DISTRIBUTION.md)
  explicitly distinguishes excluded game assets from included reconstructed engine code.
  These checks establish packaging differences, not comparative gameplay quality.

HaloPad already produces an approximately 19.7 MB personal Xbox-only IPA and imports
maps afterward. Publishing an empty launcher would not supply its required engine;
publicly distributing the existing app still includes game-derived executable code.

Next delivery steps, in order:

1. Ship the paired HaloPad/PadMint input fixes after outstanding device acceptance.
   The source now also signs and installs Xbox-only apps without a PC identity file
   or prepared PC package. Regression checks retain device/profile validation and
   ensure failed signing never installs. PC/combined package requirements remain.
2. Validate the exact Xbox-only IPA on physical iPhone/iPad: signing capabilities,
   first install, disc import, gameplay, matching-version multiplayer and in-place
   upgrade with saved data. State which signing route and account type were tested.
3. Resolve distribution treatment of the compiled Xbox engine separately from maps,
   dependencies and PC inputs. The existing source-only release policy is not proof
   that direct-download packaging is technically impossible; another fork's download
   is not distribution clearance for HaloPad either.
4. If public binary distribution is approved, publish an audited Xbox-only IPA/Mac
   app with stable download links and a short platform-specific install guide. Show
   the exact OpenCE build/network version and retain a tested prior release. Updates
   should replace the app while preserving imports/saves; do not promise automatic
   iOS updates or cross-fork network compatibility without verifying them.

No public binary uploaded, signing-tool compatibility promised or physical-device
acceptance added by this review. README and install instructions now distinguish the
live 0.3.7/0.4.9 flow from the draft Xbox-only flow. Follow-up validation: 37 focused
profile, signing, device-wrapper, Xbox-only package and builder regression tests pass;
Bash syntax, documentation links and whitespace checks pass. Signing/profile calls and
device operations are simulated in the new tests; they do not establish hardware acceptance.

## Build validation

**2026-10-06: Xbox-only installation flow (draft, not released).**
Selecting an Xbox ISO/XISO in the updated HaloPad recipe builds without the PC installer,
product key, Wine, PC translation or PC game package. Selecting HaloCESetup.exe retains
both editions. PadMint's companion draft checks tools for the selected input and refreshes
them when switching files; release both changes together. The same picker/importer/controls
are used by the Xbox-only app. Custom Edition is clearly marked as absent, with instructions
for adding it through a combined build.

Validation: full personal Mac ZIP and iOS IPA builds completed against OpenCE build 138
(`76addf661f02e2fd090d7b00f9dd12c29e562a9b`, network 20). Signatures, entitlements, OS minimums
and package contents checked; Xbox-only outputs contain no PC image, modules, product ID
or PC package. A clean source export with no PC inputs or third-party Python packages also
built the Mac app. An isolated Mac installation imported an owned Xbox disc, reached Halo's
main menu, then relaunched into the picker with its maps retained. The combined build opened
PC setup using the same test identity; all Xbox files retained identical hashes. Actual app
and player data were not replaced. Full PadMint suite: 318 passing; Xbox suite: 234 passing.
Builder failure/rollback tests and PC-cache tests pass separately. Private build records and
logs are retained under `generated/xbox-only-check-20261006/`.

No physical iOS install, new gameplay/performance acceptance or real multiplayer-match
acceptance was performed. Personal binaries are not public release assets.

**Earlier graphics investigation paused by Chris on 2026-10-03.**
The resumed installation work above does not establish resolution of that investigation.
Replacement-bot instructions and bounded priorities:
[focused handoff](HaloPad-NEXT-BOT-HANDOFF-2026-10-03.md).
The chronology below is evidence, not permission to resume or repeat old passes.

Updated 2026-10-03. **Simulator-only work: shared controls, texture compatibility and upstream updates.** The full goal is incomplete. Physical-device testing remains out of scope until Chris makes the iPad available again.

Operating loop: [HaloPad-GOAL-LOOP-PHASE4.md](HaloPad-GOAL-LOOP-PHASE4.md). Earlier device work remains in [phase 3](HaloPad-GOAL-LOOP-PHASE3.md).

**Battle Creek reference agrees; longer run exposes a sound crash (2026-10-03).**
Same-revision official Windows74/Mesa and unchanged Simulator `4e42dc6d…11175`
show matching water appearance, rock shading and foliage over22 usable stepped
camera poses. This is not continuous-motion or all-scene fidelity acceptance.
Simulator later crashes at about184s: stale looping-sound datum -> null dereference
in inlined sound-channel update; crash reporter recursively faults on guest FP.
Stationary final-pose control survives240s, so trigger remains unresolved. Preserve
the failed capture; next reproduce/isolate sound lifecycle and harden diagnostic
unwinding, not another speculative shader edit. Real saves/preferences/PC registry
exact, Original picker restored. No runtime/pin change or hardware access.
[Evidence](XBOX-SIMULATOR-PASSES.md#build74-battle-creek-reference-and-late-sound-fault-2026-10-03).

**Build74 normal multiplayer menu route verified (2026-10-03).**
Unchanged adapted `4e42dc6d…11175`: copied New001/Green Thumb profile -> System
Link -> Create Game -> Battle Creek/Slayer -> lobby -> rendered match -> Leave
Game -> main menu. Shared Fire, Melee, Throw and Pause work; raw A/Y menu actions
remain independent of the gameplay preset. One local stand-in peer, not another
full game client, so real multiplayer compatibility is not accepted. Real saves,
preferences and PC registry preserved; ordinary Original picker restored.
Next compare a moving Battle Creek water/foliage view with the pinned desktop
reference before treating its appearance as a new renderer defect. No runtime
change; broad graphics, held-score/multi-touch and hardware gates remain open.
[Evidence](XBOX-SIMULATOR-PASSES.md#build74-normal-multiplayer-menu-route-2026-10-03).

**Build74 is the accepted development pin (2026-10-03).**
Actual update-pin --accept workflow verifies save backups, passes Mac and ANGLE
Simulator menu/campaign/match gates, then advances66->74/80d30410. Preserved the
unadapted result and restored exact shared-controls preview `4e42dc6d…11175` in
place. Real saves/preferences/PC registry exact; Original picker restored.
206 Xbox tests pass both with explicit74 and the new default lock after isolating
synthetic fixtures from the production pin. No graphics/runtime change or public
release. Next normal-menu multiplayer profile/lobby/shared-control check; scripted
combat does not cover that route. Broad fidelity/human multi-touch/hardware open.
[Evidence](XBOX-SIMULATOR-PASSES.md#build74-accepted-update-workflow-2026-10-03).

**Build74 retains material fixes in both graphics modes (2026-10-03).**
Exact `4e42dc6d…11175` passes four100s a10/b30 captures: Original640x480/1x
and picker-selected Sharper1280x960/4x retain detailed water, corrected bridge
shadows and translucent displays. All four starts report read1/draw0/error0.
Real saves/preferences/PC registry exact; Original picker restored. No source
change or broad-fidelity claim. Next exercise the real reviewed74 pin-update
workflow with outgoing app/output/data protected, then restore/rebuild the adapted
preview as needed. Accepted66 is still unchanged; do not chase another release
mid-acceptance or repeat these same graphics checks without a changed input.
[Evidence](XBOX-SIMULATOR-PASSES.md#build74-both-quality-material-regression-2026-10-03).

**Adapted upstream74 passes smoke and copied-save controls (2026-10-03).**
Installed candidate `4e42dc6d…11175` carries the unchanged cumulative
render-present-v1 recipe against the reviewed74 renderer hash. Historical66/73
identities remain intact;206 Xbox tests pass. Menu/a10/match smoke and normal
Green Thumb Melee/Zoom/Swap/Fire/Reload/Pause, Save and Quit and cold checkpoint
reload pass. Frame0 is read1/draw0/error0. Real saves/preferences/PC registry
remain exact; ordinary Original picker restored. Accepted66 is unchanged.
Next exact74 Original/Sharper water/shadow regression, not pin promotion or a
claim that all graphics and sustained multi-touch are fixed.
[Evidence](XBOX-SIMULATOR-PASSES.md#adapted74-controls-and-save-regression-2026-10-03).

**Unadapted upstream74 passes Mac and Simulator smoke (2026-10-03).**
Live release/main now resolve to74/80d30410. Fresh Mac and ANGLE Simulator builds
pass menu/a10/scripted-match checks. This is not adapted-preview or save-compatibility
acceptance: the renderer-source guard rejects74, and the unmodified guest retains
startup blit0x502. Build73 presentation preview restored exactly; accepted66
unchanged. Fixed update helper to retain normal PC startup/device-local state,
with a reproduced failing regression and203 passing Xbox tests. Next extend the
reviewed adaptation identity for74 without weakening source checks or changing
historical identities, then verify the adapted candidate and copied saves.
[Evidence](XBOX-SIMULATOR-PASSES.md#upstream74-unadapted-update-gates-2026-10-03).

**Night landing compared with independent desktop73 (2026-10-03).**
Unchanged `ed257ad5…af30b` and official Windows73/Mesa both show a50's bright
landing transition, exhaust and spotlight pools. Selected settled terrain/tree
regions differ by about0.2–0.3 RGB levels out of255; spotlit cliff by0.72. This
rejects missing night lighting or a Simulator-only white transition in this
scene, not all material/temporal defects. Real state preserved, Original picker
restored. Next upstream-update acceptance: Mac output is still66 and unadapted73
Mac/Simulator gates remain open; preserve this adapted preview before building.
[Evidence](XBOX-SIMULATOR-PASSES.md#night-landing-desktop-reference-2026-10-03).

**Green Thumb shared-touch runtime check passed (2026-10-03).**
Unchanged presentation candidate `ed257ad5…af30b` correctly separates Melee and
Zoom despite their native Green Thumb swap. Swap, Fire, Reload, Pause and menu
selection also work; Save and Quit plus cold checkpoint reload retain the mapping.
Only copied Xbox state changed; real saves/preferences/PC registry preserved.
Original picker restored. Next investigate a different reproducible graphics
discrepancy against the independent desktop reference. Broad fidelity and human
multi-touch feel remain open; no new renderer or upstream-pin change.
[Evidence](XBOX-SIMULATOR-PASSES.md#green-thumb-shared-touch-runtime-2026-10-03).

**Boxer shared-touch runtime check passed (2026-10-03).**
Unchanged presentation candidate `ed257ad5…af30b` keeps Melee/Throw separate
under the genuine Boxer profile; Fire, Swap, Zoom, Pause and menu selection also
work. Save and Quit followed by cold checkpoint load retains the Boxer mapping.
Only copied Xbox state changed; real saves/preferences/PC registry preserved.
Original picker restored. Green Thumb is next, not yet runtime accepted; human
multi-touch feel and broad graphics fidelity remain open.
[Evidence](XBOX-SIMULATOR-PASSES.md#boxer-shared-touch-runtime-2026-10-03).

**Cyan beam reproduced in independent desktop reference (2026-10-03).**
The same debug-camera inputs show the narrow cyan beam and bright pulse in both
desktop73 and unchanged Simulator `ed257ad5…af30b`. Its presence is not a
HaloPad-only artifact; do not remove it or alter HUD sampling to hide it. Effect
timing is not synchronized, so exact temporal/color parity remains unproved.
Real state preserved, Original picker restored, diagnostic listeners closed.
Next exercise still-unaccepted Boxer/Green Thumb touch mappings on copied state;
broad material fidelity and sustained human multi-touch remain open.
[Evidence](XBOX-SIMULATOR-PASSES.md#cyan-beam-desktop-reference-2026-10-03).

**Presentation candidate retains water/shadow fixes in both modes (2026-10-03).**
Exact `ed257ad5…af30b` passes four bounded a10/b30 captures: Original640x480/1x
and UI-selected Sharper1280x960/4x. Detailed water and the bridge-band fix remain;
the bridge display remains translucent. All four cold starts report read1/draw0/
error0. Real saves/preferences/PC registry preserved; Original picker restored.
Live upstream still build73/d1c7243c; accepted66 unchanged. Next matched desktop
comparison of another unresolved world effect, not another identical regression.
Broad fidelity and human multi-touch remain open.
[Evidence](XBOX-SIMULATOR-PASSES.md#presentation-candidate-both-quality-regression-2026-10-03).

**First-blit fix built and verified in Simulator (2026-10-03).**
Installed `ed257ad5…af30b` / guest `4ac7e842…b60`, cumulative
`render-present-v1`, passes cold menu/campaign/local-match smoke with frame0
read1/draw0/error0. Normal shared Fire/Swap/swipe Look/Pause, Save and Quit and
cold checkpoint reload also pass on an isolated save copy.202 Xbox tests pass.
Exact-candidate Original/Sharper water and border regression is next; broad
texture/lighting fidelity and human multi-touch remain open. Accepted66/upstream73
pins unchanged. [Evidence](XBOX-SIMULATOR-PASSES.md#first-blit-fixed-build-validation-2026-10-03).

**Earlier first-blit diagnosis, superseded by the installed result above (2026-10-03).**
Debugger trace proves cold framebuffer creation overwrites the selected draw
target. A one-process draw-target correction removes startup0x502. New guarded
`render-present-v1` moves read-FBO resolution before draw-target selection;
old identities remain stable.202 Xbox tests and40 native launch/save/quality
checks pass. Installed app stays `48f118f3…213e`; no fixed-build acceptance yet.
Only1.2GiB disk space remains, so full rebuild/install is deferred. Real state
preserved, Original picker restored; pins unchanged.
[Evidence and next gate](XBOX-SIMULATOR-PASSES.md#first-blit-ordering-confirmed-2026-10-03).

**Exact shared-input candidate retains fixes in Sharper (2026-10-03).**
UI-selected Sharper runs at1280x960/effective4x on `48f118f3…213e`. Bounded b30
and a10 captures retain detailed water, the bridge-band fix and engine glow.
No new runtime change or full fidelity claim. Startup blit0x502 persists; source
inspection identifies a cold framebuffer-creation ordering hypothesis for the
next targeted check. Real state preserved, Original picker restored. Free disk
is1.8GiB: avoid large captures/rebuilds without checking available space. Pins
unchanged. [Evidence](XBOX-SIMULATOR-PASSES.md#shared-input-sharper-regression-2026-10-03).

**Southpaw thumbstick routing verified; sustained feel still open (2026-10-03).**
Genuine saved Southpaw sticks/Default buttons reload on the unchanged
`48f118f3…213e` candidate. Shared swipe Look and Fire work; trace proves Move
reaches the expected right-stick axes. Automated Move/LOOK drags last only0–1ms,
so they do not establish held movement/aiming. Added repeated-poll, short-drag
and preset-transition regression assertions;199 Xbox tests pass. Real state
preserved, ordinary Original picker restored. Next exact-build Sharper graphics,
not another identical short-gesture attempt. No runtime or pin change.
[Evidence](XBOX-SIMULATOR-PASSES.md#southpaw-thumbsticks-and-gesture-duration-2026-10-03).

**Shared-input graphics regression passed at Original quality (2026-10-03).**
Exact `48f118f3…213e` candidate retains detailed b30 water and the bridge shadow
fix; 65-second scripted local match passes. 199 Xbox tests pass. Smoke tests now
explicitly disable upstream update prompts. Live upstream main still resolves to
build73's `d1c7243c`; accepted66 is unchanged. Real saves/preferences/PC registry
preserved, Original picker restored. Next alternate-thumbstick runtime checks;
Sharper on this candidate, broader fidelity and human multi-touch remain open.
[Evidence](XBOX-SIMULATOR-PASSES.md#shared-input-original-rendering-regression-2026-10-03).

**Jumpy and Default runtime checks passed (2026-10-03).** The unchanged
`48f118f3…213e` shared-input candidate keeps Jump/Throw semantics under Jumpy's
alternate A/trigger mapping. Default Fire/Throw/Swap/Look/Pause also respond
correctly. These are bounded Simulator checks, not sustained touch-feel or
all-preset acceptance. Real saves/preferences/PC registry remain unchanged;
ordinary Original picker restored. Next exact-build water/border/local-match
regression, without promoting the accepted pin.
[Evidence](XBOX-SIMULATOR-PASSES.md#jumpy-and-default-runtime-regression-2026-10-03).

**Southpaw touch mismatch fixed in Simulator candidate (2026-10-03).** New
`shared-input-v1` exposes versioned guest mapping/menu context and adapts only
HaloPad's touch pad, without resetting profiles or remapping physical controllers.
On the same copied Southpaw profile, Fire now fires and Throw throws; normal
menus, Save and Quit and cold checkpoint reload pass. 198 Xbox tests, 153 native
overlay assertions and 39 launch/save/quality checks pass. Installed app
`48f118f3…213e`, guest `652fbebb…de17`; upstream73/accepted66 unchanged. Original
picker restored; real saves/preferences/PC registry preserved. Other runtime
presets, sustained multi-touch and exact-new-build graphics regression remain
open. [Implementation and evidence](XBOX-SIMULATOR-PASSES.md#southpaw-touch-mapping-bridge-2026-10-03).

**Earlier non-default touch mismatch reproduced (2026-10-03).** On an isolated copy,
selecting Xbox's Southpaw button preset makes shared Fire throw a grenade and
shared Throw fire the rifle (60->59). Real profile/saves/preferences/PC registry
remain intact; ordinary Original picker restored. Same `dc469db1…5997d` candidate,
no runtime change. Next implement a guarded mapping/menu-state bridge that adapts
touch only, preserves hardware preferences and clears held inputs on transitions.
The source boundary is identified but not yet implemented or runtime accepted.
[Reproduction and implementation gates](XBOX-SIMULATOR-PASSES.md#southpaw-touch-mismatch-reproduced-2026-10-03).

**Border candidate regression checks passed (2026-10-03).** Exact installed
`dc469db1…5997d` passes normal picker/menu checkpoint loading, shared Fire/Look/
Swap/Zoom/Pause, Save and Quit, and cold reload. UI-selected Sharper persists into
fresh b30 and a10 captures at 1280x960/effective4x: detailed water remains and the
bridge bands stay absent. Real saves/preferences/PC registry preserved, Original
picker restored. No rebuild, pin change or hardware. Next reproduce the known
non-default Xbox profile mismatch on a copied profile and design its adapter
boundary; sustained human multi-touch and broad fidelity remain open.
[Evidence](XBOX-SIMULATOR-PASSES.md#border-candidate-controls-saves-and-sharper-2026-10-03).

**Bridge shadow bands fixed in Simulator candidate (2026-10-03).** New opt-in
`render-border-v1` restores border-color sampling for the single-level 2D textures
implicated by the preceding draw trace. Matched bridge views lose the black floor
bands while a nearby view retains the character shadow. Water reflections and
exterior engine glow remain visible; 30-second menu and 65-second local-match smoke
pass. 194 Xbox tests and 38 native launch/save/quality checks pass. Candidate app
`dc469db1…5997d`, guest `2d03ab18…b6b6`; accepted66/upstream73 unchanged. Real saves,
preferences and PC registry preserved; ordinary Original-quality picker restored.
Next exact-candidate normal-menu controls/save/cold reload and Sharper regression.
Full mip/cube border support, broad fidelity and human multi-touch remain open.
[Evidence and limits](XBOX-SIMULATOR-PASSES.md#bridge-border-sampling-fix-2026-10-03).

**Bridge shadow bands localized (2026-10-03).** New paired a10 opening capture
finds long black floor bands on Simulator, absent in the corresponding pinned
desktop view. Native before/after draws identify shadow projection, not the floor
lightmap. Its128x128 shadow has bright edge texels and actual linear/CLAMP_TO_EDGE
sampling, while upstream requests BORDER; ANGLE Metal advertises no border-clamp
support. This is a concrete next fix target, not a completed fix: implement and
A/B-test faithful border sampling, including shadow convolution, without disabling
shadows or changing depth. Real state preserved; same candidate/accepted pin.
[Evidence](XBOX-SIMULATOR-PASSES.md#bridge-shadow-band-localization-2026-10-03).

**Shared settings regression coverage (2026-10-03).** Native overlay suite now
passes153 assertions, including12 new checks for settings/editor cancellation,
handedness, shared look sensitivity and PC/Xbox layout persistence with separate
phone/tablet keys. Actual Simulator UI mirrors controls; left-side Fire and
background swipe aiming work. Short automated LOOK-stick drag has no observable
rotation, so sustained mirrored-stick behavior is not newly accepted. Original
preferences/saves/PC state restored; same water candidate and accepted66 pin.
Next investigate a different moving material/effect against desktop, not another
unchanged checkpoint/settings repeat. [Evidence](XBOX-SIMULATOR-PASSES.md#shared-settings-and-layout-contracts-2026-10-03).

**Water candidate regression checks passed (2026-10-03).** The exact installed
`aa0c46d8…7077d` build passes ordinary picker/menu checkpoint loading, shared
Fire/Look/Swap/Zoom/Pause, Save and Quit, and cold checkpoint reload. Sharper
selected through the actual UI persists into a fresh b30 run: 1280x960 source,
effective4x world filtering, detailed water and ordinary foreground occlusion
visible in composited screenshots. This is bounded regression evidence, not all
depth/fidelity, new progression or sustained multi-touch acceptance. Original
quality restored; all real saves/preferences/PC registry preserved. No runtime,
pin or hardware change. Next compare a different moving material/effect against
the independent desktop reference. [Evidence](XBOX-SIMULATOR-PASSES.md#water-candidate-controls-saves-and-sharper-2026-10-03).

**Missing water reflections fixed in Simulator candidate (2026-10-03).** Moving
b30 reference views reveal a real difference: the prior candidate draws flat
green water where upstream desktop draws reflections/ripples. The ES mip-copy
fallback changes the framebuffer during preparation of that same draw. New
opt-in `render-water-v1` restores read/draw framebuffer and scissor state; actual
before/after frames and ordinary Simulator screen captures show restored water.
188 Xbox tests, 37 launch/save checks and menu/a10/local-match smoke pass.
Candidate executable `aa0c46d8…7077d`, guest `83dd49b6…45c5`; upstream73 and
accepted lock66 unchanged. Broader graphics, controls and hardware acceptance
remain open. [Fix, provenance and limits](XBOX-SIMULATOR-PASSES.md#water-mip-copy-state-fix-2026-10-03).

**Independent desktop reference (2026-10-03).** Upstream build73's unmodified
Windows executable runs locally under isolated Wine9/Mesa26.2.3 llvmpipe, reaches
menu and Silent Cartographer, and produces real OpenGL4.6 frames. This is the
Xbox port's desktop build, **not the HaloPad PC engine**, and does not use our
guest translation or ANGLE. Its beach landing view and the unchanged Simulator
candidate show the same broad terrain softness and blocky distant waterfall.
Regional differences remain; this is not pixel parity or overall fidelity
acceptance. The 180-second Simulator campaign pass succeeds, original state is
preserved, and Original-quality picker is restored. Next use this reference for
a corresponding moving water/effect view, not another HUD-toggle or static
landing repeat. [Evidence and provenance](XBOX-SIMULATOR-PASSES.md#independent-desktop-reference-2026-10-03).

**Cyan streak isolated (2026-10-03).** The suspected shield-HUD line reproduces
with high-res HUD on and off, and moves with the world when the camera turns.
Guest readback confirms the off setting. Map metadata contains the a30 beam
emitter and its effects: a plausible source, not yet exact draw attribution.
Retire the HUD-replacement hypothesis; do not hide the effect or modify HUD
shaders. Recorded comparison and preserved state in the
[Simulator ledger](XBOX-SIMULATOR-PASSES.md#cyan-streak-isolation-2026-10-03).
This is diagnostic progress, not a texture fix. Next use a matched upstream
desktop reference for material/effects fidelity; accepted lock stays66 and the
unchanged73 candidate is back at the ordinary picker.

**Scoreboard observation (2026-10-02).** Read-only guest observation narrows the
previous negative video result: real automated drag reaches guest Back and opens
the scoreboard path, but only for one rendered sample. Fade peaks at 0.0814
(about 0.85% opacity with upstream's curve), then closes. No evidence here of a
lost Back input or failed font/layout entry. This does not verify final pixels or
overflow paging. No runtime/pin change; original state preserved and ordinary
picker restored. Return next to the captured cyan HUD/material defect; do not
change hold semantics solely to accommodate the short automation gesture.
[Probe evidence](XBOX-SIMULATOR-PASSES.md#build-73-scoreboard-read-only-observation-2026-10-02).

**Scoreboard input bridge (2026-10-02).** Xbox Scoreboard now supports held
vertical drag via paired Page Up/Down inputs; shared PC controls stay unchanged.
185 Xbox tests and 141 native overlay assertions pass. Installed build-73
candidate `39f06f77…7198e` produces four paired page events from an actual drag;
camera/weapon stay unchanged and subsequent Fire works. Captured frames do not
establish visible scoreboard response, and the local roster has only two players.
The follow-up probe above narrows hold consumption; paging acceptance remains open.
Saves/preferences/PC registry preserved; ordinary picker restored; pin stays 66.
[Evidence and limits](XBOX-SIMULATOR-PASSES.md#build-73-scoreboard-touch-bridge-2026-10-02).

**Build 73 candidate (2026-10-02).** Frozen upstream `d1c7243c` builds with the
existing counted ANGLE adaptation and is installed on the dedicated Simulator.
Menu/a10/scripted-match smoke passes; copied build-66 checkpoint loads, shared
Fire/Look/Pause and Save and Quit work, and cold normal-menu reload succeeds.
Accepted lock stays build 66: unadapted acceptance and the new scoreboard remain
open. Source review finds no touch route for its wheel/Page Up/Down pagination;
network protocol changes from 9 to 10. A cyan vertical HUD artifact is captured,
not fixed or attributed to this upgrade. Original saves/preferences/PC registry
preserved. Candidate and rollback copies remain private; ordinary picker restored.
[Evidence and next gates](XBOX-SIMULATOR-PASSES.md#build-73-candidate-upgrade-2026-10-02).

**Normal-menu save/reload (2026-10-02).** Current counted build-66 candidate
loads a copied build-64 New001 checkpoint through the picker and normal menus.
Shared fire/look/pause/menu controls work; Save and Quit completes and a cold
process restores the outside-pod checkpoint. This closes that bounded existing-
profile gate, not fresh-profile creation, new progression or all-version save
compatibility. Original saves/PC state preserved; no runtime changes. Graphics
fidelity remains open. The misleading profile summary is explained by upstream's
deliberate unlock-all flags, not an unexplained save failure; see the earlier
[profile analysis](XBOX-SIMULATOR-PASSES.md#upstream-profile-summary-and-xbox-touch-focus-loss-2026-10-02).
[Evidence](XBOX-SIMULATOR-PASSES.md#counted-candidate-normal-menu-savereload-2026-10-02).

**Water reflection trace (2026-10-02).** Actual b30 trace identifies the water
reflection draw, four-level ripple target, -0.6 LOD bias and stage-3 cubemap.
Generated reflection-vector math agrees with the NVIDIA specification; no
justified shader fix yet. Ninety-second diagnostic run passes. Next is a matched
material/reference comparison, not more mip/expression existence checks.
[Evidence and limits](XBOX-SIMULATOR-PASSES.md#water-reflection-consumer-trace-2026-10-02).

**Water mip readback (2026-10-02).** New bounded, opt-in diagnostic finds a
complete changing 128/64/32/16 mip chain consistent with the water ripple
composite. Two-frame readback restores checked GL state and reports zero errors.
This rejects missing/frozen levels in those samples, not incorrect shader use
or appearance. 184 tests, full app build, two-minute b30 and observer-off menu
smoke pass. Next inspect the consuming shader/material or matched reference;
no new rendering fix or upstream pin change.
[Evidence](XBOX-SIMULATOR-PASSES.md#water-mip-chain-readback-2026-10-02).

**Beach material route (2026-10-02).** Harness now supports Silent Cartographer;
actual three-minute b30 run passes and reaches beach/ocean views. Water, shoreline
bands and translucent exhaust are visible, not fidelity-accepted. Source review
points the next focused check at generated water ripple mip levels, not another
terrain-filtering change. 181 Xbox tests pass; original saves, preferences and PC
registry preserved. Runtime/pins unchanged; no new graphics fix claimed.
[Evidence](XBOX-SIMULATOR-PASSES.md#beach-material-reproduction-route-2026-10-02).

**Geometry and night-scene follow-up (2026-10-02).** Six-minute stationary
Blood Gulch run verifies a fully in-viewport light hidden by the foreground
weapon (0/36 samples) and revealed again (25/25). This extends coverage evidence
beyond viewport clipping, not to BSP-wall or overall graphics acceptance.
a50 campaign smoke passes 120 and 300 seconds; manual shared controls verify
2x/10x/unscoped cycling and night vision on/off. Normal-menu resume from debug
saves remains unverified because they lack a named player profile. No runtime
change this pass. Original-quality picker restored; saves, Library, preferences
and PC registry preserved except the known Documents log. Next inspect another
material or wall-occlusion case; broader texture fidelity and sustained touch
feel remain open. [Evidence](XBOX-SIMULATOR-PASSES.md#in-viewport-light-occlusion-and-night-scene-follow-up-2026-10-02).

**Counted guest integrated (2026-10-02).** Explicit Simulator-only
`render-visibility-v1` pairs the guest with the counted backend and preserves
ordinary GLES boolean results. In-game Blood Gulch sun tests now return full,
partial and zero coverage: 2601 / 406 / 0 samples at Original; a corresponding
narrow edge slice returns 1624 at Sharper (2x dimensions). Reflections fade and
return at the viewport edge. 181 Xbox tests and 36 native launch/save/quality
checks pass; this is a specific coverage fix, not overall graphics acceptance.
Broader texture/shading issues, matched reference images, BSP-wall occlusion and
physical touch feel remain open. Upstream pin/default policy unchanged.
[Integration evidence](XBOX-SIMULATOR-PASSES.md#counted-guest-integration-2026-10-02).

**Counted backend candidate (2026-10-02).** An isolated ANGLE candidate now
returns exact visible-pixel counts through a private bridge, while ordinary
GLES queries remain boolean. 56 actual Simulator GPU cases pass across both
verified render-pass accumulation paths, including the measured sun-edge
rectangle (928 pixels), depth occlusion, query reuse and 2x target dimensions.
177 Xbox Python tests pass. This is not yet connected to the Xbox guest or
installed in HaloPad at that stage, so no in-game graphics fix was claimed. Next was to wire an
explicit, separately identified guest/backend capability and validate scale
normalization plus the same Blood Gulch view.
[Evidence](XBOX-SIMULATOR-PASSES.md#counted-metal-backend-candidate-2026-10-02).

**Measured flare coverage loss (2026-10-02).** Opt-in rectangle/result observer
correlates the Blood Gulch sun with an actual test rectangle: at most 27.6% lies
inside the viewport, but the ES boolean fallback still drives full target
visibility. Fully outside returns zero. This establishes a specific fidelity
limitation, not the cause of all shading/texture defects and not a fix. 174 tests,
full combined build and five-minute Simulator smoke pass. Next is a separately
identified counted-visibility candidate, not further aggregate tracing.
[Measured evidence and limits](XBOX-SIMULATOR-PASSES.md#sun-visibility-rectangle-measured-2026-10-02).

**Blood Gulch visual follow-up (2026-10-02).** Three- and five-minute isolated
match smoke checks pass. Manual background free-look reveals a sun flare and
reversibly moves it across the viewport edge without firing. This establishes
a specific visual test route, not incorrect brightness or a fix for texture
popping. Capture its actual query rectangle/result or a matched reference next.
No runtime/pin change. Returned to Original-quality picker; original saves,
PC registry and preferences unchanged. [Evidence](XBOX-SIMULATOR-PASSES.md#blood-gulch-sun-flare-reproduction-route-2026-10-02).

**Visibility-path investigation (2026-10-02).** New bounded, disabled-by-default
query observer confirms boolean visibility results during the copied a30 run:
11,866 zero and 103 one result reads, none above one, across 180 summaries.
These are API reads, not pixel counts or individual-flare attribution. Source
review confirms ANGLE Metal uses boolean visibility and Halo maps positive
results to a saturated flare target. This is a narrower fidelity limitation,
not a demonstrated cause of general texture/shading defects. No rendering
behavior changed. 172 tests pass; installed executable `5a677b38…2d73201e`,
Original selected, trace disabled after the pass. Saves/PC registry/settings
preserved except last-engine choice. [Evidence](XBOX-SIMULATOR-PASSES.md#boolean-visibility-observation-2026-10-02).

**Xbox graphics choice (2026-10-02).** Quality-adapted personal builds now offer
Original or Sharper (Preview) below the edition cards. Original stays default;
Sharper selects 2x resolution and 4x world filtering only for Xbox. Actual
Simulator UI verifies Cancel, About/Done, both cold-persisted choices and copied
a30 launches: 640x480/1x versus 1280x960/4x, without development quality overrides.
Windows routing reaches its license screen, left unaccepted; no PC gameplay
claim. 170 Xbox tests and 35 Simulator launch/save/quality assertions pass.
Original saves and PC registry preserved; only the intended quality preference,
last-engine selection, logs and OS snapshots differ. Preview app remains installed
at the picker with Original selected (`92db1be7…88e8a7e`); upstream pin unchanged.
[Evidence and remaining gates](XBOX-SIMULATOR-PASSES.md#player-facing-xbox-graphics-choice-2026-10-02).

**World filtering candidate (2026-10-02).** New opt-in `render-quality-v1`
adds bounded world anisotropy to the reproducible resolution experiment, without
changing the accepted upstream pin. Fixed-view a30 comparisons at 1x/4x/16x
filtering, all at 1280x960, show more ground detail at 4x/16x but continued
softness on some slopes. Shared fire/drag, swap, scope, grenade and pause respond.
170 tests pass, including compiled filtering exclusions and GPU-limit checks.
Not a shading/popping or hardware-performance acceptance; defaults stay unchanged.
Default app restored and signed/installed hash verified (`eb1e2fb0…af1f66f`);
original saves, preferences and PC registry preserved.
[Evidence](XBOX-SIMULATOR-PASSES.md#world-filtering-on-the-accepted-guest-2026-10-02).

**Reproducible guest adaptation (2026-10-02).** The private 2x experiment is now
an explicit `render-scale-v1` build option, separately identified from the
upstream pin. Exact renderer-input checks reject upstream drift; packaging
rejects unrequested/stale adaptations and pin promotion requires an unadapted
guest. Actual adapted and default builds reproduce their previous guest hashes,
leaving the upstream checkout clean. Copied a30 campaign at 1280x960 verifies
menus, drag-fire, swap, scope and pause. 167 Xbox tests and 26 actual Simulator
launch/save-helper assertions pass, including backups on same-pin guest changes
and rollback. Default guest/app restored (`c54e09c6…cf5e608`), real saves, PC
registry and preferences preserved. Effects/material fidelity remains open;
2x is not a default. [Evidence](XBOX-SIMULATOR-PASSES.md#reproducible-guest-adaptation-and-exact-save-identity-2026-10-02).

**Scaled depth gate (2026-10-02).** The opt-in depth observer now verifies actual
attachment dimensions and supports bounded scaled targets. Real 2x and 1x
Blood Gulch captures pass calibrated readback, same-frame geometry/projection
and state-restoration checks; EQUAL draws correctly leave depth unchanged.
151 Xbox tests pass. Native color/raster replay remains explicitly 640x480-only.
This validates selected draw pairs, not all graphics. Accepted build 66 restored;
2x stays private/experimental pending a reproducible adaptation and effects checks.
[Evidence](XBOX-SIMULATOR-PASSES.md#scaled-depth-observation-verified-in-game-2026-10-02).

**Resolution experiment (2026-10-02).** Private 2x guest experiment proves
1280x960 source targets/viewport against 640x480 baseline, on the same copied
a30 view. Geometry/HUD are sharper; sloped ground remains soft. Matching scopes
stay centered; pause and touch actions respond. Not promoted: depth diagnostics
still assume 640x480 and Android visibility counting needs separate review.
Accepted build 66 restored, original data audited intact; executable now
`2d563e96…734cd8d`. Experimental app/source identity and comparisons are preserved
privately. [Evidence and next gate](XBOX-SIMULATOR-PASSES.md#actual-2x-render-target-experiment-2026-10-02).

**Xbox menu clarity (2026-10-02).** Shared gameplay buttons now carry A/B/X/Y
badges and accessibility hints; an Xbox Controls guide explains menu navigation
and the required Default guest profile. PC presentation and all input mappings
stay unchanged. 134 native assertions (including 270 layout combinations) and
145 Xbox tests pass. Simulator verifies guide/Done, A/B navigation, copied a30
gameplay, fire/drag, swap, scope, save/quit and cold picker. Original saves,
PC registry and preferences preserved. Installed executable `077ca7c9…9f57c52`.
No texture fix claimed; higher render resolution is the next graphics experiment.
[Evidence](XBOX-SIMULATOR-PASSES.md#xbox-menu-labels-on-the-shared-overlay-2026-10-02).

**Build 66 and texture investigation (2026-10-02).** Accepted guest pin advances
to `f2ba71d9` after all six Mac/Simulator cases pass. A rejected intermediate
run exposed a single-frame cinematic-fade false negative; the campaign check now
retains late complete frames and requires two visible samples. 145 Xbox tests
pass. Full combined app, not the PC scene fixture, reloads the copied a30
checkpoint through normal picker/menus; fire-and-drag, swap, 2x zoom, pause and
Save and Quit work. Executable `e47cd803…dd4fb31` matches the installed app.
ANGLE still makes this a preview; accepted guest does not mean fidelity accepted.
An isolated unmerged PR35 comparison at 1x/16x filtering shows more ground detail
at 16x, but substantial 640x480 softness remains. No shading/popping fix claimed;
the experiment is preserved separately, not included in the accepted pin.
[Update evidence](XBOX-SIMULATOR-PASSES.md#build-66-repeatability-and-campaign-capture-2026-10-02).

**Shared controls, Simulator (2026-10-02).** Combined Xbox now uses the existing
PC `HPOverlay`, including sticks, fire-and-drag aim, layout and touch settings.
A small Xbox adapter preserves independent Use/Reload ownership and cancels
input on interruption. 128 native overlay checks and 143 Xbox tests pass. Actual
normal-menu a30 gameplay verifies drag aim/fire (rifle 60 to 59), movement, swap,
zoom, pause, settings/Done, Save and Quit, cold chooser and checkpoint reload.
Real Documents game/save files, PC registry and preference values remain unchanged.
Guest build 64 and ANGLE preview remain unchanged for this control baseline.
Xbox menu-aware labels, remapped Xbox profiles, sustained multi-touch and texture
fidelity remain open; internal rendering still reports 640x480. No hardware work.
[Pass evidence](XBOX-SIMULATOR-PASSES.md#shared-pc-and-xbox-overlay-2026-10-02).

**Physical hardware follow-up (2026-10-02).** Chris authorized the shared iPad.
The current-source ANGLE preview is provisioned for the exact M2 iPad Pro and
installed in place after complete Documents/Library backup and independent
byte-identical readback (320 files, 3,348,625,943 bytes). Source ad-hoc app is
preserved; signed staged executable is `90437ca6…06362e`, installed metadata
verified. Actual picker/About → Xbox → fresh isolated profile → Normal → a10
cinematic/cryo bay works. The physical log confirms 4 GiB guest allocation,
Apple M2 ANGLE/Metal automatic features and 48 kHz stereo output setup.
Sampled cryo floor/walls lack the earlier Simulator's large black floor polygons;
this is not a matched hardware/reference comparison or a shading/focus fix.
A short capture with explicit iPad audio has non-silent stereo, not speaker/
audio-quality acceptance. Sustained/direct-finger/controller play remains open.
Original Xbox saves are not opened; launch uses a fresh isolated save root.
Post-run readback preserves all 151 protected original Documents files, PC
registry and preference dictionary; reviewed config/log/test-save/cache changes
only. Physical app remains at the cryo-bay look tutorial for direct-finger testing.
No PC gameplay, upstream promotion, Xbox IPA, pairing, push or publication.
[Hardware evidence](XBOX-SIMULATOR-PASSES.md#physical-ipad-angle-preview-2026-10-02).

**Historical blocked audit (2026-10-02; hardware authorization now resolved).** After the current-source device rebuild, three
consecutive audits cannot advance the remaining physical requirements without
confirmation that the shared iPad is available. No live build/job is being
waited on. Checkout remains clean before this record; prepared device executable
still hashes to `af1be628…0dc436`. Prior audit verifies unchanged Simulator
executable and all 121 retained save-backup checksums, not new gameplay.
Repeated Simulator checks cannot close physical graphics/audio/controller or
reported shading/focus acceptance. Resume with a coordinated hardware window;
identify the affected edition/map, validate real provisioning, preserve and
read back Documents/Library, install in place, then test the exact candidate.
No physical action, IPA, publication or claim that the full goal is achieved.

**Earlier device-SDK readiness (2026-10-02; installed in the follow-up above).** Rebuilt the experimental combined
iPhoneOS app from `68cb779`, including the touch-owner fix. Executable
`af1be628…0dc436`, device Xbox archive `341f6c0d…134702`: actual SDK, source,
guest identity, automatic hardware features, iOS 17.0 load command and strict
ad-hoc signature checks pass. No profile, IPA or installation. The old device
archive is preserved and correctly rejected as stale before the rebuild.
Simulator app remains unchanged. The picker starts only the chosen engine.
Physical acceptance still requires a coordinated window, matching provisioning,
full data backup/readback, and observed graphics/audio/controller behavior.
The existing install helper does not perform that backup. Reported physical
shading/focus remains unresolved; edition/map clarification is still needed.
[Readiness evidence](XBOX-SIMULATOR-PASSES.md#current-source-device-readiness-2026-10-02).

**Touch-owner fix (2026-10-02).** Two fingers sharing RT or A previously lost
the held action when either finger released. Actual UIKit-handler fixture fails
two of 24 checks before the minimal last-owner release fix; all 24 pass after,
including independent move/look, cancellation and controller hiding. All 143
Xbox Python tests pass. Rebuilt combined app `3a933fea…95e8a` is installed in
place on the dedicated Simulator after app/full-data backup and byte comparison.
Actual normal-menu copied outdoor checkpoint and single RT 60→59 verified;
ordinary picker restored PID 74408. Real Xbox/PC files and registry preserved;
only last-edition preference/log/system snapshots change. This is not OS-level
simultaneous gesture, physical-controller or graphics acceptance. Device preview
was stale at that pass; the readiness pass above rebuilds it. No
physical operation, pin move or Xbox IPA. [Evidence](XBOX-SIMULATOR-PASSES.md#shared-touch-button-ownership-2026-10-02).

**Latest-source Simulator integration (2026-10-02).** After the device-SDK
build pass, rebuild the normal one-picker app from `84547a5` and install in place
only on the dedicated Simulator, after full app/data backup and byte comparison.
Installed executable is `96e8c317…fa652`. Actual picker/About/Done, Xbox normal
menus, copied outdoor a30 checkpoint, finite touch look, weapon swap, 2x scope
and Save and Quit work. Retain a 62-second video, not sustained-control or
moving-image fidelity acceptance. Ordinary Windows route verifies its existing
installation and stops at the original EULA, left unaccepted. Final ordinary
picker PID 67405. All real game/save/package files and PC registry remain
unchanged; final preferences match, ordinary caches/snapshots/logs differ.
No physical operation, new pin, rendering-fix claim, IPA or publication. Goal
active; [integrated evidence](XBOX-SIMULATOR-PASSES.md#latest-source-integrated-simulator-runtime-2026-10-02).

**Device-SDK renderer preview (2026-10-02).** The independently pinned ANGLE
preview now builds separately for iPhoneOS and Simulator. Actual SDK identity
and per-platform feature overrides are checked before packaging; physical builds
use automatic features, never the Simulator-only swizzle override. The first
device build fails on a Simulator diagnostic call, now guarded correctly.
Standalone host and combined app target iOS 17.0. Combined personal device app
`259fb98f…f90cd` passes ad-hoc signature, IOS load-command, bundled guest/manifest
and no-new-IPA checks. It is **not installed or provisioned for device acceptance**.
The Simulator library is rebuilt separately; its asset-free equal-depth/blit/
swizzle checks pass, as do 143 Xbox Python, 16 UIKit and 20 launch-helper checks.
Installed Simulator app `e594a1f9…15feed` remains unchanged; game files/saves,
preferences and PC registry survive. Upstream/renderer pins unchanged. No
physical operation, graphics-fix claim, IPA, push, publication or cleanup.
Next properly provisioned, backed-up hardware validation under a coordinated
window, plus matched affected/reference rendering; broader goal remains active.
Evidence: [device-SDK pass](XBOX-SIMULATOR-PASSES.md#device-sdk-angle-preview-build-without-installation-2026-10-02).

**Update-backup follow-up (2026-10-02).** The maintenance routine no longer
ignores checksum failure, reuses a second-resolution backup folder, trusts an
uncompared save copy or assumes an unreadable Simulator container has no saves.
Each attempt gets a unique folder; Mac/Simulator copies must match their source,
and checksum creation/readback must succeed before a candidate build. Frozen
baseline fails five of nine controlled shell tests; fixed source passes all
nine, including empty saves, refusal before candidate actions and gated pin
acceptance/rollback. Git/build/device boundaries are inert, not real promotion.
A backup-only execution against the actual Mac/dedicated Simulator saves verifies
121 file checksums. Final ordinary app PID 25509 shows both cards; app/guest/
library/pin unchanged. Game/disc/package bytes, preferences and PC registry remain
preserved; only ordinary log/system snapshots change against the retained backup.
All 137 Xbox Python tests pass. No upstream promotion, app build/install,
physical operation, visual fix, IPA, push, publication or cleanup. Backups do not
establish upstream save compatibility or atomic copies of a running game.
Evidence: [maintenance backup pass](XBOX-SIMULATOR-PASSES.md#update-routine-save-backup-failure-gates-2026-10-02).

**Launch-path follow-up (2026-10-02).** Empty `XG_DATA`/`XG_SAVE` no longer
select an empty development path or skip revision-change save backups. Nonempty
development paths remain supported. New asset-free native helper fixture
reproduces the baseline failure, then passes 20 checks after the three-condition
fix: exact synthetic save-copy bytes, same-pin no-op, isolated marker behavior,
failed-copy refusal and retry. These are real Foundation helper operations,
not gameplay or OS failure coverage. Integrated app rebuilt and installed in
place only on the dedicated Simulator; executable `e594a1f9…15feed`.
Actual empty-variable launch shows Play Xbox; About/Done and ordinary Windows
route work, the latter stopping at the unchanged unaccepted EULA. Final ordinary
launch shows both cards. No Xbox runtime opens real saves. Full audit preserves
all game/disc/package bytes, preference dictionaries and PC registry; normal
log/system snapshots change. 128 Xbox Python, five input-guard, 13 package,
20 launch-helper and 16 UIKit checks pass (16 package checks skipped). Frozen
build 64 and renderer unchanged. Physical shading/focus remains unresolved;
no physical operation, IPA, push, publication or cleanup.
Evidence: [launch-path pass](XBOX-SIMULATOR-PASSES.md#empty-launch-overrides-and-revision-backup-regression-2026-10-02).

**PC live material arithmetic (2026-10-02).** A private Simulator component
probe replays the exact Battle Creek ground draw into independent float targets,
capturing actual texture samples/interpolated inputs and the unmodified pixel
shader output. An independent original-bytecode interpreter matches all
1,396,060 covered pixel observations across three frames exactly. Actual coverage
has base alpha one and fog off; other blend/fog paths are not gameplay-tested by
this sample. The grain remains visible, including in the detail samples. This
weakens color-arithmetic failure for this particular material, not sampling,
geometry/depth or the unresolved physical shading/focus report. First linked
run spawns indoors and fails the exact-material capture gate; preserve it.
Successful run passes 24 assertions and retains all 30 motion frames. Analyzer
calibration and five malformed-capture controls pass. No tracked runtime edit,
app installation, pin change or physical operation. Ordinary app resumes at
the same PID; installed executable, real Xbox/PC game files, preferences and
PC registry remain unchanged. Next obtain a matched original-driver/affected
scene comparison rather than add a speculative filtering workaround.
Evidence: [live material pass](XBOX-SIMULATOR-PASSES.md#pc-live-ground-material-arithmetic-2026-10-02).

**Xbox focus-loss follow-up (2026-10-02).** Upstream build 64 deliberately
sets all ten new-profile level flags to `0x0f`; its summary interprets these as
The Maw/Legendary. The isolated New001 bytes and creation log match that code.
No profile rewrite or retail progression claim. A separate UIKit handler test
reproduces six focus-loss failures before the fix. The Xbox pad now clears live
and unread touch input on deactivation/activation, refuses inactive or hidden
presses and requires fresh touches after resume. Sixteen handler checks pass,
including ordinary short Start taps. Rebuilt integrated executable
`58111bcb…29f093` loads the copied outdoor a30 checkpoint through normal menus;
actual Home/resume retains PID 91997 and logs both resets. Fresh RT, Y, Zoom,
finite look/move and pause/Save and Quit work. This is not OS-held multi-touch,
hardware controller interruption or physical graphics proof. All 114 real Xbox
files and PC installation/package/disc bytes remain unchanged; preferences and
PC registry match the backup. Normal logs/caches change. The ordinary app is
left at both edition cards; PC still reopens its unaccepted EULA. Frozen build
64 and ANGLE PREVIEW remain unchanged. 128 Xbox tests, five input guards and
13 package checks pass (16 package checks skipped), plus 16 native UIKit checks.
No physical iPad operation, visual fix, IPA, push or publication.
Evidence: [profile and lifecycle pass](XBOX-SIMULATOR-PASSES.md#upstream-profile-summary-and-xbox-touch-focus-loss-2026-10-02).

**Disc-import follow-up (2026-10-02).** The actual native extractor now bounds
directory/map sizes and extents, rejects unsafe names/cycles/aliases and invalid
map headers before copying, and uses unique staging plus exclusive publication.
Existing maps/saves and failed stages are never overwritten. The first UI test
exposed an older linked Xbox archive; the app builder now rejects missing or
changed local runtime-source hashes. Rebuild the library, not its manifest.
Corrected integrated Simulator executable `5ea1369d…5768df9` rejects the malformed
image, returns to Editions, imports Chris's USA disc through Files, and produces
24 maps byte-identical to the reference. Fresh New001 creation, Normal a10 opening
cinematic and cold menu/profile recognition work in isolated folders. The fresh
profile summary says The Maw/Legendary; the follow-up above explains the deliberate
upstream unlock flags, not retail completion. Windows reopens the original unaccepted EULA. Ordinary
launch is left at both edition cards. All 114 existing Xbox files and existing
PC files are unchanged; normal logs/caches/preferences change. 128 Xbox tests,
five input guards and 13 package checks pass (16 package checks skipped).
ASan/UBSan finds no error in the real-disc copy or 104 bounded synthetic cases.
No physical iPad operation or rendering fix, pin update, IPA, push or publication.
Detailed evidence and limits: [disc-import pass](XBOX-SIMULATOR-PASSES.md#native-disc-import-validation-and-stale-library-gate-2026-10-02).

**Renderer comparison at build 61 (2026-10-01).** A correctly source-built,
separately pinned ANGLE/Metal Simulator preview now runs the same Xbox build 61.
Its first scenes remove the pronounced horizontal wall bands but reverse red
and blue. An asset-free sampling test reproduces that: ANGLE's Simulator default
ignores the guest-required texture swizzle; its native-feature override passes
sampling, equal-depth and blit controls on this Mac/iPadOS 26.5. The candidate
alone enables that feature. The rebuilt campaign and Blood Gulch images have
restored colors and no pronounced cliff bands in the reviewed views. Normal
menu/campaign/scripted-match checks pass (1,530 ticks, 12 shots), not full visual
acceptance or a matched-camera driver diagnosis. Apple remains the default;
that comparison held the Xbox guest fixed; physical Windows/Metal rendering is unchanged. The
physical iPad's reported shading/focus instability is still open. A follow-up
loads identical copied cryo-bay checkpoints through normal menus: Apple shows
large black floor polygons; the preview draws that floor in the untouched view.
Both use 640x480 guest rendering; NPC/prompt timing differs, so this is not a
frame-synchronized driver diagnosis. Preview four-direction look, tube exit,
short forward input, Save and Quit and fresh-process checkpoint reload work
with isolated saves. Reload returns to the last checkpoint inside the tube,
not the unsaved exit position. A later normal-menu pass now loads Halo/a30 into
the escape pod: two RT taps reduce rifle ammo 60→58, Y swaps to the pistol, and
Save and Quit completes. A fresh process identifies Halo as in progress and
restores its pod checkpoint (rifle 60, not the unsaved shots/pistol). A separate
90-second, explicitly scripted a30 rendering diagnostic reaches the outdoor
valley, changes the viewpoint and fires; reviewed terrain/tree/ring images lack
the pronounced bands. These are sampled views, not temporal or physical visual
acceptance. The smoke tool now supports a10/a30 and fails closed on accidental
scripted campaign inputs. Continue sustained human motion, simultaneous controls,
new checkpoint progression and moving-image checks before adopting the
candidate more broadly. See the pass ledger for failed first attempts and
source/probe provenance. No physical install, IPA or publication.

**Accepted experimental upstream update (2026-10-02): build 64, `c55e4e2b`.**
Frozen four-commit update adds expanded HUD/scopes, meter alpha and widescreen
flat menu fills. Candidate and guarded acceptance rerun both pass source-built
Mac and ANGLE Simulator menu/a10/scripted-match gates (acceptance 1,530 match
ticks, 12 shots). A copied build-61 a30 checkpoint loads through normal menus;
RT fire, Y pistol swap, circular 2x Zoom and pause/Save and Quit work. A fresh
process recognizes Halo in progress and restores the pod checkpoint with rifle
60. Real saves remain separate, and the outgoing app/save backups are retained.
The unreviewed texture-cache byte diagnostic remains rejected by an explicit
build-64 test. Menu/pod `top` snapshots are 145M/172M, not physical footprint,
build-61 memory comparison or iPad acceptance; `vmmap` failed. ANGLE remains an
independently pinned opt-in PREVIEW; Apple remains default. Sniper fringe/meter
coverage beyond the sampled scopes, sustained human motion, new checkpoint progression, temporal fidelity
and physical Windows shading/focus remain open. No physical install or IPA.

**Night/sniper follow-up (2026-10-02).** Build 64 remains frozen; a live remote
HEAD check still matches `c55e4e2b`. The runner now also accepts a50. A bounded
90-second scripted a50 rendering diagnostic passes with ANGLE identity,
presentation captures and all 69 HUD replacements. Video retained; sparse and
12 fps contact-sheet samples show weapon/reload and shield-damage effects, not
full continuous-motion acceptance. Actual normal-menu a50 play separately
verifies 2x/10x scope and night vision. Scope ladder/border have no obvious
missing sections in the reviewed views, largely aimed at the ground. Save and
Quit completes; a fresh process recognizes Truth and Reconciliation in progress
and reloads its opening checkpoint, not a newly reached later checkpoint.
103 Xbox tests pass; real saves still match both backups. The physical iPad
shading/focus report remains unresolved; no renderer fix or device install here.

**Audio signal coverage (2026-10-02).** The previous Simulator videos have no
audio track. A new opt-in Simulator-only callback capture skips ten seconds and
retains four seconds of HaloPad's own output. Source-built one-app build 64/ANGLE
menu and normal-input a50 launch both deliver finite, non-silent 48 kHz stereo:
RMS 0.1805/0.1066, peak 0.8450/0.6093, no sample starvation or excursions outside
±1 in these windows. It does not record other apps, establish audible quality,
callback deadlines or sync. Native bounded-buffer and invalid/silent-capture
tests bring the Xbox suite to 109 passing tests. No physical app was changed.
The physical shading/focus report remains open; a separate PC source inspection
finds explicitly ignored mipmap LOD bias, not evidence that this caused the report.

**PC focus lead checked (2026-10-02).** The fresh-state macOS PC Blood Gulch
component run renders first-person play and exits normally. New sampler fields
in the existing bounded draw trace show zero LOD bias in all 932 bound-sampler
observations across 248 draw requests in frames 300–301. Thus the ignored-bias
gap is not active in this sample; it is not the established cause of the iPad
report. No sampling/depth/shader workaround adopted. The baseline first failed
to link because shared touch cancellation references a missing Mac input API;
restored synchronous AppKit/Halo-main-thread delivery (iOS queue unchanged).
All 264 native input checks pass through that actual host API. No physical or
Simulator install in this pass; moving views and the affected edition/scene
still need matching evidence.

## Latest engineering and device results

**Earlier frozen Apple-backend passes (2026-10-01).** The launch picker clearly separates
Windows Custom Edition 1.10 from Xbox Combat Evolved, with edition-specific
multiplayer descriptions, an installed-build panel, accessible text and a safe
return from disc import. Short Xbox touch taps are latched until the engine polls
them; short analog swipes and triggers are now retained for one poll as well.
Upstream build 61 (`f8937c61`) is the accepted experimental development pin after
save-backed Mac and Simulator menu/campaign/scripted-match gates. It adds the
upstream high-resolution HUD after build 60's menu-glyph edge fix. The earlier build-59 real touch pass reached
cryo-bay training and exited the tube; Save and Quit followed by a cold relaunch
reloaded its checkpoint. A copied build-59 checkpoint also loads in build 60
through the normal menus; a copy of that fixture also reloads the cryo-bay in
61, without modifying real Simulator saves. Campaign's black presentation was narrowed to the
software blitter inheriting texture-unit/sampler state: neutralizing unit 0 during
the final blit restores the picture. The normal build now shows the opening
cinematic; physical rendering and internal texture copies are unchanged. An A/B
pass reproduced the original failure on the older pin, so it was not newly
introduced by build 57/58. Full campaign progression, visual artifacts, audio,
split-screen, human system link and hardware acceptance remain open. Artifact
captures locate the remaining defect before final presentation; uniform-array
and synchronized-buffer experiments did not resolve it. Disabling anisotropy
and changing equal-depth passes to LEQUAL also leave stripes. An ALWAYS-depth
diagnostic changes artifacts but draws hidden surfaces; it is not adopted for
normal rendering. New stationary diagnostic runs stop scripted movement/shooting,
but different spawns prevent a matched cross-launch comparison. A same-process
EQUAL → ALWAYS → EQUAL test now removes and restores the stripes at a fixed
camera position. Basic asset-free EQUAL redraws pass all 6,728 pixels within and
across programs; the precise converted-shader/depth-state cause remains open.
A read-only VS17/VS41 snapshot now proves identical indexed position inputs and
projection constants for a 144-index terrain pair. Replaying those shaders with
transform feedback produces bit-identical clip coordinates for all 144 vertices.
Replay changes linkage and omits pixel/texture state, so this does not prove
original-program invariance or establish a driver bug. The stripes remain in the
capture run. A larger 1,257-index pair also has exact position/projection identity.
Unmodified shader sources and original indexed layouts now pass isolated depth
rasterization: all 145,994 pixels survive EQUAL on texture-backed targets, with
passing same-program and ALWAYS controls. Full scene state/intervening depth
writes remain a target; a fixed-view stencil bypass did not resolve stripes.
Expanded live captures verify the same framebuffer/color/depth objects for both
draws. Opt-in level-0 readbacks now match the CPU upload bytes for every captured
2D texture with a supported upload reference (1,755-index pair, GL error 0).
This excludes upload/storage corruption for those textures, not incorrect Xbox
decoding, UVs, mipmaps, cube sampling or intervening depth writes. Raw texture
previews do not apply texture swizzles; atlas padding/bands alone are not proof
of corruption. A follow-up independent decode of the original Xbox bytes now
matches all 32,768 pixels of the same previously banded 256x128 RGB565 texture.
This validates its unswizzle/conversion stage, not the game's production of those
bytes or final sampling. The build-60 calibrated, same-frame depth observer measures
54,517 intervening depth changes; 21,611 base-changed pixels become closer.
All four observations restore without GL errors. This is not proof of bad
writes: legitimate occlusion remains possible, and the scene still has stripes.
Build-61 full native pixel replay now retains the original program/VAO, uniforms,
textures, blending and stencil state on private texture-backed targets. A
calibrated 1,944-index pair matches both its repeated replay and the real draw
byte-for-byte; copied live depth also matches. All 24,262 base-written pixels
with ALWAYS-only color response have later closer depth; none have unchanged
depth. This pair does not establish missing visible terrain. Next target the
later material draw that introduces a visible stripe. A same-frame before/after
timeline now identifies it: frame 120, draw 119, program 84, VS7 / pixel shader
`ps_0c014f79`, 402 indices, EQUAL. The wall is unstriped before and striped after
that draw. All 211 observed indexed/immediate draw pairs validate with GL
error 0. The diagnostic capture can now select VS7 rather than the default
VS41, with an explicit two-name whitelist. Three VS17/VS7 captures have exact
indexed position/projection identity and calibrated same-frame depth. However,
228- and 531-index samples have no measurable native color response, and a
1,686-index sample differs at 43 pixels in its native repeat/live checks. All
three full-pixel diagnostics are rejected. Transform-feedback replay of the
1,686 vertices is bit-identical, but changes linkage and does not establish
original-program invariance. Next select the visibly stripe-producing material,
correlating original before/after color with its texture/alpha inputs; a matching
shader name alone is not sufficient. No rendering fix is claimed.
The new one-frame material observer captures the exact VS7/`ps_0c014f79`
combination before and after its original draws. In a 211-draw trace, all 17
material pairs have unchanged sampled uniforms and level-0 texture bytes.
Draw 117 (402 indices) visibly introduces the wall bands; its two 16x16 linear,
clamp-to-edge textures also match CPU uploads. This excludes in-draw changes
and upload/storage corruption for those samples, not UV/sampling/depth faults.
An exact-count follow-up has a different spawn and no 402-index batch: its
paired/native depth test is failed, not passed. Independently, its 294-draw
trace validates 22 unchanged material pairs; draw 176 (1,377 indices) again
introduces wall bands. Attach the next native probe to the visible draw in its
own trace frame rather than assuming counts or spawns repeat. Runtime identifies
the Simulator backend as Apple Software Renderer; an independently built
Simulator ANGLE/Metal candidate remains a possible backend comparison, not an
established driver fix. Do not extrapolate this Xbox Simulator defect to the
physical Windows/Metal route.
A later 984-index VS41 native replay fails exact repeat/live-color checks and
remains rejected; it does not invalidate the independent read-only timeline.
Chris's reported physical
iPad shading/focus instability remains open and was not directly observed here.
These diagnostics have not changed
normal depth semantics; the upstream HUD update is a separate change.
Mac smoke runs now
reject mismatched executable/guest hashes. Candidates
are labeled **PREVIEW**; the accepted Xbox baseline still says **EXPERIMENTAL**.
No physical iPad changes in this pass. See [XBOX-SIMULATOR-PASSES.md](XBOX-SIMULATOR-PASSES.md).

[Build 61](https://github.com/cybersecurity/halo-ce-universal/releases/tag/build-61)
(`f8937c61`, published 09:40 UTC) passed candidate and acceptance runs before
promotion: all six cases each run, final acceptance Mac 2,130 ticks / 17 shots,
Simulator 1,358 ticks / 11 shots. Final accepted-app normal Simulator gates also
pass (1,348 ticks / nine shots). Frames and copied checkpoint reviewed; terrain
defects remain. Upstream cache/HUD/renderer changes now appear in the update
dependency report. The optional original-byte reader refuses 61's unreviewed
cache ABI; normal gameplay/update gates are unaffected. 123 tests pass with 16
skips, and both SDK syntax checks pass. No physical install, IPA or publication.
Final About/Done verifies accepted `f8937c61` and returns to the normal picker;
Windows card reaches its existing missing-data setup, not new Windows gameplay
acceptance. Real Xbox saves remain byte-identical to the acceptance backup.

**Second engine: Halo Xbox (2026-09-30).** HaloPad now opens with a choice of
Halo PC or Halo Xbox. The Xbox engine is upstream's decompilation port, pinned
and built on this Mac only as a personal build, translated to base-relative
ARM64 and run on a native iOS host. On the physical iPad it reaches its menu
and loads The Pillar of Autumn; on the Mac it also plays a system link match.
An iPad match remains unverified; missing packets did not establish its cause. Details, evidence
and the update routine: [XBOX-ENGINE.md](XBOX-ENGINE.md). The iPad now runs this
build (development scene for Halo PC, as before).

**Icon, stability and loading (2026-09-30).** New orbital-arc app icon (Chris's
pick). Renderer traps other than unknown texture formats now degrade and log
once instead of crashing. Shaders and pipelines compile in the background and
are remembered for the next launch; the worst map-load frame on the physical iPad
was 349 ms. A console-hosted benchmark hit Halo's "Your CD Key is invalid"
hosting check (the development scene has no installer-written product ID), so it
was withdrawn and its steady-state numbers are not claimed.

**Public-build pass (2026-09-29, midnight).** The repository is public.
`scripts/install-device.sh` now builds the tested `tests/halo_app_scene.c` and
no longer fails under macOS's stock bash when `--work` is omitted. The
diagnostic log adds controller poll results, Halo's controller-poll pause flag
and a one-minute health line. Held controller menu keys are released on
disconnect or focus loss, and bug reports attach the log. The iPad runs this build
(UUID 971874D9) at Halo's menu; hardware reproduction of the controller dropout
with the new log is still needed.

**Crash fix and diagnostics (2026-09-29, late).** Chris's iPad crashed repeatedly
while playing. Both crash reports (22:59, 23:04, stable-controller build UUID
987BE07F) were HaloPad's deliberate trap for a ninth texture/sampler
configuration of one pixel shader; the renderer kept at most eight. Pixel
shader variants now grow as Halo needs them. Every runtime trap now writes a
`CRASH:` reason to a persistent diagnostic log, `Documents/HaloPad Logs/HaloPad.log`
(Files app, or three-dot **Help → Share Diagnostic Log…**). It records only
changes: controller connect/disconnect, DirectInput acquire/release, Halo's
controller-to-player assignment, menu/game state, controller menu keys, video
device creation/resets, app activation and frame stalls over 300 ms with the
shader compiles inside them. No typed text, names, chat or addresses.
Controller fixes in the same build: the left stick navigates Halo's menus, A/B
accept/cancel the HaloPad text keyboard in a match (chat/console), and a
controller Halo later unassigns returns to its player slot. A trackpad pointer
over Halo's menus now moves Halo's own cursor to the same spot. Tests: menu
state machine 9/9 plus 72 original-x86 cursor routes, DirectInput and D3D9
Simulator suites 0 failures, overlay 0 failures, Python 59 OK (16 skipped).
The signed build is installed in place on the iPad after a backup to ignored
`generated/device-backups/ipad-20260929-pre-crash-fix/`; profile `Kahris`
survived and the app reached Halo's menu. The matching iPhone build is signed
but not installed. Gameplay acceptance of the crash fix, the controller
reconnect/touch-switch bug and trackpad alignment on hardware is still open.
Chris's live iPad trace showed steady ~30 FPS with first-use shader
compilation stalls (up to 1.15 s of compiling and a 1,038 ms gap in one 10 s
window). Earlier launches compiled the same match-entry shaders in under
10 ms total, which indicates the system shader cache, so a warm-up match on
the same map should reduce stutter in a recording; no code change for
compile stalls yet.

The current physical gameplay builds use `tests/halo_app_scene.c`, which enters
Halo's menu after setup for development testing. A diagnostic build using the
original entry point reached Halo's **Your product key is invalid** dialog.
Readback of the iPad registry before and after that in-place install confirmed
it had no installer-created `DigitalProductID`; the install did not erase one.
The playable development build was restored in place and reached a local match
with the existing `New001` profile. Its revised icon appeared on the Home
Screen. The full-startup product ID must be provisioned from a legitimate
original Halo PC installation and verified privately before release.

The physical iPad's first 10-second frame trace recorded one 456 ms gap while
the local map changed. The stable-controller candidate was then installed in
place after backing up its current `Documents` and `Library` to ignored
`generated/device-backups/ipad-20260929-pre-stable-controller/`. Existing
profile `New001` survived, and a local Battle Creek match reached first-person
play. The updated trace recorded a 454 ms gap on match entry, with 27 shader
libraries and 25 pipelines created in under 0.01 s reported aggregate time.
Steady intervals were about 30 FPS, usually with no >100 ms gap. This still
does not locate the work inside the stall. The stable slot passes DirectInput
Simulator tests; physical late-connect and resolution-reset acceptance remain
open. During the attempted physical test, iPadOS Bluetooth did not complete
pairing with the Xbox controller, before HaloPad could observe it. The user is
re-pairing the controller; this is not evidence for or against the gamepad fix.

Chris's physical iPad Pro 12.9-inch (6th generation, iPadOS 27.0) is connected.
Its exact development profile passed App ID, certificate, UDID and memory-entitlement
checks. The signed app was installed in place, imported the matching package, and
reached a local Battle Creek Slayer match. Its `Documents` and `Library` were read
back to ignored `generated/device-backups/ipad-20260929-first-import/`. Direct
touch/menu actions and Halo's pause/leave flow passed. Chris confirmed Xbox
controller movement and crouch after closing and reopening the earlier HaloPad
build with the controller already connected. On that earlier build, late
connection hid the touch overlay without registering gameplay input. The new
stable-slot candidate is installed, but its physical late-connect result is
still pending because the controller has not paired at the iPadOS level.
Chris reports iPad asset-load pauses and gameplay jitter. A 20-second live Time
Profiler trace is in ignored `docs/artifacts/2026-09-29/G11/`; it samples draw
and graphics-state work but does not establish frame-gap timing or the cause of
individual stalls. iPhone 14 sustained performance and a physical private-server
match are still open.

The signed source build is installed in place on Chris's connected iPhone 14;
the imported 87-file package and existing app data were preserved. Mirrored
primary pointer clicks navigate Halo's menus. A new `TouchQA` profile was
created with the native keyboard and **Enter / Accept** action. A local LAN
Battle Creek Slayer match started; **Open Leave Game Menu…** opened Halo's
pause menu, and its **Leave Game** returned to the main menu. The Controller
Guide and look-speed controls opened. The intended app icon was returned by
CoreDevice and appeared in the phone's suggestions. Real two-thumb feel and
controller acceptance still need hands-on testing.

At 800 × 600, a stationary Battle Creek scene displayed about 30 FPS. A 30-second
Time Profiler trace had 9,791 CPU-sample ms, with `halopad_lookup` at 2,698 ms
and thread-yield/Sleep at 2,234 ms. This is a static view, not a sustained
gameplay or loading baseline. The first 1280 × 720 attempt exposed a stale
generated VA runtime import, then unsupported Windows language-bar COM creation
and an unissued D3D9 query. After rebuilding and fixing those calls, the latest
physical iPhone build reached Halo's widescreen confirmation dialog and rendered
a wider scene. Accepting that prompt and pressing **OK** on **Edit Profile
Settings** saved 1280 × 720: it survived an app relaunch. A local Battle Creek
match, pause menu, and Leave Game worked at that mode with momentary overlay
readings of 29–30 FPS. Sustained frame times and direct-finger mapping remain
unverified. Original aspect preserves geometry; Fill stretches the image. The
public README is prepared as a truthful draft; no public IPA or rights clearance
is claimed. No live public match is part of the current testing scope.

## Earlier handoff on this Mac

- The supplied private kit in ignored `ref/handoff/HaloPad-iPad-test/` contains an arm64 iPhoneOS app and matching prepared game package. Package verification passed: 87 records total, 78 stock. The original app/package were not modified.
- An ad-hoc converted **copy** under ignored `generated/simulator-probe/` launched on iPad Air 13-inch (M4) and iPhone 17 Pro Simulators, reached Halo's main menu, and the iPad started a locally hosted Battle Creek Slayer match through Halo's menus. FIRE reduced plasma-pistol charge 100→99. Touch controls were shown after disabling “Hide Touch Controls with a Controller” in this Simulator. This is a compatibility probe, not a source-built Simulator binary or hardware result. Native package suite: 16/16 passed, including a real-package import on the iPad Air Simulator.
- The old three-dot **Leave Game** action did not exit an iPad Simulator local-host match. The revised **Open Leave Game Menu…** action opened Halo's pause menu and returned to the main menu after Halo's own **Leave Game** on physical iPhone 14. Two-thumb gameplay and controller use remain unaccepted. See the latest journal and `docs/artifacts/2026-09-29/G11/`.
- At the earlier iPhone-only handoff, the iPhone was wired, paired, booted, and had Developer Mode enabled (iOS 26.6.2). On Apple Developer team `VKDH2T9UTF`, the explicit App ID had Extended Virtual Addressing and Increased Memory Limit enabled. Cached development profile `765efc99-dab7-49e0-b386-d847cc001315` (expires 2027-09-29) passed exact App ID, iPhone UDID, certificate, expiry, and both memory entitlements. The accepted 1.10 executable, four modules, stock files, and reference files were restored from the supplied private handoff package to ignored inputs with hash checks. The SRW/VA pipeline and fresh source build produced a signed iPhoneOS app and IPA, core `a40934eac9383796ba5bd566d2d8bc2e28f6f54c4396208ae7d7fb738006ac00`. Its matching 87-file package verified. Before in-place install, existing HaloPad Documents and Library were backed up. The source app and package imported through the physical iPhone Files picker and reached Halo's main menu; CoreDevice listed the game folder with 78 files. CrossOver and original installer/patch provenance remain unavailable here.
- A device-platform app was inadvertently installed over an existing iPad Pro M5 Simulator app while probing the kit. Its data container was not reset, but the previous app binary has not been restored; further testing moved to the fresh iPad Air Simulator. Do not use the iPad Pro installation as an accepted baseline.
- **D5 icon:** the first H/orbit icon compiled into the installed signed app; CoreDevice returned it on iPhone. A new geometric beacon icon is now in the editable SVG and checked-in 1024-pixel PNG. It has not yet been installed or visually checked on either device.
- **Pointer recheck passed:** iPhone Mirroring primary clicks now navigate Halo's rendered menus on the physical iPhone 14. Real-finger two-thumb play remains separate acceptance.
- **D1 signing preflight:** `device_profile.py` requires the exact App ID, a matching installed signing certificate, an unexpired development profile, both memory entitlements, and the intended device UDID before installation. Separate cached profiles passed this gate for iPhone 14 and the connected iPad Pro.
- **D2 iPhone Simulator progress:** on an uncontended iPhone 17 Simulator, the fresh app imported the matching package through the actual Files picker, reached the menu, and installed all 78 stock files byte-identically. “Join Server by Address” opens; its virtual keyboard accepts numeric input and Cancel dismisses both keyboard and form. The current handoff app's long alert text makes the form clip above the screen in landscape with the keyboard shown. Source now omits that explanatory text; overlay tests pass, but this layout fix awaits a source-built app for live recheck. The iPhone 17 Pro Simulator was concurrently controlled by a YomiBoy UI test runner, so its app switching is not evidence of a HaloPad crash.
- **D2 phone profile progress:** from Halo's profile-name dialog on iPhone 17 Simulator, three-dot menu → Keyboard & Chat → Show Keyboard opened the iOS keyboard. A virtual letter replaced the selected default, virtual Return saved the new profile, and Hide Keyboard restored the full view. The guest text screen becomes small while typing; field taps alone did not summon the native keyboard. The same profile reached Multiplayer → Create Game → LAN → Battle Creek → Slayer → Server Setup; a local match has not yet been observed on this phone.

- **G0′ PASS:** workspace committed locally on `codex/halopad-phase2` at `5c85449`; safety check green; no push.
- **G1a PASS (engineering tier):** `scripts/prepare-patched-client.sh` reproduced the 1.10 files twice in fresh bottles with identical hashes; `scripts/assemble-custom-original.py` built ignored `ref/inputs/custom-original/` (104 files, manifest). Profile `accepted_sha256` = `feea46fce285ec071016cf5534abe47ecf36f6cfac8f1973ee6919851ea5a037`, `input_state` ENGINEERING_DERIVED; `inspect-inputs.py` passes 1.10, fails 1.00. Cross-check: ProcessChecker's same-size 1.10 copy has a different MD5; see `INPUTS.md`.
- **G2b PASS:** `scripts/x86-oracle.py` (Unicorn 2.0.1) loads the accepted image, sets up flat GDT + FS→TEB + TLS, traps every static and delay import by name, records registers/flags/stack/memory writes. CRC32 `0x59f2a2` fixture: 64/64 cases (lengths 0–17, 255–257, 4096, random) plus check value `0xCBF43926`. `tests/test_x86_oracle.py` (8 tests). Commit `8d881ce`.
- **G2a PASS:** `scripts/audit-executable.py` → [EXECUTION-MODEL.md](EXECUTION-MODEL.md). 583,266 instructions from 7,247 function entries; `.text` = 96.62% decoded code, 0.55% jump tables (388), 2.42% padding, 0.42% unclassified (84 regions: 66 referenced data-in-text / 6,877 bytes, 18 unreferenced / 1,415 bytes, all listed privately); 0 failed decodes, 0 overlaps. 5,667 indirect sites (3,661 vtable/struct, 1,129 import, 596 register, 247 absolute pointer). `generated/analysis/custom-en-1.0.10.0621/relocations.csv`: 55,109 relocations in SRW format, self-checked against SRW's loader rules; 779 uncertain excluded. Families: 65,382 x87, 4,898 MMX, 3,927 SSE, 2,754 3DNow!.
- **G2c PASS (capability report):** [G2C-SRW-CAPABILITY.md](G2C-SRW-CAPABILITY.md). SRW now gets through import loading, relocations and fixups on the whole image, and stops in full disassembly on FS-prefixed instructions. Exact scan with SRW's own udis86: 127 of Halo's 264 mnemonics supported; the 137 missing cover 11,769 instructions in 267 of 7,247 functions (SIMD 11,608; x87 134; other 27), and 189 FS-prefixed instructions sit in 57 functions. Patch additions: OLEAUT32 ordinals, failure-location diagnostics. Build `09571fae21d9-a4d658a6`.
- **G2d scoping PASS:** [G2D-SIMD-SCOPE.md](G2D-SIMD-SCOPE.md). With a plain-CPU contract (CPUID FPU/TSC/CX8/CMOV only; `IsProcessorFeaturePresent` 6/7/10 false), every traced SIMD selection picks the generic path: math table 0 of 71 SIMD (SSE2 control 42, Athlon 58), Halo's feature query 0/0, MMX installers generic, libjpeg `dct_method` 1, CRT SSE2 flag 0. Remaining SRW work: 134 x87, 189 FS (SEH), 17 string compares, 25 other; 171 SIMD functions become explicit traps. Audit fix: `.text` addresses used as memory operands are data (removed a mis-probed switch index table).
- **G2d progress — whole-image llasm:** SRW translates the entire image in diagnostic mode (46 MB llasm, ~2 s) with explicit traps, FS support, 1,101 generated flag hints and a hand replacement for the SEH compare. Complete remaining gap list: 134 x87 instructions, 164 80-bit loads/stores, 12 integer forms, 6 fused-flag `test` forms, 17 string compares, 17 `cpuid`, 2 `rdtsc`, 1 `jecxz` (see [G2C-SRW-CAPABILITY.md](G2C-SRW-CAPABILITY.md)). Finding: SR's x87 support uses `double` and ignores precision control; repair plan recorded. Tool build `ab2a55d63d9a-6f980c58`.
- **G2d slice 1 PASS — first real Halo code running natively:** `scripts/srw-pipeline.sh` turns the whole image into 287 MB LLVM IR; `clang -O1` compiles it to an 18 MB ARM64 object in ~70 s. `scripts/run-slice-crc32.py` links it (whole program, 267 loud import stubs, `port/runtime/halopad_slice_runtime.c`) and runs Halo's CRC32 `0x59f2a2`: **201/201 cases match the x86 oracle** (return value and stack effect; lengths 0–17, 255–257, 4096, 65536, random; check value `0xCBF43926`). Evidence `docs/artifacts/2026-09-26/G2d/slice-crc32-*`.
- **G2d PASS:** [G2D-SLICES.md](G2D-SLICES.md). Six real Halo slices match the x86 oracle natively on arm64: CRC32 121/121, CRT `memmove` 300/300 (all jump-table forms), `strrchr` 200/200, two x87 transforms 300/300 each in Halo's single-precision mode, and the map-header validator `0x4434a0` 6/6 over the real `bloodgulch.map` through HaloPad's first Windows services (`CreateFileA`/`ReadFile`/`CloseHandle`, `port/runtime/halopad_kernel32.c` + `port/llasm-runtime/`). Halo's x87 mode measured: single precision. Fixes: jump-table forms in the audit, SRW `.text` data mirroring (patch), llasm pointer initialization, x87 precision control (`port/llasm-support/`).
- **G2e PASS (macOS + iPad Simulator; physical-device row parked):** [G2E-ADDRESS-MODEL.md](G2E-ADDRESS-MODEL.md). Translated code runs at Halo's original 32-bit addresses in a checked 4 GiB guest region; every indirect jump/call/return goes through a finite build-time table (119,706 entries: 119,439 procedures + 267 imports); Halo's import table is bound to reserved import addresses, so `mov esi,[__imp_X]; call esi` works; no host code address reaches guest values (build-time check). All six G2d slices plus a real callback slice (`0x582d1a` calling Halo's `0x589484`/`0x5cc982`, 200/200) match the oracle, and six contract cases (unknown target, null and unmapped pointers with the oracle faulting at the same address, a call through Halo's `CloseHandle` slot, an unimplemented import, an address inside an import) behave as specified on both targets. Simulator: project-owned "HaloPad iPad Pro 13" (iOS 26.5), binary platform IOSSIMULATOR.
- **G2 selection: GO** — [G2-SELECTION.md](G2-SELECTION.md). The bounded alternate is not needed. Remaining translation work is enumerated: the strict-mode gap list (353 instruction sites) and 304 of 7,214 audited entries without a compiled procedure, including the PE entry point `0x5ccac7` and `WinMain` `0x5445e0`, because SRW's llasm mode does not root the entry point.
- **G3 in progress** ([G3-RUNTIME.md](G3-RUNTIME.md)): the native core (`scripts/run-core.py`) runs Halo from its PE entry point through the whole C runtime startup, `WinMain`, the registry and the single-instance mutex to the **first-run license check**, and then exits cleanly through Halo's own decline path (`ExitProcess(1)`). The reachable translation gap list is closed. Window creation and host-to-guest callbacks are implemented (the callback path matches the oracle through a CRC32 slice), but the core has not reached window creation yet. 9 slices plus 6 contract cases pass. The game's own `Keystone.dll` (the multiplayer chat UI) and `ksimeui.dll` are translated through the same pipeline and load as guest modules at their preferred bases: DllMain, exports, unload and reload (see G3-RUNTIME.md). Keystone's `Controls.dll` is translated at a rebased address, and MSXML 4.0 SP2 (`msxml4.dll`, from Halo's own installer) is a fifth translated module, served to `CoCreateInstance` as an in-process COM server. SEH (`RaiseException`/`RtlUnwind` over `fs:[0]`) works, including handlers that jump to an outer `__except` block. Halo's chat set-up (`0x51cdb0`) plus frames now lays out both chat windows from their `.ksml` layouts (parsed and schema-validated in translated MSXML) and draws them: a chat line added through Halo's own `0x4ae8a0` and the open chat input appear on screen through translated Keystone, GDI text on CoreText (Windows-exact font metrics from the font's VDMX/hdmx tables) and Direct3D 9 on Metal ([G3-RUNTIME.md](G3-RUNTIME.md)). An x87 bug that zeroed every stored double is fixed. 25 suites, the server join and 11 slices pass on macOS and on the iPad Simulator. Halo's own `main` runs its frame loop and draws the main menu on both (component test; DXT textures are decoded on GPUs without BC formats). The game's system start-up (`0x5442e0`) runs, and Halo loads `ui.map` and `bloodgulch.map` into tag memory with their scenario tags (component test). Halo's whole graphics start-up (`0x51a240`: window, 800 x 600 device, its vertex shaders and pixel shader 2.0 effects, every rasterizer subsystem, the chat) runs as a component test without a trap. Halo's warning and error dialogs run on a real Win32 dialog manager and show on the iPad as a sheet; after the license, every other start-up check passes on HaloPad (memory, CPU speed, DirectDraw video memory, Direct3D with the game's config.txt, sound, input, disk), so the product ID its installer writes is the only gate (see the parked table). Halo's own Direct3D splash (`0x519080`: bitmap `0x86` from `strings.dll` through its statically linked D3DX, stretched onto the back buffer and presented) draws pixel-exact on both (the Apple host is split into a shared Metal core and AppKit/UIKit hosts). An iPadOS app shell runs the native core on the Simulator from Halo's entry point to the first-run license check and shows the game's own license to the player (Accept/Decline in the app). Halo runs Blood Gulch: its own start-up script (`-exec`, `map_name levels\test\bloodgulch\bloodgulch`) loads the map through `main`, and the player spawns in the red base, drawn in first person with the HUD, for 330 frames (component test). With keyboard and mouse input through DirectInput, the player walks, turns and fires the assault rifle, each checked in Halo's game state; a flags miscompile in the C runtime's `acos` that blanked the world while firing is fixed (flag hints now follow call sites into function entries). **HaloPad joins the original dedicated server:** `scripts/reference-join.sh` starts `haloceded.exe` 1.10 (private, 127.0.0.1, CrossOver), Halo on HaloPad connects with `-connect`, completes the GameSpy handshake, loads the server's Blood Gulch and is spawned; the server logs `JOIN SUCCESS` (macOS and iPad Simulator). Tests run under a LAN-only network policy (`HALOPAD_NET=lan`). **A game started from Halo's own menus:** Multiplayer > Create Game > LAN > Battle Creek > Slayer > Start Game with a fresh profile; the player fires, melees, throws frag grenades, dies and respawns (macOS and iPad Simulator). The player also drives Blood Gulch's Warthog (enter, drive, exit) and picks up weapons. The session's sound is captured and checked (menu music, gunfire, the explosion that kills), and a lifecycle test covers menu return, map reload, quitting from the menu and a relaunch with the saved profile (macOS and iPad Simulator for the lifecycle; sound on macOS). The private server accepts Halo's no-key value (MD5 of ""), and so did every public server tried (see below); a server that checks keys would refuse it. Translation in use: `generated/srw/custom-en-1.0.10.0621/run-20260928T060918Z-85892`, lifter `9d6c88b47852-7ddadfc0` (80-bit x87, byte rotates and byte `rcl`, mixed-byte tests, fprem, `imul` of a byte in memory; 2 untranslated sites left, both in the C runtime's Pentium FDIV workaround, which HaloPad's CPU never selects). Reviewed and pinned as reference only: bnunu/halo-1, an Xbox build 2342 decompilation that cannot join Custom Edition servers ([REVIEW-HALO1-DECOMP.md](REVIEW-HALO1-DECOMP.md)). **Next step needs Chris:** accept the license with `scripts/accept-eula.sh`.
- **G4 lifecycle revalidated:** full consecutive launches pass on `e252ee2` (`core-arm64-apple-macosx14.0.0-20260928T110902Z`): map reload, New001 persisted, shared filesystem/registry state, and scripted clean quit. Earlier premature exit remains documented; exact cause was not proven. The original-client comparison (G1b) remains parked on a key. See [G4-REVIEW.md](G4-REVIEW.md).
- **Public servers (G5):** HaloPad joins the Custom Edition servers people play on (master server `s1.master.hosthpc.com`; `scripts/public-join.sh`): AUSSIES MADNESS 5, DEADLY ZOMBIES, POQclan Ice Fields and POQclan Massacre Island each loaded their map and spawned the player; a full server did not let it in. No server refused Halo's key value (the MD5 of the empty string); a server that checks keys would. Halo's own Internet lobby lists the servers (171 servers, 78 players, with pings). Public servers were opened by Chris's direction on 2026-09-27 ("people WANT to play online"; "try to connect to servers people are using"), overriding the phase-2 loop's G1b line that kept them off-limits. See [G3-RUNTIME.md](G3-RUNTIME.md#public-servers-g5-the-games-people-play).
- **Maps and mods (M16):** stock maps play; a server on a custom map the client lacks gets Halo's own "An error has occurred loading a map file." (POQclan Coldsnap); custom maps go in the install layer's `maps/`; mod plugins cannot load (fixed module table). A public session on POQclan's Ice Fields (M14): the server listed HaloPad's player in 42 of 44 polls alongside four other entries, but the test timed out. This does not establish a completed session with a verified desktop player (M14 remains open). AUSSIES MADNESS 1 disconnected and subsequently stopped answering this address; the cause is unknown. Custom-map validation and explicit plugin rejection remain unverified for M16.
- **iOS and iPadOS app (G8/G9):** Halo's frames now show in the app (Core Animation changes from Halo's thread are committed), and SunPad's touch controls and three-dot menu are adapted for Halo ([SUNPAD-TRANSFER.md](SUNPAD-TRANSFER.md)). The iPad Simulator app joined POQclan's Death Island CTF game and played at about 26 frames per second. The menu's Join Server (Halo's console command, typed; Halo runs with `-console`) joined POQclan's Ice Fields and Massacre Island games from the iPad app, and the app starts its sound (an audio session for Remote I/O). The touch controls pass an unattended self-test in a game (move, look, fire, jump, checked in Halo's state) on the iPad and iPhone Simulators, through handler-driven checks; actual multi-touch hit routing remains to be verified; short keyboard taps pass the original consumer checks below; virtual mouse-button edges now survive multiple pumps until a successful DirectInput state read. The app runs from device paths alone (bundle data, Application Support state, the player's Halo folder imported into Documents through the Files app or a folder picker and checked against the locked 1.10 profile). Draw data goes through a per-frame arena (one Metal buffer per draw was three to five driver round trips on the Simulator): one joined-game sample settled at 30 frames per second with no frame over 100 ms in its steady-state trace; initial loading still had a 2.5-second gap. Open: physical devices.
- **2026-09-28 follow-up:** fixed early UIKit activation suppressing the first guest window’s `WM_ACTIVATEAPP`, then a separate `MsgWaitForMultipleObjects` foreground-wake defect (both reproduced by failing regressions). Short Home/background → foreground checks now resume local Blood Gulch at 29–30 fps in the same process: twice on iPad, including with touch settings open, and once on iPhone. Touch settings scroll within the phone safe area with a fixed Done button; a Simulator swipe reached the bottom controls. Scene deactivation releases touch holds. Queued text now cancels on scene deactivation, releases delivered keys and never replays after resume; 16 real-overlay boundary checks pass, including movement/fire release and discarded look fractions (see SUNPAD-TRANSFER.md). Lock/unlock with held sticks now passes on iPad (60 s lock) and iPhone (36 s lock): same process and game, input neutral on resume, no replay, fresh MOVE/LOOK work (`G9/touch-lock`). Online lock also passes on iPad: joined the private original 1.10 server, held MOVE/LOOK, locked 78 s; the server kept the player throughout, and the same session resumed neutral with working fresh input (`G9/touch-lock-online`). The disconnect path also passes: with the server stopped and restarted during a 52 s lock, Halo returned to its own menu with the touch slot released, reconnected through its console, and respawned with neutral input and working MOVE/LOOK (`G9/touch-lock-reconnect`). Physical-device suspension may still differ. One immediate rejoin after force-quitting the app was refused by Halo ("Unable to join the game server!"), cause unconfirmed. Audio interruptions, actual console typing across interruption and held hardware input remain unverified. The runner propagates failures/timeouts and carries registry state across relaunches; 23 Python tests pass.
- **Graphics (not behind the license):** a Direct3D 9 inventory ([D3D9-INVENTORY.md](D3D9-INVENTORY.md)), the capability contract ([GRAPHICS-CONTRACT.md](GRAPHICS-CONTRACT.md)), a COM layer, all of `IDirect3D9`, and an `IDirect3DDevice9` on a Metal layer in a real AppKit window (full fixed state with Direct3D defaults, Clear and Present), plus resources and bindings (textures with locks, surfaces, buffers, declarations, validated shader bytecode, constants). The contract test passes 99 checks, including a presented pixel read back from Metal. The shader translator handles all 804 of Halo's programs: every one compiles with Metal and agrees with an independent reference interpreter on 1,024 random cases (795 strictly, 9 within texture precision, 0 failing). Programmable draws work on Metal (declarations, blend, depth/stencil, cull, textures, buffers; Direct3D pixel centres checked), and so does fixed-function processing (lighting, texture coordinate generation, vertex fog, the texture-stage cascade); render targets, offscreen surfaces and StretchRect work too; the draw test passes 169 checks under Metal validation. Next: cube and volume textures, occlusion queries, scissor, then the USER32 message loop.
- **Executable facts:** relocations stripped; 267 static imports across 6 DLLs; 9 delay-import DLLs; d3d9/dinput8/etc. loaded dynamically; TLS present; entry `0x5ccac7`.
- **Tooling fix:** `scripts/inspect-inputs.py` compared versions as strings (`621` ≠ `0621`); it now compares numerically. Nine tests pass.
- **G1b step 1 PASS (reference dedicated server):** `scripts/reference-server.sh` runs the original `haloceded.exe` 1.0.10.0621 in the project bottle `halopad-reference` (CrossOver 26.3), private and bound to 127.0.0.1, on Blood Gulch Slayer. It answers status queries (`mapname bloodgulch`, `gametype Slayer`, `gamemode openplaying`), and its log records the game starting. Evidence `docs/artifacts/2026-09-27/G1b/server-20260927T121035Z/`. The reference client row is parked on the license.
- **Reference environment:** CrossOver chosen for the system-level baseline (G1b). The Parallels "Windows 11" VM is an invalid registration with no files and is not used.

- **Touch reach/spacing follow-up:** symmetric edge-based sticks keep tablet radar clear. The six actions beside LOOK now share an evenly spaced two-column grid centred around the aiming thumb; FIRE stays above LOOK. Stick thumb/input travel now agree. All 90 layouts, 36 input/layout assertions and five renders pass. Installed on the iPad: original-menu Battle Creek reaches gameplay and five handler-driven checks pass; actual Pause/Resume verified. Short swipe/FIRE drag routing now verified in actual Halo after fixing dropped final touch-up displacement. The trace shows CUA drags contain begin/end only, so held-stick and simultaneous multi-touch acceptance remain open alongside physical ergonomics. The expanded suite passes 44 input/layout assertions. Actual swipe evidence: `G9/touch-routing-20260928T152054Z`; see the latest journal entry for the current preview.
- **Short keyboard taps:** the original translated consumer preserves all eleven overlay key controls through eight host pumps, then releases each on the next update without replay. DirectInput suite now passes 135 assertions (`G9/short-key-consumer`). The app JUMP check now uses a single immediate down/up, removing its prior hold/retry; it passes in gameplay (height -0.22→0.44, `G3/ios-app-20260928T161826Z`). Consumer delivery does not prove every gameplay action or physical multi-touch; keyboard interruption/source ownership is covered by the increment below.
- **Touch keyboard interruption:** four reproduced failures are fixed. Gameplay keys carry separate ownership; native menu/focus cancellation drops unread touch taps and releases observed holds while preserving physical keys and typed text. DirectInput passes 156 assertions through the original Halo consumer; USER32 passes 85; overlay passes 60 plus 90 layouts (`G9/touch-key-cancel`). Actual simultaneous fingers and physical ergonomics remain open.
- **Stick cancellation:** both sticks track their owning touch; late moves after reset cannot restart input, and old/unrelated touch endings cannot release a new hold. Four failing regressions reproduced the defect. The expanded suite passes 57 assertions and 90 layouts (`G9/overlay-20260928T160454Z`), including independent MOVE/LOOK release. These are view-handler checks; actual simultaneous touch routing remains unverified.
- **Touch tap reliability:** reproduced a FIRE tap disappearing across eight host pumps, then retained virtual mouse-button edges until successful DirectInput state reads. Duplicate events do not create extra taps; cancellation, focus loss and reacquisition clear pending edges. Physical and touch holds merge in DirectInput and USER32. The iPad DirectInput suite passes 80 assertions, USER32 passes 74, and overlay passes 48 plus 90 layout combinations. Evidence: `G9/touch-mouse-edges` and `G3/core-arm64-apple-ios17.0-simulator-20260928T154845Z`. Actual simultaneous multi-touch and physical ergonomics remain open.
- **Touch layout iteration:** two fixed MOVE/LOOK sticks replace the floating-stick/FIRE-ring arrangement. A dedicated fire target and rows of actions have consistent gaps; layout size is constrained as a group. Both hands and phone/tablet settings remain editable. Boundary tests pass 90 safe-area/size/spacing/handedness combinations, and five handler-driven Halo gameplay checks pass on both Simulators. The app layout now resizes only guest render layers and the invisible keyboard proxy rejects touches, preventing it from covering the game touch surface. Console key delivery was traced successfully; the game now fits above the docked software keyboard, with actual iPad/iPhone console typing and dismissal verified. Hide Keyboard is available on both, and held gameplay inputs release while typing. Pause/child menus now release and hide gameplay targets, retaining a touch Back control; actual iPad pause, child-menu back and resume were verified (`G3/ios-app-20260928T125447Z`). The overlay suite passes 30 assertions and 90 layout combinations. Direct finger selection now works through Halo's original menu cursor: the final iPhone build verifies letterboxed Settings/audio arrows, and the final iPad build starts a local match and navigates Pause/child menus/resume entirely by touch (`G3/ios-app-20260928T132504Z`). Seven gesture-sequence tests and 72 original-x86 cursor routes pass. Short keyboard taps pass original-consumer checks below; rapid repeated taps and keyboard interruption ownership remain open. The virtual mouse-button path is covered by the read-retention regression. Floating/split keyboards remain unverified. Actual simultaneous multi-touch and physical-device ergonomics remain open. See [SUNPAD-TRANSFER.md](SUNPAD-TRANSFER.md).

- **Import safety (M29 progress):** replaced delete-before-copy with staged validation and atomic publication. Same-folder selection is a no-op after validation; failed imports preserve the existing install, and successful replacement retains a backup. Twelve reported transaction scenario groups pass on macOS/iPad/iPhone. Actual iPad Files-picker import reaches the menu from device data; all 105 copied files match the retained source. Mac `.halopad.zip` preparation/verification now produces reproducible packages tied to compiled-core and approved content identities; 13 package and five repository-guard tests pass. Native ZIP import now validates/stages packages against the signed bundle identity and shares the atomic publication/backup transaction. Sixteen native tests pass on Mac and iPad, including real-data imports and Mac sanitizer checks; the new package-picker UI builds but has not replaced the live user preview. Folder import and device startup now validate every signed stock record, copy only approved files, and preserve legacy extra files in the source/backup. Startup hashes run off the UI thread. Twenty folder scenarios pass on Mac/iPad, including bounded copy and parent-link races. Actual iPad startup and same-folder migration through Files now pass: all 78 installed stock files match, the complete 105-file prior install is retained unchanged, and the existing profile reaches gameplay. iPhone tests, prepared-package picker/provider acceptance, custom-map policy and management/recovery remain open ([IMPORT.md](IMPORT.md), [PREPARED-DATA.md](PREPARED-DATA.md)).

- **Touch action acceptance:** corrected a false-positive melee assertion (the former field was nonzero at idle). The actual player timer now validates immediate MELEE (0→25→0); the full iPad host suite passes with the corrected assertion (`G3/core-arm64-apple-ios17.0-simulator-20260928T171348Z`). The final opt-in overlay sequence passes all five checks together: MELEE, USE, SWAP, FIRE (60→51), RELOAD (51→60), `G9/touch-actions/accepted-stderr.txt`. Bounded pickup navigation can fail after random spawns; incomplete routes remain recorded in `G9/touch-actions`. These are handler-driven gameplay outcomes; actual simultaneous fingers, physical ergonomics and damage against another player remain open.

- **Analog MOVE groundwork:** original binding/polling/movement path verified with 175 passing iPad DirectInput assertions and ten bit-exact original-x86 comparisons. Independent keyboard and partial controller movement coexist. The overlay still uses digital WASD; a cancelable virtual controller source, production configuration and gameplay acceptance remain to implement (SUNPAD-TRANSFER.md).

- **Touch spacing/look cancellation:** tightened action-button spacing independently of FIRE size, retained symmetric sticks and radar clearance, and changed FIRE to a quieter blue. Native-menu cancellation now removes unread touch-look motion while preserving physical mouse input. Four reproduced failures fixed; 181 DirectInput checks, 61 overlay assertions/90 layouts, and five iPad gameplay outcomes pass. Current iPad preview runs the updated build (`G9/touch-spacing-look-cancel`). Analog MOVE integration and physical multi-touch acceptance remain open.

- **Touch analog source and input-stage correction:** distinct, cancelable touch controller implemented behind an explicit development scene; it preserves physical controllers and survives a saturated host queue. Original activation/binding succeeds without writing input tables. The apparent full-speed defect was a mistaken test expectation: original `0x473c30` quantizes movement in multiplayer after the analog consumer. Native/original comparisons pass 22 cases; 210 iPad and 206 Mac DirectInput assertions pass. Updated iPad scene passes five gameplay checks plus seven analog/cancel checks. Sticks now highlight while held and their invisible square corners no longer intercept aiming swipes; 67 overlay assertions, five renders and 90 layouts pass. Current preview is the opt-in analog scene, not a promoted production default. Profile ownership/reload and actual physical multi-touch remain open; details in SUNPAD-TRANSFER.md and the latest journal.


- **Touch alignment and binding lifecycle:** larger MOVE/LOOK pads share a baseline, action columns now center on the thumbs, and THROW/FIRE share a baseline. Tablet action scaling is reduced; safe spacing, 44-point targets and radar clearance pass across 90 phone/tablet configurations. The opt-in analog scene now tracks slot ownership, revokes stale input, rolls back partial setup and uses original unbind/deactivate commands on menu return. Twenty-five policy assertions pass with ASan/UBSan. Actual Battle Creek → menu → new profile New002 → Sidewinder succeeds; New002 reports analog unavailable and uses the digital fallback, so profile-switch analog acceptance remains open. Restored New001; its saved profile hash matches the pre-test backup. Evidence: `G9/touch-binding-lifecycle`, `G9/overlay-20260928T185646Z`. Normal startup and physical multi-touch gates remain unchanged.

- **Fresh-profile analog fix:** New002 already had an empty touch-device assignment in slot 1; configuration now reuses it and preserves that assignment on cleanup. Two regressions reproduced, then 31 policy assertions passed under ASan/UBSan. New002 Sidewinder and its saved-profile Battle Creek relaunch each pass five gameplay and seven analog/cancel checks. Same-process map reload reuses slot 1. An actual in-game color save changes only the color field/checksum, with no touch bindings persisted. Evidence: `G9/touch-profile-config`. Physical/controller edits and natural server-transition acceptance remain open; analog still opt-in.

- **Touch layout editor:** controls snap to nearby rows/columns on drop while retaining safe clearance; resized targets remain at least 44 points. UIKit suite passes 71 assertions, five renders and 90 layouts. Actual editor opens/selects/exits on iPad; automated drag/resize persistence was not established. Original controller sensitivity save changes only its setting/checksum, and the saved test profile relaunch passes five gameplay plus seven analog/cancel checks. Preview PID 94466, New002 Battle Creek; source/binary evidence in `G9/touch-binding-edit`. Physical drag/two-thumb ergonomics remain open.

- **Touch network transitions:** the iPad analog development scene passes eight checks through an original dedicated server's natural Blood Gulch → Battle Creek change and console disconnect/reconnect. Held MOVE clears, each new spawn starts neutral, and movement works again. Server-side map/rejoin records and unchanged profile hashes corroborate the app checks (`G9/touch-network-transition`). This closes the tested transition path; abrupt loss, physical fingers and second-original-client acceptance remain open.

- **Abrupt server-loss acceptance:** held MOVE → verified private-server process exit/UDP outage → original “Network connection lost” dialog → released slot → restarted server → neutral respawn/new movement/release all pass on iPad (seven assertions, `G9/touch-server-loss`). Both original-server joins and unchanged saves corroborate the app result. No runtime fix required. iPhone network-transition coverage, physical fingers and controller-action edits remain open.

- **iPhone touch and import acceptance:** the fresh iPhone 17 Pro Simulator imports the prepared package through Files, validates all 78 stock files and joins the original private server. Eight map-change/disconnect/reconnect checks pass with a fresh touch slot. The rebuilt app passes five gameplay and seven analog/cancel checks. Touch settings now lead the three-dot menu; keyboard/chat actions share a submenu, improving access on short landscape displays. Actual phone settings open/Done verified; drag/scroll ergonomics and physical two-thumb use remain open (`G9/iphone-touch-network`).

- **Player binding ownership fix:** when a player adds a binding to a touch-device assignment HaloPad activated, cleanup now preserves the active device as well as the binding. Five reproduced regressions pass in the 35-assertion sanitizer suite; 16 original-call iPad checks verify held-input cancellation, edited assignment retention and neutral recovery. Saves remain unchanged (`G9/touch-player-binding`). Actual menu binding edits/save/reload and physical-controller acceptance remain open.

- **Original-menu binding persistence:** New002 forward was remapped W → I through Halo Controls Setup using the software keyboard. Save changes only the two keyboard entries plus CRC; relaunch retains I and passes five gameplay plus seven analog/cancel checks. Restoring W through the same menus returns both profile files exactly to their pre-test hashes. This proves keyboard-edit persistence and analog MOVE independence, not controller-axis capture (`G9/touch-menu-save`). Touch action buttons still emit fixed default keys/buttons; custom action-binding compatibility is the next implementation target.


- **Touch action remaps fixed:** buttons and digital MOVE now resolve current Halo keyboard/mouse bindings without editing the profile. Press-time ownership prevents stuck releases after remapping and preserves physical input. Actual original-menu JUMP Space → J makes the old app fail and the rebuilt iPad app pass; all five gameplay and seven analog/cancel checks pass. DirectInput passes 226 assertions; UIKit passes 71 plus 90 layouts. Both saves restored byte-for-byte. Preview PID 8274, New002 Battle Creek (`G9/touch-action-bindings`). Controller-only/wheel-only action support, remapped digital MOVE gameplay and physical fingers remain open.


- **Digital MOVE remap accepted:** with the virtual analog device disabled, original-menu W → I save/relaunch passes all five gameplay checks (3.07 units moved). Five new original-setter/consumer assertions cover W rebound to backward, I forward, release and menu cancellation; DirectInput passes 231. Saves restored exactly. The analog preview is restored as PID 10825, New002 Battle Creek, with the same binary hash previously accepted (`G9/touch-digital-remap`). No runtime change this turn. Controller-only/wheel-only bindings and unavailable-action feedback remain open.

- **Wheel-bound touch actions:** resolves original mouse-wheel bindings after keyboard/mouse buttons, with one notch per press and no release/hold repeat. Source-aware cancellation preserves physical scrolling in DirectInput and USER32. iPad suites pass 248/86 assertions; an original-setter wheel-only JUMP gameplay fixture passes all five gameplay and seven analog/cancel checks. Both saves remain byte-exact. Evidence `G9/touch-wheel`; controller-only/unbound feedback and physical ergonomics remain open. Latest preview details are in the journal.

- **Missing touch bindings now have recovery feedback:** a read-only Halo-thread snapshot marks unavailable action buttons and digital MOVE directions. Tapping them shows the exact original-menu path; remapping clears the warning without restarting and releases retain runtime ownership. Original-menu JUMP clear/save/relaunch/Space restore is verified, with both saves restored byte-exact. DirectInput passes 254 assertions; UIKit passes 94 checks, 90 layouts and ten renders (`G9/touch-binding-feedback`). Controller-only actions still require a keyboard/mouse alternative; direct controller synthesis and physical ergonomics remain open.

- **Played on a populated public server from the iPad app:** AUSSIES MADNESS 2 (216.245.177.89:2305, stock Sidewinder CTF, live score 9-10) with six real players (pings 48-249). The iPad joined as New002 on Red; the server roster lists it (ping 48). Through the touch controls: moved 4.4 units, turned 39.7°, fired 16 rounds (60→44), jumped (+0.65), turned with the LOOK stick. The first run reported false failures because the self-test read player-table entry 0, which on a full server is someone else; it now selects the local player. Evidence `G5/public-play-aussies2`.

- **Joined from Halo's own Internet Lobby on the iPad (player path, no -connect):** app launched with only the internet network policy; Multiplayer → Join Game → Internet → Get List showed 169 servers / 92 players with pings; tapped AUSSIES MADNESS 3 (Blood Gulch CTF, tied 12-12) and Join Game. Spawned on Red with a sniper rifle; server roster lists New002 (ping 24) with YOUR SISTER, Killer, Wilshire, Dopey. A tap on the on-screen FIRE button left a sniper tracer; the ammo counter did not drop, which fits this server's modded ammo but was not proven. Evidence `G5/lobby-join`.

- **Polish pass (2026-09-29):** three-dot menu button keeps its round dots after dismissal (system button configuration); menu grouped into play / setup / help with GitHub issue reporting; controllers get Halo's own Xbox layout automatically and navigate menus; iPad Simulator switched to Full Screen Apps; `--iphoneos` builds a device IPA with the memory entitlements (unsigned here); README and docs/INSTALL-IPHONE.md rewritten for players.

## Parked, waiting on Chris

| Item | Parks | Status |
|---|---|---|
| Accept or decline the Halo license (`scripts/accept-eula.sh` on the Mac, or in the HaloPad app on the Simulator: `scripts/build-ios-app.py --launch`) | G3 beyond first run: splash, USER32, Direct3D 9 | Needed now; the agent never accepts on the player's behalf |
| Legitimate Halo PC product key (used boxed Halo PC), typed into Halo's original installer | **Normal entry-point startup and original-client baseline**: component scenes allow runtime/gameplay development, but cannot close G1b or the dependent comparison gates; Halo's `0x5829e0` needs the installer's `DigitalProductID` and otherwise stops with "Your product key is invalid" (fatal). HaloPad never writes product IDs | Supplied string did not match the original installer’s required key format; valid installer provisioning remains needed |
| Physical iPhone/iPad + signing | Final G2e capsule row (M07): must first measure whether a 4 GiB guest reservation is allowed on device | Needed to close G2e fully; Mac work continues |
| Second legitimately provisioned player | G5 original-client comparison (a real Halo PC client in the same game) | HaloPad's client already joins the reference server; needed for the two-player match |
| Retail `halo.exe` 1.10 + campaign data | G7 | A boxed copy would cover it |

Rights: private-engineering-authorized; publication-not-authorized. Chris authorized GitHub pushes; `codex/halopad-phase2` is tracked and pushed to the private origin under that authorization. Public release remains unauthorized. Process/preview state is recorded in the latest journal entry rather than assumed here.

Known-good commands:

```sh
scripts/doctor.sh
scripts/verify-sources.sh
scripts/check-repo-safety.sh
.venv/bin/python -m unittest discover -s tests -v
```
