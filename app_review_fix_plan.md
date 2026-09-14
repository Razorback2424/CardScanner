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

- [ ] Storage architecture and local-only disclosure — Blocker — the production
  factory now keeps `.onDevice` proof-gated and uses explicit CloudKit versus
  local-only configurations; Task 4B/device proof still required
- [ ] Manifest/store-file identity and path validation — Blocker — source hardening
  now distinguishes a completely absent replica from orphaned journals and
  identity corruption, rejects unsafe replacement paths, rotates the physical
  store identity only after restoration readiness, and keeps failed path
  resolution fail-closed; runtime execution still required
- [ ] Confirmed anchor claim ordering — Blocker — source ordering and orchestration
  tests applied; claim readback now also rejects unsupported anchor format or
  missing generation before container construction; runtime execution still
  required
- [ ] Restoration observability and continuity suites — Blocker — cached empty
  checkpoints can no longer authorize startup, populated checkpoints are
  explicitly last-known/non-authoritative, and checkpoints require the current
  anchor generation; the production readiness mechanism remains deliberately
  unproven
- [ ] Fresh-process background storage preflight — High — headless preflight now
  validates the current anchor, exact generation, store identity tuple, and
  replica URL before construction; an active process session is reused without
  rotating the generation, while suspended/transitioning sessions skip safely;
  runtime execution still required
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
