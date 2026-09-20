# Release follow-ups

**Status:** current validation and measurement backlog — reconciled 2026-09-14.

This document is the aggregation point for gates that source inspection or the
ordinary simulator suite cannot retire. Completed implementation plans are
archived under [`../legacy/`](../legacy/); they are historical context, not
open work queues.

This is the aggregation point for work that cannot be retired by the ordinary
simulator suite. Items below are validation or measurement gates, not suspected
defects. Close an item with the evidence described here, or record the measured
reason to leave it unchanged.

**Where these are picked up:** the active
[launch plan](../superpowers/plans/2026-09-13-phase-0-phase-1-app-store-launch.md)
§0.1.2 references this document, and §0.1.1 binds the open
[pass-2 findings](../audits/defect_review_pass_2.md) to the tasks they block.
RF-6 gates Task 1 and Task 11; RF-7 and RF-8 open only after F01/F02 land.

## Release validation

### RF-1 — Collection cold-launch first paint

**Status:** measurement pending; no persistence change justified yet.

Measure a Release build on a real device with a seeded collection of roughly
1,500 cards. Record the time from launch to the first real collection grid row,
using the existing collection projection signposts.

- If the first row appears in roughly 300 ms or less, close this as
  **won't-fix**; the launch spinner is not perceptible enough to warrant a
  persisted projection snapshot.
- If it is materially slower, evaluate persisting the last
  `CollectionProjectionSnapshot` and replacing it when the actor read completes.

### RF-2 — Scanner tracking at 8 Hz

**Status:** hardware validation pending; simulator cannot retire this item.

Run a physical-device scan pass with a stack of 30 cards and record duplicate
and missed-card rates, confirmation latency, and thermal behavior over a normal
session. Include ordinary cards, similar neighboring cards, and at least one
graded slab if available.

The 8 Hz change should remain unchanged unless this pass produces a concrete
regression.

### RF-6 — Centering corpus bundle wiring and executable suite baseline

**Status:** fixture wiring corrected 2026-09-16; gate remains open for analyzer
assertions and a complete, storage-safe verification run.

The centering corpus is repository-owned: 57 tracked files under
`TestFixtures/TradingCards/`, including the ten `IMG_03xx`/`IMG_07xx` HEICs,
their ground truth, and the supplementary manifest. The files were not reaching
the test bundle because `project.pbxproj` reused two IDs for the fixture
resource entries and `CardFinishRenderPlanTests.swift`, while the test group
pointed to an undefined fixture reference. The resource build file and folder
reference now have unique IDs, and the group and Copy Bundle Resources phase
refer to those exact objects. The root-cause correction is recorded in
[`../audits/defect_review_pass_2.md`](../audits/defect_review_pass_2.md) F06.

The 2026-09-16 focused simulator run reached the corpus and manifest. Its
interrupted result bundle reports 38 selected results: 28 passed, 9 test cases
failed on centering accuracy, invariant, or performance assertions, and 1
profile-dump test was canceled. The direct fixture-reachability and
cryptographic-manifest tests passed. These nine failing test cases correspond
to the already-open centering gates in the
[centering contract](../../review/opus-card-centering-implementation-plan.md);
the run is not a clean baseline, and the full simulator suite was not rerun.

Do **not** add `XCTSkipUnless` guards for these fixtures: they are committed
inputs, not optional host data. To close this item:

- Triage the existing centering accuracy, invariant, and latency failures under
  the centering contract without weakening its frozen thresholds.
- Make diagnostic-dump output configurable so the corpus suites write only to
  the external SSD, then rerun all four suites to completion. Their current
  output path rewrites tracked files under `review/centering-evidence/`.
- Keep the unrelated `OwnershipLedgerCompletenessTests` source-inventory path
  check and `ScannerViewModelTests` load-sensitive wait in the full-suite
  triage; do not classify them as fixture failures.
- Record a clean or explicitly triaged full-target baseline in
  [`../release/phase-1-integrity-evidence.md`](../release/phase-1-integrity-evidence.md).

### RF-7 — Storage-bootstrap production wiring, on an entitled device

**Status:** open for entitled-device/runtime evidence. The pass-2 F01/F02
source fixes are present in the working tree; CloudKit enrollment and device
verification remain outstanding.

