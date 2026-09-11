# Device and Environment Validation

## Executed evidence

### Target discovery

Command:

```text
xcodebuild -project TradingCardScanner.xcodeproj -list
```

Result: the `TradingCardScanner` scheme and application/unit-test targets were discovered successfully.

### Debug unit suite

Command:

```text
xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath /tmp/TradingCardScannerLunaReview
```

Result: **TEST SUCCEEDED**. `TradingCardScannerTests.xctest` executed 1,005 tests, with 1 skipped and 0 failures. Result bundle: `/tmp/TradingCardScannerLunaReview/Logs/Test/Test-TradingCardScanner-2026.09.10_18-24-15--0600.xcresult`.

The one skip is the opt-in aged-store/performance fixture. This is current executable evidence for deterministic unit behavior, not camera/network/CloudKit evidence.

### Release simulator build

Command:

```text
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/TradingCardScannerLunaRelease build
```

Result: **BUILD SUCCEEDED**. The artifact was compiled, linked, packaged, code-signed for simulator execution, and validated. The build output also confirms the Release bundle identifier remains `com.example.TradingCardScanner` and the simulator signing path is local/ad hoc.

## Environment notices

- Simulator output emitted CoreMotion/missing-plist and duplicate `UIAccessibilityLoaderWebShared` runtime notices. They did not fail tests.
- Xcode’s AppIntents metadata processor reported that no `AppIntents.framework` dependency was present. The project has no declared App Intents feature; this is a build notice, not a promoted app defect.
- No Swift compiler failure or test failure occurred in the current Debug suite.

## Simulator-covered versus externally blocked

| Area | Current evidence | Boundary |
| --- | --- | --- |
| Parser, latch, identity, collection, pricing, replay, history pure logic | 1,005-test Debug suite, 0 failures | Fixture behavior does not prove external payload distributions |
| SwiftData local contexts and deterministic persistence helpers | Unit tests and Release simulator build | Does not prove CloudKit schema/delivery/account behavior |
| SwiftUI compilation and deterministic routes documented by prior audit | Current build plus historical audit | No fresh manual screenshot pass was required/created here |
| Camera capture/OCR/slab tracking | Source/tests only | Requires physical camera, real cards/slabs, device cadence/thermal observation |
| Background Tasks | Source/build only | Requires OS scheduler and suspended/resumed app execution |
| TCGdex/Scryfall/JustTCG | Injected clients/fixtures only | Requires credentials, live schemas, quota and transport behavior |
| Release signing/CloudKit/Apple sign-in | Project settings and simulator packaging only | Requires production team, identifiers, provisioning, archive/export, and iCloud container |
| Large collection cold launch/projection cost | Source signposts and prior plan | Requires Release real-device measurement with ~1,500 seeded cards |

## Required external validation records

The following are completion-gate procedures, not implementation instructions. Each item remains `BLOCKED-EXTERNAL` until the described evidence exists.

1. **Physical scanner:** run a Release build on a representative iPhone with a 30-card stack including neighboring identities and at least one graded slab. Record cadence, confirmation latency, missed/duplicate count, slab-grade attachment, camera interruption/restart, tab return, and thermal behavior.
2. **Collection cold launch:** seed roughly 1,500 cards, measure launch to first real collection row using existing projection signposts, and record device/OS/build.
3. **CloudKit/account:** test first local launch, signed-in CloudKit launch, sign-out/restart, account/store transition, two-device late inventory, duplicate delivery, and offline/reconnect. Verify activities/events, projection, close revision reason, and quantities.
4. **Live providers:** exercise successful USD, non-USD, null, malformed, transport-failure, rate-limit, stale, and artwork-miss responses against current provider contracts. Compare `PriceRecord`, observations, refresh report, Price Check state, current valuation, replay, and diagnostics.
5. **Release ownership:** archive/export with the intended production bundle ID, team, iCloud container, Sign in with Apple entitlement, background identifiers, and provisioning. Confirm the resulting signed entitlements and App Store validation.
6. **Visual centering:** capture preview and export at zero and non-zero rotations and compare guides against photo pixels; retain images and measurement input/output.

## Configuration gate observed

`TradingCardScanner.xcodeproj/project.pbxproj:906,930` uses `com.example.TradingCardScanner` for Debug and Release. Release entitlements declare `iCloud.$(CFBundleIdentifier)`, CloudKit, and Sign in with Apple. This is recorded as an external deployment gate rather than an unconditional code defect because the intended production identifiers/provisioning were not supplied in the repository.
