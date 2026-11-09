# Release follow-ups

**Status:** current validation, measurement, and catalog-hardening backlog — reconciled 2026-10-02.

This document is the aggregation point for gates that source inspection or the
ordinary simulator suite cannot retire. Completed implementation plans are
archived under [`../legacy/`](../legacy/); they are historical context, not
open work queues.

This is the aggregation point for work that cannot be retired by the ordinary
simulator suite, plus small catalog-hardening follow-ups from review. Items
below are validation, measurement, or test/documentation gates, not suspected
defects. Close an item with the evidence described here, or record the measured
reason to leave it unchanged.

**Where these are picked up:** the active
[launch plan](../superpowers/plans/2026-09-13-phase-0-phase-1-app-store-launch.md)
§0.1.2 references this document, and §0.1.1 binds the open
[pass-2 findings](../audits/defect_review_pass_2.md) to the tasks they block.
RF-6 gates Task 1 and Task 11. F01/F02 source remediation is landed; RF-7 and
RF-8 remain open for the entitled-device and measurement evidence described
below. The 2026-09-22 code-review remediation, focused simulator results, and
open acceptance items are tracked in the root
[`app_review_fix_plan.md`](../../app_review_fix_plan.md); this document owns
the residual runtime, device, provider, and scale evidence.

## Release validation

### Owner-deferred launch links — 2026-11-08

Privacy and support pages do not exist yet. The owner explicitly deferred
publishing them and setting `CARD_SCANNER_PRIVACY_URL` / `CARD_SCANNER_SUPPORT_URL`
until the final launch preparation. Keep these values empty until approved HTTPS
pages are published; do not invent destinations or treat this as an unfinished
engineering fix. Before launch, configure `/privacy` and `/support`, inspect the
built Release Info.plist, and open both links from the installed app.

The [hang inspection protocol](hang-inspection-plan.md) defines the repeatable
capture, source-attribution and fix-verification workflow for responsiveness
work, including RF-1/RF-2. It does not close these gates; current device evidence
and measured completion remain required.

### RF-1 — Collection cold-launch first paint

**Status:** targeted simulator checks passed; full-target failures and device
measurements remain open — 2026-10-29. No persistence change justified yet.

Measure a Release build on a real device with a seeded collection of roughly
1,500 cards. Record the time from launch to the first real collection grid row,
using the existing collection projection signposts.

- If the first row appears in roughly 300 ms or less, close this as
  **won't-fix**; the launch spinner is not perceptible enough to warrant a
  persisted projection snapshot.
- If it is materially slower, evaluate persisting the last
  `CollectionProjectionSnapshot` and replacing it when the actor read completes.

Launch-path changes on branch `claude/launch-speed` at `c557499` (implemented;
native verification below, device timings pending): the Yu-Gi-Oh! bundled
catalog is registered from a per-build cache and decoded on first use; static
catalog price withdrawal runs after the
portfolio starts; browse catalog preparation waits for the opening handoff; and
the opening reveals after at most `AppOpeningModel.portfolioRevealBudget`
(350 ms) once content mounts, without a copy count if the portfolio is still
calculating. Record both the first launch after install (cache miss) and a
repeat launch, with the `Launch.*` signposts listed for H01 in the
[hang inspection plan](hang-inspection-plan.md).

**Native verification — 2026-10-29:** Xcode 27.1, dedicated iPhone 17 simulator
on iOS 27.0. The checkout included the existing listing-photo UI edits and a
test-only One Piece fixture correction: delayed responses now retain their
server capture dates on either side of the withdrawal watermark. Production
launch/transport code was not changed by this verification pass. Earlier shared
simulator attempts were superseded after concurrent photo UI launches terminated
the test host.

| Targeted suite | Passed |
| --- | ---: |
| `YuGiOhCatalogTests` | 15 |
| `LaunchModelActorTests` | 6 |
| `AppOpeningTests` | 12 |
| `LorcanaOwnershipTests` | 29 |
| `OnePieceIntegrationTests` | 98 |
| `MagicTreatmentMigrationTests` | 26 |
| **Total** | **186; zero failures/skips/runtime warnings** |

The subsequent full `TradingCardScannerTests` target finished with **2,693
passed, six failed, 16 skipped**. Eight runtime warnings concern reading SwiftUI
State/Environment outside an installed view in `UncoveredSurfaceTests.swift`.
The six-case isolated rerun had **two passed, three failed, one skipped**.
The StoreKit purchase/restore and pending-approval tests passed after failing to
load a product in the full run. Interrupted-purchase acceptance skipped because
local StoreKit supplied a verified entitlement before issue resolution; that
case still requires sandbox follow-up. These three assertions still fail in
isolation:

