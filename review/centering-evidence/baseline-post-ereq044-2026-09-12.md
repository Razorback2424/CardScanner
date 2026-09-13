# Post-E-REQ044 full-suite baseline — 2026-09-12

This is the current signed baseline after the E-REQ044 transition-width guard
and per-side outer-refinement fallback. It supersedes the older
`baseline-2026-09-12.md` for current-branch status; that file remains a
historical pre-E-REQ044 record.

## Environment and command

- Worktree: `opus-card-centering-implementation`
- Device: iPhone 17 Pro, iOS 26.5, arm64
- Simulator UDID: `EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`
- OS build: `23F77`
- Test environment: macOS `26.5.1`
- Storage: DerivedData and the result bundle were written to the configured
  external SSD under `/Volumes/Keller Family Photos/June 10 2026 dump (move)/AdditionalStorage/TradingCardScannerMVP_fixed_v4/`

The run used the normal signed path; it did not set
`CODE_SIGNING_ALLOWED=NO` or otherwise suppress entitlements:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' \
  -derivedDataPath '/Volumes/Keller Family Photos/June 10 2026 dump (move)/AdditionalStorage/TradingCardScannerMVP_fixed_v4/DerivedData/revision-f-full-baseline-2026-09-12' \
  -resultBundlePath '/Volumes/Keller Family Photos/June 10 2026 dump (move)/AdditionalStorage/TradingCardScannerMVP_fixed_v4/Results/revision-f-full-baseline-2026-09-12.xcresult' \
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES
```

## Result-bundle summary

Read from the completed `.xcresult` with `xcresulttool`:

```text
1095 total test entries
1085 passed
1 skipped
9 failed
result: Failed
```

The xcodebuild console reported 66 failure entries because the accuracy tests
emit multiple assertions and XCTest reports retries/repeated occurrences. The
result-bundle summary above is the authoritative count of failed test entries.

### Failed test entries

All nine failed entries are centering failures:

- `CardCenteringGroundTruthTests.testAnalyzerMatchesHoldoutGroundTruthThroughProductionEntryPoint()`
- `CardCenteringGroundTruthTests.testFrontArtWindowIsNotReplacedByTheFullCardPrintedBorder()`
- `CardCenteringGroundTruthTests.testL1PublicPipelineReportsEveryFixtureAndNeverConfidentlyWrong()`
- `CardCenteringGroundTruthTests.testPortraitFrontArtWindowUsesTheGradeableInnerReference()`
- `CardCenteringInvariantTests.testINV4HorizontalMirrorComplementsLeftRightOnly()`
- `CardCenteringInvariantTests.testINV5QuarterTurnsMapThePerSideRatios()`
- `CardCenteringInvariantTests.testINV7UniformScaleDoesNotChangeRatios()`
- `CardCenteringInvariantTests.testREQ022AnalysisPerformanceOverAllFixtures()`
- `CardCenteringInvariantTests.testREQ043ReferenceTypeIsChosenSemanticallyAcrossDevelopmentCorpus()`

The known pre-existing
`MagicTreatmentTests.testTreatmentQualifiedDisplayLabelsCoverAtLeastTwentyDualFinishFixtures()`
failure appeared in an earlier historical baseline but did not fail in this
current result bundle. The centering diff does not modify the Magic treatment
sources. There were no Keychain `-34018` failures in this signed run.

## Current centering evidence from the same branch

- `CardCenteringAnalyzerTests`: 21/21 passed in the focused signed rerun,
  including sideways, skewed, low-contrast, unequal-border, thin-banner, and
  physical-silhouette coverage.
- `testMaskFailureDeclinesWithoutAnInnerReference`: passed; IMG_0782 remains
  declined without an exposed ratio.
- The full invariant class completed with the expected current failures:
  INV-4 `1.4 pp`, INV-5 `0.7/1.4/1.1 pp` at 90/180/270 degrees, INV-7 `1.4 pp`,
  and REQ-022 `2.801/2.972 s` median/max against `0.80/1.50 s`.
- The current E7 resolution curve reports `3/10` descriptive ratio passes at
  each tested maximum. The only pass among the ten records is the intentional
  no-ratio decline for IMG_0782 plus the two known-good development readings
  IMG_0350 and IMG_0352; no conclusion about holdout generalisation is valid
  because the corpus is development-exposed.
- The low-detection/full-resolution-refinement curve is faster than full
  resolution at 2400 (`3.716/3.916 s` median/max), but still misses the
  original budget and is not a production change.
- The latest E-A branch probe remains `9 confident / 1 declined`; IMG_0782 is
  the only decline. All nine non-`none` outputs still report `art_window`,
  including the five backs whose ground truth requires `printed_border`.

## Current REQ-042 ledger

The corrected post-E-REQ044 ledger was regenerated on the same pinned
simulator and original HEIC inputs. Its focused evidence-generation test
passed 1/1, and the full suite also regenerated the same checked-in files.
The inner metric now uses the plan’s fixed `0.0035 * H` tolerance; the earlier
29/36 result used the outer GT-band tolerance and remains historical only.

| Family | Gradeable edges | In tolerance | Recall |
|---|---:|---:|---:|
| Outer | 40 | 34 | 85.0% |
| Inner | 36 | 28 | 77.8% |

The eight gradeable inner misses are:

- left: IMG_0347, IMG_0352
- bottom: IMG_0348, IMG_0351, IMG_0780, IMG_0781, IMG_0783
- right: IMG_0780

The four IMG_0782 inner sides are excluded because its ground truth correctly
has no inner reference. `bestErrorPx` is the closest available candidate,
not the production-selected candidate; the misses therefore identify absent
candidate evidence, not selector mistakes. Candidate roles are still largely
untyped, and the universal `art_window` output remains a separate semantic
defect.

## Interpretation and next gate

This baseline confirms that the simulator and signed test path are usable and
that the synthetic analyzer regression class remains intact. It does not meet
the accuracy, invariant, semantic-reference, latency, screenshot, or device
gates. The current implementation must not be tuned against this exposed
ten-fixture corpus as though it were a holdout.

Per REQ-040, the next production perception change is blocked until at least
30 capture-condition-diverse images are added and at least 10 are frozen as a
previously unseen holdout. Once that precondition is met, the plan’s next
implementation order is the registered back-reference branch, then the
separate front-bottom candidate generator; selector tuning remains gated on
role-correct candidate recall.
