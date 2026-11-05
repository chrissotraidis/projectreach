# Service Record host checks

These checks exercise the native persistence and UIKit feature without building,
starting or packaging the game engine. All records, profiles and save files are
generated synthetic fixtures. No game data, rank PNG pack, cloud account, network
download, signing identity or installed player profile is used.

Run on macOS with Xcode selected and an output directory of your choice:

```sh
python3 tests/service_record/run.py native --work-dir /path/to/test-output
```

The Foundation/SQLite tests compile with AddressSanitizer and
UndefinedBehaviorSanitizer. They check event retries and identities, authoritative
join baselines and downward corrections, known/unknown/unfinished game results,
quarter boundaries, profile separation, medal awards and notifications, bounded
read-only history, additive migrations, SQLite contention/crash recovery,
preservation of existing XP, player-name path validation and rank-policy limits.
The store and rank sources are also syntax-checked against the iPhoneOS SDK.

For UIKit, choose an **existing** available simulator from
`xcrun simctl list devices available`. The runner boots it if necessary, generates
a separate Xcode project under the output directory, builds the host controllers,
and installs only `org.halopad.tests.servicerecord`:

```sh
python3 tests/service_record/run.py ui \
  --work-dir /path/to/test-output \
  --derived-data /path/to/derived-data \
  --device EXISTING_SIMULATOR_UDID --label tablet
```

Repeat with a small phone simulator to cover compact layouts. The app checks real
native controllers with synthetic snapshots, season/lifetime tabs, exact-source
breakdowns, generated badges, medal filters, match details, stale-query rejection,
profile changes and presentation/dismissal input ownership. It renders screenshots
and writes a JSON assertion report under `UIKit/LABEL`. The output is copied only
from this test app's own simulator container. The runner creates no simulators and
does not delete existing ones. It leaves the isolated app installed for inspection.

The generated `UIKitProject/ServiceRecordFixture.xcodeproj` also supports a Mac
Catalyst compile/link check:

```sh
xcodebuild -project /path/to/test-output/UIKitProject/ServiceRecordFixture.xcodeproj \
  -scheme ServiceRecordFixture -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath /path/to/catalyst-derived-data CODE_SIGNING_ALLOWED=NO build
```

These checks do not validate guest-hook integration, real match capture, physical
device performance, a full application build or public distribution permission.
Engine-recipe integration has its own tests. A passing host fixture is not a
claim that the complete game ran on a simulator or a physical device.
