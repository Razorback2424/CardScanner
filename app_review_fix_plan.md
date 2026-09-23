# CardScanner App Review Fix Plan

> Bootstrapped by `swift-safe-fixer` from the product-owner review supplied in
> this task. The remediation changes are now committed in the repository history;
> this plan does not constitute release certification.

## Previous checkout snapshot — 2026-09-20

At the time of this snapshot, this root-level file was the App Review
remediation authority. Its branch/SHA and suite counts describe the earlier
`feature/catalog-and-scanner-hardening` candidate, not the current worktree.
The tree at that time was
clean `feature/catalog-and-scanner-hardening` at `7dbaf40`.

Source-level storage hardening and focused regression coverage have progressed,
but production CloudKit enrollment, physical-device continuity, ownership-ledger
certification, and a clean exact-candidate suite remain open. The intended
candidate is the clean `feature/catalog-and-scanner-hardening` branch at
`7dbaf40`. The exact-candidate focused run executed 581 tests with 579 passed,
1 skipped, and 1 failed in the scanner catalog-miss test. The exact-candidate
full simulator run executed 1,278 tests with 6 skipped and 4 failures (1
unexpected); centering, ownership, and scanner catalog-miss failures remain
open. See the current
[`docs/release/phase-1-integrity-evidence.md`](docs/release/phase-1-integrity-evidence.md)
for the candidate ledger.

## Current worktree remediation — 2026-09-22

The active workspace is `main` at base `810954e`; this remediation is an
uncommitted working-tree change. N1–N3, N5–N7, and F1–F4 are implemented. N4's
Settings copy is truthful, but its Release URLs remain open until the owner
provides the actual deployed destinations. The affected simulator regression
selection passed 99 tests with 1 skip; a separate delete-actor integration test
passed 1/1. The skipped file-protection assertion is a Simulator limitation,
not a device result. An intermediate broader run exposed and led to correction
of the synthetic-CSV canonicalization regression; it also reported an unrelated
existing Cardmarket expectation in `CatalogNormalizationTests`. No full-suite,
physical-device, CloudKit, archive, TestFlight, provider, or release
verification is claimed. No branch or commit was created. Earlier candidate
and test counts above remain evidence for that historical checkout only.

The targeted follow-up batch for scanner-to-Settings bulk-operation access,
identity-aware fallback eligibility, retry latching, and truthful deletion
copy passed 4/4 selected tests on iPhone 17 Pro / iOS 26.5 Simulator. This
confirms source behavior only; active-refresh timing and physical-device
behavior remain open.

