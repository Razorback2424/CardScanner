# Guided centering repair

**Status:** guided correctness and regression checks pass apart from the known
latency case; review follow-up fixes applied; final numeric-field accessibility
and inner-capture rechecks await an unlocked Mac — 2026-10-02.

**Candidate:** uncommitted working tree on `fix/october-review-boundaries`, based
on `73898e8`. This records the approved centering repair, not release certification.
The [centering contract](../../review/opus-card-centering-implementation-plan.md)
continues to govern automatic accuracy and held-out acceptance.

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
