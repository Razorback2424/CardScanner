# Bounded bug-review repairs — 20 October 2026

Status: native repairs verified; goal blocked on the remaining interactive UI acceptance checks. The continuation audit repaired an F2 preservation regression and an F4 interrupted-copy intent gap, recorded below.

Starting HEAD: `e2c37ad` (clean worktree), following the report's reviewed baseline
`be183f22cdfec5febd9091608d23bf5d1e65213d`. The two intervening Collector Tools
commits remain intact. No commits, pushes, normal-device installs, purchases,
provider calls, collection resets, rollout changes or commercial configuration
changes were part of this repair.

## Findings and regression evidence

Each reported defect remained present at starting HEAD. New focused native tests
failed before the relevant behavior was repaired. None was classified as already
fixed or disproven. The final status for F1–F13 is **fixed and verified by native
regressions**, subject to the separate UI limitations below.

| Finding | Repair / changed production files | Native regression |
| --- | --- | --- |
| F1 | [ScannerViewModel.swift](../../TradingCardScanner/Views/ScannerViewModel.swift): exact recovery row or same-session equivalent suppression identity; failed commits and explicit additional copies remain independent. Printing IDs/numbers no longer authorize deletion. | `ScannerViewModelTests.testRecoveryCleanupPreservesDistinctPhysicalAcquisitionsAcrossReload`: persisted failed certificates, real retry, reload, raw success, extra-copy survival and owned quantity. Existing recovery/rescan tests cover legitimate cleanup. |
| F2 | [CollectionStore.swift](../../TradingCardScanner/Services/CollectionStore.swift), [ScannerViewModel.swift](../../TradingCardScanner/Views/ScannerViewModel.swift), [PriceRefreshController.swift](../../TradingCardScanner/Services/PriceRefreshController.swift), [PriceRecord.swift](../../TradingCardScanner/Models/PriceRecord.swift), [PriceStore.swift](../../TradingCardScanner/Services/PriceStore.swift): retain provider printing evidence; invalidate unproven/incompatible corrected quotes; carry finish/run to the serialized writer; fence publication and rerun corrected graded lookup. | `ScannerViewModelTests.testGradedFinishCorrectionRejectsIncompatibleLookupInEitherOrder`, `testCorrectedGradedScanKeepsItsCompatibleResolvedPrice`; `CollectionItemKindTests.testDelayedGradedBindingRechecksDurableCorrectedFinish`. Includes displayed quote, usable evidence, quantity, certificate and ledger checks. The old blanket-preservation case now supplies compatible provider evidence. |
| F3 | [ScannerViewModel.swift](../../TradingCardScanner/Views/ScannerViewModel.swift): cancellation, original request/session and storage checks after preparation/existence awaits and before routing; authorized writes retain their durable completion contract. | `ScannerViewModelTests.testAbandonedRetryExistenceCheckCannotPublishOrAuthorizeAWrite`: true/false/error crossed with purpose switch, background and departure/reentry. Existing authorized-write interruption regressions remain passing. |
| F4 | [ScannerViewModel.swift](../../TradingCardScanner/Views/ScannerViewModel.swift): validate consumed held permit before choice preflight suppression; preserve the permit through choices; cancel it when a choice is dismissed. Final identity and one-shot checks remain. | `ScannerViewModelTests.testHeldRepeatSurvivesRequiredFinishAndPrintRunChoices`: Normal/Holo, vintage print run, cancel, repeated taps; existing stale/mismatched permit and ordinary suppression tests; `CardLatchTests` expiry cases. |
| F5 | [ScannerViewModel.swift](../../TradingCardScanner/Views/ScannerViewModel.swift): distinct stale commit outcome prevents old duplicate/held offers from being restored. | `ScannerViewModelTests.testLateAdditionalCopyCompletionCannotReviveOldSessionPrompt`: success/failure after the two-second drain and reentry; existing same-session held-save failure regression. |
| F6 | [CollectionStore.swift](../../TradingCardScanner/Services/CollectionStore.swift), [CollectionActivityLogView.swift](../../TradingCardScanner/Views/CollectionActivityLogView.swift): shared reacquisition predicate accepts only proven, single disposal reversals. | `CollectionActivityHistoryTests.testIndependentRemovalsCanBothBeRestored`; existing reacquisition, sibling, repeated restore, window and lineage protections. |
| F7 | [JustTCGRefreshCoordinator.swift](../../TradingCardScanner/Services/JustTCGRefreshCoordinator.swift), [PriceFallbackQuoteResolver.swift](../../TradingCardScanner/Services/PriceFallbackQuoteResolver.swift), [PriceRefreshController.swift](../../TradingCardScanner/Services/PriceRefreshController.swift), [CardMarketHistoryService.swift](../../TradingCardScanner/Services/CardMarketHistoryService.swift): carry explicit print run, reuse edition requirements and group owners by edition. | `JustTCGContractTests.testDirectPokemonListingRespectsExplicitEnglishEdition`, `testSharedCardBatchKeepsEditionOwnersSeparate`: one mocked response, Unlimited $96 / First Edition $480, one request and two distinct owners. Existing UUID, named/unknown finish, Magic and sealed cases pass. No Japanese-support assumption or live quota. |
| F8 | [CollectionStore.swift](../../TradingCardScanner/Services/CollectionStore.swift), [CollectionCatalogNormalizer.swift](../../TradingCardScanner/Services/CollectionCatalogNormalizer.swift): populate sealed catalog ID; validate exact vendor product/variant handles; safely normalize namespaced existing holdings. Existing sealed provider protocol enables deterministic injection. | `CatalogNormalizationTests.testBrowseSealedNormalizationConvergesWithoutChangingOwnershipIdentity`, `testSealedNormalizationRepairsMissingArtworkAndRejectsConflictingVendorIdentity`: two passes, request counts, artwork repair, conflict rejection and stable ownership/price identity. |
| F9 | [PortfolioEngine.swift](../../TradingCardScanner/Services/PortfolioEngine.swift): degrade the retained live cache as well as replay/status after unreadable storage. | `PortfolioReconciliationTests.testLiveDeltaCannotRestoreTrustAfterUnreadableReplay`: authoritative replay → failed read → changed live delta → authoritative replay, with defects retained until the final step. |
| F10 | [PortfolioReplay.swift](../../TradingCardScanner/Services/PortfolioReplay.swift): nil→nil evidence retains pending acquisitions; removal consumes only its own position, while first price remains instrument-wide. | `PortfolioReplayEngineTests.testUnusableObservationDoesNotConsumePendingFirstPrice`, `testRemovalConsumesOnlyItsOwnPendingPosition`; existing shared-position partial removal, ordinary first price and real de-pricing cases. |
| F11 | [CardCenteringView.swift](../../TradingCardScanner/Views/CardCenteringView.swift): retire superseded/unshared successful files, rejected workers and screen outputs inside a narrowly owned per-process directory. Share transfer retains its file through the process lifetime; next-process cleanup removes old session directories. | `CenteringExportTests.testRepeatedSuccessfulExportsRetireSupersededArtifacts`: replacement deletes the earlier PNG, current PNG survives, and a file handed to sharing survives retirement. Existing export snapshot/geometry tests pass. Actual system-share smoke is tracked separately. |
| F12 | [PortfolioHistoryEngine.swift](../../TradingCardScanner/Services/PortfolioHistoryEngine.swift): disclose either newer or older non-exact anchors without changing windows. | `PortfolioHistoryEngineTests.testLongRangeDisclosesNewerAvailableAnchor`: newer, exact and older anchors; remaining history accounting suite passes. |
| F13 | [EbayListingPhotoExport.swift](../../TradingCardScanner/Services/EbayListingPhotoExport.swift): include intended hidden folders in owned archive preflight. Existing path sanitization is unchanged. | `EbayListingPhotoExportTests.testArchiveIncludesLeadingDotBatchFolders`: leading-dot, normal and mixed folders, with expected paths in actual ZIP bytes; existing ten-image output tests pass. |

