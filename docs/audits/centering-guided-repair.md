# Guided centering repair

## Current precision candidate — 2026-11-01

Branch provenance: `refinement/centering-native-2026-11-01`, based on
`b592c914d2bae7ecfbea03218b20f94bdef90364`; implementation commit `f5f2e14`.
This section supersedes historical candidate and timing claims below for this
patch only. No publication, automatic-release or calibrated accuracy acceptance
is implied. The REQ-045 guided contract and §5.1 tolerances are unchanged.

Implemented guided changes use actual raster dimensions and all eight EXIF
orientations, independent X/Y transforms and rounded presentation canvases.
Advanced controls translate either frame's selected line in 0.1 native-pixel
steps and turn it about its midpoint in 0.01-degree steps. Adjacent supporting
lines stay fixed; invalid intersections retain the last valid geometry with a
reason. Undo/reset, a registered source-pixel detail crop and locale-aware
numeric fields support manual recovery. Decimal granularity is not accuracy.
Typed values keep a localized draft until Done/focus loss. Actual UIKit editing
events preserve French `119,11` and `-0,25`, and English `123.45`, then commit the
exact values; incomplete drafts do not move guides. Focus/Done without editing
preserves the authoritative unrounded Double. Headless HID text injection
reported success without changing even a distinct replacement, so keyboard
tool automation is not counted as acceptance. A scene-less first test harness
failed before locating a field; its scene-backed correction passes.
Original compressed bytes plus one small cached crop are retained for detail;
the disclosure does not retain a full decoded camera raster.

Photo-only rotation remains intentional. Rotation and reset revoke frame
confirmation and immediately invalidate stale share snapshots. Pending or
invalid frames cannot expose ratios/export. Existing homography, candidate
precedence and automatic-reporting safety remain in place.

Native independent-slope refinement is **DEBUG opt-in and disabled in
production**. Development iterations preserve bounded strip sampling, spatial
coverage, residual, slope, nesting and ambiguity gates. V1 accepted 1/36 available
development inner sides; coherent multi-peak V2 accepted 1/36; deduplicated-track
V2b accepted 3/36. These are fit-gate counts, not accuracy. V1's narrow band
included the development reference at enough positions on only 11/36 sides.
Existing profile alternatives repaired some seed coverage, but stable artwork
edges can still win with the wrong semantic identity. One accepted V2b bottom
line is about 1,186 native pixels from a short art-window development reference.
No threshold relaxation can certify that selection. Automatic reporting and
the failed joint selector remain disabled; no sealed holdout was opened.

The exact original Gengar JPEG (1112×1536; SHA256
`d174c27d5aaba21dd4602d926488eb6d93a535f31eabdee5937c13bc4a405562`)
takes `scalarInner` with a Vision outer proposal throughout. Confirming its
unchanged starting guides gives baseline 64.5/35.5 LR, 44.4/55.6 TB; default
candidate 64.4/35.6, 44.0/56.0; experimental V2b 49.8/50.2, 44.2/55.8.
V2b repairs only the left side, leaving top/right/bottom unresolved. The actual
manual-control example gives 52.2/47.8, 50.4/49.6 after explicitly human-selected
guide placement. None of these is calibrated ground truth or automatic success.

Executed scope: 58 selected guided/export tests, 57 passes and one intentional
experimental-benchmark skip; then 109 applicable analyzer, development ground
truth, invariant, export and native tests with 108 cases passing and two latency
assertions failing in the single native benchmark. That failed run included an
unused legacy DEBUG research generator. Its receipt is preserved. A separate
production-equivalent native run with that generator off passes the unchanged
0.8/1.5-second limits (upper median 0.715 s, max 1.414 s). The final applicable
recheck passes **109/109 with zero skips**, including the enabled native gate;
production REQ-022 measures 0.491/0.536 s and native V2b 0.538/1.380 s.
The earlier aggregate's production measurement was 0.493/0.540 s. These are existing ten-fixture Debug
Simulator methods, without new repetitions or device performance acceptance;
they are not a full-target run. Earlier failed raster-test receipts and their
pure-color test correction are also retained, without relaxing its one-device-
pixel registration tolerance.

