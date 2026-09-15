# CardScanner 1.0 Phase 0/1 release evidence

**Status:** current candidate ledger, not release certification — reconciled
2026-09-14

This path is the current evidence authority for the active Phase 0/1 launch
plan. The previous candidate ledger is retained as the
[legacy evidence record](../legacy/phase-1-integrity-evidence.md); its `main`
branch and `a115e4e`/`ec7dc6b` identities do not describe this checkout.

## Candidate identity

- Repository: `TradingCardScannerMVP_fixed_v4`
- Branch: `codex/scanning-workflow-review-remediation`
- HEAD at this reconciliation: `0b4ac34`
- App/test targets: `TradingCardScanner` / `TradingCardScannerTests`
- Marketing/build version: `1.0 (1)`
- Bundle identifier: `com.seankeller.CardScanner`
- Minimum OS: iOS/iPadOS 17.0
- Device families: iPhone and iPad (`1,2`)

The working tree contains user-owned source, test, asset, and documentation
changes. Evidence must be rerun against the exact tree intended for the release;
the short SHA above is a locator, not a certification claim for uncommitted
changes.

## Current recorded evidence

- `git diff --check`: PASS at this reconciliation.
- Latest logged full simulator run: 1,256 tests discovered, with 48 failures
  classified in the progress log as unrelated fixture/source-environment or
  signal-kill failures. This is not a clean release-suite result.
- Latest focused Browse/Catalog verification: 46 tests, 0 failures; the settled
  iPhone 17 Pro capture and Debug build are recorded in `progress.md` and the
  Browse checklist.
- Scanner workflow fixes have focused regression/build evidence, but physical
  camera, thermal, and live-provider validation remain open.
- Card-centering remains blocked by the current accuracy, invariant, latency,
  and device-only gates in the active centering plan.

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