Regression changes are in the test files named by each row under
`TradingCardScannerTests/`: `ScannerViewModelTests.swift`,
`CollectionItemKindTests.swift`, `CollectionActivityHistoryTests.swift`,
`JustTCGContractTests.swift`, `CatalogNormalizationTests.swift`,
`PortfolioReconciliationTests.swift`, `PortfolioReplayEngineTests.swift`,
`PortfolioHistoryEngineTests.swift`, `CenteringExportTests.swift` and
`EbayQuadrantCropperTests.swift` (contains `EbayListingPhotoExportTests`).

## Executed native verification

Environment: Xcode 27.1, iOS 27.0 simulator, isolated Collection Quote QA.
Build/dependency caches remained on the external SSD under
`/Volumes/Keller Family Photos/CodexBuilds/CollectorTools-20261020/`.
Raw logs and synthetic exports are not repository artifacts.

The final audited run executed **804 tests, zero failures, one skipped** and
finished with `TEST SUCCEEDED`. The skip is
`PortfolioReconciliationTests.testAgedStoreBaseline`, an existing opt-in test
requiring `PERF_BASELINE=1`.

Exact common command arguments:

```sh
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=97F6D99C-3B99-422E-8395-EEAA10943CBC' \
  -derivedDataPath '/Volumes/Keller Family Photos/CodexBuilds/CollectorTools-20261020/DerivedData' \
  -clonedSourcePackagesDirPath '/Volumes/Keller Family Photos/CodexBuilds/CollectorTools-20261020/SourcePackages' \
  -resultBundlePath '/Volumes/Keller Family Photos/CodexBuilds/CollectorTools-20261020/BugRepair-F1-F13-Audited.xcresult' \
  -only-testing:TradingCardScannerTests/ScannerViewModelTests \
  -only-testing:TradingCardScannerTests/UnresolvedScanStoreTests \
  -only-testing:TradingCardScannerTests/CollectionActivityHistoryTests \
  -only-testing:TradingCardScannerTests/CollectionItemKindTests \
  -only-testing:TradingCardScannerTests/OwnershipConcurrencyStressTests \
  -only-testing:TradingCardScannerTests/OwnershipLedgerCompletenessTests \
  -only-testing:TradingCardScannerTests/CatalogNormalizationTests \
  -only-testing:TradingCardScannerTests/JustTCGContractTests \
  -only-testing:TradingCardScannerTests/PricingTests \
  -only-testing:TradingCardScannerTests/ProductFallbackTests \
  -only-testing:TradingCardScannerTests/ScannedGradedResolverTests \
  -only-testing:TradingCardScannerTests/PriceRefreshLifecycleTests \
  -only-testing:TradingCardScannerTests/RefreshStructuralWriteTests \
  -only-testing:TradingCardScannerTests/PortfolioReconciliationTests \
  -only-testing:TradingCardScannerTests/PortfolioReplayEngineTests \
  -only-testing:TradingCardScannerTests/PortfolioHistoryEngineTests \
  -only-testing:TradingCardScannerTests/PortfolioLedgerTests \
  -only-testing:TradingCardScannerTests/PortfolioCloseTests \
  -only-testing:TradingCardScannerTests/PortfolioTrustPassTests \
  -only-testing:TradingCardScannerTests/CenteringExportTests \
  -only-testing:TradingCardScannerTests/EbayListingPhotoExportTests \
  -only-testing:TradingCardScannerTests/CardLatchTests test
```