After adding the draft-field and scene-backed UIKit editing regression, the
final binary, including unchanged-draft preservation, passes **110/110
applicable cases, zero failures or skips**. Production REQ-022 is
0.495113/0.542783 s (upper median/maximum); native V2b is
0.549302/1.387473 s. These final measurements supersede the intermediate 109-case
recheck for this candidate; all earlier receipts remain available.

Evidence is private under `/Volumes/T7/ScanStash-Centering-Evidence-20261101/`:
raw baseline/default/V1/V2/V2b proposals, native points/lines and rejection
reasons, actual app screenshots and model exports, logs and `.xcresult` bundles.
The [precision checklist](../../references/centering_native_precision_checklist.md)
separates executed evidence from pending acceptance. Independent visual review,
VoiceOver traversal, native save completion, representative physical
capture, held-out accuracy and real-device gates remain open.
Native share-popover presentation is visually verified with the confirmed
manual example and retained PNG. Save Image is visible but absent from the
headless semantic target list, so no save completion is claimed. A later
off-viewport semantic rotation target misdirected to Pro; that attempt is
retained as a tooling limit and excluded from rotation acceptance.

## Historical checkpoints

**Rotation correction — 2026-10-29, base `f306918` plus working-tree patch:**
manual rotation now applies only to the photo, leaving the red/cyan measurement
guides fixed on screen and in the shared export. Zoom/pan still move both layers
together. Updated pixel regression expectations supersede the earlier shared
rotation contract; helper text now reads “Rotates photo only.” The focused
`CenteringExportTests` run passes all 28 cases with zero failures/skips. An initial
run used reversed expected signs for the photo stripe's rendered slope; the
corrected test verifies opposite slopes and their magnitudes in both directions.
Evidence is retained externally under `CodexBuild/CenteringRotation-20261029/`.
The [current checklist](../../references/centering_guided_success_checklist.md)
records Simulator visual acceptance separately from historical evidence.

**Latest timing follow-up — 2026-10-14:** the previously failing REQ-022 case
passes in the current Lorcana working tree after exact native scalar/median
optimization. Final full-target results: 2,188 passed, zero failed, 12 skipped;
REQ-022 upper median 0.586 s, maximum 0.649 s at unchanged 0.8/1.5 s limits.
Kernel and ten-fixture geometry/profile parity pass. See the
[production checkpoint](../release/lorcana-production-acceptance.md) for candidate,
stage measurements and archive/export evidence. This replaces the simulator
timing failure status in the historical checkpoints below; hardware/automatic
held-out and rendered accessibility acceptance remain separate.

**Status:** guided correctness and regression checks pass apart from the known
latency case; review follow-up fixes applied; final numeric-field accessibility
and inner-capture rechecks await an unlocked Mac — 2026-10-02.

**Candidate:** uncommitted working tree on `fix/october-review-boundaries`, based
on `73898e8`. This records the approved centering repair, not release certification.
The [centering contract](../../review/opus-card-centering-implementation-plan.md)
continues to govern automatic accuracy and held-out acceptance.

**2026-10-03 refinement checkpoint:** the full signed simulator run against
`dd2a1e3` plus B–J working-tree changes retains REQ-022 as the single observed
centering failing case (upper-middle/median statistic 1.6244 s; maximum 1.9206 s).
Other centering correctness/diagnostic assertions passed. Final post-fix
regression includes the UI/export/input cases and passes 1,707 cases with seven
existing skips across the remaining target. No centering source or tolerance
was changed by this pass. The owner requested wrapping up without further
screenshots or device-specific testing; latest rendered/accessibility/native
acceptance is deferred, not blocked on an inferred locked-Mac state. See the
[refinement evidence](../plans/october-production-refinement-review-plan.md).

## Implemented behavior

- Moving a perspective guide changes its supporting line and adjacent corners,
  preserving the opposite corners, frame roles, and rectification. Valid edits
  after one explicit confirmation update the reading immediately. Invalid,
  inverted, crossing, nonfinite, out-of-bounds, non-nested, or singular geometry
  cannot expose ratios or an export. A new input revokes approval before loading.
- Pending valid frames say **Review frames**. Invalid or missing frames say
  **Reading unavailable**. Confirmation is beside the guide controls and requires
  valid outer and inner frames. Numeric fields, steppers, zoom, and pan remain
  available; accessibility text uses stacked controls and a smaller preview.
  Camera, Photos, and file choices share one toolbar menu so the title fits.
