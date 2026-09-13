# Simulator validation status — 2026-09-11 (amended 2026-09-12, revision-E-REQ044)

Required pinned destination: iPhone 17 Pro, iOS 26.5,
`EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`.

## Availability and recovery

The first availability check encountered a transient `CoreSimulatorService`
failure. A fresh invocation of:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun simctl list devices
```

recovered the device set, and the pinned iPhone 17 Pro was booted. The service
failure was environmental and did not justify treating the simulator as
permanently unavailable. The separate iOS 26.5 device named `TradingCardScanner
RM Gate` was not used.

A later check on 2026-09-12 briefly received the same connection-invalid error.
After the simulator service was observed running, a fresh `simctl` invocation
returned the device list again: the pinned iPhone 17 Pro was `Booted` and
`TradingCardScanner RM Gate` was `Shutdown`. The exact documentation guard then
ran against the pinned device; the transient check did not change the retained
test results below.

## Historical full-suite result before E-A/E-B/E-D

The recovered simulator ran the full test suite against the pinned device. The
retained result was:

```text
1,076 tests; 1,045 passed; 24 failed; 7 skipped; approximately 294 seconds
```

The 24 failures were classified as follows:

| Count | Classification | Treatment |
|---:|---|---|
| 6 | Keychain `storeFailed(-34018)` / `errSecMissingEntitlement` | Harness/environment artifact from `CODE_SIGNING_ALLOWED=NO`; excluded from centering count and named explicitly |
| 1 | `MagicTreatmentTests/testTreatmentQualifiedDisplayLabelsCoverAtLeastTwentyDualFinishFixtures` | Pre-existing and outside the centering branch diff; not attributed to this work |
| 17 | Centering implementation/test failures | Genuine centering failures; retained as failing evidence |

The earlier focused runtime invocation that exposed fixture-detection
mismatches is retained as diagnostic evidence, not as a passing L1/L2 result.
Subsequent focused runs on the same pinned simulator established the retained
20/20 `CardCenteringAnalyzerTests`, the E0/E1 diagnostics, the E5 EXIF
self-check/invariant, and the E7 curves documented in
[`../experiments-log.md`](../experiments-log.md). Those focused results do not
erase the 17-failure full-suite result or substitute for a fresh final L1 run
after all remaining changes.

## Fresh signed REQ-039 baseline — 2026-09-12

The pinned iPhone 17 Pro / iOS 26.5 simulator completed a new full signed
`xcodebuild test` run before the REQ-041/REQ-042 spike. DerivedData and the
result bundle were written to the external SSD. The exact command, bundle path,
machine-readable summary, and failure classification are in
[`../baseline-2026-09-12.md`](../baseline-2026-09-12.md).

```text
1088 test cases; 1078 passed; 1 skipped; 9 failed test cases
116 console assertion failures; test session 1037.664 seconds
```

Eight failed test cases are centering failures: rederived-GT/L1 accuracy,
INV-4, INV-5, INV-7, and REQ-022. One is the unchanged Magic-treatment label
leak outside the centering diff. No Keychain `-34018` failures occurred in
this signed run. This pre-E-REQ044 result is historical. The current
post-E-REQ044 baseline is recorded below and in
[`../baseline-post-ereq044-2026-09-12.md`](../baseline-post-ereq044-2026-09-12.md).
The earlier 1076/1045/24/7 run remains historical and is not overwritten.

## Current post-E-REQ044 full-suite baseline — 2026-09-12

The signed full suite was rerun after the final per-side fallback on the same
pinned iOS 26.5 simulator, with DerivedData and the result bundle on the
external SSD. The completed result-bundle summary is:

```text
1095 result entries; 1085 passed; 1 skipped; 9 failed
```

All nine failed entries are centering failures (rederived-GT/L1 accuracy,
INV-4, INV-5, INV-7, REQ-022, and REQ-043). The known pre-existing
Magic-treatment label leak from an older baseline did not recur in this run.
The console reported 66 failure entries because some tests emit multiple
assertions and retries. No Keychain `-34018` failures occurred. The exact
failure identifiers and bundle path are in
[`../baseline-post-ereq044-2026-09-12.md`](../baseline-post-ereq044-2026-09-12.md).

## REQ-041 stage profile — 2026-09-12

The signed DEBUG diagnostic
`CardCenteringInvariantTests/testREQ041ProfilesNamedStageTimingsAcrossAllFixtures`
ran two complete passes over all ten development HEIC fixtures on the same
pinned simulator. All 20 analyses completed; named stages accounted for
`0.999` of both median and maximum independently measured wall time. Median
wall time was `2.7548 s` and maximum wall time was `3.0003 s`.

The dominant measured stages were scalar fields (`1.4909 s`, 54.6% of median
wall time) and inner candidate generation (`0.8349 s`, 30.0%). Decode/
orientation/downscale was `0.2058 s` (7.6%), colour preparation `0.1324 s`
(4.5%), outer candidate/refinement `0.1180 s` (4.1%), and Vision requests
`0.0216 s` (0.8%); joint selection, rectification, and result construction
were each below `0.0001 s` at the reported precision. The original
0.80/1.50-second budget remains unmet, and the 1200-pixel production safety
cap remains in force.

The complete records and discarded watchdog attempt are described in
[`../diagnostics/REQ-041/README.md`](../diagnostics/REQ-041/README.md). This
profile identifies the next performance bottleneck; it does not justify
reopening the closed sampling experiment class.

## Historical REQ-042 candidate recall ledger — pre-E-REQ044

The signed DEBUG test
`CardCenteringInvariantTests/testREQ042CandidateRecallDiagnosticCoversAllFixtures`
ran against the original HEIC bytes for all ten development fixtures on the same
pinned iPhone 17 Pro / iOS 26.5 simulator. The test passed in `27.617` seconds
and wrote a complete candidate ledger for every fixture. The result bundle is
`revision-e-req042-recall-retry-2026-09-12.xcresult` on the external SSD; the
checked-in evidence is under [`../diagnostics/REQ-042/README.md`](../diagnostics/REQ-042/README.md).

At that point the analyzer returned eight confident and two declined fixtures:
the five sleeved fixtures retained an inner source, IMG_0781 declined for its
existing rectification path, and IMG_0782 declined with `innerSource = none`.
The harness found at least one candidate within the existing rederived-GT
edge-band tolerance for `34/40` outer edges and `29/36` gradeable inner edges
(`80.6%`). The seven inner misses are bottom edges on IMG_0348, IMG_0780,
IMG_0781, and IMG_0783, plus left edges on IMG_0347, IMG_0350, and IMG_0352.
IMG_0782's four inner edges are not gradeable and are excluded. Because
`bestErrorPx` is the best candidate available—not the selected candidate—these
seven misses are generator-recall failures. This is preliminary geometric
evidence, not the semantic completion gate: inner candidates are still mostly
labeled `untyped_inner_reference` or
`unknown_inner_candidate`, and the 95% REQ-042 target is not met.

## Current REQ-042 candidate recall ledger — post-E-REQ044

The corrected ledger was regenerated after the final per-side fallback on the
original HEIC bytes. It uses `τ_e` for outer edges and the fixed `0.0035 * H`
tolerance for gradeable inner edges. The evidence-generation test passed, and
the checked-in files are current under
[`../diagnostics/REQ-042/README.md`](../diagnostics/REQ-042/README.md).

```text
outer: 34/40 (85.0%)
inner: 28/36 gradeable (77.8%)
analyzer branch: 9 confident / 1 declined
```

The eight inner misses are IMG_0347 left, IMG_0352 left, IMG_0348 bottom,
IMG_0351 bottom, IMG_0780 right and bottom, IMG_0781 bottom, and IMG_0783
bottom. These are generator-recall misses because `bestErrorPx` is the closest
available candidate. The earlier 29/36 (80.6%) result used the wrong inner
tolerance and remains historical only.

## Historical branch validation after E-A/E-B

The DEBUG-only E-A branch diagnostic was rerun against all ten original HEIC
fixtures. The shape-gated E-B repair produced 8 confident and 2 declined
results at the default 1200-pixel path before the later E-REQ044 outer-guard
and per-side-fallback change:

| Fixture | State | Reason | Inner quad / ratio |
|---|---|---|---|
| IMG_0781 | declined | rectification failure | scalar inner evidence exists, but no reliable result is reported |
| IMG_0782 | declined | missing gradeable inner reference | inner quad is nil and no ratio is exposed |

The five sleeved fixtures retain independent profile/scalar inner evidence.
This is recorded in [`diagnostics/EA/summary.json`](../diagnostics/EA/summary.json)
as availability/safety evidence. The ground truth was rederived separately on
2026-09-12; accuracy is now adjudicable against the current records.

The focused E-B regression and IMG_0782 safety tests passed, and the historical
`CardCenteringAnalyzerTests` class passed 20/20. E-D then introduced a deterministic
outer-edge refinement. Its unconstrained form caused eight assertions across six retained
analyzer tests; the local-offset guard restored the historical analyzer class to 20/20.
The first post-fit invariant run also exposed roll drift; preserving the proposal roll signal
restored INV-3. The latest post-E-REQ044 analyzer regression class is 21/21.

The pre-E-REQ044 post-roll targeted run executed 25 tests: the analyzer class passed
20/20 and the five invariant tests produced six assertion failures. INV-3 passed; INV-4
measured 1.4 pp, INV-5 measured 0.7/1.4/1.1 pp for 90/180/270 degrees, INV-7 measured
1.4 pp, and INV-8 measured 1.1 pp. An intermediate 23-test invariant-class run after
the transition-width guard but before per-side fallback had 14 failures. The full invariant
class and L1/E7 accuracy curve have not yet been rerun after the final per-side fallback.

## Latest focused validation after E-REQ044 — 2026-09-12

The latest production change added a transition-width guard of `max(12 px, 2% of the short edge)` and
made outer-refinement rejection per-side. A rejected side keeps the Vision proposal while
accepted sibling sides remain available; no refinement is returned only when every side is rejected.

The focused broad-transition regression test passed after the guard. The physical-outer test
first failed under an all-or-nothing rejection policy on IMG_0347's right edge (13.0348 px
versus a 10.7449 px tolerance), then passed after the per-side fallback. The refreshed E-D
telemetry dump passed and records broad/low-support left-side rejections on IMG_0347, IMG_0350,
IMG_0352, and IMG_0781 while retaining good sibling proposals/refinements.

The latest signed `CardCenteringAnalyzerTests` run passed 21/21 in 24.326 test seconds.
The refreshed E-A branch diagnostic passed and reported 9 confident / 1 declined: IMG_0782
still declines for missing inner reference and IMG_0781 now reaches a confident state. The
branch fields show mixed `outlineHasInner` availability, while all nine non-none outputs still
report `innerReference = art_window`. The focused REQ-043 semantic test remains red with
5 failures, exactly the five backs expected to report `printed_border`.

A complete invariant-class, L1 accuracy, and E7 resolution rerun after the final per-side
fallback has now run in the full suite. The current invariant failures are INV-4 `1.4 pp`,
INV-5 `0.7/1.4/1.1 pp` at 90/180/270 degrees, INV-7 `1.4 pp`, plus the recorded L1 and
REQ-022 failures. The current E7 curve is retained under `../diagnostics/E7/`; the older
curves remain historical baselines for the prior implementation state.

The exact REQ-028 regression methods were subsequently rerun under the correct
`CardCenteringAnalyzerTests` XCTest class on the same pinned simulator. Both
`testACardPhotographedSidewaysIsStillFound` and
`testStraightensASkewedCardBeforeMeasuring` passed, 2/2, in 4.827 test seconds.
The first attempt used the wrong test-class filter and executed zero tests; that
attempt is discarded rather than counted as validation.

The post-refinement E-E diagnostic then passed in 90.912 seconds, retaining
24 raw/equalized variant snapshots and 96 per-edge records. The records match
at the active 1200-pixel cap and classify the residual as both outer-line
displacement and profile depth selection. This classification does not close
the failing metamorphic gates or the L1 accuracy gate.

The raw-HEIC E-C metamorphic harness then ran the renamed E1 test on this same
pinned simulator. It passed in 85.941 s and wrote twelve raw/equalized records
for IMG_0783 and IMG_0347. Every GT-derived working short-edge assertion was
within ±0.5% of its fixture base. Because the 1200-pixel cap was already active,
the short edge was already constant before equalization. IMG_0347 still
declined at rot90 and rot270 in both raw and equalized runs; this is a branch
stability observation, not an accuracy adjudication.

The original signed post-REQ-027 E7 result bundle is pre-E-REQ044: it shows
IMG_0782 declined at 1200, 1600, 2000, and 2400 pixels in both benchmark curves,
with full-resolution median/max `2.706/2.935 s` at 1200 and `7.971/9.723 s` at
2400, and low-detection/full-resolution-refinement `3.660/3.848 s` at 2400.
Both E7 tests passed in 330.965 test seconds, with the result bundle retained at
`req027-groundtruth-e7-refresh.xcresult` on the external SSD.

The tracked `diagnostics/E7/resolution-curve.*` and `low-detection-curve.*`
files were later overwritten during the intermediate transition-width-guard
invariant run, before the final per-side fallback. That snapshot reports
full-resolution median/max `2.733/2.972 s` at 1200 and `7.974/9.748 s` at 2400;
the low-detection curve reports `2.722/2.975 s` at 1200 and `3.685/3.861 s` at
2400. It is retained for chronology and is not a final post-change curve. Both
snapshots confirm the tested no-inner decline behavior; the original latency
budget remains unmet.

## Current ground-truth adjudication

The provisional five-pixel-grid records were archived under
`ground-truth/provisional-2026-09-11/`. The current ten records were rederived
from the oriented fixture pixels by two independent analyzer-free profile passes,
with visual adjudication against the physical silhouette. The records use
`analyzer_free_dual_profile_fit_with_visual_adjudication`, retain non-integral
coordinates and pre-reconciliation `agreementPx`, and validate 10/10. The full
profile diagnostics and selection manifest are under
`diagnostics/GT-rederived/`; the tracked overlay sheets were regenerated.

The first XCTest run against this current GT set executed 12 test cases: 8
passed and 4 failed on the pinned iOS 26.5 iPhone 17 Pro. Passed checks included
provenance, schema/aspect, resource reachability, baseline checksum, camera
configuration, evidence-table coverage, and IMG_0782 no-inner safety. The
failed cases were the holdout ratio helper, the IMG_0780 art-window ratio check,
the all-fixture L1 production-entry-point gate, and the IMG_0348 portrait-art-
window check. The result bundle is
`req027-ground-truth-after-rederive.xcresult` on the external SSD. These are
current accuracy failures, not provisional-GT or simulator-availability failures.

## Current evidence consequences

- The simulator is **not blocked**. The full-suite runtime work was attempted
  and produced actionable failures.
- REQ-027 remains complete as a ground-truth provenance gate. The pre-E-REQ044
  8/12 accuracy result and its 0/8 confident-numeric ratio result are historical.
  The current post-E-REQ044 full suite/E7 run is 9 confident / 1 declined at
  1200 px with 3/10 descriptive ratio passes, and the current L1 accuracy gate
  still fails. The current result is recorded in
  [`../baseline-post-ereq044-2026-09-12.md`](../baseline-post-ereq044-2026-09-12.md).
- All nine latest E-A records with an inner reference report `art_window`, including
  all five backs. `outlineHasInner` is mixed. Reference-type classification is therefore open under
  REQ-043.
- Higher resolution can convert a decline into a confidently wrong result, so 1200 remains
  the provisional safety cap until REQ-044. REQ-041 stage attribution is complete, with scalar
  fields and inner candidate generation accounting for about 85% of measured median wall time;
  optimization and any budget revision remain open.
- The ten real-fixture L3 screenshots and JSON metadata were produced by the
  required route **before E-B**. They are retained under `screenshots/` and
  `metadata/` as a 3-confident/7-declined historical capture snapshot; they
  have not been recaptured after the latest 9/1 focused branch probe. REQ-021 remains open
  for independent screenshot-pixel measurement and the injected-2 px
  sensitivity check; a manually corrected UI screenshot is also still open.
- The injected-2px screenshot sensitivity check remains open.
- The current rederived GT makes L1/L2 comparisons adjudicable. The first run is
  failing as recorded above; no accuracy result is promoted beyond what the
  retained test bundle proves.
- E0 and historical E1 remain diagnostic-only pre-downsampled artifacts. E-C
  is the named raw-HEIC/equalized replacement for the two E0 fixtures, but it
  does not close the final invariant or accuracy gates.
- E-D remains partial and is documented under
  [`diagnostics/ED/README.md`](../diagnostics/ED/README.md). The latest E-REQ044
  transition-width/per-side-fallback change passes the focused physical-outer test and
  the latest analyzer regression class is 21/21. The older INV-4/5/7/8 failures are
  pre-E-REQ044 evidence; a full current invariant rerun remains pending.
- The five device-only gates remain open: macro/ultra-wide, wide-lens fallback,
  distortion correction, level indicator, and on-device latency.

The production sources and test target build for the generic iOS device SDK; the
latest fresh device-SDK build completed successfully. This file intentionally
does not treat that compile as simulator or hardware validation.

For repeatable large outputs, the working artifact/cache root supplied for this
run is `/Volumes/Keller Family Photos/June 10 2026 dump (move)/AdditionalStorage`.
