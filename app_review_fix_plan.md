# CardScanner App Review Fix Plan

## Browse pagination render investigation — 2026-11-05

Owner-authorized follow-up from clean `0a11fc7`. Tracing the held-provider fixture,
`BrowseViewModel` pagination and the actual `BrowseView` footer establishes an app
concurrency bug: a shared page batch blocks a newly ready lane. The original
four-request and zero-cancellation assertions and their deadlines are unchanged;
no retry-to-green or test skip. Baseline: the unchanged render
test fails 8/10 repetitions with three requests instead of four
(`BrowseRender-20261105/Baseline.xcresult` on the external T7 SSD).

- [x] Reproduce the unchanged failure.
- [x] Establish whether the missing request is fixture synchronization or app
  pagination; add a controlled interleaving regression.
- [x] Apply the smallest verified fix, rerun the original render test repeatedly
  and verify related search/cancellation behavior.

The five diagnostic repetitions all fail with both first responses finished,
one next page held and zero cancellations. The controlled real-view regression
then fails in both game orders (four assertions): an early page batch pins the
single footer, so a late initial response cannot start its next page. This is an
app concurrency bug; increasing the wait cannot release the held batch.

The implementation gives each card/sealed lane its own task in the same footer
and removes the shared key/revision/coordinator. The original render
test is byte-for-byte unchanged. Its first post-fix run and both new native
interleaving/departure tests pass. One adapted model test initially observed the
existing coalesced sealed-results update before delivery; it now awaits that
same result count within its existing readiness helper, retaining its assertions.
The native scroll-out/re-entry check caught a gap in the first fix: a replacement
footer could return while the cancelled request still marked its lane busy, then
never restart after that request settled (two failed assertions). Each lane now
advances its own pagination revision on settled cancellation, waking only its
replacement task without consuming the retained cursor. Existing query, error,
filter and hidden-screen gates remain in the view-model entry points.

The isolated Debug build passed, but `VerifiedFix.xcresult` records an early
test-host exit before any methods ran (zero tests, one infrastructure error).
The same built binary passed all 18 focused checks on a dedicated simulator
(`DedicatedFix.xcresult`), including the re-entry regression and all sealed
surface tests. The exact final source then passes **80 repeated render
executions: 20/20 for each of four methods**, including the unchanged original.
The controlled method exercises both game orders on every run. The stored
`RepeatedFinal.xcresult` metrics report four distinct methods with zero
failures/skips; console records retain all 80 executions. The exact final broader
selection passes **254 distinct methods, zero failures/skips**, covering Browse
search/loading/filtering, collection/checklist integration, presentation, rendered
pagination, sealed surfaces and view construction. `BroaderFinal.xcresult`
metrics agree with all 254 individual console records. The exact final **arm64
Release simulator build passed** (`release-final.log`, exit 0), with the tested
source unchanged. Its slower cold compile is not a controlled timing comparison
with the earlier warm build; a brief sample confirmed active LLVM optimization.
No optimization settings were changed. Whitespace, project-file syntax and added
local documentation-link checks pass.

Concurrent card-detail/pricing edits are preserved. Final verification uses an
external snapshot of `0a11fc7` plus only `BrowseView.swift`,
`SealedBrowseViews.swift` and `BrowseFeatureTests.swift` from this fix; its source
hashes are retained beside the results. Other in-progress changes are not
included or certified by that evidence.
Artifacts are retained under `/Volumes/T7/CodexBuild/BrowseRender-20261105`.
The two production files have 41 fewer net lines; no persistence schema changes.

Rollback is limited to this investigation's source/test/documentation diff.
The fix is committed and pushed on `main`; no physical-device or release
acceptance is claimed.

## High-confidence refinement fixes — 2026-11-05

User-authorized implementation following the repository-wide source review at
clean `40403c1`. This scope includes the small, high-confidence usability and
removal findings. The implementation is committed and pushed on `main`; no
publication or release-policy change is authorized by this implementation record.

| Slice | Acceptance and verification | Status |
| --- | --- | --- |
| Graded expiry | Wire conversion, retained graded variants, Price Check and collection binding reject elapsed current quotes; preserve legacy responses, historical evidence and new-sale recovery. Focused contract/quote-cache/pricing tests. | Implemented; affected 179-test selection passes |
| Sealed pagination | Search and set browsing advance by the provider limit, including empty filtered pages and cached continuation. Legacy cached products remain visible offline while incompatible cursors require refresh; fresh terminal pages retain their original freshness. | Implemented; all 11 sealed surface tests pass |
| Sealed setup | Missing credentials are reported for the requested game even when offline Lorcana is available; cached results remain usable. Search-state tests; HIG gate. | Implemented; affected selection passes |
| Quota preflight | Known daily/monthly/cooldown refusals precede pacing without spending quota or a pacing slot; final reservation stays atomic. Transport/ledger/cancellation tests. | Final 185-test contract/fallback recheck passes |
| Unused Browse history | Remove the unconsumed local history renderer/recorder/stamp request and obsolete diagnostic wiring; preserve current market charts, prices, portfolio history and existing files. Browse/history/portfolio tests and Release build. | Implemented; history/chart/portfolio checks and final Release build pass |

