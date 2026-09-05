# App Review Fix Plan

## Progress

- [x] Fix tracker observation feed-forward and terminal request lifecycle — High confidence / High severity — verified
- [x] Propagate correction success/failure to the review sheet — High confidence / Significant production issue — verified
- [x] Make `Same card` the visually prominent duplicate action — High confidence / Significant UX issue — verified

All three supplied findings are implemented and verified on `fix/app-review-preflight`.

## New attached review slice

- [x] Make the held-card “Already added” offer actionable for stacked duplicates — High confidence / explicit user-authorized quantity path — implemented

Evidence: the supplied specification identifies the existing eight-match latch-hold signal as reliable while Vision spatial exit can be ambiguous for aligned identical cards. Acceptance requires a one-shot, identity-bound authorization that cannot be created by OCR, weak absence, timeout, tracker loss, or a different card.

Rollback: revert the held-offer/authorization commit(s); the existing spatial-proof duplicate flow remains the fallback.

## Baseline verification

The focused baseline passed 28 `CardLatchTests`. The full suite had three unrelated simulator Keychain failures in `ProductIdentityTests`; a later build was blocked by unavailable CoreSimulator runtimes during asset processing.

## Acceptance criteria

- Every successful seed and tracking observation becomes the request's next `inputObservation`.
- Terminal tracker paths mark the request as the last frame before release; continuity loss remains non-authorizing.
- A failed correction leaves the review sheet's local selection unchanged and exposes a concise failure note.
- `Same card` is first and prominent; `Add another` remains at least 44 points and secondary.
- Focused tests cover the tracker feed-forward assignment and existing collection safety regression remains green.
- The held-card fallback is nonblocking, Collection-only, one-shot per held presentation, and dismissed by a different card, spatial proof, undo/delete, purpose/lifecycle invalidation, or session end.
- A held-repeat authorization is verified on the Vision queue, expires before encounter consumption, carries through resolution, and bypasses duplicate interception only after matching committed history and canonical identity validation.

## Verification notes

### Tracker slice — `6a53aa6`

- Status: Done
- Verification: `xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath .codex_build_test_device -only-testing:TradingCardScannerTests/CardLatchTests` — 29 tests passed.
- Coverage includes latest `inputObservation` assignment, terminal tracker behavior, and preservation of lost lineage across repeated invalidation.

### Correction slice — `c6d08b5`

- Status: Done
- Verification: `xcodebuild test -quiet -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath .codex_build_test_device -only-testing:TradingCardScannerTests/BrowseCollectionTests/testVariantCorrectionWithMissingSourceDoesNotCreateAnUnbalancedPosition` — passed.
- The target compiled `ScanReviewSheet`, `ScannerViewModel`, and `CollectionStore`; only pre-existing Swift 6 warnings were emitted.

### Duplicate-action hierarchy — `02ce8d1`

- Status: Done
- Verification: source inspection confirms `Same card` remains first, uses `.borderedProminent`, and retains a 48-point minimum height; `Add another` uses `.bordered` with the same minimum height and remains secondary in VoiceOver sort order. The focused `CardLatchTests` command also exited successfully after this UI-only change.

### Final verification

- `xcodebuild test -quiet -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -derivedDataPath .codex_build_test_device` — 506 passed, 0 failed, 0 skipped.
- `git diff --check` — clean for the working-tree changes; each fix commit also passed its staged diff check.

### Held-card fallback slice

- Status: Implemented
- `xcodebuild build -quiet -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/trading-card-scanner-held-repeat-no-explicit SWIFT_ENABLE_EXPLICIT_MODULES=NO` — passed; only pre-existing Swift 6 warnings were emitted.
- `xcodebuild build-for-testing -quiet -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/trading-card-scanner-held-repeat-tests SWIFT_ENABLE_EXPLICIT_MODULES=NO` — an initial attempt completed without source diagnostics; a later rerun was blocked before test execution by the local SwiftData macro server returning a malformed response.
- Added focused coverage for one-shot latch authorization, non-spatial semantics, identity mismatch, authorized reseeding after tracker loss, fake-clock expiry, and request carry-through.
- Runtime XCTest execution after this slice was not available because CoreSimulatorService was disconnected and no simulator device set could be discovered. The previously recorded 506-test baseline remains unchanged; on-device validation is still required for stacked-card camera behavior.

## Remaining code-sweep fixes

This slice follows the later validated code-sweep report. The working tree also
contains newer user-owned browse, portfolio, and card-movement changes; those
are preserved and are not being reset or folded into unrelated fixes.

