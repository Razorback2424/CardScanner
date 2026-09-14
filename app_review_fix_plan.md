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
- Baseline runtime: the full Debug suite executed 1,205 tests with 45 known
  failures before this remediation; physical-device verification remains
  unavailable.

## Remediation buckets

- [ ] Storage architecture and local-only disclosure — Blocker — the production
  factory now keeps `.onDevice` proof-gated and uses explicit CloudKit versus
  local-only configurations; Task 4B/device proof still required
- [ ] Manifest/store-file identity and path validation — Blocker — source hardening
  now distinguishes a completely absent replica from orphaned journals and
  identity corruption, rejects unsafe replacement paths, rotates the physical
  store identity at physical store replacement before container construction;
  readiness authority remains checkpoint-only and failed path resolution stays
  fail-closed; runtime execution still required
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
  replica URL before construction and returns without constructing a
  non-authoritative container while the G4 readiness gate is unproven; an
  active process session is reused without rotating the generation, while
  suspended/transitioning sessions skip safely; runtime execution still required
- [ ] Magic treatment migration generation fencing — High — token propagation,
  cancellation, rollback, and gate invalidation applied; runtime execution still required
- [ ] Ownership-ledger production-entry matrix — High/specification gap — disk-backed
  production-entry/restart/rollback coverage added; full matrix execution still required
- [x] Screenshot tooling bundle identifier — High — default corrected to
  `com.seankeller.CardScanner`

## C1–C4 review follow-up

- [x] C1 — forced restoration now binds a replacement identity to the sidecar
  and manifest before CloudKit container construction; the readiness checkpoint
  remains the only readiness authority. A failed remote adoption is covered by
  a relaunch regression test and retries restoration instead of entering the
  identity-metadata support block.
- [x] C2 — headless preflight retains anchor/generation/identity/path checks but
  returns before constructing a non-authoritative production container. The
  populated-checkpoint continuity test asserts `makeCount == 0`.
- [x] C3 — the replica-state fixture now models an explicitly missing sidecar,
  and the test target's Debug configuration matches the app's
  `LOCAL_ONLY_SIGNING` condition. Release remains the no-flag production-path
  compile configuration. No-flag XCTest coverage remains a follow-up because
  Release does not enable `ENABLE_TESTABILITY`; add a `DebugProduction`
  configuration with testability enabled and without `LOCAL_ONLY_SIGNING`,
  without changing the shipping Release configuration.
- [x] C4 — dependency defaults for anchor reads are now `.unknown`, preserving
  fail-closed behavior when a caller omits the dependency.

Focused storage verification is `PASS — 59 tests, 0 failures` across
`CollectionStoragePolicyTests`, `CollectionStoreContinuityTests`,
`CollectionStorageBootstrapTests`, `CloudCollectionAnchorStoreTests`, and
`CloudRestorationReadinessTests` on the iOS 26.5 simulator.

Full-suite verification is `EXECUTED — 1,205 tests; 45 failures at baseline,
43 with these fixes`. The remaining 43 are pre-existing and unrelated:
centering-corpus/fixture failures, source-path tests that resolve relative to
`/` under `xcodebuild`, a `CollectionSyncDiagnostics` date-encoding mismatch,
and two tracked `OwnershipLedgerCompletenessTests` assertions. The storage
suites have zero failures. No commit hash is claimed until the owner requests
or approves a commit containing the complete working tree.

## Verification and rollback

Each bucket will be source-checked before the next bucket is advanced. No
destructive commands or broad worktree reset are permitted. Because the tree
already contains user-owned implementation and documentation edits, rollback
is by targeted patch only; no commit hash is claimed until the owner requests
or approves a commit that includes the complete reviewed working tree.