Rollback is limited to each slice's source/test diff. Baseline and final build
artifacts use the external T7 SSD. Baseline: 46 tests passed. All five new
regression methods failed against unchanged production code (23 assertions).
After the fixes, 179 affected methods pass with no failures/skips. This includes
expiry boundaries, history retention, new-sale recovery, cache isolation, empty
filtered pages, quota cancellation, interactive reserve and post-pacing quota
revalidation. Prior non-green full-suite evidence is not superseded here.
The direct-fallback regression separately reproduced both blocked waits before
its fix; all 54 fallback tests now pass. Its failed run required interruption
after tests finished because Xcode remained in diagnostic collection; the
assertions are retained in its log, without claiming a completed result bundle.
The cleanup retires tests solely for the removed recorder/chart factory, retains
chart scaling/range/scrubbing checks against provider history, and keeps the
provider-date parser used by bulk current pricing. Existing history files and
ownership/portfolio evidence are not deleted or migrated.
The cleanup selection passed 125/126 methods. One unchanged card-only render
test observed three requests instead of four. It failed twice in three isolated
current-tree runs and once in three runs of an isolated, unmodified `40403c1`
export. Its assertions and pagination implementation remain unchanged; this
pre-existing timing-sensitive check stays open rather than being weakened.
The first combined affected run subsequently passed **966 tests, one opt-in aged-store
benchmark skipped, zero failures** (967 total). Stored result-bundle metrics
agree with the console counts; all 966 passes have distinct method IDs. The run
includes all rendered-pagination cases, 29 selected graded/Price Check scanner
methods, current charts, cache upgrades, collection writes and portfolio replay.
Final quota fixtures additionally intercept HTTP at a synthetic host so a future
regression cannot contact a live provider. Their 185-test recheck passes.
The final cache refinement avoids refreshing a fresh legacy page without a
continuation, preserving its original timestamp. All 11 sealed surface tests,
including both migration paths, pass in the exact final affected run.
That final run executes **968 distinct methods: 966 passed, one opt-in benchmark
skipped, and the same pre-existing rendered-pagination assertion failed**.
`FinalAffected.xcresult` metrics agree with the console method records. The
earlier green combined run predates the terminal-cache refinement and fixture
hardening; it does not replace this non-green final result. The assertion, its
test body and the card-pagination implementation remain unchanged.
The exact final **arm64 Release simulator rebuild passed**
(`release-final-v2.log`, exit 0). An earlier universal Release build was
interrupted to finish cache compatibility and is not counted as a passing build.
The production diff removes 1,281 net lines without a persistence-schema change.
Final whitespace, project-file syntax and local documentation-link checks pass.
Artifacts are retained under `/Volumes/T7/CodexBuild/RefinementFixes-20261105`.

- [x] Implement the five scoped fixes and preserve stored data/current charts.
- [x] Reconcile final simulator test records, retain the baseline render failure,
  and complete the arm64 Release simulator build.

Source HIG gate: PASS; existing native empty-state copy/navigation and controls
are retained, with no added prompt or interaction. Rendered/device accessibility
acceptance is not claimed.
Centering-reference adjudication, published feed/public URLs and device profiles
remain evidence-dependent follow-ups, not automatic code fixes.

## Feed-cache fallback follow-up — 2026-10-31

Based on clean `main@17658c9`, following review of `21e6ec1`:

- [x] Reproduce loss of a still-valid saved snapshot after learning a newer
  feed build, including manual retry and the failure cooldown.
- [x] Return the original snapshot on refresh failure or cooldown while its
  validation remains under 24 hours old. Preserve quote/validation dates, failed
  request backoff, strict new-file validation and waiter cancellation.
- [x] Verify expiry during a request, lagging publication files, recovery and
  shared cancelled/non-cancelled waiters with recorded-response simulator tests.

