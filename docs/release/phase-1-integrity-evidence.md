# CardScanner 1.0 Phase 0/1 release evidence

**Status:** current candidate ledger, not release certification — reconciled
2026-09-20; F06 follow-up recorded 2026-09-16

This path is the current evidence authority for the active Phase 0/1 launch
plan. The previous candidate ledger is retained as the
[legacy evidence record](../legacy/phase-1-integrity-evidence.md); its `main`
branch and `a115e4e`/`ec7dc6b` identities do not describe this checkout.

## Candidate identity

- Repository: `TradingCardScannerMVP_fixed_v4`
- Branch: `main`
- HEAD at the 2026-09-20 reconciliation: `31eb97e`
- App/test targets: `TradingCardScanner` / `TradingCardScannerTests`
- Marketing/build version: `1.0 (1)`
- Bundle identifier: `com.seankeller.CardScanner`
- Minimum OS: iOS/iPadOS 17.0
- Device families: iPhone and iPad (`1,2`)

The working tree is clean at this reconciliation. The short SHA above is a
locator, not a certification claim: the recorded test evidence below predates
this HEAD unless explicitly stated otherwise, and must be rerun against the
exact tree intended for release.

## Current recorded evidence

- `git diff --check`: PASS at this reconciliation.
- Latest complete full simulator run: `a4375df`, 1,277 executed, 6 skipped,
  40 failures (36 fixture-resource lookup failures, 1 load-sensitive flake,
  and 3 substantive failures). This is not a clean release-suite result; see
  the F06 follow-up below. The earlier 1,256-discovered/48-failure snapshot at
  `0b4ac34` is historical and must not be reused as the latest run.
- 2026-09-16 focused F06 follow-up based at historical `main` commit `c381c99`:
  the PBX
  resource-ID collision was corrected and the committed corpus reached the
  test bundle. The selected centering tests produced 38 results (28 passed,
  9 test cases failed on centering assertions, and 1 profile-dump test was
  canceled); fixture reachability and manifest tests passed. This is not a
  full-suite rerun.
- Latest focused Browse/Catalog verification: 133 tests, 0 failures. A8/B6 are
  backed by the settled iPhone 17 Pro light/dark capture; C7/RF-9 remains open.
- Scanner workflow fixes have focused regression/build evidence, but physical
  camera, thermal, and live-provider validation remain open.
- Card-centering remains blocked by the current accuracy, invariant, latency,
  and device-only gates in the active centering plan.

## F06 follow-up — fixture bundle wiring, 2026-09-16

All 57 files under `TestFixtures/TradingCards/` were tracked at both the
historical `a4375df` run and the F06 follow-up tree based at `c381c99`. Duplicate
`PBXBuildFile`/`PBXFileReference` UUIDs caused the test target's fixture resource
entry to resolve as `CardFinishRenderPlanTests.swift`; the test group also used
an undefined fixture reference. The project file now has unique resource IDs
and consistent group/build-phase references.

The external-SSD result bundle `f06-fixture-copy-20260916.xcresult` records 38
selected results: 28 passed, 9 test cases failed on already-open centering
accuracy/invariant/performance assertions, and 1 profile-dump test was canceled.
`testRealFixturesAndGroundTruthAreReachableFromTheTestBundle` and
`testCorpusManifestIsCompleteAndCryptographicallyFrozen` passed. The profile
suite writes generated diagnostics into tracked review paths, so it was stopped
before more workspace outputs accumulated; the seven changed outputs were
preserved on the external SSD and the tracked files restored. The result is
partial and does not replace the last full-suite run. The corpus is committed
input, so skip guards are not appropriate; continue with RF-6 and the centering
contract's existing analyzer gates.

## Gates not yet certified

The following remain `NOT RUN` or open for the exact release candidate:

- approved App ID, entitlements, CloudKit Development/Production schema, and
  two-device convergence;
- production-entry storage/bootstrap and ownership-ledger evidence;
- clean-install, archive, TestFlight, and App Store metadata inspection;
- full current-tree regression without the unrelated simulator failures;
- physical iPhone/iPad scanner and Browse accessibility/provider passes;
- the frozen normal/adversarial scanner acceptance program;
- current centering accuracy and latency gates.

## Current references

- [`app_review_fix_plan.md`](../../app_review_fix_plan.md) — source remediation
  status and owner-controlled storage gates.
- [`cloudkit-compatibility-audit.md`](cloudkit-compatibility-audit.md) and
  [`cloudkit-release-matrix.md`](cloudkit-release-matrix.md) — CloudKit gates.
- [`ownership-ledger-completeness-audit.md`](ownership-ledger-completeness-audit.md)
  — current gate shell for quantity-mutation completeness.
- [`../plans/release_followups.md`](../plans/release_followups.md) — device and
  measurement backlog.
- [`../../review/opus-card-centering-implementation-plan.md`](../../review/opus-card-centering-implementation-plan.md)
  — active centering contract.