- Loading and analysis use request generations: a late transfer, analysis,
  failure, or cancellation cannot restore an older measurement. Exports capture
  an immutable revision, render away from the main actor, and publish only while
  current. Each export has its own directory, preserving an in-flight share's
  file while subsequent edits prepare a new one.
- Diagnostic options, callbacks, and timing ledgers belong to each analysis.
  Registered-back detection can legitimately bypass scalar profiles. E0/E-E
  checks record the branch and still require four sides when profiles run;
  synthetic profile and concurrent-request tests provide dedicated coverage.
- Pixel preparation reuses RGB/Lab data, caches byte linearization and repeated
  profile transitions, and uses three private C kernels for existing Lab,
  gradient, and foreground arithmetic. Strict floating-point contraction is
  disabled. Resolution, detection thresholds, and selection policy are retained.
  DEBUG keeps the original calculation path for parity tests.

## Test contract and evidence

Guided transform tests apply independently annotated final frames to the
rendered rotation, mirror, quarter-turn, EXIF, scale, and crop variants, then
explicitly confirm them. Their original numerical tolerances remain unchanged.
Nine gradeable exposed development annotations are checked within two percentage
points; the tenth has no gradeable inner reference. The sealed holdout was not
used. No ground truth was changed and no new skips were introduced.

The original automatic transform comparisons are also executed and recorded
under `automatic-transform-gates/results.json`, with their original transforms
and tolerances. They are research evidence, not proof of the guided contract.
Twelve EXIF comparisons pass; ten rotation/mirror/quarter-turn/scale/crop
comparisons remain outside tolerance. Automatic reporting remains disabled, and
all ten original detector outputs must remain unreportable before confirmation.
These automatic gates remain open.

| Verification | Dated result |
| --- | --- |
| Seven centering classes, `Centering-v1` | 109 cases; 108 pass; only `testREQ022AnalysisPerformanceOverAllFixtures` fails, with two latency assertions. No skips. |
| Remaining test target, `NonCentering-v1` | 1,661 cases; seven existing skips; zero failures. |
| Optimized calculations versus original Swift path | Identical measurement geometry and full profile arrays for all ten exposed fixtures. |
| Private pixel kernels | Bit-exact Lab/gradient/mask comparisons, including 65,536 RGB combinations and all byte channel values. |
| Preview geometry | Independent expected positions within 0.5 point and rendered guide centers within one device pixel at scales 2/3, rotations 0/+7/−3 degrees, and zoom/pan. |
| Final UI/export/input rerun, `FinalUI-correctness-v2` | 31 cases pass after toolbar and accessibility refinements. |
| Final regression, `Final-regression` | 1,692 cases; seven existing skips; zero failures after the final DEBUG route correction. Includes those 31 cases and the remaining 1,661; excludes the five already-covered analyzer/corpus/invariant/profile classes. |
| ReleaseLocal simulator build, `Release-build-v3` | Passed for arm64 and x86_64; no archive or release acceptance implied. |
| Physical device | Device build succeeded using the existing signing team. Test launch encountered a locked-device preflight and lost the runner connection; no passing physical-device result claimed. |

The first two rows partition the test target; they are separate runs, not one
passing full-suite invocation. The final regression reruns the UI/export cases
and the rest of the target against the final working-tree binary. The only
observed XCTest failure remains the unchanged latency case in the centering run.
ReleaseLocal used a project-metadata copy on the SSD with links to the current
source, configuration, fixtures, and local packages after macOS file coordination
blocked the project in Documents; the repository project was not relocated.

REQ-022 retains its median ≤0.8 second and maximum ≤1.5 second assertions. The
centering selection measured median **1.6149 seconds**, maximum **1.9211 seconds**.
The earlier October-2 baseline was approximately 3.0119/3.3811 seconds. These are
simulator measurements, not a controlled physical-device comparison. The owner
explicitly accepted wrapping up correctness work while leaving latency open;
the budget was neither relaxed nor skipped.

## Visual verification before the uncommitted-change review

Final phone/tablet captures were visually inspected against the completed
[success checklist](../../references/centering_guided_success_checklist.md).
They cover pending, confirmed, invalid, missing-reference, rotation, zoom/pan,
numeric controls, light/dark appearance, and maximum accessibility-text states.
The initial phone capture exposed toolbar crowding; the first accessibility
capture prompted the smaller preview. Final controls remain readable and
reachable by scrolling; rotation increments keep their complete labels.