Log: `/tmp/cardscanner-f1-f13-audited.log`. The intermediate 803-test run also
passed (`/tmp/cardscanner-repairs-continuation-final.log`). The earlier 802-test
run passed (`/tmp/cardscanner-repairs-verified.log`); its result bundle used
`/tmp/CardScanner-BugRepair-Final.xcresult` after automatic external result
collection stalled. The continuation's result bundle, compilation, derived
data and package caches are on external storage.

## Continuation audit — compatible graded correction

The earlier preservation test always returned a successful vendor result a
second time. A new native regression,
`ScannerViewModelTests.testCompatibleGradedCorrectionRetainsQuoteWhenAnotherLookupWouldBeUnavailable`,
reproduced a regression in the initial F2 repair: correcting to a compatible finish erased the
scanner's valid quote and depended on another successful lookup. Before-fix
log: `/tmp/cardscanner-compatible-correction-before.log` (one native failure).

The serialized correction now returns `ScannerCorrectionReceipt`, containing
the mutation and a quote only when the corrected durable row, exact vendor
variant, provider printing/edition and usable USD record all agree. The scanner
retains that quote without another request. An incompatible or unproven binding
still resolves the corrected identity through the existing graded path. Late
results/failures from the old identity cannot overwrite the retained quote.
Only `CollectionStore.swift`, `ScannerViewModel.swift` and its native test file
received further code changes in this continuation.