- `CollectionKeyTests.testREQ001UnderlyingPrintingIDUsesTheProductionSourceForEveryItemKind`:
  expected a nil catalog provider ID; actual value is `direct-product`.
- `JustTCGV2GradedSurfaceTests.testGradedIdentityGroupingAndOwnedFiltersUseExactFields`:
  the actual grouping key has an additional trailing `none` field.
- `SwiftDataConcurrencyCharacterizationTests.testDidSaveKeysAndPersistentIdentifierEntityName`:
  the actual notification keys also include `historyTokens` on this runtime.

The full target remains failed; the isolated StoreKit passes/skip do not
supersede that result. These assertions were left unchanged.

The device-target **Release build compiled successfully with
`CODE_SIGNING_ALLOWED=NO`**. Normal signed Release failed because the installed
provisioning profile lacks the app's iCloud capability/container entitlements.
No device app was installed or removed, no collection data was changed, and
neither first-install nor repeat-launch timing was captured. The approximately
1,500-card device workload/restoration setup still needs confirmation.

Local evidence is retained outside Git on the external SSD at
`/Volumes/Keller Family Photos/CodexBuilds/TradingCardScanner-launch-speed-20261029/`:
`targeted-dedicated.xcresult`, `full.xcresult`, `full-failure-rerun.xcresult`,
`release-build.xcresult` (signing failure), and `release-unsigned.xcresult`.

### RF-2 — Scanner tracking at 8 Hz

**Status:** hardware validation pending; simulator cannot retire this item.

The current [scanner module review](../audits/scanner_module_review.md) adds
three measurement concerns to this gate's scope. In particular, compare OCR
interval durations with tracking event rate and `trackerSeeded`/`trackerLost`
diagnostics on the slowest supported device at 4K, and record stationary-card
false spatial-exit prompts separately from true departures.

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
source fixes are present in the committed tree; CloudKit enrollment and device
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
signposts. The scanner module review also calls for measuring the
`offerHeldDuplicateRebuild` interval and its relationship to session length;
retain that evidence with the scanner performance result. Close each sub-item
independently when its evidence is available.

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

## Catalog fingerprint hardening follow-ups

These items are non-blocking follow-ups to the completed artwork-enrichment
fingerprint fix. The Core parity test protects the publisher-side enrichment
boundary; the items below preserve the remaining code intent and close the
publisher-to-device mapping seam.

### RF-10 — Document the descriptor artwork fallback rung

**Status:** open; documentation hardening.

Keep a code comment at
[`CatalogBuilder.swift`](../../PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogBuilder.swift)
explaining that the directory row's `logo`/`symbol` fallback remains
load-bearing for a raw provider value of `""` when artwork resolution returns
`nil`. The fallback is descriptor-only and is not redundant with the resolved
artwork fields or the raw values hashed by `v1`; it should not be removed as a
cleanup.

Close when the comment lands and `git diff --check` remains clean.

### RF-11 — Add device-side canonical fingerprint parity coverage

**Status:** open; iOS test coverage follow-up.

Add a focused iOS catalog test that maps a `TCGdexSetCatalog` through the real
device-side `canonicalFingerprint` implementation in
[`PokemonChecklistSnapshot.swift`](../../TradingCardScanner/Services/PokemonChecklistSnapshot.swift)
and compares it with
`PokemonCatalogProviderFingerprint.v1` on the equivalent raw Core model. The
existing
[`ArtworkFingerprintParityTests.swift`](../../PokemonCatalogCore/Tests/PokemonCatalogCoreTests/ArtworkFingerprintParityTests.swift)
exercises `fetchFixture`, all three artwork-enrichment paths, and descriptor
resolution, but it uses a hand-built Core value rather than the app-target
mapping. Close when the focused iOS test passes and its test evidence is
recorded; this does not by itself retire physical-device acceptance.

### RF-12 — Collection write, refresh, and lifecycle acceptance

**Status:** implementation and simulator verification are present; scale,
OS-lifecycle, and device-timing evidence remains open.

