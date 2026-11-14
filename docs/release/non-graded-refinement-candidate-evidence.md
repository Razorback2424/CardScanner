# Non-graded refinement — candidate verification and release evidence

**Status:** candidate checklist, **not passed**. **Review baseline:** `4c4a2e6f3720`.
This document coordinates the small refinement PRs without creating a second release authority. The [launch contract](launch-contract.md) controls all app-wide supported-scope and release decisions. This slice does **not** approve or waive any outstanding launch gate.

**This pass excludes all graded/slab work**. Exclusion from *this refinement batch* does not mean the full product's prior requirements have been satisfied, removed or deferred.

## Freeze and verify only what changed

1. Record the exact candidate SHA, branch ancestry and final diff. Verify no unintended changes to catalog signatures, game activation flags, pricing-service access, purchases, or storage schema.
2. Review the non-graded refinement slices independently: [baseline protocol](../benchmarks/release-refinement-device-baseline-2026-11.md) (once available), collection provenance fingerprint, bounded snapshot-read recovery, ordinary-card interruption regression.
3. For each source change, execute its specifically named regression, then its parent test class and applicable neighboring suites. Count failures and skips separately.
4. Run the *existing* release/build and broad testing procedure, rather than building another test runner. On a suitable macOS/Xcode host, `scripts/run_app_tests.sh fast` supports `-only-testing:` filters; it requires `DEVICE_ID` (simulator) and `DERIVED_DATA` on an external `/Volumes/...` drive. Use `WORKERS=1` if the host has memory pressure.
5. Build the actual release configuration and inspect entitlements, supported games/capabilities, missing support/privacy URLs, and purchased-feature gating. Simulator compilation does not prove signing, archived distribution or device operation.
6. Re-run the ordinary-card device scenarios in [interruption acceptance](../benchmarks/non-graded-interruption-acceptance-2026-11.md) (once available) and the [device baseline](../benchmarks/release-refinement-device-baseline-2026-11.md), with the **same** data and device conditions before and after.
7. Leave unresolved failed checks, unmet launch contract gates, and missing evidence explicitly open. Do not merge unrelated cleanup into the release candidate merely to make the diff look tidier.

## Small focused regression selection (after the corresponding PRs are present)

- `StoreRevisionMonitorTests/testProvenanceOnlyChangeInvalidatesCollectionProjectionFingerprint`
- `PricingTests/testPriceSnapshotRebuildRecoversAfterOneTransientReadFailure`
- `PricingTests/testPriceSnapshotReadFailureStopsAfterBoundedRetriesAndRetainsPrices`
- `CSVImportResumeTests/testLargeInterruptedRawImportResumesWithoutDuplicateEvents`

Run these together with existing ordinary-card regressions, including the raw CSV import resume/replay tests, collection query behavior, stored quantity continuity, foreground/background price refresh, and storage generation transitions. Do not interpret a zero-test selection as a pass.

## Evidence ledger (populate for each candidate)

| Gate | Candidate result | Required evidence |
| --- | --- | --- |
| Release configuration compiles | Not run | Xcode/toolchain, command, log and candidate SHA |
| New focused tests pass | Not run | `.xcresult`, test count, failures and skips |
| Neighboring regression suites pass | Not run | `.xcresult` and deviations from prior baseline |
| Real-device ordinary scan/save/navigation | Not run | Hardware, OS, video/trace, before/after state |
| Raw import interruption and recovery | Not run | Before/after row, quantity and ledger digests |
| Price-snapshot transient failure recovery | Not run | Deterministic injected failure result |
| Performance does not regress | Not run | Matched-workload Instruments traces, p50/p95 |
| Required app-wide launch gates | **Open** | See authoritative [launch contract](launch-contract.md) and latest launch audit |

## Decision rules

- **Pass a slice** only with executed evidence on the intended revision; documentation alone does not pass it.
- **No-go** if any supported ordinary-card journey produces incorrect ownership, materially false prices, a crash, a blocked action, or a reproducible unacceptable delay.
- Missing device or distribution evidence stays **not run**, never silently treated as pass.
- **Do not** relabel a pre-existing release blocker as resolved, or change the product acceptance criteria, simply because these narrow PRs are merged.
- Each additional reproduced defect receives a small independent issue/PR with a regression and a before/after check; no opportunistic rewrite.

## Sign-off

Candidate SHA: **not selected**  
Xcode release build: **not run**  
Focused tests: **not run**  
Physical-device checks: **not run**  
App-wide launch decision: **unchanged; use launch contract**
