# CardScanner App Review Fix Plan

> Bootstrapped by `swift-safe-fixer` from the product-owner review supplied in
> this task. Existing uncommitted work is intentionally not committed or
> reset by this remediation pass.

## Baseline

- Branch: `fix/app-review-preflight`
- Baseline commit: `a115e4e`
- Baseline source checks: Debug/Release source typechecks, simulator app-module
  and XCTest-source typechecks, CloudKit source audit, plist validation, and
  `git diff --check` passed before this remediation pass.
- Runtime XCTest and physical-device verification: unavailable because
  CoreSimulator is disconnected and no entitled devices are present.

## Remediation buckets

- [ ] Storage architecture and local-only disclosure — Blocker — source guard applied;
  Task 4B/device proof still required
- [ ] Manifest/store-file identity and path validation — Blocker — source hardening
  and continuity coverage applied; runtime execution still required
- [ ] Confirmed anchor claim ordering — Blocker — source ordering and orchestration
  tests applied; runtime execution still required
- [ ] Restoration observability and continuity suites — Blocker — continuity/readiness
  suites added; production readiness mechanism remains deliberately unproven
- [ ] Fresh-process background storage preflight — High — headless preflight and
  checkpoint fencing applied; runtime execution still required
- [ ] Magic treatment migration generation fencing — High — token propagation,
  cancellation, rollback, and gate invalidation applied; runtime execution still required
- [ ] Ownership-ledger production-entry matrix — High/specification gap — disk-backed
  production-entry/restart/rollback coverage added; full matrix execution still required
- [x] Screenshot tooling bundle identifier — High — default corrected to
  `com.seankeller.CardScanner`

## Verification and rollback

Each bucket will be source-checked before the next bucket is advanced. No
destructive commands or broad worktree reset are permitted. Because the tree
already contains user-owned implementation and documentation edits, rollback
is by targeted patch only; no commit hash is claimed until the owner requests
or approves a commit that includes the complete reviewed working tree.
