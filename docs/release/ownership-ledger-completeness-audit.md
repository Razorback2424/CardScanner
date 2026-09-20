# Ownership-ledger completeness audit

**Status:** current gate shell — not certified for the current checkout;
reconciled 2026-09-20

This document is the current authority for proving that every production
quantity mutation leaves a complete, durable, idempotent `InventoryEvent`
history. The detailed 2026-09-13 candidate audit is preserved in the
[legacy audit](../legacy/ownership-ledger-completeness-audit.md) and must not be
carried forward without rerunning it against the current tree.

## Current candidate

- Branch: `main`
- HEAD locator: `31eb97e`
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

## Evidence status

The current source contains `InventoryLedger` and the related mutation paths,
but the archived candidate matrix is not evidence for `31eb97e`. Run the
exhaustive inventory and the production-entry/restart/
rollback matrix before treating the ledger as CloudKit conflict authority.

Record the result in this file and link the exact result bundle from
[`phase-1-integrity-evidence.md`](phase-1-integrity-evidence.md).

## Known findings against this proof — 2026-09-14

`OwnershipLedgerCompletenessTests` was red in the historical `a4375df` run with
three failures, triaged in
[`../audits/defect_review_pass_2.md`](../audits/defect_review_pass_2.md). Two of
them bear directly on requirement 4 above — that quantities rebuilt from
canonical events agree with the persisted collection projection — and must be
resolved before the matrix is rerun, not classified as environmental noise:

| Test | Pass-2 finding | Bearing on this proof |
| --- | --- | --- |
| `testDiskBackedPreLedgerBaselineIsOneDeterministicEventAfterRestart` | F04 | `PortfolioEpoch.establishIfNeeded` writes `initialBalance` events with no matching `CollectionActivity`, so `CollectionActivity.integrityDefects` reports a `quantityMismatch`. In production the invariant holds only because `backfillExistingCollectionIfNeeded` runs first, from a `try?` call whose failure is discarded. This is requirement 3 (a failed write leaving inconsistent activity state) and requirement 4. |
| `testCorrectionRequiresTwoCompleteLegsToPreserveTotalOwnership` | F05 | `InventoryLedger.quantities(from:)` filters `!= 0` and therefore retains a negative net as an owned quantity. The function has no production callers today, so this is a contract defect in the rebuild helper rather than a live ownership defect — but it is the helper this audit's requirement 4 would naturally reach for. |
| `testSourceInventoryNamesEveryOwnershipEntryPoint` | F05 (second half) | Reads `$SRCROOT`-relative paths from the test process working directory; a harness defect, no bearing on ownership. |

Do not rerun the completeness matrix while these are open: F04 in particular
means the baseline path this audit is meant to certify currently produces a
state the integrity check rejects.
