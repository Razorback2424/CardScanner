# Ordinary-card interruption and collection-scale acceptance

**Status:** review test plan and automated raw CSV regression, not distribution/device acceptance.
**Scope:** non-graded collection journeys only. See [launch contract](../release/launch-contract.md) for the product's authoritative release gates.

## Automated coverage added

`CSVImportResumeTests.testLargeInterruptedRawImportResumesWithoutDuplicateEvents` creates 160 distinct ordinary-card CSV entries, interrupts after multiple durable batches, then resumes from a fresh context. It asserts exactly-once inventory events and quantity one for every card, then replays the same file to prove idempotence. Unlike smaller existing 2–3 row fixtures, this crosses more than one checkpoint. It does **not** benchmark elapsed time or stand in for a live Files import.

Existing tests to rerun unchanged: `CSVImportResumeTests`, `OwnershipConcurrencyStressTests`, `StoreRevisionMonitorTests`, `CollectionStoreModeTransitionTests`, `PriceRefreshLifecycleTests` (excluding any dedicated graded scenarios when evaluating this slice).

## Device/manual acceptance still required

| Interruption | Expected result | Evidence to retain |
| --- | --- | --- |
| Suspend/resume application while a raw scan is saving | No duplicate holding or phantom acknowledgement; pending write resolves safely | Video + persisted rows/activity |
| Leave scanner while resolving a raw catalog identity | No scan completion displayed in the wrong session or tab | Video + session trace |
| Background during ordinary price refresh | Browsing and edits remain usable; stale quote remains honest; no duplicate refresh storm | OSLog + source/check times |
| Import 160+ ordinary holdings from Files, interrupt, reopen same file and resume | Completed rows are not imported twice; remaining rows eventually appear | Import result + inventory digest |
| Airplane mode with existing holdings | Local collection, search, editing and export remain functional; missing network evidence is explicit | Screen recording |
| Switch storage session during pending raw save or import | Old-generation completion cannot mutate newly selected store | Before/after digest + generation log |
| Browse and sort 100, 1,000, 5,000 logical holdings | Correct results with no unacceptable UI stalls | Instruments traces, not subjective claims |

Run only against a disposable profile/store. Preserve the user's real collection. File a distinct issue/PR for each reproduced failure; do not add extra concurrency machinery prophylactically.

## Acceptance

Automated checks and fresh-device scenarios must be separately recorded as passed, failed, or not run, including candidate commit, OS/device, trace and data integrity evidence. A checked-in plan or a passing simulator suite is not a substitute for physical-device acceptance.
