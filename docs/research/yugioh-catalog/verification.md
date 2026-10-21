# Yu-Gi-Oh implementation verification — 2026-10-20

Starting and ending revision: `main` at
`81a6f2c56db0008091887f219d9370202b0e2ce1`. Starting worktree was clean;
ending changes are uncommitted. Reviewed plan `fd917fd` was fetched and compared
with HEAD; only the plan differed. No branch merge, reset, commit or push.

## Catalog evidence

659 groups and all of their product/price responses were fetched, plus one
YGOPRODeck cardinfo response. The build retained 46,504 printings / 37,846
codes from 47,910 source products. 1,138 codes fail one or more identity or
printing checks. Physical edition completeness is independently verified for
**zero** products: 46,504 are quarantined, with **zero automatic and zero
manual acquisition eligible products**. This implementation does not make the
whole catalog usable for collection entry yet.

Observed lanes: 36,539 First, 21,006 Unlimited, 2,416 Limited. These counts
are price-response observations, including null quotes, not physical coverage.
No observed lane union was promoted to a complete physical universe. See the
[generated report](build-report.md) for every input's URL, cache timestamp,
available provider timestamp, SHA-256 and exception counts/examples.

Seed generation: `yugioh-en-c2137cc710ee`.
Seed SHA-256:
`809b68e111c2c35029a683eb9e170707318705b0ab4cc1c514e600b6cd8da338`.
An offline replay produced identical bytes. Generation was independently
recomputed with the generation field empty and matched. Builder fixtures are
synthetic and do not prove camera accuracy or physical edition completeness.

Smallest remaining catalog action: review a bounded product subset's physical
edition validity **and complete universe**, record product-specific editions,
`complete: true` and independent evidence in
[`scripts/yugioh_physical_editions.json`](../../../scripts/yugioh_physical_editions.json),
then rebuild offline. Do not derive completeness from any group's price rows.
No exhaustive manual catalog research is required to enable a reviewed subset.

## Commands

All simulator runs use the dedicated `YuGiOh Integration QA` simulator, created
for this pass. Journey's devices, processes and saves were not changed.

```bash
git fetch origin claude/yugioh-plan-review-revisions
git diff HEAD origin/claude/yugioh-plan-review-revisions --stat
xcrun simctl create 'YuGiOh Integration QA' com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0

python3 -I scripts/build_yugioh_catalog.py \
  --cache-dir '/Volumes/Keller Family Photos/YuGiOhSourceCache/2026-10-21' \
  --out TradingCardScanner/YuGiOhCatalogSeed/catalog.json \
  --report docs/research/yugioh-catalog/build-report.md
python3 -I scripts/build_yugioh_catalog.py --offline \
  --cache-dir '/Volumes/Keller Family Photos/YuGiOhSourceCache/2026-10-21' \
  --out TradingCardScanner/YuGiOhCatalogSeed/catalog.json \
  --report docs/research/yugioh-catalog/build-report.md
python3 -I scripts/build_yugioh_catalog.py --self-test
bash scripts/audit_game_boundaries.sh
git diff --check
```

The following zsh arrays expand to the test invocations used in this pass;
each result bundle uses the unique name in the results table.

