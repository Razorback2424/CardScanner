# Card-centering evidence table

Status date: 2026-09-21 (REQ-045 selector/hybrid outcome and hybrid seed-prior diagnostic; earlier fixture rows remain historical).
The original `TUNE` and `HOLDOUT` labels
are retained below for chronology, but all ten fixtures are now `DEV-HISTORICAL`: every original
holdout has been inspected or used in repeated diagnostics, and E-B included IMG_0349 and
IMG_0351. They no longer measure generalisation. The new corpus manifest covers those ten plus
23 additional raw HEIC captures and 11 PNG reference images, with 24 new files in `DEVELOPMENT`
and 10 in a cryptographically frozen `HOLDOUT-INTERIM`. This is a provisional safeguard only:
the HEICs are from one iPhone model, the PNG capture role is unknown, no new ground truth exists,
and REQ-040's final 30-capture varied-condition gate remains open. See the
[implementation plan](../opus-card-centering-implementation-plan.md) and
[corpus manifest](../../TestFixtures/TradingCards/Supplementary/corpus-manifest.json).

The 2026-09-20 remediation checkpoint formalizes the interim split with a machine-readable
`holdoutFreeze` block and keeps its final REQ-040 gate open. Centering diagnostic writers now
default to simulator temporary storage (or the explicit `CENTERING_DIAGNOSTIC_OUTPUT_ROOT`), so
diagnostic reruns do not modify tracked review artifacts. The registered back-template branch
and front-bottom candidate generator are implemented; their focused ledger evidence is recorded
in the plan and experiments log, while the checked-in 2026-09-12 ledger remains the historical
pre-remediation snapshot.

The 2026-09-21 follow-up gates the discarded front-bottom generator call to DEBUG. A controlled
same-session ten-fixture A/B measured inner-generation medians of `0.7869/1.0085 s` without/with
the generator and wall medians of `2.5304/2.7284 s`; the overall latency contract remains
failing. The five development front identity scores were also recorded: the largest winning
family score was `0.5500`, below the unchanged `0.72` gate, and no front passed the full
registered-back gate. The new registered-branch constants are inventoried in the plan; the
interim holdout remains sealed and unevaluated.

The bounded REQ-044 selector attempt then ran on the ten development fixtures only, without
reading the sealed holdout. Nine fixtures were gradeable; `0/9` selected candidate readings met
both `≤ 2.0 pp` ratio tolerances and `9/9` remained wrong under the pre-hybrid
automatic-confidence interpretation. The zero-wrong / `≥ 80%` bar failed, so the selector was
not promoted. The current product contract is hybrid: automatic geometry is an editable starting
guide, but both frames are `manualConfirmationRequired` and ratios/export remain unavailable
until explicit confirmation or adjustment of both frames. Unsupported cases remain declined.

The post-confirmation-boundary centering rerun used the seven centering classes on the pinned
iPhone 17 Pro / iOS 26.5 simulator with `CODE_SIGNING_ALLOWED=NO`: 92 tests, 72 passed and 20
failed in `1,077.241 s`. The changed-contract classes passed (`CardCenteringAnalyzerTests` 21/21,
`CenteringExportTests` 19/19, `CardCenteringGroundTruthTests` 12/12,
`CardCenteringSurfaceTests` 2/2, and the corpus manifest 1/1). The 20 remaining failures are
open INV-2/4/5/7/8, REQ-022 latency, and E0/E-E diagnostic assertions; no holdout was read.
The result bundle is `/tmp/TradingCardScannerCenteringFull-20260921-v2.xcresult`.

The hybrid seed-prior diagnostic then compared detector-seeded inner depths with a leave-one-out
same-family median across nine gradeable development fixtures and 36 edges. It passed 1/1 and
showed a mixed family/side result: Pokémon bottom favored the prior, Magic top/bottom favored
the detector, and the remaining sides were mixed or prior-favoring. This does not justify a
blanket T/B seed replacement. The sealed holdout was not read and no production seed policy or
threshold changed; the diagnostic output remained in simulator temporary storage.

The screenshot/metadata cells in the fixture table are a **pre-E-B capture
snapshot**. They are intentionally preserved because they are the artifacts
actually captured by the L3 route; their 3-confident/7-declined count is not the
current hybrid analyzer count. The earlier E-A/E-B branch result was 8 confident / 2
declined; the latest focused E-REQ044 branch result is recorded separately below
as 9 confident / 1 declined, both pre-hybrid historical snapshots. Accuracy is evaluated
against the rederived analyzer-free GT. The pre-E-REQ044 accuracy run passed 8/12 cases and failed
4; it remains historical. The current post-E-REQ044 full suite has 1,095 result
entries: 1,085 passed, 1 skipped, and 9 failed; all nine failed entries are
centering failures. The known pre-existing Magic-treatment failure from an
older baseline did not recur in this run. The current E7 curve is now retained
in `diagnostics/E7/`:
at 1200 px it is 9 confident / 1 declined with 3/10 descriptive ratio passes.
The prior transition-width-guard files are retained only as intermediate history.

