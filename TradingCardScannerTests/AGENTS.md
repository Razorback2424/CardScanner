# App Test Guide

**Scope:** `TradingCardScannerTests/`. Also follow the root [`AGENTS.md`](../AGENTS.md). Before changing an expectation, read the guide for the code under test: [`TradingCardScanner/`](../TradingCardScanner/AGENTS.md), [`Services/`](../TradingCardScanner/Services/AGENTS.md), [`Models/`](../TradingCardScanner/Models/AGENTS.md), [`Views/`](../TradingCardScanner/Views/AGENTS.md), [`Games/`](../TradingCardScanner/Games/AGENTS.md).

## Filenames do not identify test classes

`-only-testing:` selects **classes**, and many files declare several classes or a class whose name differs from the file. Running the class named after a file often misses the tests you need. Look up the declaring file instead of guessing:

```bash
grep -rn "class CenteringNativePrecisionTests" TradingCardScannerTests
```

```bash
grep -rhoE "class [A-Za-z0-9_]+ *: *XCTestCase" TradingCardScannerTests/CenteringExportTests.swift
```

Notable multi-class files: `CenteringExportTests.swift`, `OpusImplementationPlanTests.swift`, `UncoveredSurfaceTests.swift` (17 surface/smoke classes), `YuGiOhIntegrationTests.swift`, `BrowseFeatureTests.swift`, `PokemonCatalogTests.swift`, `PokemonCatalogSliceBTests.swift`, `SignedCatalogReleaseStoreTests.swift`, `VariantResolverTests.swift`, `CenteringNativeResearchTests.swift`.

## Centering: behavior → class

| Changed behavior | Class | File |
| --- | --- | --- |
| Typed numbers, Done, localized input, blur/refocus/removal | `CenteringNativePrecisionTests` | `CenteringExportTests.swift` |
| Boundary choices and their provenance | `CenteringBoundaryEvidenceTests` | `CenteringExportTests.swift` |
| Guide editing, confirmation, export, rotation, zoom/pan | `CenteringExportTests` | `CenteringExportTests.swift` |
| Detection, pixel kernels, synthetic scenes | `CardCenteringAnalyzerTests` | `CenteringExportTests.swift` |
| Review rendering, stale review/share snapshots | `CenteringReviewTests` | `CenteringReviewTests.swift` |
| Spatial ratios, coordinate transforms | `CenteringSpatialMeasurementTests` | `CenteringSpatialMeasurementTests.swift` |
| Ground-truth fixtures through the production pipeline | `CardCenteringGroundTruthTests` | `OpusImplementationPlanTests.swift` |
| Measurement invariants | `CardCenteringInvariantTests` | `OpusImplementationPlanTests.swift` |
| Frozen fixture manifests | `CardCenteringCorpusManifestTests` | `OpusImplementationPlanTests.swift` |

Example for a precision-editor change: `-only-testing:TradingCardScannerTests/CenteringNativePrecisionTests`.

## Running

Use the shape the workflows use (`.github/workflows/catalog-coverage-tests.yml`), with derived data and the result bundle on the external SSD per the root guide:

```bash
xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination "platform=iOS Simulator,id=<SIMULATOR_ID>" -derivedDataPath "<SSD>/TradingCardScannerDerivedData/<run>" -resultBundlePath "<SSD>/TradingCardScannerDerivedData/<run>.xcresult" -only-testing:TradingCardScannerTests/<Class>
```

Select classes (or `<Class>/<testMethod>`) by changed behavior; widen to neighboring suites when the change crosses a boundary named in the source guides.

## Writing tests

- The project lists files explicitly. Add a new test file, and any fixture it reads, to the `TradingCardScannerTests` target in `TradingCardScanner.xcodeproj`; a fixture that is not in the bundle makes tests skip or fail for the wrong reason.
- Prefer retained inputs (`Fixtures/`, root `TestFixtures/`) and existing injection seams (`…ForTesting` hooks) over live providers, wall-clock waits, or randomness.
- Keep expected results independent of the implementation under test; do not regenerate an expectation from the code you just changed.

## Reporting evidence

- Record source SHA (plus whether the tree was dirty), configuration, destination, selected tests, result bundle path, failures, and skips.
- A filtered run is not complete-target evidence; say which it is.
- Opt-in checks are gated by environment (for example `RUN_NATIVE_REFINEMENT_BENCHMARK`, `TCS_ENTITLED_INTEGRATION`). A skipped test provides no passing evidence for its behavior.
- When a test fails, check the product contract (the relevant guide and current plan) before changing either the expectation or production code. Do not record current pass counts in this file.