- [x] Repair the Browse price-sort request lifecycle and completion coverage.
- [x] Make effective price invalidation the shared production source of truth.
- [x] Make portfolio close reads fail closed, matching the repaired write path.
- [x] Make portfolio bootstrap fail closed when inventory or collection rows cannot be read.
- [x] Make scanner review deletion and centering capture lifecycle-safe.
- [x] Cancel artwork work with the detail view and reject non-sealed fallback data.
- [x] Repair retry/cancellation/single-flight defensive paths and concrete Swift 6 warnings.

Baseline for this slice: the user reports 561 tests with four repeated
network-dependent failures. The edited sources pass parser validation and
`git diff --check`; the most recent local `xcodebuild` attempt was blocked
before compilation because CoreSimulator had no discoverable runtime.

### Final code-sweep verification

- All production Swift sources and tests pass `swiftc -frontend -parse`.
- `git diff --check` is clean.
- Generic iOS app build and test bundle build both pass with explicit modules
  disabled; the only emitted messages are Xcode's signed XCTest bundle-strip
  notices.
- Focused agent-run tests covered Browse/catalog lifecycle, portfolio
  reconciliation/ledger behavior, camera/artwork/sealed paths, and shared
  JustTCG cancellation/lane behavior.
- The user-reported full suite remains 561 tests with four repeated
  network-dependent failures; no screenshot loop was run.
- Portfolio bootstrap now propagates inventory/collection fetch failures rather
  than treating either store as empty and writing a false initial baseline.

## Audit pass 1 remediation — N1 through N7

The follow-up remediation plan was applied on `codex/unrelated-fixes`.

- [x] N1 — background price refresh runs the local migration gate without waiting for deferred network enrichment, so a cold background process can still price its bounded target set.
- [x] N2 — Pokémon checklist refresh state records attempts separately from successful crawls, backs off failed attempts, persists progress after failures, and retries recorded failures after the resumable cursor.
- [x] N3 — checklist skip decisions require a decodable resource; unreadable checklist IDs are tracked and cleared when resources are discarded or republished, allowing corruption to self-heal.
- [x] N4 — CSV metadata re-imports no longer silently rewrite a certified row's quantity; existing quantity defects remain available to ledger diagnostics.
- [x] N5 — `Money` equality and hashing remain consistent with `Comparable`; invalid amounts are excluded from CSV output and portfolio geometry ratios.
- [x] N6 — observation backfill no longer uses a blocking process-local mutex, and the computation actor reuses its bulk-fetched observations instead of fetching the log twice.
- [x] N7 — per-set checklist values use bounded LRU caches, and Browse no longer keeps a second Pokémon checklist cache.

Focused regression coverage was added for certified CSV idempotency and quantity preservation, supplied-observation backfill reuse, checklist corruption recovery, failed-refresh backoff/cursor progress, and `Money` ordering identity.

Verification on 2026-09-04:

- `xcodebuild build-for-testing` — succeeded with normal local simulator signing and `SWIFT_ENABLE_EXPLICIT_MODULES=NO`.
- Focused remediation tests — 8 passed, 0 failed.
- Full `xcodebuild test-without-building` suite — 755 passed, 0 failed, 0 skipped.
- `git diff --check` — clean.

## Follow-up against updated review

### Scanner foreground recovery

- [x] After an active-scene transition starts the visible camera session,
  immediately call `resumeRecognitionIfPossible()` so recognition does not
  remain paused after `invalidatePendingScan()` paused it in the inactive
  branch.
- [x] Keep the existing eligibility, Price Check, pending-question, tab, and
  presentation guards in the resume helper.

Status: implemented in `38ca38a`. Generic iOS app and test-target builds passed;
Control Center, app-switching, permission-prompt, interruption, and physical
camera verification remain deferred because CoreSimulatorService has no
discoverable runtime and no physical device is attached.

The updated performance findings remain intentionally unstarted. They are
measure-first work, not high-confidence correctness fixes: no changes were
made to collection projection memoization, migration gates, fallback indexing,
refresh progress cadence, image caching, activity-log bulk indexing, or refresh
context ownership.

## Review remediation implementation — remaining planned slices

The remaining roadmap slices are implemented in `29ca750`.

### Slice 5 — synced price evidence and duplicate records

- [x] Reconcile changed and explicitly invalidated synced `PriceRecord` rows
  into the device-local observation log at the time this device learns them.
- [x] Preserve local knowledge time rather than copying another device's fetch
  time, and reject delayed remote evidence that is older than the newest local
  knowledge.
- [x] Select duplicate price rows deterministically by knowledge watermark,
  invalidation state, and stable provenance; never by price magnitude.