[`../audits/defect_review_pass_2.md`](../audits/defect_review_pass_2.md) F01 and
F02 are deterministic source traces and do not need a device to be believed.
What does need a device is the confirmation that their fixes behave correctly
end to end:

- Clean install on a simulator and on a device signed in to iCloud reaches the
  collection rather than the restoration screen, and `.restoringFromCloud(.failed)`
  offers a non-cloud continuation.
- A `BGAppRefresh` launch on a device whose manifest is `.suspended` resolves a
  `cloudKitDatabase` of `.none`, and no collection records appear in the private
  database afterwards.
- `TradingCardScannerApp.activeStorageMode` reflects the headless session, so
  `PortfolioEpoch`'s `isAwaitingInitialSync` gate is evaluated against the real
  container mode.

Coordinate with
[`../release/cloudkit-compatibility-audit.md`](../release/cloudkit-compatibility-audit.md);
that audit owns schema promotion, this item owns the bootstrap's runtime
behavior.

### RF-8 — Background price-check coverage budget

**Status:** open; the source dependency on pass-2 F02 is fixed, and the
remaining work is device-measured.

Slice B of [`price_history_chart_plan.md`](price_history_chart_plan.md) proposes
replacing `BackgroundPriceRefresh.appRefreshTargetLimit = 3` with an elapsed-time
budget, so a `BGAppRefresh` pass completes as many targets as its window allows.
The existing count is justified in source by JustTCG's 6.5 s pacer, which does
not apply to Scryfall-priced Magic rows.

This cannot be retired in the simulator, and it must not be started early:

- **Blocking.** The F02 source fix must remain in the candidate before raising
  background throughput; device evidence still needs to confirm that headless
  preflight resolves on-device-only stores without CloudKit mirroring.
- Measure the real `BGAppRefresh` window on device and record how many targets a
  budgeted pass completes, split by provider.
- Confirm a large collection does not trip `JustTCGQuota.backgroundDailyCeiling`
  (75).
- Re-measure per-card chart continuity on a real collection after a week.

Close each sub-item independently. A continuity improvement measured on a seeded
simulator collection does not close this item.

## Measurement-gated backlog

### RF-3 — Projection rebuild cost and coalescing

Capture rebuild frequency and `CollectionProjectionSnapshot` equality cost on a
seeded store during a representative refresh. Only replace deep equality with
an actor-computed revision token, or change completed-read coalescing, if the
profile shows meaningful main-thread or churn cost.

### RF-4 — Graded label parser coverage

When more real slab samples are available, add focused cases for BCCG/BVG,
ambiguous labels, proximity boundaries, and the confirmation window. Include
PSA labels with the observed 8- and 9-digit certificate formats before widening
the parser range again. This is test debt, not a reported misread.

### RF-5 — Existing performance device gates

**Status:** hardware/runtime profiling pending.

The remaining gates from the archived
[`performance_review_remediation_plan.md`](../legacy/performance_review_remediation_plan.md) are grouped
here so they do not get lost between plan revisions: verify the explicit camera
pixel format against OCR hit rate and thermal behavior, evaluate tab-bar
flicker during repeated scan receipts, measure camera restart latency on tab
return, and capture one live-provider refresh profile to confirm the off-main
signposts. Close each sub-item independently when its evidence is available.

The current price-refresh scale plan is
[`price_refresh_scale_plan.md`](price_refresh_scale_plan.md); its actor boundary
is landed, while continuous resumable sweeps, Magic batching, and large-store
measurement remain open.

### RF-9 — Browse set-directory price-sort measurement

**Status:** open; implementation is landed, but this is a provider/device
measurement gate and was not retired by deterministic tests.

Record before/after evidence for the Browse remediation on `me02.5` ASC:

- time to first reorder after choosing Price: High to Low on the 629-slot set;
- total `fetchCard` calls, including the effect of provider-card deduplication;
- whether opening the set without choosing a price sort stays within the 400
  distinct-provider prefetch gate, including Low Power Mode behavior.

Keep the result separate from the simulator regression evidence. The source and
focused tests establish the incremental/cancellable ordering contract, not live
provider latency or quota behavior.

## Closed cleanup

`PortfolioHistoryMode` was removed because the product exposes one history
presentation: additive market movement. The range remains user-selectable;
performance factors remain internal replay data. `PortfolioEngine.cancelRecompute`
is intentionally retained because its cancellation test protects a real task
lifecycle path.
