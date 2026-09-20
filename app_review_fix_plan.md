# CardScanner App Review Fix Plan

> Bootstrapped by `swift-safe-fixer` from the product-owner review supplied in
> this task. The remediation changes are now committed in the repository history;
> this plan does not constitute release certification.

## Current checkout reconciliation — 2026-09-20

This root-level file is the current App Review remediation authority. The
branch/SHA and suite counts in the original baseline below belong to the
earlier `fix/app-review-preflight` candidate and are historical context, not
the current checkout. The current tree is
clean `main` at `31eb97e`.

Source-level storage hardening and focused regression coverage have progressed,
but production CloudKit enrollment, physical-device continuity, ownership-ledger
certification, and a clean exact-candidate suite remain open. The latest logged
full simulator run remains the historical `a4375df` run: 1,277 executed, 6
skipped, and 40 failures. See the current
[`docs/release/phase-1-integrity-evidence.md`](docs/release/phase-1-integrity-evidence.md)
for the candidate ledger.

## Pass-2 F01–F03 remediation — 2026-09-19

The three requested pass-2 findings are now addressed in the committed tree:

- [x] F01 — an unproven restoration source is now an explicit policy input.
  Fresh and unsafe-to-recreate iCloud paths stay on-device, failed restoration
  exposes **Keep on This Device**, and the manifest is not changed to
  `.attached` until affirmative readiness.
- [x] F02 — headless container construction now takes the manifest-derived
  `CollectionStorageMode`; `.neverAttached` and `.suspended` production paths
  request `.onDevice`, and headless installation updates the app's active mode.
- [x] F03 — pending scanner answers are retained until the resolution task is
  accepted. A busy pipeline reports a recoverable problem and leaves the answer
  available for retry; the regression test covers the interleaving directly.

Focused evidence on the iPhone 17 Pro iOS 26.5 simulator is 64 storage,
policy, and continuity tests passing in both Debug and DebugProduction (the
DebugProduction run has one intentional entitlement-gated skip), 20 readiness
tests passing, and the new F03 regression passing. This is source and simulator
evidence only; RF-7 still requires the entitled-device and clean-install/
background-refresh checks below.

## Historical baseline — `fix/app-review-preflight`

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

Current focused verification is `PASS` for 64 storage/policy/continuity tests
in Debug, the same 64 tests in DebugProduction with one intentional skip, 20
`CloudRestorationReadinessTests`, and the new pending-resolution regression.
The older 59-test count is retained only in historical notes elsewhere; it is
not the current evidence count.

## Historical verification snapshot — pre-current-checkout

The following storage-remediation run belongs to the earlier candidate and is
retained for implementation evidence only; it is not the current full-suite
result:

`EXECUTED — 1,205 tests; 45 failures at baseline, 43 with these fixes.` The
remaining 43 were classified as pre-existing and unrelated:
centering-corpus/fixture failures, source-path tests that resolve relative to
`/` under `xcodebuild`, a `CollectionSyncDiagnostics` date-encoding mismatch,
and two tracked `OwnershipLedgerCompletenessTests` assertions. The storage
suites have zero failures. No commit hash is claimed until the owner requests
or approves a commit containing the complete working tree.

The latest complete full-suite result is recorded in the [current release
ledger](docs/release/phase-1-integrity-evidence.md): the historical `a4375df`
run executed 1,277 tests with 6 skipped and 40 failures. No full suite has been
rerun at current HEAD `31eb97e`.

## Verification and rollback

Each bucket will be source-checked before the next bucket is advanced. No
destructive commands or broad worktree reset are permitted. Rollback is by
targeted patch only; release evidence must name the exact candidate it covers.