- [x] Repair redundant rows on the next write/refresh and report the repair
  only after the surrounding save succeeds.
- [x] Add changed-price, out-of-order, invalidation, duplicate, and
  invalidation-precedence regressions.

Status: implemented in `29ca750`. The scalar ledger, bulk replay, collection
display, and portfolio computation now share the same authoritative evidence
rules. Two-device CloudKit convergence remains unverified because the available
environment has no working simulator runtime or second device.

### Slice 7 — scoped browse searches

- [x] Pass the visible Cards/Sealed/All scope into search scheduling.
- [x] Restrict sealed requests to the selected game and defer omitted lanes
  until the user selects them.
- [x] Add transport-count regressions for Cards-only and single-game searches.

Status: implemented in `29ca750`. Cached sealed results remain available
offline; only missing or stale requested lanes with credentials reach the
vendor.

### Slice 9 — centering export freshness

- [x] Key export preparation by image revision, measurement, and rotation.
- [x] Coalesce guide changes before preparing the shareable file, and clear the
  prior URL while a newer export is pending.
- [x] Preserve rotation in the rendered export and filename.

Status: implemented in `29ca750`. The stale-export path is covered in source
and filename tests. The PNG render/encode/write remains synchronous on the
main actor; no runtime hitch measurement was available, so moving it to a
background renderer was intentionally deferred rather than guessed.

### Slice 10 — CSV import progress and selective recovery

- [x] Publish row progress, disable a second import from Settings while one is
  active, and invalidate queued progress callbacks on completion.
- [x] Preserve row-level transaction isolation and expose normalized failed
  entries as a retry-only CSV.
- [x] Distinguish partial completion from complete success in the completion
  message.

Status: implemented in `29ca750`. Persistence failures and parser exclusions
remain separate in the import result; the partial-completion action prioritizes
exporting persistence-failed rows for safe retry.

### Slice 11 — device-local custom artwork ownership

- [x] Add a device-local `LocalArtworkOverride` mapping keyed by collection key.
- [x] Migrate legacy filename values at launch, then clear the legacy bridge for
  new writes so another device cannot overwrite a local filename.
- [x] Update collection, portfolio, diagnostics, and missing-artwork export
  paths to read the local mapping.

Status: implemented in `29ca750`. Intentional compatibility deviation: the
legacy `CollectedCard.userArtworkFilename` property remains in the model schema
as a temporary migration bridge rather than being removed in one destructive
schema change. Launch migration copies it locally and clears it; all new
artwork writes use the local mapping. Full image synchronization was not added,
consistent with the plan's product boundary.

### Slice 12 — truthful storage/sync status

- [x] Report the actual local-only versus CloudKit-backed container mode chosen
  at launch.
- [x] Correct Settings wording so Sign in with Apple is described as the cloud
  configuration gate, while the private database follows the device's iCloud
  account.
- [x] Keep restart requirements explicit after account changes.

Status: implemented in `29ca750`. CloudKit account behavior and fallback paths
still require device/account checks in an environment with iCloud provisioning.

### Slice 13 — Magic set-page cache expiry

- [x] Apply a 24-hour age policy to disk-backed Magic card pages.
- [x] Revalidate stale pages, retain stale content when the provider is
  unreachable, and leave the old timestamp in place so a later visit retries.

Status: implemented in `29ca750`. The existing cache and offline behavior were
retained; no new cache layer was introduced.

### Cleanup — reference-only portfolio calculation

- [x] Remove the unused legacy calculation walk from the production target.
- [x] Move it into `PortfolioCloseReference.swift` in the test target so the
  independent reference oracle and existing tests remain available.

Status: implemented in `29ca750`. Production keeps only the attribution result
type used by UI/history models.

### Final verification for these slices

- `xcodebuild build` for `generic/platform=iOS` — passed after `29ca750`.
- `xcodebuild build-for-testing` for `generic/platform=iOS` — passed after
  `29ca750`.
- `git diff --check` — clean.
- Simulator XCTest execution — not available: CoreSimulatorService reports no
  discoverable runtime.
- Not claimed: physical-camera lifecycle checks, two-device CloudKit
  convergence, provider-network behavior, centering frame-time measurements,
  large-import scaling, or activity-log/collection performance measurements.

## Review against `ef689ce` — planned remediation

The following slices track the supplied static review in its stated roadmap
order. Runtime claims remain limited to the verification recorded for each
slice; physical-camera, two-device CloudKit, and provider behavior require
their corresponding environments.

### Baseline

- Branch retained as `codex/review-fixes` to preserve the reviewed commit and
  existing user-owned history; this differs from the generic
  `fix/app-review-preflight` branch name in the safe-fixer template.