No release gate or provider configuration changes were made. The source/test
fix is committed as `2b31f0d`; rollback is limited to its service/test diff.
Both new outage regressions failed against the committed service before the fix.
The post-fix feed suite passed **50 tests, zero failures/skips**, including all
five new regressions. The expanded feed/pricing/quote-cache selection passed
**171 tests, zero failures/skips**. The **Release simulator build passed**. The final feed
suite rerun also passed **50/50**, including the deterministic in-flight expiry
check. Diff whitespace and added local documentation links pass validation.
Earlier counts below describe the earlier candidate. The cache is never
restamped or rewritten on failure, and freshness is rechecked after the network
await. No live-provider, physical-device or distribution readiness is claimed.

## High-confidence refinement fixes — 2026-10-31

Scope: the five source-proven findings from the current review, based on clean
`main@36c2a64`. The owner authorized all high-confidence fixes, including the
small UI findings. The fixes are split into focused commits. Publication,
release-gate changes and speculative performance refactors remain out of scope.

- [x] Respect acquisition quantity in aggregated graded finish correction;
  verify split/merge, shared vendor quotes, earlier removed acquisitions,
  pricing, lineage, undo and transaction rollback.
- [x] End nil-artwork loading in Price Check and scan review; preserve existing
  artwork sizing and loading/error behavior.
- [x] Retry transient graded discovery in place; verify failure-to-success,
  incomplete search, terminal absence and overlapping-load protection.
- [x] Recover a daily feed publication rollover with one bounded marker refresh;
  verify ordinary/manual retry, torn responses and cache/coalescing behavior.
- [x] Restore the resolved-identity pricing diagnostic without weakening more
  specific reasons; remove the confirmed unused graded-picker summary state.

Baseline: repository status and diff were clean; prior review package tests had
145 passes and one opt-in live-network skip. The focused iOS baseline passed
168/168 tests. The four new correction/rollover/diagnostic regressions then
failed against unchanged production logic, confirming the reviewed defects.
Verification uses external-SSD DerivedData and recorded provider responses.
The first post-fix selection passed 175 tests; its graded-picker test could not
write its synthetic key because the unsigned simulator host lacks Keychain
entitlements (`-34018`). The signed rerun passed all three checks, including a
credential round trip; this was a test-host configuration failure. The broader
selection then passed 757 tests with one opt-in benchmark skipped. A Release
simulator build passed. A further correction-boundary regression reproduced
shared vendor price/history migration affecting another slab; its scoped ledger
fix and historical-acquisition regression passed the 273-test correction,
scanner/history and refresh-race selection. The final combined signed-simulator
selection passed **764 tests, zero failures, one opt-in benchmark skipped**.
The final 45-test feed suite passed, including fresh-cache manual retry,
known-build invalidation of cached sets and unchanged-build quote-date retention.
The exact final **Release simulator rebuild passed**, with no new compiler
warning messages relative to the earlier Release build. `git diff --check`
and the added local documentation links pass validation. All five code findings
are implemented; the owner-controlled and measurement gates below remain open.

The correction reuses the existing split/ledger transaction and removes the
duplicated graded branches. Partial corrections preserve other quantities;
bound whole-row corrections preserve shared vendor instruments and historical
events, moving only the selected claims with correction legs. Compatible
quotes retain their original retrieval date; incompatible quotes are not
borrowed. The detail screen explains which copies change and confirms a split.

UI gate: **PASS** for these scoped changes: native Retry and unavailable states,
existing navigation, no added confirmation prompt, and unchanged artwork sizing.
Hosted Price Check/scan review renders exposed the unavailable text at standard
and accessibility text sizes. Physical-device VoiceOver and provider acceptance
are not claimed. No dependency, persistence-schema or release-policy change.
Each fix stays local to its existing path; rollback is its focused source/test
diff. Privacy/support destinations require published owner-controlled URLs;
Activity/CSV performance changes require measurements and remain outside scope.
Commit references are recorded in the 2026-10-31 entry in `progress.md`.

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

## Remediation snapshot at `810954e` — 2026-09-22

This remediation was recorded in the working tree based on `main@810954e` and
was subsequently committed in the repository history through
`main@9759050`. N1–N3, N5–N7, and F1–F4 are implemented. N4's
Settings copy is truthful, but its Release URLs remain open until the owner
provides the actual deployed destinations. The affected simulator regression
selection passed 99 tests with 1 skip; a separate delete-actor integration test
passed 1/1. The skipped file-protection assertion is a Simulator limitation,
not a device result. An intermediate broader run exposed and led to correction
of the synthetic-CSV canonicalization regression; it also reported an unrelated
existing Cardmarket expectation in `CatalogNormalizationTests`. No full-suite,
physical-device, CloudKit, archive, TestFlight, provider, or release
verification is claimed for the current `9759050` checkout. The counts below
remain evidence for the earlier `810954e` working-tree snapshot only.

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
