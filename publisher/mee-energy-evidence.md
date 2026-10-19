# MEE Basic Energy onboarding

Evidence captured 2026-10-19 UTC (2026-10-18 local). This describes repository
and public-provider evidence, not the downloaded catalog on a personal device.

## Physical identities and sources

The [TCGdex MEE set](https://api.tcgdex.net/v2/en/sets/mee) and its eight card
records contain only 001–008. Their Normal and Reverse flags produce 16
checklist slots, not 16 collector numbers. The bounded primary capture is
[mee-primary.json](fixtures/mee-primary.json).

The [MEE product records](https://tcgcsv.com/tcgplayer/3/24461/products) and
[finish records](https://tcgcsv.com/tcgplayer/3/24461/prices) verify eight
additional numbered products, each with one Holofoil finish. Product artwork
for Psychic and Darkness shows the rainbow anniversary stamp. The source
capture is [mee-reviewed-products.json](fixtures/mee-reviewed-products.json).
Volatile price amounts are omitted from recorded finish evidence.

| Footer | TCGplayer product | App provider ID |
| --- | --- | --- |
| MEE 009 | 713248 | tcgplayer:713248 |
| MEE 010 | 713249 | tcgplayer:713249 |
| MEE 011 | 713250 | tcgplayer:713250 |
| MEE 012 | 713251 | tcgplayer:713251 |
| MEE 013 | [713252](https://www.tcgplayer.com/product/713252) | tcgplayer:713252 |
| MEE 014 | 713253 | tcgplayer:713253 |
| MEE 015 | [713254](https://www.tcgplayer.com/product/713254) | tcgplayer:713254 |
| MEE 016 | 713255 | tcgplayer:713255 |

Current reviewed membership supplies one physical printing per 009–016
footer. The existing variant resolver can resolve Holo directly; payloads
retain generic `30th-anniversary` stamp metadata. No unstamped counterpart is
inferred. New evidence of shared footers requires reviewing the mapping and
offering the physical variants through the existing picker.

The existing reviewed `PokemonTCGCSVMapping` is the authoring source for the
secondary rows. Their IDs explicitly name their real provider. No missing
TCGdex IDs or artwork paths are fabricated. Artwork uses the product feed's
exact URLs. Price joins check group, product, number and name and accept only
Holofoil. Missing prices stay unavailable. Psychic 005 and Darkness 007 retain
their existing IDs and records.

## Catalog maintenance and compatibility

`catalog-input.json` explicitly onboards `mee` with recognition kind `energy`,
rules version 2, prefix MEE, three-digit numeric local IDs and no denominator.
The bundled registry agrees. The historical ignore inventory is unchanged:
the publisher unions explicit override and active IDs into its fetch set, so
MEE is fetched through the explicit input rather than historical discovery.

Rules version 2 adds the Energy kind. Older binaries cannot decode that new
enum case and reject such releases instead of interpreting Energy as promos
or expansions. Checklist schema/master-set rules remain version 1. Old scan
snapshots and collection IDs retain their meaning. Signature validation is
unchanged. A downloaded release lacking MEE does not grant MEE scan authority;
that configuration still needs a subsequent signed release prepared from the
new input. This task does not publish a release or inspect personal devices.

The existing checklist builder adds reviewed secondary rows on generation and
refresh. The regression generator builds only MEE in disposable storage with
`PokemonChecklistStore.publish`, which writes the resource before the manifest.
Primary fingerprints still describe actual TCGdex content; reviewed secondary
membership ships with the app mapping. A future primary backfill must preserve
existing secondary holding IDs and receive explicit mapping review.

After running
`PokemonTCGCSVPriceTests/testReviewedEnergyProductsAndChecklistRegenerationPreserveOldRows`,
pass its `MEE_GENERATED_CHECKLIST` directory to
`python3 scripts/update_mee_snapshot.py <directory>` to install only the
generated MEE resource and manifest entry. Rerun with `--check` for parity.

## Acceptance boundary

Parser tests use transcribed footer text and synthetic observation geometry.
The original two photos were absent from the accessible task context; local
paths were requested. No photo OCR, live-camera, physical-device, CloudKit or
remote-publication acceptance is claimed. The task report records verification
commands and results separately.

## Verification record

Checkout: `8209b9f8a71ca01911d58fbceecc721ee74e8845` plus the existing dirty
working tree and this focused change. Unrelated edits were preserved.

- `swift test --package-path PokemonCatalogCore --scratch-path '<external SSD>/CardScannerBuild/MEE-Core'`:
  75 passed, including explicit onboarding and a subsequent catalog build.
- After tightening the Energy descriptor's field contract,
  `swift test --package-path PokemonCatalogCore --scratch-path '<external SSD>/CardScannerBuild/MEE-Core' --filter EnergyDescriptorTests`:
  1 passed.
- First Simulator batch: app built; 275 executed, 3 fixture-access failures.
  Simulator could not read authoring inputs under the host Documents folder.
  The same authoring files were then added directly to test resources, including
  the existing Classic authority test's publisher input. No duplicate copies.
- Corrected Simulator batch: 275 passed, 0 failures. Exactly two app builds
  were used. No interactive Simulator review or live-camera acceptance was run.
  The fixture tests generated one MEE checklist in disposable Simulator storage;
  test holdings and CSV import targets used in-memory SwiftData containers.
- `python3 scripts/update_mee_snapshot.py '<MEE_GENERATED_CHECKLIST directory>'`
  installed the generated resource; the same command with `--check` passed.
  A separate JSON comparison against HEAD verified that only the MEE manifest
  entry changed, every resource exists, and all 16 original primary slots are
  identical. The installed generated bytes match the tested output; no third
  app build was run solely to repackage those bytes.
- `plutil -lint TradingCardScanner.xcodeproj/project.pbxproj` and
  `git diff --check` passed.

Final-audit qualification: after the passing Simulator batch, a narrow guard
was added at both offline historical candidate-set filters. Registered Energy
sets cannot use a provider `officialCount` as a printed denominator. This
prevents hypothetical `013/8` evidence from acquiring the new Energy printing.
Regression assertions for 005/8, 013/8 and 015/8 were added to the recorded MEE
checklist test. Those added assertions and guards have **not** been rerun in
Simulator because both permitted app builds were already used. The command
`xcrun swiftc -frontend -parse TradingCardScanner/Games/Pokemon/PokemonCatalogSupport.swift TradingCardScannerTests/PokemonTCGCSVPriceTests.swift`
passed for the final source, as did whitespace validation. Thus 275 passing
tests describe the preceding built revision, not full final-source acceptance.
This final guard and the missing original-photo acceptance remain explicit
verification gaps; no third app build was attempted.

The corrected Simulator command below uses a destination label for readability;
the actual invocation selected that existing iPhone 17 Simulator by its ID.

```sh
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath '<external SSD>/CardScannerBuild/MEE-DerivedData' \
  -clonedSourcePackagesDirPath '<external SSD>/CardScannerBuild/SourcePackages' \
  -resultBundlePath '<external SSD>/CardScannerBuild/MEE-Energy-Final.xcresult' \
  -only-testing:TradingCardScannerTests/ScanParserTests \
  -only-testing:TradingCardScannerTests/PokemonTCGCSVPriceTests \
  -only-testing:TradingCardScannerTests/PokemonCatalogSliceCTests \
  -only-testing:TradingCardScannerTests/PokemonCatalogRegistryTests \
  -only-testing:TradingCardScannerTests/PokemonCatalogParityTests \
  -only-testing:TradingCardScannerTests/PokemonCatalogPromoPadWidthTests \
  -only-testing:TradingCardScannerTests/CardLatchTests \
  -only-testing:TradingCardScannerTests/VariantResolverTests \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO test
```

Local logs: `/tmp/mee-core-final.log`, `/tmp/mee-core-correction.log`,
`/tmp/mee-app-first.log`, `/tmp/mee-app-final.log`. Result bundles are on the
external SSD under `CardScannerBuild/MEE-Energy-{First,Final}.xcresult`.

## Changed files for this task

- Contract/publisher: `PokemonCatalogCore/Sources/PokemonCatalogCore/{CatalogContract,CatalogBuilder}.swift`,
  `PokemonCatalogCore/Tests/PokemonCatalogCoreTests/EnergyDescriptorTests.swift`,
  `publisher/catalog-input.json`, the two `publisher/fixtures/mee-*.json` captures,
  `publisher/README.md`, and this evidence record. Discovery policy is unchanged.
- Recognition/identity: `TradingCardScanner/Services/{ScanParser,SetCodeMap,PokemonCatalogRegistry,UnresolvedScanStore}.swift`,
  `TradingCardScanner/Games/Pokemon/PokemonRecognitionAdapter.swift`,
  `TradingCardScanner/Views/ScannerViewModel.swift`.
- Resolution/presentation/pricing: `TradingCardScanner/Games/Pokemon/{PokemonCatalogAdapter,PokemonCatalogSupport}.swift`,
  `TradingCardScanner/Games/Core/LegacyResolvedCard.swift`,
  `TradingCardScanner/Services/{TCGdexService,PokemonTCGCSVMapping,BrowseCatalog,PokemonChecklistSnapshot}.swift`.
- Generated checklist: `TradingCardScanner/PokemonChecklistSnapshot/manifest.json`,
  replacement MEE resource `sets/47e60a59a078cb3.json`; superseded MEE resource
  `sets/fffed6ec3fadb142.json` removed by bounded regeneration.
- Verification: `TradingCardScannerTests/{ScanParserTests,PokemonTCGCSVPriceTests,PokemonCatalogSliceCTests,PokemonCatalogTests}.swift`,
  test-resource references in `TradingCardScanner.xcodeproj/project.pbxproj`,
  `scripts/update_mee_snapshot.py`, and the task entry in `progress.md`.