Native simulator interaction confirmed that one explicit confirmation exposes
the reading and a subsequent valid edge increment updates it without another
confirmation. Export Image presented the native phone share sheet and anchored
iPad share popover with the prepared PNG and descriptive filename. Both were
dismissed without choosing a destination. Actual VoiceOver traversal and
share/save completion on physical hardware were not verified.

## Evidence location and remaining gates

Builds, logs, result bundles, and captures are on the external SSD under
the external SSD under `CodexBuilds/TradingCardScannerCenteringRepair`.
Generated diagnostics use an explicit `CENTERING_DIAGNOSTIC_OUTPUT_ROOT` when
provided, otherwise simulator temporary storage; they do not rewrite tracked
evidence. Current diagnostics are copied into the SSD evidence directory.
CoreSimulator could not create/capture directly on that removable volume, so
task-owned simulator state and brief screenshot staging use system temporary
storage. A custom-set iPad installer also failed, so final iPad captures used a
task-owned device in the standard simulator set. Existing simulator data is
preserved, and temporary appearance/text-size settings were restored.

Latency, automatic accuracy/held-out acceptance, physical-device responsiveness,
VoiceOver interaction, share/save completion, and release/archive/provider/
CloudKit acceptance remain separate gates. Passing injected rendering and
snapshot tests or simulator share presentation does not certify those manual or
hardware gates.

This repair supersedes the earlier measure-only export-thread-placement
restriction for the authorized immutable revision export implementation. Device
profiling remains necessary before making responsiveness claims or pursuing
further performance work. Other measurement-only backlog items are unchanged.

## Uncommitted-change review — 2026-10-02

The follow-up review at `73898e8` plus the repair working tree found and fixed
five issues with focused changes:

- Crossing a perspective guide swapped the displayed left/right or top/bottom
  positions. Scalar projections now keep each named side's own coordinate.
- Moving a guide exactly onto its opposite erased adjacent supporting lines,
  preventing later edits. Such collapsing edits leave the editable frame intact.
- Inverting both inner axes restored clockwise winding and exposed a false
  reading. Eligibility now checks named side direction as well as winding.
- Confirmed `CenteringOuterControls` and `CenteringInnerControls` fixtures opened
  with collapsed controls. Those routes now initialize the requested disclosure.
- Regular-size numeric fields were embedded in a Stepper label and absent as
  editable elements in the observed simulator accessibility tree. Fields now sit
  beside the Stepper with their own labels and bindings, matching the existing
  accessibility-size separation.

All three geometry regressions failed before the fix and passed afterward. The
seven-class `Uncommitted-review-centering` run executed 111 cases: 110 passed,
with only REQ-022 failing its two unchanged latency assertions. Analyzer/kernel
parity and profile coverage passed. After the view changes,
`Uncommitted-review-final-ui` passed all 33 UI/export/input correctness cases;
its separate REQ-022 recheck still failed at median **1.5814 seconds**, maximum
**1.8764 seconds**, without concurrent compilation. This does not change the
existing latency disposition or establish a performance improvement.
The final `Uncommitted-review-release-final` ReleaseLocal simulator build passed
for arm64 and x86_64 after the view fixes. Project parsing, shell syntax,
all 202 local Markdown link targets, and `git diff --check` also passed.

The final outer-control phone capture shows the expanded, readable controls and
aligned preview. The inner route exposes its requested controls, but its capture
has an incomplete preview/navigation frame while the Mac is locked. The final
accessibility-tree and inner-capture rechecks await an unlocked Mac; no completed
VoiceOver traversal is claimed. Evidence is retained on the SSD under the
`Uncommitted-review-*` names, alongside the earlier evidence.

**HIG verdict: RISK pending final accessibility verification.** Platform patterns,
clarity, typography in the inspected outer capture, interaction cost, and design
behavior pass the scoped review: native controls remain, labels fit, no extra
confirmation is added, and invalid frames cannot expose readings. Accessibility
remains a risk until the final numeric fields and focus order are verified. The
top issues were the hidden numeric fields, misleading inverted readings, and
unrecoverable collapsed guides; the minimal fixes are confined to
`CardCenteringView.swift` and `CardCenteringMeasurement.swift`. To close the risk,
verify independent field editing and focus order and repeat the incomplete
inner capture after unlocking the Mac.