`REQ-006 before` is the immutable scalar baseline in
[`baseline-2026-09-11/baseline.json`](baseline-2026-09-11/baseline.json). Every
`after` cell is either linked to a retained artifact or explicitly marked
`OPEN`; no simulator result is inferred from a build or a console-only run.
The pinned simulator did run after a transient service recovery; the retained
full-suite classification is in
[`after/simulator-status-2026-09-11.md`](after/simulator-status-2026-09-11.md).
The historical signed REQ-039 baseline is summarized in
[`baseline-2026-09-12.md`](baseline-2026-09-12.md). The current post-E-REQ044
baseline is summarized in
[`baseline-post-ereq044-2026-09-12.md`](baseline-post-ereq044-2026-09-12.md);
its result bundle is on the external SSD. Both earlier runs remain available
for historical comparison.
Status vocabulary: `FAILING` means a runtime assertion genuinely failed;
`UNADJUDICATED` means a historical result predates the rederived GT and is
retained only for chronology;
`OPEN / DEVICE-PENDING` means the required app route or physical device has
not been exercised. These are distinct from the earlier environmental
simulator interruption. `SNAPSHOT` means an artifact is retained from an older
implementation state and is not a current-branch claim.

## Latest focused raw-HEIC branch result (E-REQ044, default 1200-pixel path)

This table is the latest focused analyzer branch evidence after the E-REQ044
outer-guard/per-side-fallback change, not screenshot-pixel evidence. The earlier
E-A/E-B 8-confident / 2-declined result remains historical; a full accuracy and
resolution-curve rerun after the final per-side fallback is still pending.

| Fixture | State | Inner source | Scalar pinned | Scalar/Vision agree | Reason |
|---|---|---|---:|---:|---|

| `IMG_0347` | confident | profile | yes | no | — |
| `IMG_0348` | confident | visionArtWindow | no | no | — |
| `IMG_0349` | confident | profile | yes | yes | — |
| `IMG_0350` | confident | profile | yes | yes | — |
| `IMG_0351` | confident | profile | yes | yes | — |
| `IMG_0352` | confident | profile | yes | no | — |
| `IMG_0780` | confident | profile | no | no | — |
| `IMG_0781` | confident | scalarInner | no | yes | — |
| `IMG_0782` | declined | none | yes | no | missing inner reference |
| `IMG_0783` | confident | profile | no | yes | — |

The original signed post-REQ-027 E7 resolution sweep is the complete pre-E-REQ044
accuracy/latency benchmark; IMG_0782 declined at 1200, 1600, 2000, and 2400 pixels in
both benchmark curves. The tracked E7 JSON/Markdown were later overwritten by the
intermediate transition-width-guard run, before the final per-side fallback, and are
retained as that intermediate snapshot. Both snapshots confirm REQ-030's no-inner
safety behavior for their tested benchmark modes; a new complete post-per-side-fallback
curve is required before promoting confidence/accuracy counts as current.

The E-A branch fields are present under each record's nested `finalAnalysis` object. The latest
focused probe is 9 confident / 1 declined. `outlineHasInner` is mixed: true for IMG_0347, IMG_0348,
IMG_0350, IMG_0352, IMG_0781, and IMG_0782, and false for IMG_0349, IMG_0351, IMG_0780, and IMG_0783.
All nine records carrying any inner reference still report `art_window`, including the current
`scalarInner` path and all five backs whose GT requires `printed_border`; IMG_0782 correctly
reports `none`. Branch availability improved, but reference-type classification is not complete.