- `xcodebuild build-for-testing -quiet -project TradingCardScanner.xcodeproj
  -scheme TradingCardScanner -destination 'generic/platform=iOS Simulator'
  -derivedDataPath /private/tmp/trading-card-scanner-baseline
  SWIFT_ENABLE_EXPLICIT_MODULES=NO` — passed.
- Simulator test execution is currently unavailable: CoreSimulatorService
  reports no discoverable runtime.

### Slice 1 — scanner lifecycle eligibility

- [x] Add explicit scene-active, scanner-visible, presentation-blocked, and
  camera-interruption eligibility; use it for all recognition resumes.
- [x] Restart the capture session when the visible scanner returns to an active
  scene, without requiring `interruptionEndedNotification`.
- [x] Add pure eligibility regression coverage.

Status: implemented in `320050c`, awaiting simulator execution. Generic
build-for-testing passes; source changes are limited to `ScannerViewModel`,
`ScannerView`, and the existing `CardLatchTests` file. Rollback is the
slice-local commit.

### Slice 2 — catalog price freshness

- [x] Preserve catalog resolution time through session and disk identity-cache
  hits.
- [x] Carry that time through scanner finish/print-run choices, collection
  commits, corrections, and Price Check.
- [x] Compare a catalog quote with newer local evidence before selecting it;
  stale selected evidence keeps the existing auto-refresh path enabled.
- [x] Add regressions for session timestamp preservation and a cached `$10`
  catalog quote versus a newer local `$20` quote.

Status: implemented in `822135a`, generic build-for-testing passes. Simulator test execution
is unavailable because CoreSimulatorService has no discoverable runtime.

### Slice 3 — currency propagation

- [x] Carry the provider currency into `CardMarketPrice`.
- [x] Format catalog detail and scan review values using the quote currency.
- [x] Exclude non-USD master-set quotes from USD browse sorting.
- [x] Add Cardmarket display-currency regression coverage.

Status: implemented in `1c7fa64`, generic build-for-testing passes. No exchange-rate behavior
was introduced.

### Slice 4 — canonical invalidation precedence

- [x] Make scalar ledger key selection preserve an explicitly invalidated
  canonical key.
- [x] Carry the same authoritative-key marker into bulk portfolio replay.
- [x] Verify collection read, scalar ledger, and bulk valuation precedence
  against a priced legacy alias.

Status: implemented in `10de4f4`, generic build-for-testing passes.

### Slice 6 — persistence outcomes

- [x] Make `PriceStore` write, failure-stamp, and unsupported-provider paths
  return whether their mutation was accepted; keep save rollback outcomes
  observable.
- [x] Count catalog, fallback, and graded prices only after a successful save;
  surface partial persistence failure in the refresh summary and Portfolio UI.
- [x] Make JustTCG batch application/checkpoint callbacks return persistence
  outcomes and prevent a failed batch from advancing the delta checkpoint.
- [x] Add regression coverage for a failed JustTCG checkpoint.

Status: implemented in `0548cf1`. Generic device build completed after
the simulator service recovered; simulator XCTest execution remains unverified.

## Audit pass 1 remaining remediation — L1 through L3

The remaining findings from `audit_pass1_remaining_plan.md` are implemented on
`codex/unrelated-fixes`.

- [x] L1 — checklist loading distinguishes a deterministic decode failure from
  a transient file-read failure. Only undecodable resources enter the
  in-process negative cache; transient reads are retried, while corrupt
  resources still remain eligible for the existing republish/healing path.
- [x] L2 — CSV import never changes the quantity of a non-aggregating row,
  including rows carrying an empty certificate string. Ledger and activity
  records are emitted only when a real quantity delta is applied.
- [x] L3 — observation backfill treats a failed observation-table read as an
  unreadable baseline rather than an empty log, so it cannot seed duplicate
  observations. The computation actor skips backfill after that failed bulk
  read and lets the snapshot builder publish its unreadable-store defect.

Regression coverage includes the transient checklist retry, corrupt checklist
healing, empty-certificate quantity preservation, distinct certified CSV
round-trips, no-seed observation backfill failure, migration/refresh gate
directionality, background migration bypass, and marketplace identity
persistence for illustrated rows.

Verification on 2026-09-04:

- `xcodebuild build-for-testing` — succeeded with normal simulator signing and
  `SWIFT_ENABLE_EXPLICIT_MODULES=NO`.
- Focused remaining-plan regressions — 7 passed, 0 failed, 0 skipped.
- Full `xcodebuild test-without-building` suite — 765 passed, 0 failed, 0
  skipped.
- `git diff --check` — clean.