Four focused native checks passed in
`/tmp/cardscanner-compatible-correction-after.log`: the new compatible case,
the existing compatible case, both incompatible lookup orders and the delayed
serialized binding check. Result bundle:
`/Volumes/Keller Family Photos/CodexBuilds/CollectorTools-20261020/BugRepair-CompatibleCorrection-After.xcresult`.
The intermediate 803-test combined run then passed. Final native checks also passed
(2 tests, 0 failures, `TEST SUCCEEDED`): the compatible-quote case and
`ScannerViewModelTests.testIncompatibleGradedCorrectionResolvesTheCorrectedFinishPrice`.
The latter starts with $250 Holo, confirms Normal, and verifies the distinct $80
Normal graded binding, certificate, quantity and ledger agreement. It proves the
corrected path restores the right graded price rather than merely withholding
the wrong one. These two checks were selected with the common command arguments
and result bundle
`/Volumes/Keller Family Photos/CodexBuilds/CollectorTools-20261020/BugRepair-CorrectedQuote-Final.xcresult`.
Log: `/tmp/cardscanner-corrected-quote-final.log`. The refreshed app build is
recorded below; no full-goal completion is claimed.

## Continuation audit — held-repeat recovery intent

The new choice paths also needed to preserve the consumed permit's additional
copy intent when interrupted. Extending
`ScannerViewModelTests.testHeldRepeatSurvivesRequiredFinishAndPrintRunChoices`
to background at both finish and print-run choices produced two native failures:
the recovery rows were filed as ordinary scans. Before-fix log:
`/tmp/cardscanner-held-recovery-before.log`.

`fileInterruptedWork` now preserves the additional-copy marker only when the
request matches the consumed scanner permit and its suppression identity. This
does not restore a permit or authorize a write; recovery still needs fresh copy
confirmation. The focused native run passed all four selected tests: the
extended choice test, stale permit rejection, canonical identity mismatch
rejection, and interrupted additional-copy storage round-trip. Log:
`/tmp/cardscanner-held-recovery-after.log`; result bundle:
`/Volumes/Keller Family Photos/CodexBuilds/CollectorTools-20261020/BugRepair-HeldRecovery-After.xcresult`.
The choice test additionally asserts durable quantity remains one after either
interruption. The final 804-test combined run above includes those assertions
and both final F2 quote-preservation/replacement cases; it passed with no failures
and the one unchanged opt-in performance skip.

Earlier evidence is intentionally not presented as a clean run:

- `/tmp/cardscanner-f1-before.log`: F1 fails before repair.
- `/tmp/cardscanner-regressions-before.log`: F2/F6/F10/F12 and hidden batch archive fail before repair.
- `/tmp/cardscanner-scanner-before.log`: F3/F4/F5/F7 fail before repair; F1 passes. The graded gate initially blocked the second lookup; corrected to allow subsequent calls after release.
- `/tmp/cardscanner-edge-before.log`: F8/F9/F11 and hidden archive fail before repair; F1–F5 pass.
- `/tmp/cardscanner-repairs-combined.log`: 487 tests, one skip, two assertions fail in the new F7 test because it read `id` instead of v1 `variantId`. Corrected assertion; no pricing relaxation.
- `/tmp/cardscanner-repairs-final-tests.log`: the new delayed-binding rejection exposed unsaved context changes. Fixed by rolling back its rejected transaction. The runner restarted and printed passing totals for subsequent tests; this interrupted run is **not** accepted as a complete passing suite.

## App build, final assertions and UI smoke