| Fixture | Cohort / conditions | Ground-truth target | Outer edge, corners, centre — before → after | Inner edge and ratios — before → after | Rotation and rectification — before → after | Confidence / decline — before → after | L2 metamorphic coverage | L3 screenshot / REQ-021 | REQ-022 and trace |
|---|---|---|---|---|---|---|---|---|---|
| `IMG_0347` | TUNE · back · sleeve, shadow, low contrast | [GT JSON](../../TestFixtures/TradingCards/GroundTruth/IMG_0347.gt.json) · [overlay](ground-truth/IMG_0347_gt.png) | [Baseline bbox](baseline-2026-09-11/baseline.json) `L49 T59 R848 B1136`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `LR 24.8/75.2`, `TB 78.0/22.0`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) rotation `1.253°`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `ok=true` with warning; after must be confident or decline | [INV suite](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) · `FAILING`; current L1 run reports outer/inner geometry, centre, aspect, ratio, and reference-selection errors | [PNG](after/screenshots/IMG_0347_CenteringExpanded.png) · [JSON](after/metadata/centering-IMG_0347.json) · captured; declined | [OPEN](after/simulator-status-2026-09-11.md) |
| `IMG_0348` | TUNE · front · sleeve, glare | [GT JSON](../../TestFixtures/TradingCards/GroundTruth/IMG_0348.gt.json) · [overlay](ground-truth/IMG_0348_gt.png) | [Baseline bbox](baseline-2026-09-11/baseline.json) `L58 T60 R873 B1165`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `LR 44.2/55.8`, `TB 42.9/57.1`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) rotation `1.863°`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `ok=true`; after must be confident or decline | [INV suite](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) · `FAILING`; current L1 and portrait art-window checks report geometry/ratio errors | [PNG](after/screenshots/IMG_0348_CenteringExpanded.png) · [JSON](after/metadata/centering-IMG_0348.json) · captured; confident | [OPEN](after/simulator-status-2026-09-11.md) |
| `IMG_0349` | HOLDOUT · front · sleeve, glare, low contrast | [GT JSON](../../TestFixtures/TradingCards/GroundTruth/IMG_0349.gt.json) · [overlay](ground-truth/IMG_0349_gt.png) | [Baseline bbox](baseline-2026-09-11/baseline.json) `L50 T22 R849 B1166`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `LR 21.6/78.4`, `TB 88.2/11.8`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) rotation `0.887°`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `ok=true` with warning; after must be confident or decline | [holdout test](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) · `FAILING`; current holdout/L1 runs report ratio and geometry/inner-edge errors | [PNG](after/screenshots/IMG_0349_CenteringExpanded.png) · [JSON](after/metadata/centering-IMG_0349.json) · captured; declined | [OPEN](after/simulator-status-2026-09-11.md) |
| `IMG_0350` | TUNE · back · sleeve, shadow, low contrast | [GT JSON](../../TestFixtures/TradingCards/GroundTruth/IMG_0350.gt.json) · [overlay](ground-truth/IMG_0350_gt.png) | [Baseline bbox](baseline-2026-09-11/baseline.json) `L21 T47 R858 B1168`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `LR 39.2/60.8`, `TB 93.4/6.6`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) rotation `-0.715°`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `ok=true` with warning; after must be confident or decline | [INV suite](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) · `FAILING`; current L1 run reports outer/inner geometry and ratio/reference-selection errors | [PNG](after/screenshots/IMG_0350_CenteringExpanded.png) · [JSON](after/metadata/centering-IMG_0350.json) · captured; declined | [OPEN](after/simulator-status-2026-09-11.md) |
| `IMG_0351` | HOLDOUT · front · sleeve, glare | [GT JSON](../../TestFixtures/TradingCards/GroundTruth/IMG_0351.gt.json) · [overlay](ground-truth/IMG_0351_gt.png) | [Baseline bbox](baseline-2026-09-11/baseline.json) `L55 T57 R826 B1156`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `LR 23.7/76.3`, `TB 69.4/30.6`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) rotation `0°`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `ok=true` with warning; after must be confident or decline | [holdout test](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) · `FAILING`; current holdout/L1 runs report ratio, centre, and inner-edge errors | [PNG](after/screenshots/IMG_0351_CenteringExpanded.png) · [JSON](after/metadata/centering-IMG_0351.json) · captured; declined | [OPEN](after/simulator-status-2026-09-11.md) |
| `IMG_0352` | TUNE · back · sleeve, shadow | [GT JSON](../../TestFixtures/TradingCards/GroundTruth/IMG_0352.gt.json) · [overlay](ground-truth/IMG_0352_gt.png) | [Baseline bbox](baseline-2026-09-11/baseline.json) `L38 T85 R846 B1164`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `LR 38.6/61.4`, `TB 78.8/21.2`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) rotation `0.711°`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `ok=true` with warning; after must be confident or decline | [INV suite](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) · `FAILING`; current L1 run reports outer/inner geometry and ratio/reference-selection errors | [PNG](after/screenshots/IMG_0352_CenteringExpanded.png) · [JSON](after/metadata/centering-IMG_0352.json) · captured; declined | [OPEN](after/simulator-status-2026-09-11.md) |
| `IMG_0780` | TUNE · front · un-sleeved, low contrast | [GT JSON](../../TestFixtures/TradingCards/GroundTruth/IMG_0780.gt.json) · [overlay](ground-truth/IMG_0780_gt.png) | [Baseline bbox](baseline-2026-09-11/baseline.json) `L60 T56 R859 B1206`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `LR 75.7/24.3`, `TB 39.7/60.3`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) rotation `1.099°`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `ok=true`; after must retain `artWindow` | [art-window test](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) · `FAILING`; current art-window/L1 checks report ratio and inner-edge errors | [PNG](after/screenshots/IMG_0780_CenteringExpanded.png) · [JSON](after/metadata/centering-IMG_0780.json) · captured; confident | [OPEN](after/simulator-status-2026-09-11.md) |
| `IMG_0781` | TUNE · back · un-sleeved, low contrast | [GT JSON](../../TestFixtures/TradingCards/GroundTruth/IMG_0781.gt.json) · [overlay](ground-truth/IMG_0781_gt.png) | [Baseline bbox](baseline-2026-09-11/baseline.json) `L64 T62 R856 B1168`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `LR 48.7/51.3`, `TB 36.8/63.2`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) rotation `0.841°`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `ok=true`; after must retain `printedBorder` | [INV suite](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) · `PASS` for the retained decline/rectification safety result; no successful ratio is claimed | [PNG](after/screenshots/IMG_0781_CenteringExpanded.png) · [JSON](after/metadata/centering-IMG_0781.json) · captured; declined | [OPEN](after/simulator-status-2026-09-11.md) |
| `IMG_0782` | HOLDOUT · front · un-sleeved, internal light region | [GT JSON](../../TestFixtures/TradingCards/GroundTruth/IMG_0782.gt.json) · [overlay](ground-truth/IMG_0782_gt.png) | [Baseline bbox](baseline-2026-09-11/baseline.json) `L54 T39 R846 B661`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) produced `LR 44.5/55.5`, `TB 86.0/14.0`; GT requires no ratio; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) rotation `0.401°`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `ok=true` was unsafe; after must be `declined` | [decline assertions](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) · `PASS` for no-inner-reference safety; real route capture passed; UI manual entry remains open | [PNG](after/screenshots/IMG_0782_CenteringExpanded.png) · [JSON](after/metadata/centering-IMG_0782.json) · captured; declined/no ratio | [OPEN](after/simulator-status-2026-09-11.md) |
| `IMG_0783` | HOLDOUT · back · un-sleeved, low contrast | [GT JSON](../../TestFixtures/TradingCards/GroundTruth/IMG_0783.gt.json) · [overlay](ground-truth/IMG_0783_gt.png) | [Baseline bbox](baseline-2026-09-11/baseline.json) `L53 T55 R847 B1161`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `LR 52.6/47.4`, `TB 29.2/70.8`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) rotation `0°`; after `OPEN` | [Baseline](baseline-2026-09-11/baseline.json) `ok=true`; after must be confident or decline | [holdout test](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) · `FAILING`; current holdout/L1 runs report LR/TB ratio and inner-edge errors | [PNG](after/screenshots/IMG_0783_CenteringExpanded.png) · [JSON](after/metadata/centering-IMG_0783.json) · captured; confident | [OPEN](after/simulator-status-2026-09-11.md) |