| Finding | Code-level change and acceptance | Status / remaining evidence |
| --- | --- | --- |
| N1 — duplicate proof lifetime | `ScannerViewModel.pruneSpatialResetProofsToLiveHistory()` retains token-bound evidence only while its encounter and presentation token remain in `committedSessionHistory`. A proof with `presentationToken == nil` is provisional and survives only while `oneCardScanIntervals[encounterID]` shows that encounter is still pending. Prune immediately after the bounded history trim and after automatic routing, `addAnother`, held-repeat, and suppression. Keep the full clears at session reset and interruption. `undoScan` already removes the undone encounter's proof; retain that scoped behavior and cover it. Acceptance: A→B→A′ presents the duplicate dialog; choosing **Same card** never inserts A′. This explicitly accepts a prompt for the same physical A after B where the prior behavior silently suppressed it. | Regression coverage exercises A→B→A′, `addAnother`, held-repeat, scoped undo, and the no-add Same card choice. Device stack acceptance remains open. |
| N2.1 — skip an unused account probe | When `readinessSource.isProven == false`, pass `CloudAccountAvailability.notQueried` through `CollectionStoragePolicy`; do not substitute `.noAccount`. Policy opens a verified local replica but conservatively blocks when a manifest exists and the replica is absent. Bootstrap skips account and anchor probes and ignores account-change notifications in unproven mode. | Policy/bootstrap tests cover fresh local open, verified-replica open, missing-replica block, zero account-probe calls, and account-change no-op. Fresh-install airplane-mode launch timing remains a device check. |
| N2.2 — reuse a same-process local container (separate slice) | Before `start()` suspends the storage generation, cancels refresh, pauses Magic migration, or creates a container, reuse `storageGeneration.activeSession()` only when readiness remains unproven, the session is `.onDevice`, and policy selects the exact same `storeID` with `.restorationUnproven`. Preserve the generation token and current attachment state. | A bootstrap test asserts the container instance is reused, its generation token remains current, and neither the account probe nor a second container creation occurs. Device acceptance must exercise background-task launch followed by foreground start in the same process and verify no duplicate store open/write. |
| N3 — locked background refresh | Remove the `isProtectedDataAvailable` early return from `BackgroundPriceRefresh.run`. Set `completeUntilFirstUserAuthentication` at all four manifest/identity write sites in `CollectionStoreManifestStore`: the manifest metadata directory and temporary manifest before replacement; the identity metadata directory and temporary identity sidecar before replacement. On a readable foreground load, best-effort migrate existing manifest, sidecar, and metadata-directory attributes. | Simulator cannot report the protection attributes; its test skips explicitly. Keep locked-and-charging device verification open. The privacy policy states the tradeoff: after first unlock, the local manifest and identity metadata (store ID, attachment/migration state, opaque account fingerprint, checkpoint, and file identity) are readable while locked; collection rows and images are not in those metadata files. |
| F1 / N5 — no-provider price result | `PriceLookup.hasObservation` controls persistence: `.unavailable(nil)` is never stored as a provider observation. Fallback eligibility is separate: scanner, Browse, and automatic refresh callers pass `identifiedCatalogCard: true` when a catalog identity exists, so an identified Pokémon/Magic card with no catalog quote may still reach JustTCG when fallback is enabled. The eventual vendor result is persisted only when it carries an observation. Browse keeps its fallback call behind this shared identity-aware rule and avoids saving an empty context or reporting a false price-save failure. | Regression coverage distinguishes no-observation persistence from identity-aware fallback eligibility. Acceptance: skipped `.unavailable(nil)` catalog data leaves no price record and remains immediately eligible on the next automatic pass because `lastCheckedAt == nil`. Fallback remains user opt-in and consumes the shared JustTCG budget. |
| F2 / refresh eligibility | Automatic `.noSupportedProvider` stamps for raw and graded cards use the same 30-day retry interval while fallback is enabled; with fallback disabled they are not retried automatically. Manual `forceUnsupportedRetry` bypasses the interval. A never-checked row remains immediately eligible. Rows with no price **or** missing artwork retry immediately when `lastCheckedAt == nil`, otherwise after eight hours. Include `usesPriceFallback` in monitor observation and the target fingerprint; persist the observed preference and reset coalescing on change. If enabling fallback meets an active same-collection pass, retain the forced retry and start it after that pass using a fresh collection fingerprint; forced retry bypasses target deduplication. Accepted delay: there is no eight-hour wake timer; a row crossing the threshold mid-session becomes eligible at the next launch, store/save observation, or relevant preference change. | Boundary tests cover provider-negative 30-day behavior, missing artwork, immediate never-checked eligibility, and the retry latch. Same-collection live-toggle timing remains a device/runtime acceptance check. |
| N6 — normalizer retry loop | Scan/Browse catalog rows retain `catalogProviderID`. If that ID exists, require exact provider-ID agreement and fill only missing fields. If a row has no catalog ID but already has a real provider ID equal to the result, also fill only missing fields. A synthetic `csv:` row uses full canonical metadata after the importer resolver successfully matches it, so its imported set label is normalized. Missing rarity alone is not unresolved after exact catalog identity exists; missing image or catalog identity remains actionable. | Tests pass for exact Pokémon-row enrichment, known-field preservation, synthetic-CSV set canonicalization, and missing-rarity eligibility. |
| F4 — save notifications | Deliver both `ModelContext.didSave` and `NSPersistentStoreRemoteChange` through `RunLoop.main` before changing SwiftUI-observed generations. This is a prerequisite to moving deletion off-main because the save observer uses `object: nil` and will see model-actor saves. | Source compiles in the successful affected-suite build. There is no direct callback-thread assertion yet; keep any notification integration check separate from the actor delete test. |
| N7 — bulk import/delete | App-scoped `DerivedStateWriteCoordinator` owns CSV progress and result/export data after Settings is dismissed. It grants one exclusive import or delete token and refuses either operation while the other is active; keep the existing shared write-depth gate as an additional guard. When Settings opens from Scan, pause recognition and release the scanner session's long-lived bulk interval; reacquire it on dismissal. Disable the Done action and interactive dismissal while an exclusive operation is active. `CollectionDeletionModelActor` deletes off the UI context, checks the storage-generation continuation before each position and before its single commit, and rolls back on invalidation. | Focused scanner-to-Settings coverage passes for both exclusive operations; the existing delete-all ledger/history test runs through the model actor. Import throughput at 1,000/5,000 rows and dismiss/reopen behavior remain to measure manually. UTF-8-only CSV parsing is unchanged. |
| N4 — public links | Release build settings for privacy/support URLs remain empty until the owner provides the actual deployed destinations. Settings now says each link is unavailable in this build instead of claiming it is configured. | **Open release blocker / owner input.** Do not publish guessed or undeployed URLs. |
| N8/N9 — measurement and provider migration | Centering PNG export, first-use treatment-catalog decode, Activity Log main-thread reload, portfolio replay cost, and 1,000/5,000-row CSV import remain measurement-gated. The Pokémon TCG API's own [documentation](https://docs.pokemontcg.io/) says existing keys continue through 2027-03-01 and directs integrators to migrate to Scrydex. Keep migration, a separate Magic signing key, and non-UTF-8 CSV support on the release backlog. | No code change in this slice. Recheck the provider timeline and gather measurements before scheduling these changes. |

Implementation order: (1) supply live N4 privacy/support URLs; (2) N1 proof retention and duplicate interaction; (3) F1/N5 shared no-observation pricing rule; (4) N6 exact-identity, fill-only normalization; (5) N2.1 account-probe removal with conservative `.notQueried` policy; (6) N2.2 same-process container reuse as a separate slice after probe removal; (7) F2 refresh eligibility; (8) N3 locked-background metadata protection and privacy disclosure; (9) F4 main-run-loop notification delivery; (10) N7 mutually exclusive bulk import/delete; (11) measure before N8/N9 changes. N4 cannot close until the owner supplies deployed destinations. Keep the release candidate uncertified until device, provider, full-suite, archive, and URL evidence is recorded against the exact candidate.

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
rerun at current candidate `7dbaf40`.

## Verification and rollback

Each bucket will be source-checked before the next bucket is advanced. No
destructive commands or broad worktree reset are permitted. Rollback is by
targeted patch only; release evidence must name the exact candidate it covers.