```bash
SIM=AA89C572-9D2C-4A93-B98D-73A54A9AE504
OUT='/Volumes/Keller Family Photos/CardScannerBuilds/yugioh'
common=(-project TradingCardScanner.xcodeproj -scheme TradingCardScanner
  -configuration Debug -destination "platform=iOS Simulator,id=$SIM"
  -derivedDataPath "$OUT/DerivedData"
  -clonedSourcePackagesDirPath "$OUT/SourcePackages")
focused=(YuGiOhCatalogTests YuGiOhRecognitionTests YuGiOhResolutionTests
  YuGiOhRecoveryTests YuGiOhPricingTests YuGiOhImportTests YuGiOhWorkflowTests)
seams=(GameRecognitionRegistrySupplementalTests)
neighbors=(CardGameForwardCompatibilityTests ScanParserTests ScannerViewModelTests
  CardLatchTests LorcanaIntegrationTests LorcanaPricingTests OnePieceIntegrationTests
  PricingTests CSVImportResumeTests CollectionKeyTests)
affected=(ScanParserTests ScannerViewModelTests CardLatchTests)
only=(); for cls in $focused; do only+=(-only-testing:TradingCardScannerTests/$cls); done
allFocused=($only)
for cls in $seams; do allFocused+=(-only-testing:TradingCardScannerTests/$cls); done
allNeighbors=(); for cls in $neighbors; do allNeighbors+=(-only-testing:TradingCardScannerTests/$cls); done
finalFocused=($allFocused)
for cls in $affected; do finalFocused+=(-only-testing:TradingCardScannerTests/$cls); done

xcodebuild build-for-testing $common -resultBundlePath "$OUT/compile-1.xcresult" CODE_SIGNING_ALLOWED=NO
xcodebuild test $common -resultBundlePath "$OUT/focused-1.xcresult" -parallel-testing-enabled NO $only CODE_SIGNING_ALLOWED=NO
xcodebuild test $common -resultBundlePath "$OUT/focused-2.xcresult" -parallel-testing-enabled NO $allFocused CODE_SIGNING_ALLOWED=NO
xcodebuild test $common -resultBundlePath "$OUT/neighbors-1.xcresult" -parallel-testing-enabled NO $allNeighbors CODE_SIGNING_ALLOWED=NO
xcodebuild test $common -resultBundlePath "$OUT/final-focused.xcresult" -parallel-testing-enabled NO $finalFocused CODE_SIGNING_ALLOWED=NO
xcodebuild test $common -resultBundlePath "$OUT/final-focused-2.xcresult" -parallel-testing-enabled NO $finalFocused CODE_SIGNING_ALLOWED=NO
xcodebuild test $common -resultBundlePath "$OUT/price-check-final.xcresult" -parallel-testing-enabled NO \
  -only-testing:TradingCardScannerTests/YuGiOhWorkflowTests \
  -only-testing:TradingCardScannerTests/YuGiOhPricingTests \
  -only-testing:TradingCardScannerTests/ScannerViewModelTests/testPriceCheckCatalogMissDoesNotClaimToSaveNeedsAttention \
  -only-testing:TradingCardScannerTests/ScannerViewModelTests/testPriceCheckNameMismatchDoesNotClaimToSaveNeedsAttention \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test $common -resultBundlePath "$OUT/catalog-boundaries-final.xcresult" -parallel-testing-enabled NO \
  -only-testing:TradingCardScannerTests/YuGiOhRecognitionTests/testTwoKnownCodesRemainAmbiguous \
  -only-testing:TradingCardScannerTests/YuGiOhResolutionTests/testIncompleteIdentityAndForgedPrintingCannotAuthorizeAcquisition \
  CODE_SIGNING_ALLOWED=NO
```

Baseline reproduction uses a separate source archive of unchanged HEAD and a
separate derived-data directory on the SSD, without modifying this worktree:

```bash
mkdir -p /tmp/yugioh-baseline-source
git archive HEAD | tar -x -C /tmp/yugioh-baseline-source
cd /tmp/yugioh-baseline-source
xcodebuild build-for-testing -project TradingCardScanner.xcodeproj -scheme TradingCardScanner \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$OUT/BaselineDerivedData" -clonedSourcePackagesDirPath "$OUT/SourcePackages" \
  -resultBundlePath "$OUT/baseline-compile.xcresult" CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building -project TradingCardScanner.xcodeproj -scheme TradingCardScanner \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath "$OUT/BaselineDerivedData" -clonedSourcePackagesDirPath "$OUT/SourcePackages" \
  -resultBundlePath "$OUT/baseline-collection-key.xcresult" -parallel-testing-enabled NO \
  -only-testing:TradingCardScannerTests/CollectionKeyTests/testREQ001UnderlyingPrintingIDUsesTheProductionSourceForEveryItemKind \
  CODE_SIGNING_ALLOWED=NO
```

## Results

Counts are per invocation. Suites overlap and must not be summed.

