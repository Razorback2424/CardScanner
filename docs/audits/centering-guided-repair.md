# Guided centering repair

## Localized Done investigation — 2026-11-01 (open)

This investigation is isolated in [draft PR #19](https://github.com/Razorback2424/CardScanner/pull/19),
on `fix/centering-done-event-sequence`, from merged main
`4a9d70b12d941877e2752fe9cfb5fd1508ce0520` (tree
`6809ca82f89cea5cb69ed10d64c25b679181e042`). It is separate from the portfolio,
token and Reset Guides work in draft PR #18. Existing worktrees, edits and
stashes were preserved. No merge or release acceptance is part of this work.

The earlier passing native precision receipts below remain historical evidence.
They do not supersede the later merged-main failure or establish that it is a
harmless flake.

### Explicit Done boundary repair — 2026-11-02

**Status:** the explicit Done repair has executed natively. Its first repaired
run passes the sequencing methods but fails the overall validation gate for
the separate readiness/evidence problems recorded below. The follow-up also
corrects a native-removal publication warning found by that run. The exact
current-head verdict, checkout SHA and artifact receipts are maintained in
[PR #19's validation receipt](https://github.com/Razorback2424/CardScanner/pull/19)
and the generated Actions manifests; source review alone is not a runtime pass.
PR #19 stays draft and unmerged.
Remote main and the starting PR head were rechecked as `4a9d70b12d941877e2752fe9cfb5fd1508ce0520`
and `47279260010de4d6d1c4ab1c9062115334e0ae4d`. No newer fix was present.

The complete decoded [job 125081729300](https://github.com/Razorback2424/CardScanner/actions/runs/41384336534/job/125081729300)
was inspected before editing. Its exact checkout was `47279260010de4d6d1c4ab1c9062115334e0ae4d`.
This supersedes the older PR/ledger statement that this candidate was queued
without execution. It reproduced a production event-sequencing defect:

| Starting-head selection, run 41384336534 attempt 1 | Methods | Passed | Failed methods | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Localized focused attempt 1 | 1 | 0 | 1 | 0 |
| Localized focused attempt 2 | 1 | 1 | 0 | 0 |
| Localized focused attempt 3 | 1 | 1 | 0 | 0 |
| Complete native precision class | 35 | 33 | 1 | 1 |
| Affected centering/export suites | 120 | 118 | 1 | 1 |
| Original combined selection | 1,503 | 1,500 | 1 | 2 |

The rapid-refocus method fails in each of the last three selections. XCTest's
two failure assertions, one unexpected, belong to **one failed method**.
Focused attempt 1 separately fails while waiting for the initial untouched
Done/blur/unchanged-display guard; later focused passes do not erase it.

In the combined rapid-refocus trace, Done for A (`119,1193`) arrives at
1,874.201 ms, UIKit ends editing at 1,924.061 ms, and the fixture refocuses at
1,926.280 ms while SwiftUI still reports true. B (`119,2297`) reaches the draft
at 2,003.449 ms. A never commits. The later teardown blur at 4,188.576 ms
enters commit and publishes B at 4,188.770 ms as callback 1. The full-class
trace independently delivers B's Done at 2,003.445 ms with SwiftUI focus false;
the delayed focus-true observation arrives at 2,043.016 ms, and B only commits
during teardown at 4,477.379 ms. Times are per-case monotonic milliseconds.

The cause is the dependency on an observed SwiftUI focus transition, not the
locale parser or a value subscription installed too late. These traces do
**not** establish the cause of every historical French-locale timeout.

The starting run retained `catalog-native-results`, artifact `13114804763`,
139,792,040 bytes, SHA-256
`49f911d657ac2cea7c5789aadb658d58924053e37b6ef56df58ace8dbcb461fd`.
It contains the commands/attempt manifest, logs, keyboard diagnostics, per-run
result bundles and combined execution summary. The original artifact's stated
expiry is 2026-11-16 04:07:24 UTC. Complete decoded logs were inspected; local
result-bundle extraction is unavailable through this workspace's configured
network route.

A single fresh [pre-fix reproduction, attempt 2](https://github.com/Razorback2424/CardScanner/actions/runs/41384336534/job/125260500820),
again checked out the unchanged `4727926` head. It **reproduced** the rapid-refocus
failure while waiting for commit 2 in the native class, affected suites and
combined selection. No second retry was requested. The three localized focused
attempts each passed 1/1; native was 33 passed / 1 failed / 1 skipped (35 total),
affected 118 / 1 / 1 (120 total), and combined 1,500 / 1 / 2 (1,503 total).
Each failed selection again has one failed method and two assertions, not two
failed methods. The earlier focused failure in attempt 1 remains recorded.
Attempt 2 retains native artifact `13142235545`, SHA-256
`d958f0b8f2f1996835afc745a55ceafe774de15accff309b46e745dcc40576b3`;
the original attempt's artifact remains separately available.

#### First repaired native run — retained failed attempt

[Run 41444747470, job 125274962125](https://github.com/Razorback2424/CardScanner/actions/runs/41444747470/job/125274962125)
checked out repair commit `ecb4d6a7d6cf108a06a4c7a5a1cacecb216f086a` exactly.
The job was **cancelled**, its execution gate **failed**, and its native
artifact upload **failed**. Passing method totals do not make this a passing
workflow:

| Repaired-head selection | Methods | Passed | Failed methods | Skipped | Execution receipt |
| --- | ---: | ---: | ---: | ---: | --- |
| Localized focused attempt 1 | 1 | 0 | 1 | 0 | Focus-readiness polling deadline |
| Localized focused attempt 2 | 1 | 0 | 1 | 0 | Untouched-Done readiness polling deadline |
| Localized focused attempt 3 | 1 | 1 | 0 | 0 | Exact method completion |
| Focused sequencing/removal | 9 | 9 | 0 | 0 | All nine exact methods completed |
| Complete native precision class | 42 | 41 | 0 | 1 | All 42 exact methods completed |
| Affected centering/export suites | 127 | 126 | 0 | 1 | XCTest total; one completion line was interleaved, so the method gate failed |
| Original combined selection | 1,510 | 1,508 | 0 | 2 | All methods completed; result finalization was cancelled |

The preserved rapid-refocus trace commits A (`119,1193`) at 167.906 ms after
Done at 160.196 ms, before requesting dismissal at 180.140 ms. Immediate
refocus occurs at 287.764 ms with SwiftUI still reporting true. B's own Done
at 341.519 ms commits `119,2297` at 350.633 ms; the first observed blur is only
at 479.071 ms. The stale-focus regression delivers Done with focus false at
1,491.180 ms and publishes at 1,510.091 ms, before focus true at 1,891.670 ms.
The saved-old-end regression replays A's end at 1,392.173 ms without a second
publication; B's legitimate blur at 1,506.189 ms commits B at 1,507.006 ms.
These are production-component traces, not simulated commit implementations.

The two focused failures remain failures in this receipt. Their traces identify
an additional fixture timing defect: the waiter judged its own delayed resume
time rather than the recorded completion time. In attempt 1, focus was observed
at 1,176.348 ms, within the deadline that began after native focus returned at
218.681 ms; the waiter resumed at 2,278.184 ms with `condition=true`. In attempt
2, Done was requested at 2,591.300 ms, the unchanged guard ran at 2,602.600 ms,
UIKit ended at 3,647.440 ms and SwiftUI observed blur at 3,649.689 ms. All required
events were within two seconds, but the waiter resumed at 4,761.701 ms. The
follow-up uses the latest timestamp of **every** required event from the same
field/request, while still requiring the original live condition. Missing,
contrary, stale or post-deadline events cannot satisfy it. The original two-second
limit, observer-before-Done ordering and no-premature-update assertions remain.

Eight new SwiftUI runtime warnings, each also reported by XCTest, occurred in
context replacement and valid focused removal across the four broader phases.
They identify the model publication in the fixture's `accept` callback: native
removal was committing during SwiftUI reconciliation. The follow-up consumes
the immutable removal snapshot synchronously, then publishes only that captured
removal value outside the view-update transaction, with per-field session fences
and context revalidation. Done and ordinary blur still commit synchronously.

The affected-suite stdout split
`testPrecisionDoneReentrantRepeatedActionAndRemovalPublishOnce` across an
unrelated simulator message. Its pass is visible in the fragments and the other
three selections, but the original exact-method gate correctly remained failed.
The follow-up retains raw stdout and extracts exact method identities/statuses
from each finalized `.xcresult`; it does not infer missing methods from totals.
Missing or invalid result data and failures from either evidence source still
fail verification.

The combined XCTest summary finished at 13:02:20 UTC with 1,508 passes and two
skips. Cancellation at 13:02:34 UTC interrupted result finalization after the
35-minute job budget. The subsequent upload failed with `ENOENT` for a moving
file inside `catalog-tests.xcresult/Staging`; only the separate census artifact
survived. **No native result bundle from this candidate was successfully retained.**
The decoded job log remains available at the job link and was inspected in full
(SHA-256 `370c165692fcf6d8ebebfe32a4f403af3344b928f5ab517ddaff2f0836e609b9`).
This evidence loss is a remaining limit of that attempt, not a successful upload.
The follow-up combines the redundant focused launches into one fixed selection
and uploads completed comparison bundles before starting the original combined
selection. It does not increase the job or test timeouts or retry until green.

#### Bounded production change

Only the precision number input owns a native editing session. The enclosing
SwiftUI labels, stepper, reason and model validation remain. A plain SwiftUI
focus Boolean cannot distinguish A's delayed blur from B's legitimate blur,
so the field uses a small `UITextField` representable with a captured native
responder boundary. Other inputs retain their existing behavior.

- Toolbar Done synchronously captures the active editor, field, session,
  locale and native text. It consumes that session before invoking its
  captured update callback, then separately dismisses that same responder.
- Native resignation captures an immutable end event before UIKit can begin
  another edit. Delayed end callbacks carry that event; they never read the
  latest field or draft. Consumed/older sessions cannot publish again.
- Ordinary blur and focused removal still commit valid edits. Removal consumes
  its captured session immediately and publishes the validated captured value
  after SwiftUI reconciliation; a later callback never reads a live draft.
  Per-field boundary tokens also protect against replacement native editors.
  Invalid and
  untouched drafts are consumed without publication. No global next-blur
  suppression is used. Typing alone only changes the native draft.
- The existing locale parser and finite-number validation are unchanged.
  The untouched guard uses the edit's starting display; a captured live-value
  getter preserves unrounded precision, rejects invalidated image contexts,
  avoids duplicate writes before SwiftUI rerenders and restores the actual
  accepted geometry if model validation rejects a parsed value.
- The existing field identity now includes image revision. Captured side,
  frame, image revision, getter and updater remain tied to the same context.
  SwiftUI focus observations affect UI/diagnostics only. The `view.appear` and
  `view.disappear` trace events now identify the owned native window lifecycle;
  a delayed SwiftUI disappearance callback is not a commit source.

#### Regression and execution contract

The preserved rapid-refocus interaction waits only for UIKit blur before
refocusing. The localized observer still precedes Done, all original
precision/text/no-premature-update assertions remain, and the timeout remains
two seconds. Seven additional methods exercise stale focus, immediate
equivalent-value refocus, delayed old end callbacks, legitimate B blur,
context replacement/invalidation, reentrant/repeated Done, removal, invalid
and untouched drafts. The follow-up adds one exact readiness-deadline method
and two native removal methods: a distinct editor's newer same-field boundary
must suppress A, while a different field's boundary must preserve A's legitimate
removal publication. Trace assertions compare native identity, session identity,
exact values, callback counts and Done → consumption → update → dismissal order.

The follow-up recorder runs one fixed `focused-regressions` selection containing
the original localized method and every sequencing/removal/readiness regression,
then the full native class and affected suites. The original combined selection
is unchanged. Every selected method must have an exact completion record from
stdout or a finalized result bundle; aggregate totals cannot supply missing
methods. Missing/duplicate methods, unexpected skips, conflicting status and
earlier failures remain gates. Each invocation records its command, commit,
toolchain, simulator state, raw log, result extraction and `.xcresult`. Completed
comparison bundles are uploaded before combined execution as well as in the
final native artifact. The final head must execute this entire plan; its current
receipt is linked from PR #19 rather than inferred from an earlier commit.
Source discovery for this follow-up selects 13 focused methods, 45 native-class
methods and 130 affected methods; the unchanged combined selection gains ten
methods over the 1,503-method starting head. These are expected selection counts,
not an assertion that the new head has passed.

Local checks cover Python syntax, selection completeness and rejection of
missing/failed/skipped/duplicate completion records, plus `git diff --check`.
Nine persisted Python tests exercise exact result recovery, status conflicts,
failure preservation, wrong-target/missing/duplicate cases and malformed data.
This Linux authoring workspace has neither Swift nor Xcode. Native execution
uses the existing GitHub Actions workflow with an exact-head checkout check;
the unavailable local proxy was not bypassed. The hosted input regressions
exercise the production Done action; actual keyboard-toolbar visibility,
manual VoiceOver/keyboard interaction and physical-device behavior remain
separate UI limits unless explicitly verified below.

### Original failure and evidence limits

The complete [failed job](https://github.com/Razorback2424/CardScanner/actions/runs/41375910704/job/125055978381)
was inspected and retained privately (7,962 log lines). The native result
artifact is available in that run as `catalog-native-results`, artifact
`13111359872`, with a 14-day retention period. Its connector download reference
was obtained, but local transfer failed because the configured proxy was
unreachable. No alternate network route was used; the result bundle's internal
records have not been inspected.

| Historical selection | Executed | Passed | Failed | Skipped |
| --- | ---: | ---: | ---: | ---: |
| Combined native selection | 1,501 | 1,498 | 1 | 2 |
| Native precision class, included above | 33 | 31 | 1 | 1 |
| Export class, included above | 47 | 47 | 0 | 0 |
| Pokémon package, separate from native | 84 | 83 | 0 | 1 |
| Magic package, separate from native | 18 | 18 | 0 | 0 |

`testTypedLocalizedDraftPreservesAllDigitsAndCommitsOnlyOnDone` took 57.321
seconds. Its only failure was the two-second `fr_FR` Done expectation; later
numeric/text assertions did not separately fail. Both French inputs shared the
description, so the failed signed input cannot be recovered from this log.

No test failure preceded it. The preceding classes were Browse (72), sharing
(17), catalog normalization (40), and centering export (47), all passing.
There is no recorded simulator reset, test-process restart or crash. The same
application process continued through later tests. Absence of a reset message
does not establish simulator health.

| Original clock | UTC, November 2 | Observed event |
| --- | --- | --- |
| Application | 02:17:36.318812 | Keyboard main-thread queue timeout. |
| Application | 02:17:39.434007 | Invalid keyboard session ID. |
| Application | 02:18:05.205657; 02:18:19.547168 | Remote keyboard connection invalidation. |
| GitHub log ingestion | 02:18:28.651157 | French Done expectation timeout received. |
| GitHub log ingestion | 02:18:35.406104 | Test failure result received, duration 57.321 s. |

GitHub ingestion and application clocks are buffered/interleaved by up to
approximately 26 seconds here. This table cannot establish the order or delay
of focus, Done, commit, parse, publication or fulfillment; those events were
not instrumented. Keyboard disruption is established, infrastructure-only
causation is not.

Source inspection establishes that commit, parsing and probe publication are
synchronous once invoked, and the value subscription precedes the Done token.
It also establishes unobserved 80/40 ms fixture assumptions and hide-only
window cleanup. Neither source observation alone identifies the failed event.

### Observational baseline

Diagnostic head `b0c6ae3ad548e6d8e11f55bd273e776b91e71b1b` adds unique
locale/signed-input identifiers and per-host monotonic events. It retains the
three inputs, every original assertion, fixed sleeps, original cleanup,
production commit decisions and the two-second deadline. The app installs no
default trace sink or input logging. Instrumented bindings forward the original
transaction, and notification observers add no dispatches or waits.

The recorded events cover UIKit responder/editing calls, the actual draft
binding, observed SwiftUI focus, Done delivery, commit and parse outcomes,
model assignment/publication, fulfillment and teardown. Baseline callbacks
after a case ends are detected during subsequent cases; this does not prove
absence of callbacks after the entire test method has ended.

[Native comparison run](https://github.com/Razorback2424/CardScanner/actions/runs/41381240608)
uses three predetermined focused attempts, one whole-class attempt and one
affected-suite attempt, followed by the unchanged combined selection. It
retains logs, result bundles and an attempt manifest, uses the exact PR head,
and checks actual test-completion records. It reuses the selected simulator
without erasing or resetting it. A failed attempt remains failed even if a
later attempt passes.

| Baseline selection | Executed | Passed | Failed | Skipped | Localized test duration |
| --- | ---: | ---: | ---: | ---: | ---: |
| Focused attempt 1 | 1 | 1 | 0 | 0 | 26.579 s |
| Focused attempt 2 | 1 | 1 | 0 | 0 | 6.689 s |
| Focused attempt 3 | 1 | 1 | 0 | 0 | 7.370 s |
| Full native precision class | 33 | 32 | 0 | 1 | 17.958 s |
| Affected centering suites | 118 | 117 | 0 | 1 | 4.252 s |
| Original combined selection | 1,501 | 1,499 | 0 | 2 | 5.067 s |

These are six executions of the localized method, containing 18 locale/input
cases. They are repeated selections, not a count of distinct methods. The
combined total is XCTest's authoritative suite summary; one unrelated
completion line was interleaved with another log stream. Every required
centering method was individually confirmed. The recorder now preserves both
the suite summary and raw completion counts, and never substitutes an aggregate
count for a missing required method.

All 18 edited drafts were in SwiftUI before Done, and Done arrived with SwiftUI
focus true. Each published exactly once after the request, in 70.264–645.461 ms.
Observed blur to commit took 4–14 microseconds; commit to publication took
0.095–12.498 ms, and publication to fulfillment approximately 0–1 microseconds.
This baseline does not demonstrate a parsing, subscription or publication race.

The baseline had 31 invalid keyboard-session warnings but none of the original
queue timeouts or remote-keyboard invalidations. One initial UIKit focus call
blocked for 5.086 seconds. The original two-second edited-Done failure did not
reproduce; its precise cause remains unresolved, and it is not classified as
infrastructure-only.

### Demonstrated fixture sequencing and cleanup defects

**Eight of 18 initial unchanged-Done blur transitions coalesced across refocus.**
The assertions about preserving the untouched Double passed without executing
the unchanged-display commit guard. **Fourteen disappearance callbacks arrived
after cases were marked ended.** Those callbacks all had focus false; no late
model update or publication was observed.

The affected-suite English case supplies a complete 50-event example. Times
are milliseconds from that case's monotonic origin:

| Time | Event |
| ---: | --- |
| 145.109 | SwiftUI observed focus true. |
| 239.388 | Fixture requested unchanged Done. |
| 242.610 | Field received Done while focused. |
| 292.750 | Fixture requested refocus; UIKit was no longer first responder. |
| 405.738 | UIKit refocus returned true. |
| 498.533 | Fixture inserted `123.45`. |
| 501.235 | SwiftUI draft contained `123.45`. |
| 545.658 | Fixture requested edited Done. |
| 548.526 | Edited Done arrived with focus true and the correct draft. |
| 706.189 | SwiftUI observed its only blur. |
| 706.195 | Commit entered for the edited draft. |
| 706.427 | Model published `123.45`. |
| 706.428 | Expectation was fulfilled. |

There is no intermediate observed blur/refocus pair or unchanged-display
commit. This demonstrates that the original fixed-sleep fixture did not
complete its intended first focus cycle. It does not prove that this caused
the historical edited-Done timeout.

### Fixture correction and behavioral coverage candidate

The corrected localized test retains the same single-field host, locale/input
cases, precision/text/no-premature-update assertions, and Combine subscription
before Done with the original two-second fulfillment timeout. It observes
mounting, fresh UIKit and SwiftUI focus, and the actual draft. Before asserting
untouched-value preservation or refocusing, it requires Done delivery, native
responder loss, a fresh observed SwiftUI blur, and the real unchanged-display
commit guard. Exact callback-count and request-to-mutation deadline assertions
are added.

The shared fixture ends only its own editing session, observes blur and
disappearance, detaches the host, restores the previously visible key window,
and removes its observers before marking the case ended. No cleanup task is
launched from a synchronous defer. Retained traces detect callbacks during
subsequent cases; they do not claim observation forever after the test method.

Two new native cases cover the latest full-precision draft, repeated Done,
rapid native refocus before SwiftUI blur acknowledgment, movement between two
fields, and focused removal with valid, invalid and untouched input. The rapid
refocus case deliberately does not add the ordinary readiness gate that would
remove the interaction under test. Production commit behavior remains
unchanged at this checkpoint. These new cases and the fixture correction are
written and source-reviewed at that historical checkpoint. Their subsequently
failed native execution is recorded in the explicit-boundary repair section
above; the earlier pending statement is no longer current evidence.

The initial diagnostic head `26cad32794930de0e4c13500ecb6a44580eac2be` had a
missing computed-property brace caught in source review. Its superseded
[run](https://github.com/Razorback2424/CardScanner/actions/runs/41381093991)
was canceled during its first build and executed **zero native test cases**.
Its package step passed 101 cases with one skip. That cancellation is not a
reproduction or native pass.

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
