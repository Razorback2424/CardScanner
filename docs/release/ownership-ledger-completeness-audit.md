# Ownership-ledger completeness audit

**Status:** current gate shell — not certified for the current checkout;
reconciled 2026-09-14

This document is the current authority for proving that every production
quantity mutation leaves a complete, durable, idempotent `InventoryEvent`
history. The detailed 2026-09-13 candidate audit is preserved in the
[legacy audit](../legacy/ownership-ledger-completeness-audit.md) and must not be
carried forward without rerunning it against the current tree.

## Current candidate

- Branch: `codex/scanning-workflow-review-remediation`
- HEAD locator: `0b4ac34`
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
but the archived candidate matrix is not evidence for `0b4ac34` or the dirty
working tree. Run the exhaustive inventory and the production-entry/restart/
rollback matrix before treating the ledger as CloudKit conflict authority.

Record the result in this file and link the exact result bundle from
[`phase-1-integrity-evidence.md`](phase-1-integrity-evidence.md).