**Latest simulator evidence (2026-09-23):** the iPhone 17 Pro / iOS 26.5
non-centering suite executed 1,510 tests with 7 skipped and no failures. A
separate Debug simulator build succeeded. Centering tests were excluded. This
does not close the physical-device or operating-system lifecycle checks below.

The current pass-2 remediation serializes ownership writes, applies refresh
metadata as guarded patches, suspends refresh around price-identity rewrites,
and makes CSV imports resumable. Focused tests cover the deterministic
concurrency, patching, retry, and resume rules. Before treating the paths as
operationally accepted, collect the remaining evidence:

- On a physical device, overlap a background-owned price pass with a foreground
  launch and confirm the foreground collection becomes usable promptly.
- Exercise real iOS background-task expiration during a long CSV import and a
  background refresh. Confirm the next launch resumes the import without
  double-counting and the refresh does not publish a partial completion.
- On the 300-card fixture, record the `scannerPersistence`,
  `priceRefresh.commitStaged`, and `portfolio.recompute` signpost counts and
  durations before and after the fresh-context writer and row-patch changes.
- Complete the planned simulator flows for removing a row and running
  delete-all during refresh, interrupting and resuming CSV import, retrying a
  first-open container failure, and sorting/filtering a native-currency row.

Simulator tests cannot establish actual background scheduling/expiration or
real-device timing. Do not use simulator-only results to claim those gates are
closed.

### RF-13 — October review performance measurements

**Status:** physical-device capture pending — 2026-10-02.