Supplementary route cases are tracked explicitly even though their source
captures are not available in this session:

| Supplementary case | Ground truth / source | Geometry and ratios | Screenshot / metadata | Status |
|---|---|---|---|---|
| Declined fixture route | [IMG_0782 GT](../../TestFixtures/TradingCards/GroundTruth/IMG_0782.gt.json) | GT has `innerQuad=null`; expected ratio is `none` | [PNG](after/screenshots/IMG_0782_CenteringExpanded.png) · [JSON](after/metadata/centering-IMG_0782.json) | PASS — automatic route declined with no inner reference and no ratio; screenshot retained |
| Manual correction route | [IMG_0782 GT](../../TestFixtures/TradingCards/GroundTruth/IMG_0782.gt.json) plus manual guide input | Manual recovery target is within 2.0 pp of GT when an inner reference is supplied | [OPEN](after/README.md#simulator-status) | PARTIAL — manual recovery XCTest passed; screenshot after actual UI guide entry remains open |
| Wide-lens / flatbed / graded-slab fixtures | [supplementary status](../../TestFixtures/TradingCards/Supplementary/README.md) | Independent GT not present; no result claimed | [OPEN](after/README.md#simulator-status) | OPEN / DEVICE-PENDING |

## Cross-fixture REQ status

| Requirement | Measured result | Traceable artifact | Status |
|---|---|---|---|
| REQ-001 / REQ-003 ground truth | Ten analyzer-free dual-pass records and ten regenerated review overlays; non-integral coordinates, recorded agreement, strict aspect, and exact ambiguity metadata validate | [GroundTruth tests](../../TradingCardScannerTests/OpusImplementationPlanTests.swift), [ground-truth review](ground-truth-review.md), [rederived diagnostics](diagnostics/GT-rederived/) | PASS for the ground-truth/provenance gate; L1 accuracy remains failing separately |
| REQ-002 holdout discipline | The original holdout is development-exposed and cannot measure generalisation; a new varied set is required by REQ-040 | [revision-E plan](../opus-card-centering-implementation-plan.md) and fixture rows above | FAILING / replacement OPEN |
| REQ-004 / REQ-025 public L1 entry point | Accuracy tests call `CardCenteringAnalyzer.analyze(Data)`; the first current rederived-GT run executed 12 test cases, 8 passed and 4 failed | [L1 tests](../../TradingCardScannerTests/OpusImplementationPlanTests.swift), [REQ-027 result](after/simulator-status-2026-09-11.md) | FAILING accuracy subset; result bundle retained on external SSD |
| REQ-006 baseline freeze | SHA-256 manifest covers the immutable baseline directory | [SHA256SUMS](baseline-2026-09-11/SHA256SUMS), [baseline JSON](baseline-2026-09-11/baseline.json) | PASS by manifest test |
| REQ-007 / REQ-008 quad geometry and ratio source | Ordered quads, perpendicular borders, and rectified aspect are implemented | [measurement model](../../TradingCardScanner/Models/CardCenteringMeasurement.swift), [geometry tests](../../TradingCardScannerTests/CenteringExportTests.swift) | PASS in focused analyzer/geometry tests; real-fixture accuracy has current failures |
| REQ-009 / REQ-010 / REQ-011 / REQ-012 detection robustness | Shape and sleeve/card proposal machinery exists, but the current L1 run reports geometry/ratio failures and E-A shows no effective face-specific reference classification: all nine non-`none` records report `art_window`, including five backs | [E-A summary](diagnostics/EA/summary.json), [L1 tests](../../TradingCardScannerTests/OpusImplementationPlanTests.swift), [experiments log](experiments-log.md) | PARTIAL / FAILING perception architecture |
| REQ-013 orientation and supplementary coverage | EXIF 1/3/6/8 variants are generated in tests; real wide/flatbed/JPEG/slab sources remain unavailable | [supplementary status](../../TestFixtures/TradingCards/Supplementary/README.md), [INV-6 tests](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) | OPEN / DEVICE-PENDING |
| REQ-014 upload/camera convergence | Import path and camera lens/correction configuration are represented in source; hardware convergence not exercised | [camera configuration test](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) | OPEN / DEVICE-PENDING |
| REQ-015 / REQ-016 rotation and rectification | Fitted-edge skew and rectification guards are implemented; INV-3 passed in the current targeted run, while the rederived-GT L1 run still reports fixture residuals | [analyzer](../../TradingCardScanner/Services/CardCenteringAnalyzer.swift), [rectification tests](../../TradingCardScannerTests/CenteringExportTests.swift), [experiments log](experiments-log.md) | PARTIAL / FAILING accuracy subset |
| REQ-017 / REQ-018 manual fallback, confidence and no-ratio safety | Manual editing, explicit confidence, declined display and no-ratio paths are implemented; automatic outer and inner frames remain pending until explicit confirmation or adjustment, while declined recovery remains available; the no-inner-reference assertion and declined screenshot passed | [measurement tests](../../TradingCardScannerTests/CenteringExportTests.swift), [view](../../TradingCardScanner/Views/CardCenteringView.swift), [experiments log](experiments-log.md) | PARTIAL; manual-correction screenshot remains OPEN |
| REQ-017 manual fallback | Manual setters and declined recovery are covered by the invariant test source; IMG_0782 automatic decline screenshot is retained | [manual recovery test](../../TradingCardScannerTests/OpusImplementationPlanTests.swift), [declined screenshot](after/screenshots/IMG_0782_CenteringExpanded.png) | PARTIAL; screenshot after actual guide entry OPEN |
| REQ-019 / REQ-020 export and rendering | Quad-traced guides share the fitted image frame and rotation | [export tests](../../TradingCardScannerTests/CenteringExportTests.swift) | PASS in static test-target build; runtime suite pending |
| REQ-021 screenshot validation | All ten real-fixture PNG/JSON route artifacts are retained; independent screenshot-pixel measurement, injected-2 px sensitivity, and manual-correction capture remain open | [after status](after/simulator-status-2026-09-11.md), [screenshots](after/screenshots/README.md), [metadata](after/metadata/README.md) | PARTIAL / measurement OPEN |
| REQ-022 analysis cost | The signed pre-E-REQ044 1200 path measured 2.706/2.935 s versus 0.80/1.50 s; the tracked E7 files now contain an intermediate transition-guard snapshot at 2.733/2.972 s before the final per-side fallback. Higher resolution is slower and can convert declines into confidently wrong results. REQ-041 stage attribution identifies scalar fields and inner candidate generation as the measured bottlenecks; 1200 remains the provisional safety cap | [E7 curve](diagnostics/E7/resolution-curve.md), [low-detection curve](diagnostics/E7/low-detection-curve.md), [REQ-041 profile](diagnostics/REQ-041/README.md) | FAILING budget and resolution safety / optimization OPEN |
| REQ-024 no fixture-specific behavior | Source scan test passed; no fixture identity is intentionally used by production | [source scan test](../../TradingCardScannerTests/OpusImplementationPlanTests.swift), [experiments log](experiments-log.md) | PASS in focused invariant run |
| REQ-026 artifact traceability | This table names the GT, baseline, ten real-fixture screenshot/metadata pairs, and explicit after-status artifacts; manual/injected measurement artifacts remain open | [after README](after/README.md), [experiments log](experiments-log.md) | PARTIAL |
| REQ-027 re-derived ground truth | Ten current records use the analyzer-free dual-profile/visual-adjudication method, contain non-integral geometry and agreement values, validate 10/10, and have regenerated overlays; the original records are archived | [GT review](ground-truth-review.md), [rederived diagnostics](diagnostics/GT-rederived/), [E4 candidates](diagnostics/E4/README.md), [REQ-027 result](after/simulator-status-2026-09-11.md) | PASS for provenance/rederivation; first L1 run against current GT is 8/12 with 4 failed cases |
| REQ-028 sideways/skewed detection | The exact sideways and skewed-card methods were rerun under `CardCenteringAnalyzerTests` on the pinned iOS 26.5 simulator and passed 2/2; the latest containing focused analyzer class is 21/21 | [verification record](verification-2026-09-11.md), [experiments log](experiments-log.md) | PASS in focused current run; full final suite pending |
| REQ-029 resampling-stable inner selection | E2/E6 is historical; the pre-E-REQ044 post-E-D targeted run left INV-4 at 1.4 pp, INV-5 at 0.7/1.4/1.1 pp, INV-7 at 1.4 pp, and INV-8 at 1.1 pp. The full invariant class has not been rerun after the final per-side fallback | [E-D diagnostic](diagnostics/ED/README.md), [E0 comparison](diagnostics/E0/comparison.md), [experiments log](experiments-log.md) | FAILING pre-change subset / current rerun OPEN |
| REQ-030 no-inner safety | IMG_0782 declines at the default path and in both retained E7 snapshots at 1200/1600/2000/2400; the original snapshot is pre-E-REQ044 and the tracked snapshot is pre-final per-side fallback | [E-A summary](diagnostics/EA/summary.json), [E7 curve](diagnostics/E7/resolution-curve.md), [E-D diagnostic](diagnostics/ED/README.md) | PASS for tested benchmark modes; broader supported-mode and all-fixture accuracy closure OPEN |
| REQ-031 latency decision | Signed pre-E-REQ044 E7 median/max: 2.706/2.935 s at 1200 and 7.971/9.723 s at 2400; tracked intermediate transition-guard snapshot: 2.733/2.972 s at 1200 and 7.974/9.748 s at 2400; low-detection/full-refinement reaches 3.685/3.861 s at 2400 in that snapshot. Neither is post-per-side-fallback | [resolution curve](diagnostics/E7/resolution-curve.md), [low-detection curve](diagnostics/E7/low-detection-curve.md) | FAILING original budget / decision OPEN |
| REQ-032 diagnostics and negative-result log | Named E0/E-A diagnostics and experiment ledger exist. The centering test writers now default to simulator temporary storage or the explicit `CENTERING_DIAGNOSTIC_OUTPUT_ROOT`, so reruns no longer dirty tracked review paths; the final intentional-diagnostic review remains open | [experiments log](experiments-log.md), [diagnostics/REQ-042/README.md](diagnostics/REQ-042/README.md), [diagnostics/EA](diagnostics/EA/summary.json) | PARTIAL |
| REQ-033 current status/adjudication vocabulary | Simulator recovery, failure classification, and `FAILING`/`UNADJUDICATED`/`OPEN` vocabulary are recorded | [simulator status](after/simulator-status-2026-09-11.md), [verification](verification-2026-09-11.md) | PASS for documentation guard |
| REQ-034 raw branch diagnosis | Ten raw-HEIC records include branch flags, selected inner source, and profile failure telemetry | [E-A summary](diagnostics/EA/summary.json), [E-A test](../../TradingCardScannerTests/OpusImplementationPlanTests.swift) | PASS for evidence capture |
| REQ-035 independent sleeved inner evidence | Five sleeved fixtures pass the E-B regression at default resolution; both retained E7 snapshots keep IMG_0782 declined at all four maxima; current rederived-GT accuracy still has failures | [E-B test](../../TradingCardScannerTests/OpusImplementationPlanTests.swift), [E-A summary](diagnostics/EA/summary.json), [E7 curve](diagnostics/E7/resolution-curve.md) | PARTIAL / current accuracy failures and broader supported modes OPEN |
| REQ-036 production-equivalent metamorphic harness | Named E-C replacement starts all variants from original HEIC bytes, retains raw/equalized records and source dimensions, and passes the ±0.5% GT-derived working-short-edge assertion for IMG_0783 and IMG_0347; the older E0/E1 values remain historical | [E-C README](diagnostics/E1/README.md), [E-C artifact](diagnostics/E1/resolution.json), [E0 comparison](diagnostics/E0/comparison.md) | PASS for harness construction; invariant/accuracy conclusions remain open |
| REQ-037 deterministic outer refinement | E-D's historical `max(8 px, 2% short edge)` guard preserved the synthetic behavior; E-REQ044 added a general `max(12 px, 2% short edge)` transition-width guard plus per-side fallback. The focused physical-outer test passes and the latest analyzer class is 21/21; full invariant/accuracy stability remains open | [E-D diagnostic](diagnostics/ED/README.md), [experiments log](experiments-log.md), [plan](../opus-card-centering-implementation-plan.md) | PARTIAL / metamorphic stability OPEN |
| REQ-038 post-refinement inner-profile classification | E-E passed with 24 raw/equalized snapshots and 96 per-edge records; raw/equalized records match at the 1200-pixel cap, and the residual is classified as both outer-line displacement and profile depth selection | [E-D diagnostic](diagnostics/ED/README.md), [E-E JSON](diagnostics/ED/profile-normalization.json), [E-E table](diagnostics/ED/profile-normalization.md), [experiments log](experiments-log.md) | PASS for diagnostic classification; REQ-029 remains failing |
| REQ-039 closed sampling class / fresh baseline | Sampling, smoothing, interpolation, radius, fixed-offset, and single transition-feature tuning are closed absent candidate-level proof; current signed post-E-REQ044 baseline and ledger refresh are complete, focused IMG_0783 re-audit remains | [current baseline summary](baseline-post-ereq044-2026-09-12.md), [historical baseline](baseline-2026-09-12.md), [revision-E plan](../opus-card-centering-implementation-plan.md), [experiments log](experiments-log.md) | PARTIAL / re-audit OPEN |
| REQ-040 varied corpus and new frozen holdout | Existing ten are `DEV-HISTORICAL`; the 34-image intake is classified in the corpus manifest, with 24 `DEVELOPMENT` files and 10 cryptographically frozen `HOLDOUT-INTERIM` files. The machine-readable `holdoutFreeze` block records the ten-image split, pre-change selection, sealed/no-GT status, nine cohorts, HEIC+PNG formats, and the explicit limitations. No new ground truth has been assigned. The HEICs are from one iPhone model and the PNG capture role is unknown, so the final varied-condition gate remains open | [corpus manifest](../../TestFixtures/TradingCards/Supplementary/corpus-manifest.json), [supplementary status](../../TestFixtures/TradingCards/Supplementary/README.md), [revision-F plan](../opus-card-centering-implementation-plan.md) | PARTIAL / final gate OPEN |
| REQ-041 stage timing and 1200 safety cap | The redirected post-remediation profile passed 1/1 over 20 analyses; named stages accounted for 0.9991 median / 0.9995 max, with wall time 2.7409/3.2918 s median/max. A same-session ten-fixture A/B measured inner-generation medians of 0.7869/1.0085 s and wall medians of 2.5304/2.7284 s without/with the observational front generator. The call is now DEBUG-only; the 0.80/1.50 s budget still fails and 1200 remains the provisional safety cap | [REQ-041 profile](diagnostics/REQ-041/README.md), [E7 curve](diagnostics/E7/resolution-curve.md), [revision-F plan](../opus-card-centering-implementation-plan.md) | PASS for attribution / original budget still FAILING |
| REQ-042 candidate recall ledger | The post-remediation DEBUG ledger retains outer/inner candidates with source, geometry, support/transition fields, roles, and rejection metadata. The focused run passed 1/1 and measured 34/40 outer edges (85.0%) and 34/36 gradeable inner edges (94.4%) using the fixed `0.0035 * H` inner tolerance; the remaining inner misses are IMG_0352 left and IMG_0780 right, and IMG_0782's no-reference inner edges are excluded. The back-template and front-bottom alternatives are present, but the 95% role-specific gate is not met, so this is diagnostic progress, not completion | [REQ-042 README](diagnostics/REQ-042/README.md), [revision-F plan](../opus-card-centering-implementation-plan.md), [experiments log](experiments-log.md) | FAILING / recall gate OPEN |
| REQ-043 semantic reference branch | The focused semantic test now passes: all five development backs select `registeredBackTemplate`, front fixtures remain on front/profile paths, and IMG_0782 remains `none`. The five-front identity negative-class probe recorded a maximum winning score of 0.5500 versus the unchanged 0.72 gate, with no full-gate false positive. The branch registers observed border transitions; the front-bottom generator is candidate-only until REQ-042 clears. Automatic inner readings are now held for manual confirmation, and the public automatic L1 gate remains failed | [L1/invariant tests](../../TradingCardScannerTests/OpusImplementationPlanTests.swift), [revision-F plan](../opus-card-centering-implementation-plan.md), [experiments log](experiments-log.md) | PARTIAL / semantic validation and L1 OPEN |
| REQ-044 joint selection and stability-aware confidence | The bounded DEBUG selector attempt completed without holdout access: `0/9` gradeable candidate readings met both ratio tolerances and `9/9` remained wrong under the pre-hybrid confidence interpretation. The zero-wrong / `≥ 80%` bar failed and the selector was not promoted. The hybrid confirmation contract is implemented; metamorphic, screenshot, and stability work remain open | [REQ-044 experiment](experiments-log.md), [revision-F plan](../opus-card-centering-implementation-plan.md), [E7 curve](diagnostics/E7/resolution-curve.md) | FAILING selector experiment / hybrid verification OPEN |
| REQ-045 hard go/no-go | Development evidence triggered the hard safety decision: automatic release is stopped, the bounded selector failed its pre-registered bar, and the hybrid path is implemented with ratios/export blocked until explicit confirmation or adjustment of both outer and inner frames. The changed-contract centering tests are green on the targeted run; screenshot/human review, open invariants/latency, device gates, and the sealed holdout remain open | [revision-E plan](../opus-card-centering-implementation-plan.md), [experiments log](experiments-log.md), [corpus manifest](../../TestFixtures/TradingCards/Supplementary/corpus-manifest.json) | FAILING automatic path / hybrid verification and final holdout OPEN |
| Hybrid seed-prior diagnostic | Nine gradeable development fixtures / 36 edges compared detector-seeded normalized inner depths against a leave-one-out same-family median. Pokémon bottom favored the prior (`0.10` versus `0.75` pp median); Magic top/bottom and Pokémon top favored the detector; no blanket T/B replacement was justified | [experiments log](experiments-log.md), [hybrid seed test](../../TradingCardScannerTests/OpusImplementationPlanTests.swift), [implementation plan](../opus-card-centering-implementation-plan.md) | PASS diagnostic / no production change |
| Static verification | Device SDK test build, GT validation, baseline checksum, shell syntax, and diff hygiene | [verification record](verification-2026-09-11.md) | PASS |

## Device-only gates

All five gates remain open as required by the plan; simulator work cannot close
them. The authoritative definitions are in
[`§12 of the plan`](../opus-card-centering-implementation-plan.md).

| Gate | Required evidence | Status / artifact |
|---|---|---|
| DEVICE-PENDING-1 macro / ultra-wide | Real macro-capable iPhone capture through `CenteringCameraView` | OPEN · [status](after/simulator-status-2026-09-11.md) |
| DEVICE-PENDING-2 wide lens fallback | Non-macro device capture through the wide-lens branch | OPEN · [status](after/simulator-status-2026-09-11.md) |
| DEVICE-PENDING-3 distortion correction | Device-supported geometric correction and straightness measurement | OPEN · [status](after/simulator-status-2026-09-11.md) |
| DEVICE-PENDING-4 level indicator | Hardware gravity versus rectification residual | OPEN · [status](after/simulator-status-2026-09-11.md) |
| DEVICE-PENDING-5 on-device latency | Ten-fixture device timing, median and max | OPEN · [status](after/simulator-status-2026-09-11.md) |
