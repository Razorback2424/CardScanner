# Ownership-ledger completeness audit

**Status:** ownership-ledger gate passed for the current checkout; CloudKit
production/device certification remains open; reconciled 2026-09-20

This document is the current authority for proving that every production
quantity mutation leaves a complete, durable, idempotent `InventoryEvent`
history. The detailed 2026-09-13 candidate audit is preserved in the
[legacy audit](../legacy/ownership-ledger-completeness-audit.md) and must not be
carried forward without rerunning it against the current tree.

## Current candidate

- Branch: `feature/catalog-and-scanner-hardening`
- HEAD locator: `7dbaf40`
- Exact ownership-ledger status: **PASSED**
- Exact release status: **NOT CERTIFIED**

## Required proof

Reconcile every production quantity-changing path, including scanner adds and
undo, CSV import, raw/graded/sealed operations, correction/rekey/merge flows,
restore, and Magic-treatment migration. For each path, prove:

1. the mutation and its ledger event use one operation identity;
2. retries are idempotent;
3. failed writes do not leave partial ownership, activity, price, or ledger
   state; and
4. rebuilding quantities from canonical events agrees with the persisted
   collection projection.

## Evidence status — 2026-09-20

F04/F05 were reproduced and resolved on `7dbaf40`:

- F04: `PortfolioEpoch.establishIfNeeded` now inserts the matching
  `CollectionActivity` for each appended baseline event in the same save
  transaction. The disk-backed baseline/restart test passes with one event and
  no activity/ledger defect.
- F05: `InventoryLedger.quantities(from:)` now excludes negative nets, and the
  source-inventory test resolves services from `#filePath` rather than assuming
  the test runner's working directory.

The exhaustive simulator matrix was rerun on the iPhone 17 Pro / iOS 26.5
destination with all DerivedData, module caches, package sources, and result
bundles on the external SSD. The matrix executed 106 tests: 105 passed and 1
intentional opt-in performance test was skipped; 0 failures and 0 unexpected
failures. Result bundle:

`/Volumes/Keller Family Photos/June 10 2026 dump (move)/AdditionalStorage/TradingCardScannerMVP_fixed_v4/exact-7dbaf40/ownership-matrix.xcresult`

### Mutation / restart / rollback matrix

| Ownership surface | Mutation and integrity proof | Restart / rollback / retry proof | Result |
| --- | --- | --- | --- |
| Scanner raw add, quantity change, remove, restore | `OwnershipLedgerCompletenessTests.testDiskBackedMixedProductionWorkflowReconstructsAfterRestart`; `CollectionActivityHistoryTests.testAddRemoveRestoreKeepsCollectionLedgerAndHistoryInAgreement` | Disk reopen; scanner save-failure rollback; repeated undo/removal idempotency | PASS |
| Scanner save boundary | `OwnershipLedgerCompletenessTests.testScannerSaveFailureRollsBackAggregateAndLedgerTogether` | Injected save failure reopens with neither collection nor ledger row | PASS |
| CSV import and re-import | `OwnershipLedgerCompletenessTests.testDiskBackedCSVFailureRollsBackAndRetryCommitsOneRow`; `PortfolioReconciliationTests.testCSVImportCommitsAndReportsDurableBatches` | Stopped generation rolls back; retry commits exactly one durable ownership event; certified re-import is a no-op | PASS |
| Raw, graded, scanned-graded, and sealed entries | `OwnershipLedgerCompletenessTests.testDiskBackedGradedScannedGradedAndSealedPathsEmitCompleteFacts` | Disk reopen reconstructs all three item kinds and three events | PASS |
| Quantity adjustment and duplicate physical rows | `CollectionActivityHistoryTests.testQuantityAdjustmentsAlsoAppearInTheActivityProjection`; `testDuplicatePhysicalRowsAreMergedBeforeEveryOwnershipMutation`; `PortfolioReconciliationTests.testDuplicatePhysicalRowsProjectToOneSummedPosition` | Projection sums duplicates; event/activity quantities agree | PASS |
| Correction and rekey / merge | `OwnershipLedgerCompletenessTests.testCorrectionRequiresTwoCompleteLegsToPreserveTotalOwnership`; `CollectionActivityHistoryTests.testCorrectingOneEntryLeavesSiblingEntriesUntouched`; `testRepeatingCorrectionTapDoesNotAppendAnotherMutation`; `testLegacyRowRepairsToARekeyedCanonicalLedgerBeforeWriting` | Two-leg correction, sibling isolation, repeated-tap idempotency, canonical rekey | PASS |
| Undo and restore | `CollectionActivityHistoryTests.testUndoLeavesOriginalActivityAndAppendsAnUndoneEntry`; `testRepeatedUndoAndRemovalActionsDoNotAppendSecondMutations`; `testRestoreMergesBackIntoSurvivingSiblingCopies`; `testRestoreIsBlockedAfterThePositionIsReacquired` | Inverse activity/event lineage and blocked stale restore | PASS |
| Magic-treatment migration | `CollectionActivityHistoryTests.testAddingTreatedPrintingRekeysLegacyCollectionHistoryWithoutDuplicate`; `testMagicTreatmentIdentityFollowsActivityAndRemovalSnapshot`; `PortfolioReconciliationTests.testMigrationBaselinesDuplicateRowsAsOneEventWithTheSummedQuantity` | Legacy-to-canonical identity migration preserves one ownership projection | PASS |
| Pre-ledger baseline | `OwnershipLedgerCompletenessTests.testDiskBackedPreLedgerBaselineIsOneDeterministicEventAfterRestart`; `PortfolioReconciliationTests.testEquivalentBaselineDuplicatesCanonicalizeToEarliestOwnershipTime`; `testFailedEpochSaveDoesNotMarkTrackingEstablishedAndRetries` | F04 fixed; deterministic one-event restart; failed save leaves epoch unset and retries | PASS |
| Canonical replay and negative-net guard | `OwnershipLedgerCompletenessTests.testAcquisitionAndRemovalReconstructToCurrentQuantity`; `testCorrectionRequiresTwoCompleteLegsToPreserveTotalOwnership` | Positive projection only; negative correction leg is not exposed as owned quantity | PASS |
| CloudKit duplicate/conflict read and repair guard | `PortfolioReconciliationTests.testReadSideCanonicalizesCloudKitDuplicatesAndSurfacesConflicts`; `testConflictingLedgerRowsPauseHistoryWithoutHidingCurrentValue`; `testQuantityRepairAppendsOneAdjustmentPerMismatchedPosition`; `testQuantityRepairRejectsMixedDefectsWithoutMutation` | Equivalent rows canonicalize; conflicting rows pause publication; repair refuses mixed defects | PASS (simulator only) |

The separate exact-candidate full simulator run remains non-clean because of
centering and scanner catalog-miss failures. That does not reopen this
ownership matrix, but it means G3/G4 and release certification remain
unapproved until the other gates close. Physical-device, entitled CloudKit
production, and two-device convergence evidence are still required.