The [October review ledger](../audits/october-review-remediation.md#measurement-gate)
records the approved workload and acceptance boundary: actor and CSV thread
placement, centering export, artwork normalization, revision-monitor fetch cost,
and first paint with roughly 1,500 synthetic cards. Use
`TradingCardScanner-ProfileLocal` on the oldest supported device. The local
device listing showed only offline iPhone/iPad devices, so no trace or measured
duration is available. Keep F9, artwork worker changes, and actor placement
changes gated on those results; simulator test timings cannot retire this item.

### RF-14 — November production refinement acceptance

**Status:** local implementation and final focused simulator verification complete;
broader target remains non-green; device and publication gates open —
2026-11-04, working tree based on `a404f67`.

This checkpoint owns the seven findings from the November whole-production
review and its approved conservative implementation plan. The October findings
with the same F-numbers in older documents are separate historical work.
Existing catalog authoring and Browse lifecycle/pagination changes are retained.

| Finding | Implemented behavior | Verification boundary |
| --- | --- | --- |
| Scanner save recovery | Each authorized write captures its storage continuation and original session. Late failure retains a distinct acquisition row; late success retires its exact source row without publishing into a replacement session. Only the affected recovery row is locked against retry/dismissal; Clear is disabled while any recovery write runs. | Delayed success/failure beyond the departure drain, replacement storage, persisted recovery, durable quantity, and replacement-session summary tests. Native saving state and available Back/other-row actions inspected on Simulator. |
| Artwork latency | Price-only requests skip artwork recovery. Catalog resolution applies signed artwork first. Bulk refresh recovers artwork only for accepted imports needing an image and preserves existing saved artwork when enrichment is absent. Existing Browse/normalization service defaults retain recovery. | Recorded transport tests prove no probes for price-only fetches or rejected identities, signed-artwork ordering, retained saved images, and imported-row backfill. No measured wall-clock speed claim. |
| Live historical Magic | The adapter owns exact family/candidate validation. Final provider acquisition validation runs before write exclusivity; local context checks remain at the retry boundary. | Scanner selection/save uses two family searches and one exact-card fetch, including a forced exclusive-write retry. Recovery's existing preparation lookup remains a separate validation; no prepared-result cache was added. |
| All Games set filtering | Selected sets constrain card games, status, results, resume, and pagination. Sealed lanes keep the original game scope. | Single-game and mixed-game filters, explicit-game switching with retained selections, and card/sealed pagination tests. |
| Unavailable completion checklist | Owned collector numbers remain visible with an unknown denominator. Available empty checklists still mean zero matched slots. | Unchanged-manifest retry test now expects ownership-only progress, then exact progress after restoration. Unknown fractions remain last in Most Complete. Normal catalog publication/reappearance can rebuild; no retry timer was added. |
| Slab's ungraded reference | The query uses the exact price key, including Magic treatment and Pokémon print run. Same-key duplicate authority selection is retained. | Real SwiftData queries exclude newer quotes for other treatments, omit missing exact references, preserve print-run separation, and exclude ineligible/raw rows. |
| Release links | Empty target overrides were removed from all five configurations. The existing production xcconfig now owns both empty URL settings. | Release build succeeds; built plist still has empty URLs. Owner-approved public pages, real URL configuration, built-app navigation, and submission metadata remain open under the [publication checks](../legal/README.md). The price-feed endpoint remains deliberately unconfigured. |

Pre-change baseline: 372 selected cases, 369 passed and three scanner cases
failed (24 assertion failures). The failing cases were
`testChooseCardFromGradedRowPreservesSlabAndPrintedPrintRun`,
`testClassicPhotoFootersOfferBothPrintingsBeforeFinishOrCollectionWrite`, and
`testHeldRepeatIdentityMismatchClearsAcknowledgementWithoutWriting`.
Do not treat these baseline failures as new findings or claim a green baseline.

Post-change focused checks: 61 passed, followed by 27 passed and three skipped
in the live-Magic/signed-artwork selection. Debug test build and generic Release
simulator build passed. One initial regression test caught saved artwork being
cleared by absent enrichment; the metadata application was corrected and that
test now passes. The final selection after follow-up changes executed 118 cases:
115 passed, three skipped, zero failed. The final generic Release simulator
rebuild also passed. The focused selection includes all 17 recovery-store tests,
the current-session stale-storage interval cleanup, the exact-row merge contract,
and all live Magic recognition/choice tests. Shared Magic discovery-family
validation is retained; removing it broke the multi-oracle title case during
verification and was reverted before the final green selection.

The broad run attempted 3,110 cases: **3,077 passed, 19 skipped, 14 failed**
(including one test-host crash), confirmed from the result bundle's metrics.
It preceded the final exact-row test update and interval cleanup; it is not a
green full-target result for the final tree. Failure disposition:

| Cases | Evidence / remaining limit |
| --- | --- |
| Three scanner cases listed above | Reproduced the pre-change failures. |
| Historical recovery merge expectation | Updated to identify the exact retry row; distinct failed acquisitions now have an explicit regression assertion. Passes in the final selection. |
| Jumbo variant expectation | Untouched static expected list omits `.jumbo`, which the unchanged production variant policy includes. Reproduces in isolation. |
| Three automatic-finish repair/price cases | Reproduce in isolation, including a direct call to unchanged finish-reconciliation logic. Fixtures/policy expectations need a separate reconciliation; do not weaken physical-review rules to make them pass. |
| Three keychain cases | Fail with `storeFailed(-34018)` in the unsigned simulator test host. No credential fallback was introduced. |
| Native centering field blur | Two-second blur deadline fails in both broad and isolated runs. The field implementation/test is untouched by these slices. |
| SwiftData notification characterization | Untouched expected keys omit the observed `historyTokens`; reproduces in isolation. |
| Duplicate recovery-record test host crash | One broad-run `SIGTRAP` has SwiftData/SwiftUI frames. The exact test and all 17 recovery-store tests pass in fresh runs. The cause is unproven; keep lifecycle/runtime acceptance open. |

Generated logs/results and synthetic screenshots are on the T7 SSD under
`ScanStash_Refinement_20261104`, outside the repository. Result bundles are
`Baseline.xcresult`, `FullSuite.xcresult`, `FinalRegression.xcresult`, and
`FailureIsolation.xcresult`. No full-target or release-readiness claim follows
from the green focused selection.

Additional centering source/plan edits arrived concurrently after the final
focused test binary was built. They are preserved and are outside this slice's
behavioral verification; centering failure evidence above describes the tested
binary, not those later edits.

The normal-size recovery list/detail were visually checked, including disabled
Clear, visible Saving status, available Back, and usable other-row actions.
The largest Dynamic Type message wraps without overlap; its existing native
large navigation title truncates, and row scrolling was not verified in that
capture. These observations are not physical-device or VoiceOver acceptance.

Keep RF-1/RF-2/RF-3/RF-8/RF-9/RF-12/RF-13 open. No new queue architecture,
persistent cache, background artwork worker, completion retry loop, schema
migration, or speculative performance optimization was introduced. Measure
remaining launch/OCR/projection/rendering work before changing it.

## Closed cleanup

`PortfolioHistoryMode` was removed because the product exposes one history
presentation: additive market movement. The range remains user-selectable;
performance factors remain internal replay data. `PortfolioEngine.cancelRecompute`
is intentionally retained because its cancellation test protects a real task
lifecycle path.