| Invocation / bundle | Passed | Failed | Skipped | Result |
|---|---:|---:|---:|---|
| Offline builder self-test | 11 | 0 | 0 | PASS, including failed/incomplete input preserving existing outputs |
| `compile-1` | — | — | — | App and test targets compiled |
| `focused-1` | 0 | 0 | 0 | Build failed: test used Pokémon candidate accessor; no tests executed |
| `focused-2` | 27 | 0 | 0 | PASS |
| `neighbors-1` | 543 | 1 | 3 | 547 executed; separate collection-key failure below |
| `final-focused` | 0 | 0 | 0 | Build failed: new scanner fixture tests needed MainActor annotations; no tests executed |
| `final-focused-2` | 319 | 0 | 0 | PASS, including both full persistence chains and encounter/recovery regressions |
| `price-check-final` | 9 | 0 | 0 | PASS; final Price Check recovery, strengthened missing/null/later quote test and both persistence chains |
| `baseline-compile` | — | — | — | App and test targets compiled at unchanged HEAD |
| `baseline-collection-key` | 0 | 1 | 0 | Same collection-key failure reproduced at unchanged HEAD |
| `catalog-boundaries-final` | 2 | 0 | 0 | PASS; multiple valid codes, incomplete acquisition and forged printing rejection |

The neighboring failure is
`CollectionKeyTests.testREQ001UnderlyingPrintingIDUsesTheProductionSourceForEveryItemKind`:
line 247 expects a directly added sealed product's `catalogProviderID` to be
nil, but the production store writes `direct-product`. The test and sealed
write implementation were unchanged in this pass. Baseline runtime reproduction
at unchanged HEAD failed identically (one test, one failure). No unrelated
sealed-product behavior or test assertion was changed.
The three skips are Lorcana opt-in cases reported by the test runner.

The strict boundary audit fails with **48 branches**, exactly the same branch
text as the starting revision's audit (line numbers differ). No `.yuGiOh`
branch occurs in designated central files. The audit is not reported as passed.
Local Markdown links and whitespace pass. Xcode project lint passes and its
PBX object declarations contain no duplicate IDs. Logs and result bundles are
retained under `/Volumes/Keller Family Photos/CardScannerBuilds/yugioh/`.

Synthetic chains cover rarity choice → edition by tap and printed evidence →
save → exact refresh → CSV export → isolated fresh-store import → persistence
reload. Printing ID, edition and collection key survive the transfer; the
source's exact price key/value survive reload. CSV remains an inventory transfer,
not a backup of separate price-record history. Conflict blocks the write and
survives retry; a new encounter does not inherit the old record's conflict.

No physical camera, physical-device installation/performance, provider rights,
CloudKit, archive, App Store approval or release gate is certified. The full
test target was not run; the scoped regressions did not reveal an unexpected
shared behavioral regression requiring it.

## Changed files

- App/Xcode: `TradingCardScanner.xcodeproj/project.pbxproj`;
  `Games/Core/{CardGameRuntime,GameRecognitionAdapter}.swift`;
  `Games/YuGiOh/{YuGiOhCatalog,YuGiOhRecognitionAdapter,YuGiOhCatalogAdapter,YuGiOhGameRuntime,YuGiOhBrowseAdapter,YuGiOhImportAdapter,YuGiOhPriceAdapter}.swift`.
- Models: `Models/{CardGame,CardGameRegistry,CardVariant}.swift`.
- Shared services: `Services/{CardScanner,CollectionStore,ScanParser,TCGCSVProductPriceSource,UnresolvedScanStore,VariantResolver}.swift`;
  `Views/ScannerViewModel.swift`.
- Tests: `TradingCardScannerTests/{CardGameForwardCompatibilityTests,YuGiOhIntegrationTests}.swift`.
- Builder/data: `scripts/{build_yugioh_catalog.py,yugioh_name_aliases.json,yugioh_physical_editions.json,audit_game_boundaries.sh}`;
  `scripts/fixtures/yugioh/{catalog.json,test_builder.py}`;
  `TradingCardScanner/YuGiOhCatalogSeed/catalog.json`.
- Documentation: `docs/README.md`, `docs/plans/{yugioh_code_implementation,documentation_audit}.md`,
  `docs/legacy/plans/yugioh_code_implementation_reviewed.md`, this record,
  `docs/research/yugioh-catalog/build-report.md`, and root `progress.md`.

All relative app paths above are under `TradingCardScanner/`. Generated build
artifacts and raw input cache remain on the external SSD; test stores are
isolated under the dedicated simulator's temporary directory.