The final strengthened F1/F2 tests both passed (2 tests, 0 failures,
`TEST SUCCEEDED`): the recovery case now retries a persisted failed slab through
the actual writer, saves a raw copy afterward, reloads storage and verifies the
other certificate plus explicit extra-copy intent survive. The graded case also
checks usable price evidence and ledger quantity. Command: the common arguments
above, with only those two `ScannerViewModelTests` method selectors and
`-resultBundlePath '/Volumes/Keller Family Photos/CodexBuilds/CollectorTools-20261020/BugRepair-FinalAssertions.xcresult'`.
Log: `/tmp/cardscanner-repairs-final-assertions.log`.

The app-only command used the common project/scheme/configuration/destination,
derived-data and package arguments, followed by `build` (no test selectors or
result-bundle argument). Earlier builds ended with **BUILD SUCCEEDED**
(`/tmp/cardscanner-repairs-app-build.log` and
`/tmp/cardscanner-repairs-continuation-app-build.log`). The final post-audit
build also ended with **BUILD SUCCEEDED**, recorded in
`/tmp/cardscanner-f1-f13-audited-app-build.log`.

Native UI checks used the iOS debugger skill and XcodeBuildMCP, on the QA
simulator only:

- Launched `-ui_debug_route Centering -ui_debug_state confirmed`.
  The existing unowned Collector Tools gate renders. Full centering/share-sheet
  interaction is **blocked by the preserved entitlement**. No purchase or
  entitlement bypass was attempted.
- Navigated Pro → eBay Listing Photos → Batch → Choose an even number of
  photos. Added two synthetic app-icon JPEGs to the QA simulator. The system
  picker visibly shows them. Runtime automation does not expose its remote
  photo/checkmark controls, and the alternate native UI surface cannot bind the
  simulator app. Thus the interactive batch prepare/ZIP/share and inspector
  smoke is **blocked by UI automation**, not reported as passing. Actual ZIP
  creation/content and ten-output regressions passed natively.
- Launched `-ui_debug_route TrustScanReceipt -ui_debug_state attention-session`.
  Opened `5 need attention`; all five fixture rows and explanatory text render.
  This is a UI rendering check, not persisted-recovery evidence. Persistence is
  proved by the separate real-write/reload XCTest.
- Full interactive held repeat through choices and graded finish-correction UI
  are **unexecuted**: the simulator has no physical camera input and no existing
  injectable UI route for these flows. Their real scanner/domain/writer paths
  were exercised by deterministic native gates and scanner-footer input tests.

The speculative listing-photo full-screen-cover concern remains **unconfirmed**;
the smoke did not reach the inspector, and no speculative repair was made.
Centering files explicitly handed to sharing remain retained for the process
lifetime because ShareLink has no completion callback; a subsequent process
cleans old owned session directories. Ordinary edits/departures retire their
unshared outputs immediately.

No physical-device, provider, CloudKit, archive, StoreKit-purchase or release
acceptance is implied by this verification. These UI gaps remain launch-relevant
acceptance work; the opt-in aged-store performance baseline was not executed.

Stop condition: full requested acceptance remains incomplete. Finishing the UI
checks needs a deterministic UI harness with mocked entitlement/scanner input
and a way to drive the system picker, or a manual native pass. The continuation
stops at that verification blocker rather than repeating the same failed UI
automation or changing the commercial boundary. No goal completion is claimed.

## Verification-blocker revalidation — 20 October 2026

After the separate card-detail cleanup, the resumed goal rechecked HEAD
`e2c37ad`, current local changes, the 804-test repair log and the newer 508-test
detail/pricing log; both recorded runs ended successfully. No new test run is
claimed by this audit. The card-detail changes and existing repairs were
preserved without additional production edits.

Current source still obtains centering access from `CollectorToolsStore.shared`,
and the QA entitlement has not been purchased or overridden. The scanner still
has no existing injected UI route for the requested held-repeat/graded flows.
The successful basic Cards Added smoke in the separate cleanup does not supply
system-picker control or centering/scanner acceptance evidence. The same
verification barrier remains after the original handoff, continuation handoff
and this resumed goal audit; the goal is therefore marked blocked, not complete.

Remaining acceptance needs a deterministic mocked native UI harness or a manual
pass in an isolated QA environment. The owner's personal device must not be
run, installed to, debugged or otherwise used. No personal device was accessed.
No commercial boundary, rollout, collection-data or StoreKit change was made
to bypass these checks.
