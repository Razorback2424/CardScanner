# Non-graded refinement — candidate verification and release evidence

**Status:** candidate checklist, **not passed**. **Review baseline:** `4c4a2e6f3720`.
This document coordinates the small refinement PRs without creating a second release authority. The [launch contract](launch-contract.md) controls all app-wide supported-scope and release decisions. This slice does **not** approve or waive any outstanding launch gate.

**This pass excludes all graded/slab work**. Exclusion from *this refinement batch* does not mean the full product's prior requirements have been satisfied, removed or deferred.

## Freeze and verify only what changed

1. Record the exact candidate SHA, branch ancestry and final diff. Verify no unintended changes to catalog signatures, game activation flags, pricing-service access, purchases, or storage schema.
2. Review the non-graded refinement slices independently: [baseline protocol (PR #26)](https://github.com/Razorback2424/CardScanner/pull/26), collection provenance fingerprint, bounded snapshot-read recovery, ordinary-card interruption regression.
3. For each source change, execute its specifically named regression, then its parent test class and applicable neighboring suites. Count failures and skips separately.
4. Run both the existing curated native/catalog CI and the complete iOS Release build/test gate proposed in [PR #23](https://github.com/Razorback2424/CardScanner/pull/23), once that workflow is present in the candidate. The curated selection alone does **not** constitute a full-suite pass. On a suitable local macOS/Xcode host, `scripts/run_app_tests.sh fast` supports `-only-testing:` filters; it requires `DEVICE_ID` and `DERIVED_DATA` on an external `/Volumes/...` drive. Use `WORKERS=1` under memory pressure.
5. Build the actual release configuration and inspect entitlements, supported games/capabilities, missing support/privacy URLs, and purchased-feature gating. Simulator compilation does not prove signing, archived distribution or device operation.
6. Re-run the ordinary-card device scenarios in [interruption acceptance (PR #27)](https://github.com/Razorback2424/CardScanner/pull/27) and the [device baseline (PR #26)](https://github.com/Razorback2424/CardScanner/pull/26), with the **same** data and device conditions before and after.
7. Leave unresolved failed checks, unmet launch contract gates, and missing evidence explicitly open. Do not merge unrelated cleanup into the release candidate merely to make the diff look tidier.

## Small focused regression selection (after the corresponding PRs are present)

- `StoreRevisionMonitorTests/testProvenanceOnlyChangeInvalidatesCollectionProjectionFingerprint`
- `PricingTests/testPriceSnapshotRebuildRecoversAfterOneTransientReadFailure`
- `PricingTests/testPriceSnapshotReadFailureStopsAfterBoundedRetriesAndRetainsPrices`
- `CSVImportResumeTests/testLargeInterruptedRawImportResumesWithoutDuplicateEvents`

Run these together with existing ordinary-card regressions, including the raw CSV import resume/replay tests, collection query behavior, stored quantity continuity, foreground/background price refresh, and storage generation transitions. Do not interpret a zero-test selection as a pass.

## Integration order and overlapping changes

- PR #23 contains the initial provenance-fingerprint fix and bounded price-snapshot recovery. The narrower [PR #24](https://github.com/Razorback2424/CardScanner/pull/24) has its own provenance test; [PR #25](https://github.com/Razorback2424/CardScanner/pull/25) extends the same snapshot work with storage-container isolation. Review their shared hunks after bringing them onto a combined candidate; no duplicate or conflicting runtime implementation should survive.
- [PR #27](https://github.com/Razorback2424/CardScanner/pull/27) adds raw import interruption coverage and opts that suite into native PR CI; [PR #26](https://github.com/Razorback2424/CardScanner/pull/26) is a measurement protocol, not evidence of performance.
- Record the combined head SHA **after** resolving overlaps. A clean CI result for any isolated PR does not certify a different, combined candidate. Leave all changes unmerged until that verification exists.

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
