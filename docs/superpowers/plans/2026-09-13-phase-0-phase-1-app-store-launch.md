# CardScanner Phase 0 and App Store-Critical Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Freeze the corrected Collection Integrity retention experiment, eliminate launch-critical silent-integrity risks, and certify one free iPhone/iPad 1.0 binary whose local collection remains continuous and whose structured records demonstrably converge through production CloudKit.

**Architecture:** Preserve the current scanner, collection, pricing, portfolio, import/export, graded, sealed, and device-local artwork architecture. Replace the Sign in with Apple storage proxy with a storage bootstrap boundary that evaluates the real system iCloud account before the persistent store opens, assigns one stable local collection identity, and fails closed on unproven account/store transitions. Keep the five existing structured models in the CloudKit-backed SwiftData configuration and the five local-knowledge/artwork models in a separate device-local configuration; do not add Place, Verify, Reconcile, Collection Health, StoreKit, or Grade/Sell in this release.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, CloudKit private database, CryptoKit, Security/Keychain, XCTest, Xcode/xcodebuild, physical iPhone and iPad, TestFlight, Markdown release evidence.

---

## 0. Authority, scope, and superseded decisions

This is the executable implementation plan for:

- **Phase 0 — Freeze the experiment**, completely; and
- only the parts of **Phase 1 — Make the existing product worthy of a trust promise** that are required for the first public App Store release.

It reconciles:

1. [`docs/vision/CardScanner Collection Integrity Strategy — Start-to-Finish Implementation Plan.md`](../../vision/CardScanner%20Collection%20Integrity%20Strategy%20%E2%80%94%20Start-to-Finish%20Implementation%20Plan.md);
2. [`docs/vision/collection-integrity-codebase-gap-analysis.md`](../../vision/collection-integrity-codebase-gap-analysis.md);
3. [`docs/release/card-scanner-1.0-go-no-go-framework.md`](../../release/card-scanner-1.0-go-no-go-framework.md);
4. the live source and tests at `d647a794edc349be52fb6c643649ce26de2c834a`; and
5. the product-owner corrections recorded on September 13, 2026.

When those sources disagree, this plan controls this release. In particular, it supersedes the following older decisions:

- Collection Integrity is **not** the first monetization experiment.
- The public 1.0 is free and contains no StoreKit product, subscription, paywall, entitlement, or purchase/restore flow.
- Collection Integrity is currently a retention and defensibility hypothesis. Grade/Sell/economic workflows will receive their own separately versioned monetization experiment later.
- The Phase 0 scorecard contains no `$30–$40/year` willingness-to-pay criterion.
- Place, Verify, Reconcile, Collection Health, migration adapters for named incumbent apps, binder-page recognition, and all related monetization are outside the 1.0 binary.

This plan does **not** authorize broad refactors. A change belongs in this release only when it closes a named launch gate, makes that gate observable, or is required to build/sign/submit the exact release binary.

## 1. Repository-grounded starting point

### 1.1 Current checkout

- Repository: `/Users/seankeller/Documents/TradingCardScannerMVP_fixed_v4`
- Branch when this plan was written: `scan-hardening-and-release`
- HEAD when this plan was written: `d647a794edc349be52fb6c643649ce26de2c834a`
- App target: `TradingCardScanner`
- Test target: `TradingCardScannerTests`
- Minimum OS: iOS/iPadOS 17.0
- Device families: iPhone and iPad (`TARGETED_DEVICE_FAMILY = "1,2"`)
- Current marketing/build version: `1.0 (1)`
- Current placeholder bundle ID: `com.example.TradingCardScanner`
- Approved production bundle ID: `com.seankeller.CardScanner`
- Intended CloudKit container: `iCloud.com.seankeller.CardScanner`

### 1.2 User-owned working-tree changes that must be preserved

At plan time, these files were already modified:

```text
TradingCardScanner/Services/PortfolioEngine.swift
TradingCardScanner/Views/CollectionCardDetailView.swift
TradingCardScanner/Views/PortfolioDebugFixtures.swift
TradingCardScannerTests/CardFinishRenderPlanTests.swift
TradingCardScannerTests/OpusImplementationPlanTests.swift
docs/CardScanner-Website-Implementation-Spec.md (untracked; appeared during plan preparation)
docs/vision/ (untracked)
```

The `PortfolioEngine.swift` change corrects a portfolio day to the half-open interval `[dayStart, nextDayStart)` and adds a boundary regression test. The artwork changes make the performance fixture reuse a safe deterministic filename. These are pre-existing user changes, not work created by this plan. Do not reset, overwrite, or silently absorb them into an unrelated commit. Before execution, either commit them as their own reviewed baseline or create the implementation worktree from a commit that intentionally contains them.

### 1.3 What the code already provides

The following are real foundations and should be preserved:

- `TradingCardScannerApp` splits five synced models from five device-local models.
- `CollectedCard`, `PriceRecord`, and `ProductIdentity` use application-level identity because CloudKit does not support SwiftData uniqueness constraints.
- `CollectionActivity` and `InventoryEvent` provide durable mutation and economic history.
- `CollectionStore` centralizes collection writes and rollback behavior.
- CSV import/export already preserves a broad set of raw, graded, sealed, variant, print-run, treatment, provider, and quantity fields.
- `PortfolioPriceEligibility` prevents non-USD amounts from silently entering USD totals.
- scanner purposes distinguish Collection from Price Check.
- the trust-hardening suite is broad; the latest recorded clean run in `progress.md` predates the current dirty tree and therefore is evidence of the prior baseline only.

### 1.4 Current launch-critical gaps

The current code still has these release gaps:

1. `TradingCardScannerApp.makeContainer()` chooses `.automatic` CloudKit only when `AppleAccountCredentials.isSignedIn`; Sign in with Apple is not the account CloudKit uses.
2. A CloudKit container-construction failure falls back to a `.none` configuration without proving both configurations open the same local store identity.
3. An iCloud availability or account change can therefore create, reveal, strand, or upload a different set of local records unless continuity is made explicit and tested.
4. `TradingCardScanner.entitlements` declares Sign in with Apple even though 1.0 needs only the system iCloud account.
5. `UIBackgroundModes` omits `remote-notification`, which Apple documents as part of SwiftData CloudKit synchronization.
6. the bundle ID and inferred iCloud container are placeholders.
7. the production CloudKit schema and production two-device convergence have not been proven.
8. the synced model schema has not been signed off in a named CloudKit compatibility audit.
9. the privacy manifest declares only UserDefaults access even though `BrowseCatalog.swift` and `BrowseView.swift` read file modification timestamps.
10. Settings has no in-app privacy-policy or support link.
11. the release framework still describes a monetized 1.0 and treats purchase/restore as a hard gate, while no StoreKit code exists and the approved 1.0 is free.
12. the normal/adversarial scanner evidence, physical iPhone/iPad matrix, exact archive inspection, and exact TestFlight-binary pass remain incomplete.
13. there is no durable release evidence document for this exact candidate.
14. the new website specification defines `/contact` and explicitly freezes exactly four routes, while the approved App Store launch contract requires a canonical `/support` URL.
15. `PortfolioEpoch.initialSyncGrace` uses a 120-second elapsed-time heuristic when collection rows arrive before ledger rows. That may remain a conservative portfolio-baseline guard, but elapsed time is not proof that SwiftData has finished importing a cloud collection and must never authorize an authoritative empty/restored state.
16. production code has several legitimate quantity-changing paths beyond the ordinary scanner flow—including CSV application, row merge/rekey, graded/sealed operations, correction flows, restore/undo, and Magic treatment migration—but there is no named audit proving that every path leaves a complete, durable, idempotent `InventoryEvent` history from which aggregate quantity can be rebuilt.

### 1.5 Confirmed model fact: condition

`CollectedCard` does **not** currently persist a raw-card condition field. The word “condition” appears in provider SKU/listing data and display copy, and `CollectedCard.tcgplayerSKUID` is explicitly not treated as owned-copy condition. Phase 1 must document condition as absent from 1.0 durable collection semantics. Do not accidentally add it, sync it, export it, or claim it during this launch slice.

## 2. Locked product and engineering decisions

### 2.1 Phase 0 retention hypothesis

Freeze this exact hypothesis:

> Serious collectors who establish a canonical collection and use Place → Verify → Reconcile will voluntarily return to CardScanner after their physical collection changes, making the integrity system a meaningful retention advantage.

The critical future behavioral event is:

```text
repeat_verify_after_change
```

No willingness-to-pay threshold is part of this experiment. No monetization conclusion may be inferred from first-verify completion, compliments, App Store downloads, or general engagement.

### 2.2 Public 1.0 scope

Included:

- unlimited ordinary scanning;
- Price Check;
- current collection management;
- current generic CSV import and basic export;
- current pricing and portfolio features;
- graded and sealed behavior already present;
- system iCloud synchronization for structured collection records;
- device-local custom artwork with explicit disclosure;
- privacy/support links;
- diagnostics and release evidence necessary to support the trust promise.

Excluded:

- physical containers and placements;
- Scan-to-Place;
- Verify and Reconcile;
- Collection Health;
- source-aware Collectr/TCGplayer/Dex/ManaBox migration experiences;
- StoreKit, Pro, paywalls, entitlements, trials, and subscriptions;
- Grade/Sell monetization;
- binder-page recognition;
- QR workflows, insurance reports, shared households, seller tools, and new TCG breadth.

### 2.3 Synced versus device-local data

The structured CloudKit configuration remains limited to:

```swift
CollectedCard.self
PriceRecord.self
ProductIdentity.self
CollectionActivity.self
InventoryEvent.self
```

The device-local configuration remains limited to:

```swift
ReferenceQuote.self
PriceObservation.self
PriceCheckDay.self
PortfolioDailyClose.self
LocalArtworkOverride.self
```

Custom artwork remains device-local. Settings must display this exact disclosure near sync status:

> Custom artwork is stored on this device and is not currently synced with iCloud.

Do not move `LocalArtworkOverride` or image files into CloudKit in this release.

### 2.4 Canonical-store invariant

This is a hard launch invariant:

> A change in iCloud availability must never cause CardScanner to open an empty or different collection, upload the existing collection to a different iCloud account without explicit confirmation, or strand records created while iCloud was unavailable. One continuous local collection identity must survive every supported transition. If SwiftData requires separate stores, the transition must be an explicit, idempotent, tested migration whose source remains recoverable until destination verification succeeds.

“The container opened” is not proof of this invariant. Proof requires stable store identity plus pre/post record digests.

### 2.5 iCloud account-switch policy

The approved policy is **Suspend and confirm**:

1. detect the real system iCloud account before opening a CloudKit-backed collection store;
2. if the installation is genuinely fresh and has no local user data, an available account attaches automatically: adopt its anchor when one exists, or claim an anchor for the newly created empty collection when one does not;
3. if it is the same account previously attached to this local collection, continue;
4. if no account is available, keep the canonical local collection intact and use only a transition path proven by Task 4;
5. if an existing nonempty local collection is unattached or a different account appears, do not upload or merge automatically;
6. preserve the existing local collection and suspend cloud attachment;
7. require explicit confirmation before attaching/uploading that existing collection to the newly encountered account;
8. if the new account already has a different `storeID`, refuse an automatic merge in 1.0 and direct the user to export/support;
9. transient statuses (`couldNotDetermine` and `temporarilyUnavailable`) never authorize deletion, store replacement, a new identity, or an account reattachment.

“Fresh” is not inferred from the absence of fetched SwiftData rows. It means there is no pre-existing structured-store file or manifest, no locally committed user-data evidence, and restoration readiness has established the remote account state. An empty fetch while a cloud import may still be in flight is never a fresh-install signal.

Because SwiftData automatic mirroring does not expose a documented live “pause sync” switch, the exact safe local-only transition is a proof obligation. Task 4 must establish it before Tasks 6–8 are accepted. If neither same-file reconfiguration nor an explicit verified migration can satisfy this policy, iCloud is a NO-GO for 1.0; do not weaken the invariant in code.

### 2.6 Storage architecture selection order

Do not begin by assuming CardScanner needs to alternate one store between `.none` and CloudKit-backed configurations. SwiftData uses `NSPersistentCloudKitContainer`, whose intended architecture is a local persistent store mirrored asynchronously to CloudKit. Task 4 must therefore test candidates in this order:

1. **Path 0 — one always-CloudKit-configured local replica.** Keep one explicit structured-store URL and one explicit private CloudKit configuration through no-account, account-available, offline, reconnect, and account-change conditions. If it remains locally writable/durable without an account and satisfies the suspend-and-confirm policy before any changed-account upload can occur, select it and delete the `.none`↔CloudKit transition/migration design.
2. **Path A — same-file reconfiguration.** Only if Path 0 fails, prove that the same explicit store URL can be safely reopened under `.none` and CloudKit-backed configurations without changing identity or content.
3. **Path B — explicit verified migration.** Only if Paths 0 and A fail, use distinct source/destination URLs and an atomic, resumable copy/validate/commit protocol.

Architecture is selected by evidence, not by implementation convenience. A Path 0 success removes transition machinery; it does not remove account fingerprinting, remote-anchor conflict protection, restoration-readiness proof, digest comparison, or the rule against uploading an existing local collection to a newly encountered account without confirmation.

### 2.7 Truthful cloud-restoration readiness

Opening a CloudKit-backed `ModelContainer` proves only that the local persistent store opened. It does not prove that an asynchronous remote import is complete. The app must distinguish these states:

```swift
enum CloudRestorationReadiness: Equatable, Sendable {
    case notApplicable
    case checkingRemoteCollection
    case importingRemoteCollection
    case readyEmpty
    case readyPopulated
    case failed(category: String)
}
```

Only affirmative evidence may produce `readyEmpty` or `readyPopulated`. Task 4 must first test whether `NSPersistentCloudKitContainer.eventChangedNotification` and its setup/import events are reliably observable for the exact SwiftData-created store on supported iOS/iPadOS versions. A successful import event is potentially useful evidence, but is not accepted until the spike proves store correlation, cold-install behavior, empty-zone behavior, error reporting, relaunch behavior, and ordering relative to SwiftData fetch visibility.

If those events are unavailable or insufficient, the implementation must use another explicitly proven handshake, such as a remote anchor/generation marker whose corresponding synced marker is observed locally. It must not invent a timeout. Until affirmative readiness exists, the UI remains in an honest “Restoring collection from iCloud…” state, collection-empty affordances are withheld, background normalization/baselining is fenced, and zero fetched rows are treated as unknown rather than empty.

The hard readiness gate applies whenever the local structured store is new/replaced, has adopted a remote anchor it has never completed restoring, or lost the local proof associated with that anchor. A previously proven local replica may display its nonempty last-known collection while background sync continues, provided the UI does not claim it is fully current. A zero-row local replica remains non-authoritative until the selected mechanism proves the remote state for that launch or proves an unchanged remote generation. Any persisted readiness checkpoint must be scoped to the exact `storeID`, account fingerprint, store-file identity, and mechanism version, written only after affirmative proof, and invalidated by reinstall/new store, account/anchor change, failed migration, corrupt manifest, or a changed readiness protocol.

The existing `PortfolioEpoch.initialSyncGrace = 120` may not be used as cloud-restoration readiness. If retained, it is only a conservative legacy-ledger deferral after storage readiness has independently been established; it cannot transition startup UI to ready, authorize a new empty collection, or prove all remote `InventoryEvent` rows arrived.

## 3. Phase 0 metric definitions

These definitions are frozen now so a later implementation cannot optimize the names instead of measuring the behavior.

### 3.1 Cohort

- Target: approximately 15 deliberately recruited serious collectors.
- Inclusion: owns and actively changes multiple physical storage locations or a collection large enough that location/identity drift is a real problem.
- Exclusion from the primary scorecard: developer accounts, synthetic QA collections, scripted test data, and casual users who never attempt a real physical workflow.
- Participant identifier: random study ID only. Do not store name, email, card identities, certification numbers, or physical-location names in the scorecard.

### 3.2 Event semantics

| Event | Frozen meaning |
| --- | --- |
| `catalog_established` | Participant has imported or cataloged a real collection segment they regard as meaningful enough to organize. |
| `meaningful_physical_location_established` | At least 18 distinct owned units are placed into one real named container, or a real smaller container is fully placed. Repeated movement of one item does not count. |
| `first_verify_started` | First non-synthetic verification session starts against at least nine expected positions or the full contents of a smaller real container. |
| `first_verify_completed` | Every expected position in that session ends matched, explicitly empty/missing, discrepant, or deliberately unresolved; abandoning a partially scanned page does not count. |
| `genuine_discrepancy_discovered` | Verify surfaces a mismatch that the participant confirms reflects actual disagreement or meaningful uncertainty. Seeded demonstrations and known QA fixtures do not count. |
| `genuine_discrepancy_reconciled` | The participant completes an explicit reconciliation action for a genuine discrepancy. Silent automatic repair never counts. |
| `qualifying_collection_change` | After a completed Verify, ownership, placement, or identity materially changes outside that verification’s reconciliation actions. |
| `repeat_verify_after_change` | The participant voluntarily completes another meaningful Verify after a qualifying collection change. It may target the same or another real container, but cannot be a facilitator-requested immediate rerun. |

### 3.3 Directional success thresholds

For a cohort of approximately 15:

- 10+ establish a meaningful physical location;
- 8+ complete a real first verification;
- 5+ discover and reconcile at least one genuine discrepancy;
- 4+ produce `repeat_verify_after_change`.

These are directional product-validation thresholds, not statistical proof. The strongest signal remains repeated behavior after actual drift.

### 3.4 Experiment boundary

- Version identifier: `collection-integrity-retention-v1`.
- Evaluation window: 42 days from each participant’s first meaningful placement.
- A repeat verification counts only when its qualifying change occurred after the earlier verification completed.
- A second Verify without a qualifying change is recorded separately and does not satisfy the critical metric.
- A monetization prompt, price question, or Grade/Sell workflow is not part of this experiment.
- Before Phase 10 product analytics exists, validation uses a participant’s on-device aggregate support export plus structured researcher notes. Do not upload `CollectionActivity` or inventory contents as a substitute.

## 4. Release invariants and hard NO-GO gates

The release is NO-GO if any condition below is known and unresolved in the exact candidate.

| Gate | NO-GO condition |
| --- | --- |
| G1 — Identity | A reproducible path silently persists, refetches, imports, resolves, or prices the wrong supported printing/variant/print run/graded or sealed identity. |
| G2 — Valuation | A reproducible path binds the wrong product, treats unsupported currency as USD, accepts invalid chronology, or makes Collection and Portfolio disagree on the same facts. |
| G3 — Quantity/data | A reproducible path loses, duplicates, collapses, or changes collection quantity/history without an intentional action. |
| G4 — Persistence/sync continuity | Launch, iCloud availability, account switching, conflict, retry, reinstall, or cross-device convergence can reveal an empty/different collection, strand local records, upload to a different account without confirmation, or silently lose a valid mutation. |
| G5 — Privacy/compliance | Required privacy/support links are missing/broken, declared practices conflict with code, required-reason APIs are undeclared, signing/capabilities are wrong, or material private data appears in logs/diagnostics. |
| G6 — Availability | A supported critical flow reproducibly crashes, deadlocks, loops forever, or becomes unrecoverable on a supported iPhone/iPad/OS. |

Purchase and restore are not gates because the release has no purchasable product.

Additional binary invariants:

1. persistence never substitutes an empty in-memory store while presenting it as the saved collection;
2. local recovery leaves the original store untouched and visibly blocks ordinary collection use;
3. all valid ownership mutations have durable, idempotent ledger representation;
4. immutable activity/ledger rows converge as a union across devices;
5. mutable aggregate quantity is treated as repairable from event facts only after Task 12 proves ledger completeness for every supported mutation path; until then, any aggregate/ledger mismatch fails closed;
6. source chronology compares provider clocks correctly and never lets an older value displace newer valid evidence;
7. unsupported currencies may display in native currency but never enter USD portfolio arithmetic;
8. export remains available in the free release and preserves every field claimed as round-trippable;
9. custom artwork absence on another device is disclosed and never interpreted as collection-data loss;
10. all five synced model schemas meet CloudKit constraints before development schema initialization;
11. the Production schema is deployed before the release archive is certified;
12. a named ledger-completeness audit proves every supported ownership mutation is reconstructible before event facts are used to repair a CloudKit conflict;
13. a deterministic restoration-readiness signal—not an elapsed-time guess—separates a genuinely empty cloud collection from an incomplete import;
14. only the exact TestFlight build produced from the frozen RC commit can satisfy the final device gates.

## 5. External prerequisites and owner inputs

The implementation agent must not invent external product identity or claim external work is complete. Entitled CloudKit work and Production schema work require the release owner to provide or confirm:

- active Apple Developer Program access with permission to manage identifiers and CloudKit schema;
- registered App ID `com.seankeller.CardScanner`;
- CloudKit container `iCloud.com.seankeller.CardScanner` attached to that App ID;
- provisioning profiles/certificates for Development and App Store distribution;
- the exact production HTTPS privacy URL ending in `/privacy`;
- the exact production HTTPS support URL ending in `/support`;
- access to two physical devices on separate installs, including at least one iPhone and one iPad;
- ability to test same-account sync and a controlled account-change scenario;
- App Store Connect app record and TestFlight access.

Repository source content belongs in `docs/legal/`. Production URLs should use the product domain. A GitHub Pages URL is an emergency fallback only and must be explicitly recorded as such. No placeholder URL, localhost URL, inaccessible staging URL, or invented domain may enter the RC archive.

### 5.1 Expected enrollment gate and execution stages

Apple documents that adding the iCloud capability requires an active Apple Developer account with sufficient permissions. This repository currently uses placeholder identity/local entitlements, so lack of enrollment is an expected dependency boundary, not a surprise product defect.

**Stage E0 — may execute before enrollment:**

- Tasks 1–3 in full;
- Task 4A: local controls, fixture/digest work, Path 0 source construction where it can run without signing, and the restoration-event observability harness;
- Task 5 source audit and any runtime compatibility checks that do not require an entitled host;
- Task 6 in full;
- Task 7 protocol, mock, redaction, policy, and anchor-concurrency tests against injected clients;
- privacy/support source drafting and deterministic Phase 1 tests that do not claim CloudKit evidence.

**Gate E1 — owner enrollment/identity action:**

1. enroll/confirm Apple Developer Program access;
2. register `com.seankeller.CardScanner`;
3. create and attach `iCloud.com.seankeller.CardScanner`;
4. configure Development and App Store signing plus iCloud/CloudKit and Remote Notifications capabilities;
5. build a test host and inspect its signed entitlements.

**Stage E2 — entitled proof before bootstrap:**

- complete Task 4B on an entitled physical device/test host, including Path 0, restoration readiness, no-account→account, offline/reconnect, and changed-account behavior;
- complete Task 5's entitled runtime construction check;
- complete Task 7's production `CKContainer`/private-database integration;
- only then implement/accept Task 8 bootstrap behavior.

Task numbers describe ownership of work, not permission to skip this gate. If E1 is unavailable, record `BLOCKED — external enrollment` for E2 work and continue only with explicitly listed E0 work. Do not weaken tests, manufacture entitlements, or declare Task 4 complete from local-only evidence.

## 6. Planned file structure

The implementation should use these boundaries. If the live code has moved, update paths in the evidence record before editing; do not spread the same responsibility across unrelated existing files.

| File | Responsibility |
| --- | --- |
| `docs/experiments/collection-integrity-v1-retention-contract.md` | Frozen hypothesis, definitions, cohort, thresholds, exclusions, falsifiers. |
| `docs/experiments/collection-integrity-v1-scorecard.md` | Privacy-safe cohort scorecard and interpretation rules. |
| `docs/release/phase-1-integrity-evidence.md` | One authoritative gate/evidence ledger for the candidate. |
| `docs/release/cloudkit-compatibility-audit.md` | Per-model compatibility table and production schema record. |
| `docs/release/cloudkit-release-matrix.md` | Device/account/conflict/reinstall test cases and observed digests. |
| `docs/release/ownership-ledger-completeness-audit.md` | Exhaustive quantity-mutation inventory, ledger contract, reconstruction proof, and exceptions. |
| `docs/legal/privacy-policy.md` | Source-of-truth privacy text mirrored at the production URL. |
| `docs/legal/support.md` | Source-of-truth support text mirrored at the production URL. |
| `TradingCardScanner/Services/CollectionStoragePolicy.swift` | Pure account/store decision types and policy. No SwiftUI or disk I/O. |
| `TradingCardScanner/Services/CollectionStoreManifestStore.swift` | Atomic local manifest persistence and legacy-store adoption. |
| `TradingCardScanner/Services/CloudAccountProbe.swift` | `CKContainer` account status, opaque fingerprint, notification handling. |
| `TradingCardScanner/Services/CloudCollectionAnchorStore.swift` | Direct private-CloudKit anchor read/claim/compare; no inventory content. |
| `TradingCardScanner/Services/CollectionStorageBootstrap.swift` | Main-actor startup orchestration and `ModelContainer` construction. |
| `TradingCardScanner/Services/CloudRestorationReadiness.swift` | Readiness state and selected, proven remote-import completion evidence; create only after Task 4 selects a mechanism. |
| `TradingCardScanner/Services/CollectionStoreDigest.swift` | Stable redacted structured-record digest and counts. |
| `TradingCardScanner/Views/CollectionStorageBootstrapView.swift` | Loading, confirmation, conflict, unavailable, and recovery UI. |
| `TradingCardScanner/Views/PrivacyAndSupportSettingsView.swift` | In-app production Privacy and Support links and data-boundary copy. |
| `TradingCardScannerTests/CollectionStoragePolicyTests.swift` | Exhaustive pure decision table. |
| `TradingCardScannerTests/CollectionStoreContinuityTests.swift` | Explicit-URL store transition, manifest, migration, and digest tests. |
| `TradingCardScannerTests/CloudRestorationReadinessTests.swift` | Store-correlated import/readiness, cold-install, empty-zone, failure, and relaunch tests. |
| `TradingCardScannerTests/CloudKitSchemaCompatibilityTests.swift` | Source/runtime schema guards and application-level identity checks. |
| `TradingCardScannerTests/CollectionStoreDigestTests.swift` | Stable ordering, mutation sensitivity, and redaction. |
| `TradingCardScannerTests/OwnershipLedgerCompletenessTests.swift` | Per-entry-point quantity reconstruction, idempotency, rollback, and retry proof. |
| `TradingCardScannerTests/PrivacyAndSupportSurfaceTests.swift` | URL/config/disclosure and privacy-manifest guards. |
| `scripts/audit_cloudkit_schema.sh` | Fast source guard for prohibited CloudKit schema declarations. |

All new Swift files must be added to the correct app/test groups and build phases in `TradingCardScanner.xcodeproj/project.pbxproj`. Do not rely on folder synchronization; this project currently uses explicit file references/build-file entries.

## 7. Execution discipline

- Implement in an isolated worktree created with `superpowers:using-git-worktrees` after the current user-owned changes are safely committed or intentionally included.
- Use TDD for production code: failing focused test, minimal implementation, focused pass, relevant suite pass, commit.
- Never edit Production CloudKit schema before the local audit passes.
- Never promote a schema merely because a Development container initializes.
- Never mark a manual/device row passed without device/build/account IDs, timestamp, expected result, observed result, and evidence location.
- Never let a timeout, an empty fetch, successful container construction, or absence of an error stand in for cloud-restoration completion.
- Never use aggregate quantity as repairable derived state until the named ledger-completeness audit passes every supported mutation path.
- Environment failure is not a product failure. Record it separately, repair the environment, and rerun.
- A source/schema/entitlement/bundle-ID change after evidence collection invalidates all affected evidence.
- Do not delete or reset user-owned working-tree changes.
- Do not log card names, certification numbers, exact inventory contents, raw CloudKit user record IDs, full store IDs, or physical locations.

---

### Task 1: Establish a reproducible baseline without disturbing user work

**Files:**
- Read: `progress.md`
- Read: `TradingCardScanner.xcodeproj/project.pbxproj`
- Create: `docs/release/phase-1-integrity-evidence.md`
- Preserve: every file listed in §1.2

- [ ] **Step 1: Record the source baseline and dirty-tree ownership**

Run:

```bash
git status --short
git diff --check
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
xcodebuild -version
df -h /
```

Expected:

- branch and HEAD match the intended implementation base;
- all pre-existing changes are listed under a “User-owned pre-plan changes” heading;
- `git diff --check` is clean;
- Xcode version and free disk are recorded.

If the five modified files in §1.2 are still uncommitted, stop implementation setup long enough to preserve them in a dedicated commit or an explicit patch. Do not stash/reset them automatically.

- [ ] **Step 2: Recover enough disposable build space**

The planning build failed with approximately 104 MiB free and left `/private/tmp/cardscanner-phase01-plan-build`. Verify that exact directory is disposable, remove only that directory, and recheck capacity. Do not recursively delete a workspace, home directory, or all DerivedData.

Run:

```bash
du -sh /private/tmp/cardscanner-phase01-plan-build 2>/dev/null || true
rm -rf /private/tmp/cardscanner-phase01-plan-build
df -h /
```

Expected: the known temporary directory is gone. Maintain at least 15 GiB free before the full build/test/archive sequence; if that cannot be achieved safely, record an environment blocker rather than deleting unrelated user data.

- [ ] **Step 3: Inventory destinations and select stable IDs**

Run:

```bash
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -showdestinations
xcrun simctl list devices available
```

Record one iPhone simulator UUID and one iPad simulator UUID. Do not use `OS=latest` when a stable UUID is available.

For the shell session that executes simulator commands, assign the selected iPhone UUID to a task-specific variable and verify it is nonempty:

```bash
export CARD_SCANNER_SIMULATOR_ID='the exact iPhone simulator UUID recorded above'
test -n "$CARD_SCANNER_SIMULATOR_ID"
```

Replace the descriptive quoted value in the shell session with the actual UUID. Do not commit a machine-specific UUID into scripts.

- [ ] **Step 4: Create the evidence ledger before changing source**

Create `docs/release/phase-1-integrity-evidence.md` with these sections:

```markdown
# CardScanner 1.0 Phase 0/1 Release Evidence

## Candidate identity

## Environment and signing identity

## User-owned pre-plan changes

## Automated baseline

## Phase 0 document freeze

## Deterministic integrity gates G1–G6

## CloudKit compatibility audit

## CloudKit production schema

## CloudKit continuity and two-device matrix

## Scanner normal/adversarial evidence

## iPhone and iPad rendered/device checks

## Privacy, support, and App Store metadata

## Archive and TestFlight binary inspection

## Residual risks and R1/R2/R3 decisions

## Final GO/NO-GO sign-off
```

Every evidence entry must include date/time, commit SHA, build number, device/OS, command or procedure, result, and artifact path. Start every unexecuted gate as `NOT RUN`; never prefill `PASS`.

- [ ] **Step 5: Run the current-tree baseline once**

Use a disposable derived-data directory and the recorded iPhone simulator UUID:

```bash
xcodebuild build-for-testing \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -derivedDataPath /private/tmp/cardscanner-phase01-baseline \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO

xcodebuild test-without-building \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -derivedDataPath /private/tmp/cardscanner-phase01-baseline \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO
```

Expected: build succeeds and the complete discovered suite is recorded. A failure belongs in the baseline section with its exact cause and must not be attributed to later changes.

- [ ] **Step 6: Commit only the baseline evidence**

```bash
git add docs/release/phase-1-integrity-evidence.md
git commit -m "docs: establish phase 0 and launch baseline"
```

### Task 2: Freeze the corrected retention experiment and reconcile stale strategy documents

**Files:**
- Create: `docs/experiments/collection-integrity-v1-retention-contract.md`
- Create: `docs/experiments/collection-integrity-v1-scorecard.md`
- Modify: `docs/vision/CardScanner Collection Integrity Strategy — Start-to-Finish Implementation Plan.md`
- Modify: `docs/vision/collection-integrity-codebase-gap-analysis.md`
- Modify: `docs/release/card-scanner-1.0-go-no-go-framework.md`
- Modify: `docs/CardScanner-Website-Implementation-Spec.md`
- Modify: `docs/release/phase-1-integrity-evidence.md`

- [ ] **Step 1: Write the retention contract from the frozen definitions**

Create `docs/experiments/collection-integrity-v1-retention-contract.md` containing, verbatim where quoted:

- version `collection-integrity-retention-v1`;
- the hypothesis in §2.1;
- cohort rules from §3.1;
- every event definition in §3.2;
- the 42-day window and thresholds in §§3.3–3.4;
- falsification/interpretation rules:
  - import/catalog without meaningful placement means Place activation failed or the job is weak;
  - Place plus one Verify without repeat means one-time organization utility, not recurring retention;
  - repeated Verify with few discrepancies means frequency/targeting needs reassessment;
  - repeated Verify with speed complaints supports later page-level CV investment;
  - repeated Verify is evidence of retention value, not willingness to pay;
- an explicit statement that Grade/Sell receives a separate future experiment and no price is frozen here;
- an explicit privacy rule prohibiting raw inventory upload for validation.

- [ ] **Step 2: Create a privacy-safe scorecard**

Create `docs/experiments/collection-integrity-v1-scorecard.md` with this schema:

```markdown
| Study ID | Cohort eligible | First meaningful placement date | Meaningful location | First Verify complete | Genuine discrepancy found | Genuine discrepancy reconciled | Qualifying later change | Repeat Verify after change | Days placement→repeat | Evidence source | Notes category |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- |
```

Add aggregation formulas in prose:

```text
meaningful_location_rate = meaningful_location_count / eligible_cohort_count
first_verify_rate = first_verify_complete_count / eligible_cohort_count
reconciled_discrepancy_rate = reconciled_discrepancy_count / eligible_cohort_count
repeat_after_change_rate = repeat_verify_after_change_count / eligible_cohort_count
```

The table may contain pseudonymous IDs, booleans, dates, elapsed days, and coarse note categories only. It must not contain collector names, emails, card names, container names, locations, certificate IDs, values, or full exported inventories.

- [ ] **Step 3: Correct the strategy document**

In Phase 0, replace the commercial hypothesis and willingness-to-pay threshold with the retention hypothesis and metrics above. In Phase 9 and the milestone summary, state that:

- the first public release is free;
- Collection Integrity’s first test is retention, not subscription conversion;
- any future Integrity packaging decision follows behavioral validation;
- Grade/Sell/economic monetization will be planned separately;
- no current plan promises a `$39.99/year` Integrity subscription.

Do not delete the long-term product loop. Correct only the monetization claims that conflict with the approved strategy.

- [ ] **Step 4: Correct the gap analysis**

Update its executive sequence, Phase 9/12 rows, entitlement gaps, and Milestones I–K so they no longer prescribe StoreKit or Integrity WTP as the next validation. Keep the codebase finding “no StoreKit implementation exists,” but classify that as a deliberate non-gap for free 1.0.

- [ ] **Step 5: Convert the release framework from monetized to free 1.0**

In `card-scanner-1.0-go-no-go-framework.md`:

- remove Purchase → entitlement → restore from release-critical flows;
- replace old G4 purchase failure with G4 persistence/sync continuity from §4;
- remove purchase tests from binary invariants and diagnostics;
- freeze “free 1.0, no StoreKit product” at RC;
- add the canonical-store and account-switch invariants;
- keep Place/Verify/Reconcile out of 1.0 critical flows;
- update “current known defects” to distinguish fixed code paths from evidence still required.

- [ ] **Step 6: Reconcile the website route contract with App Store support requirements**

Update the website specification’s frozen route set from:

```text
/, /privacy, /terms, /contact
```

to:

```text
/, /privacy, /terms, /support
```

The `/support` page owns the contact mechanism and support content; do not add a fifth route merely to keep `/contact`. Update header/footer copy, repository structure, SEO metadata, QA, acceptance criteria, and implementation sequence consistently. If an already-deployed `/contact` URL exists later, it may redirect to `/support`, but `/support` is the canonical URL used by the app and App Store Connect.

- [ ] **Step 7: Verify the old hypothesis is gone from active documents**

Run:

```bash
rg -n '\$30|\$39\.99|willingness.to.pay|Purchase → entitlement|monetized release|StoreKit' \
  docs/vision \
  docs/release/card-scanner-1.0-go-no-go-framework.md \
  docs/experiments
```

Expected: no active statement claims Integrity WTP or a monetized 1.0. Historical documents outside this set may retain chronology, but they must link to this plan if they could otherwise be mistaken for the current decision.

- [ ] **Step 8: Record and commit the Phase 0 freeze**

```bash
git add docs/experiments docs/vision docs/release docs/CardScanner-Website-Implementation-Spec.md
git commit -m "docs: freeze collection integrity retention experiment"
```

Expected: the evidence ledger links the contract and scorecard and records Phase 0 as complete. Phase 0 completion means the test is defined; it does not mean the future product behavior has been observed.

### Task 3: Define the storage/account decision policy with exhaustive pure tests

**Files:**
- Create: `TradingCardScanner/Services/CollectionStoragePolicy.swift`
- Create: `TradingCardScannerTests/CollectionStoragePolicyTests.swift`
- Modify: `TradingCardScanner.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add failing tests for the complete decision table**

Define test fixtures around these value types and cases:

```swift
enum CloudAccountAvailability: Equatable, Sendable {
    case available(fingerprint: String)
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

enum StoreMigrationState: String, Codable, Equatable, Sendable {
    case notStarted
    case copying
    case validating
    case committed
}

enum CloudAttachmentState: String, Codable, Equatable, Sendable {
    case neverAttached
    case attached
    case suspended
    case conflict
}

struct CloudRestoreCheckpoint: Codable, Equatable, Sendable {
    var storeID: UUID
    var accountFingerprint: String
    var storeFileIdentity: String
    var mechanismVersion: Int
    var confirmedAt: Date
}

struct CollectionStoreManifest: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1
    var formatVersion: Int
    var storeID: UUID
    var lastAttachedAccountFingerprint: String?
    var attachmentState: CloudAttachmentState
    var migrationState: StoreMigrationState
    var cloudRestoreCheckpoint: CloudRestoreCheckpoint?
}

struct CloudCollectionAnchor: Equatable, Sendable {
    var storeID: UUID
    var formatVersion: Int
}

enum LocalStorageReason: String, Equatable, Sendable {
    case noAccount
    case restricted
    case temporarilyUnavailable
    case attachmentSuspended
}

enum CollectionStorageDecision: Equatable, Sendable {
    case openCloud(storeID: UUID, accountFingerprint: String)
    case openProvenLocal(storeID: UUID, reason: LocalStorageReason)
    case requireAttachmentConfirmation(storeID: UUID, newAccountFingerprint: String)
    case adoptRemoteCollection(storeID: UUID, accountFingerprint: String)
    case blockDifferentRemoteCollection(localStoreID: UUID, remoteStoreID: UUID)
    case retryAccountCheck
    case blockUnprovenTransition
}
```

Write named tests for at least these rows:

1. fresh install + no account → one new local `storeID`;
2. fresh empty install + available account + no remote anchor → automatically claim/open the new empty local `storeID` with no confirmation;
3. fresh empty install + available account + remote anchor → automatically adopt the remote `storeID`, but remain in restoration state until readiness is proven;
4. existing local collection + same account + matching anchor → open cloud;
5. existing local collection + same account + missing anchor → require safe anchor claim, never mint another store;
6. existing nonempty local collection + never-attached/new account + no anchor → confirmation required before upload;
7. existing local collection + new account + different anchor → blocked, no automatic merge;
8. temporarily unavailable/could not determine → retry or proven-local path only;
9. restricted/no account → proven-local path only;
10. missing/corrupt manifest beside an existing store → block recovery; do not mint a replacement ID;
11. existing local data + confirmation accepted + empty remote account → claim/open cloud;
12. confirmation canceled → keep the local identity and remain cloud-suspended;
13. a stale asynchronous result for another startup generation is ignored;
14. raw CloudKit account IDs never appear in `CustomStringConvertible` or diagnostics.

The policy input must carry explicit local-presence facts—at minimum manifest presence, structured-store-file presence, and `localHasUserData` from a successfully opened/probed local store. It must not infer “fresh empty” from `context.fetch(...).isEmpty` while a cloud import is possible. Add a negative test proving that zero currently fetched rows plus an existing manifest/store is **not** treated as a fresh install.

Add checkpoint tests proving a restore checkpoint is accepted only when its store ID, opaque account fingerprint, store-file identity, and mechanism version all match; any mismatch returns to restoration checking and never to authoritative empty.

- [ ] **Step 2: Run the new test target and confirm failure**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/CollectionStoragePolicyTests
```

Expected: compile failure because the policy types do not exist.

- [ ] **Step 3: Implement only the pure policy**

`CollectionStoragePolicy.swift` must:

- import `Foundation` only;
- have no `SwiftUI`, `SwiftData`, `CloudKit`, `Security`, file I/O, or global mutable state;
- accept manifest/account/anchor/store-presence facts as input;
- distinguish a new empty installation from an existing empty-looking store using durable local-presence facts and restoration readiness;
- return a decision without side effects;
- distinguish transient unavailability from no account;
- never return a cloud-open decision for a changed account without confirmation;
- never return automatic merge for unequal local/remote `storeID`s;
- never create a new `storeID` when an existing store has no trustworthy manifest.
- automatically attach only a genuinely fresh empty installation; require confirmation before attaching pre-existing local user data to an unrecognized account.

The caller, not the pure policy, generates the UUID for a genuinely new install.

`openProvenLocal` is a logical access/sync-status decision, not an instruction to configure SwiftData with `.none`. If Task 4 selects Path 0, that decision opens the same always-CloudKit-configured local replica while synchronization is unavailable/suspended only where the physical-device proof showed it is safe. Keep policy vocabulary independent of the eventual `ModelConfiguration` mechanism.

- [ ] **Step 4: Run focused tests**

Expected: every decision-table test passes.

- [ ] **Step 5: Run the existing storage/account surface tests**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/UncoveredSurfaceTests
```

Expected: current tests still pass before old Sign in with Apple code is removed in Task 7.

- [ ] **Step 6: Commit**

```bash
git add TradingCardScanner/Services/CollectionStoragePolicy.swift \
  TradingCardScannerTests/CollectionStoragePolicyTests.swift \
  TradingCardScanner.xcodeproj/project.pbxproj
git commit -m "test: define canonical collection storage policy"
```

### Task 4: Select the simplest proven canonical-store and restoration architecture

**Files:**
- Create: `TradingCardScannerTests/CollectionStoreContinuityTests.swift`
- Create: `TradingCardScannerTests/CloudRestorationReadinessTests.swift`
- Create after mechanism selection: `TradingCardScanner/Services/CloudRestorationReadiness.swift`
- Modify: `TradingCardScanner.xcodeproj/project.pbxproj`
- Modify: `docs/release/phase-1-integrity-evidence.md`

This is a mandatory proof spike, not a production-bootstrap implementation task. It has a pre-enrollment part (4A) and an entitled part (4B). Test Path 0 first. Do not build `.none`↔CloudKit migration machinery unless the simpler always-CloudKit local replica fails a named invariant.

#### Task 4A — pre-enrollment local and observability work

- [ ] **Step 1: Write production-shaped fixture and digest helpers**

Use a unique temporary directory per test and the exact current `syncedSchema`. Seed one production-shaped row of every synced model, including:

- raw card quantity greater than one with variant/print-run/treatment provenance;
- graded card with grader/grade/qualifier and provider identifiers;
- sealed item with provider identity;
- linked optional `CollectedCard.activityBackfillAnchor` ↔ `CollectionActivity.backfillAnchorCard`;
- two-leg `InventoryEvent` correction sharing one operation ID;
- `PriceRecord` with source/freshness/invalidation fields;
- `ProductIdentity` with resolved vendor handle.

The test digest must sort by stable application identity and hash all material fields. It must not rely on SwiftData `PersistentIdentifier`, insertion order, or localized display strings.

- [ ] **Step 2: Prove the local control**

Using an explicit URL with `ModelConfiguration(_:schema:url:allowsSave:cloudKitDatabase:)`, prove:

```text
.none write → destroy container → .none reopen
interrupted local open leaves source bytes recoverable
manifest storeID remains unchanged
all five model counts and material digest remain identical absent a deliberate edit
```

A failure means the fixture/digest/local persistence basis is invalid. Correct it before any CloudKit conclusion.

- [ ] **Step 3: Build the Path 0 test harness before enrollment**

Add a factory that can construct one structured configuration with:

- one explicit stable store URL;
- `.private("iCloud.com.seankeller.CardScanner")` selected continuously rather than conditionally switching to `.none`;
- injected account/notification/readiness observers;
- no production decision based on Sign in with Apple.

The harness may compile and run non-network tests before enrollment. A failure caused solely by absent signing/capabilities is `BLOCKED — external enrollment`, not evidence that Path 0 is invalid.

- [ ] **Step 4: Build a restoration-readiness observability probe**

Observe `NSPersistentCloudKitContainer.eventChangedNotification` without yet trusting it. Capture only redacted facts needed to evaluate:

- event type (`setup`, `import`, or `export`);
- start/end/success/error category;
- whether the event can be correlated to the exact structured store URL/configuration;
- whether a completed import is followed by SwiftData-visible rows before readiness is emitted;
- event ordering on cold install, empty private database, nonempty private database, relaunch, offline launch, retry, and failed import.

Tests must prove that none of these independently means `readyEmpty`: container construction, account status `.available`, setup completion, absence of an import event, an empty fetch, or elapsed wall-clock time. Add a regression test that advances beyond 120 seconds and still refuses to declare readiness without affirmative evidence.

Do not add production notification coupling yet. The outcome of 4B decides whether event notifications are sufficient, need to be combined with an anchor/generation handshake, or must be rejected.

#### Gate E1 — stop for enrollment and production identity

- [ ] **Step 5: Complete the owner-controlled enrollment/capability gate**

Complete §5.1 Gate E1 and the production-identity/capability portions of Task 9 before drawing any CloudKit conclusion. Inspect the actual built test host:

```bash
export CARD_SCANNER_TEST_HOST_APP='the exact built test-host .app path reported by xcodebuild'
test -d "$CARD_SCANNER_TEST_HOST_APP"
codesign -d --entitlements :- "$CARD_SCANNER_TEST_HOST_APP"
```

Expected: exact production bundle/container entitlement, CloudKit service, correct environment from the provisioning profile, and no Sign in with Apple entitlement. Archive this result in the evidence ledger.

#### Task 4B — entitled physical-device proof

- [ ] **Step 6: Test Path 0 first on supported physical devices**

Keep the same explicit URL and CloudKit-backed configuration throughout. Execute each row from a clean controlled baseline:

```text
no iCloud account → create/edit → terminate/relaunch
no account → account becomes available → attach/sync
available account → offline → create/edit → terminate/relaunch → reconnect
temporarily unavailable/restricted → relaunch → recover
account A → account B before confirmation
account A → account B after explicit confirmation with empty B
account A → account B with a different remote anchor
return to account A
```

For every row capture storeID, five-model counts, total quantity, material digest, store URL, observed account/anchor state, and whether any export began before policy authorization.

Path 0 passes only if:

- no-account and offline writes remain durably available in the same local store;
- later account availability mirrors that same identity rather than revealing a second store;
- an existing local collection cannot begin exporting to a newly encountered account before confirmation;
- a different remote anchor cannot merge automatically;
- account changes never cause automatic deletion or an authoritative empty UI;
- retry/relaunch is idempotent.

If framework behavior begins synchronizing to a changed account before CardScanner can fence it, Path 0 fails the approved policy even if all data eventually appears.

- [ ] **Step 7: Prove a restoration-readiness signal**

On clean installations against both an empty and a production-shaped nonempty private database:

1. record the remote anchor/store identity before install;
2. start the exact entitled build and observe event/readiness evidence;
3. delay, interrupt, and resume imports;
4. verify when the first rows become visible to SwiftData;
5. verify when all five model counts and digest converge;
6. relaunch before and after completion;
7. repeat with no network and with a recoverable import failure.

Accept Core Data event notifications only if a successful, store-correlated import boundary reliably precedes the app’s readiness transition and all fetched state expected by the protocol is visible. If an empty remote database emits no usable import boundary, combine event evidence with the private anchor/generation protocol so “known remote empty” is affirmative rather than inferred.

If no deterministic signal is available through the chosen SwiftData stack, record the limitation and keep the product in a truthful non-authoritative restoring state. Do not replace the failed proof with a fixed, exponential, or “reasonable” timeout. That unresolved condition is G4/NO-GO for a launch that promises automatic restore.

- [ ] **Step 8: Only after Path 0 fails, test fallback Paths A then B**

Path A — same-store reconfiguration:

```text
.none write → destroy container → CloudKit-enabled reopen
CloudKit-enabled write → destroy container → .none reopen
.none edit while unavailable → destroy container → CloudKit-enabled reopen
```

Acceptance requires the same explicit URL, stable storeID/digest, preserved relationships, idempotent repeats, and physical-device confirmation.

Path B — explicit migration, only if Path A fails:

- use distinct, explicitly named source and destination URLs;
- read the source without CloudKit side effects;
- copy all five synced entities in dependency order using stable application IDs;
- validate destination counts and digest before switching the manifest;
- retain the source unchanged until validation and one relaunch succeed;
- retry after injected interruption without duplicates;
- record migration state (`notStarted`, `copying`, `validating`, `committed`) atomically;
- never copy raw SQLite files while a store may be open.

For A/B, inject failures before destination open, after partial copy, after save/before validation, and after validation/before manifest commit. Recovery must resume idempotently or reopen the unchanged source—never an empty destination.

If none of Paths 0/A/B satisfies continuity, account fencing, and readiness, record G4 failed and stop. Do not keep the current silent `.automatic`→`.none` fallback.

- [ ] **Step 9: Select one mechanism, delete rejected complexity, and record proof**

The evidence entry must state:

- why Paths 0/A/B passed, failed, or were not reached;
- explicit URLs/configuration identifiers and signed entitlement result;
- device/OS/account scenario IDs;
- pre/post storeID, counts, quantity, and digest;
- selected restoration-readiness signal and the evidence that falsifies premature empty state;
- framework limitations and resulting UX constraints;
- production files that must and must not be created.

If Path 0 passes, update later tasks to use one continuously CloudKit-configured local replica and do not implement `StoreMigrationState` behavior beyond compatibility with an already-written manifest type. Remove dead spike code rather than shipping alternate architectures.

```bash
git add TradingCardScannerTests/CollectionStoreContinuityTests.swift \
  TradingCardScannerTests/CloudRestorationReadinessTests.swift \
  TradingCardScanner/Services/CloudRestorationReadiness.swift \
  TradingCardScanner.xcodeproj/project.pbxproj \
  docs/release/phase-1-integrity-evidence.md
git commit -m "test: select canonical collection storage architecture"
```

### Task 5: Make CloudKit schema compatibility a named pre-deployment gate

**Files:**
- Create: `scripts/audit_cloudkit_schema.sh`
- Create: `TradingCardScannerTests/CloudKitSchemaCompatibilityTests.swift`
- Create: `docs/release/cloudkit-compatibility-audit.md`
- Modify: `TradingCardScanner.xcodeproj/project.pbxproj`
- Modify: `docs/release/phase-1-integrity-evidence.md`

- [ ] **Step 1: Create the fast prohibited-syntax audit**

`scripts/audit_cloudkit_schema.sh` must exit nonzero if any synced model source contains:

```text
@Attribute(.unique)
@Attribute(... .unique ...)
@Unique
deleteRule: .deny
```

It must scan only:

```text
TradingCardScanner/Models/CollectedCard.swift
TradingCardScanner/Models/PriceRecord.swift
TradingCardScanner/Models/ProductIdentity.swift
TradingCardScanner/Models/CollectionActivity.swift
TradingCardScanner/Models/InventoryEvent.swift
```

It must print each checked path and a final `CloudKit source audit passed` line. Make it executable.

- [ ] **Step 2: Add pre-enrollment source/local-runtime and application-identity tests**

`CloudKitSchemaCompatibilityTests.swift` must prove before enrollment wherever possible:

- the synced schema constructs locally from the exact five-model `Schema`;
- all relationships are optional;
- `CollectedCard.activityBackfillAnchor` and `CollectionActivity.backfillAnchorCard` have explicit inverse behavior and nullify safely;
- no relationship crosses from a synced model to `ReferenceQuote`, `PriceObservation`, `PriceCheckDay`, `PortfolioDailyClose`, or `LocalArtworkOverride`;
- duplicate `collectionKey`, `PriceRecord.key`, `ProductIdentity.key`, and `InventoryEvent.idempotencyKey` inputs are resolved or rejected by application code instead of a uniqueness constraint;
- a collision with unequal payload fails closed rather than choosing one silently;
- all new fields remain optional or have migration-safe defaults.

- [ ] **Step 3: Produce the per-model audit table**

`docs/release/cloudkit-compatibility-audit.md` must contain one row per synced model with columns:

```markdown
| Model | Stable application identity | Unique constraint absent | Relationships optional | Explicit inverse | Delete rule | Cross-configuration relationship absent | Defaults/optionality | Duplicate reconciliation owner | Result |
```

Record these current relationship facts:

- `CollectedCard.activityBackfillAnchor: CollectionActivity?`;
- `CollectionActivity.backfillAnchorCard: CollectedCard?`;
- both are optional;
- the inverse is explicit on the `CollectedCard` side and must be verified by runtime behavior;
- the other three synced models currently have no relationships.

Also record that raw-card condition is not persisted in the 1.0 schema.

- [ ] **Step 4: Run pre-enrollment compatibility gates, then the entitled construction gate after E1**

```bash
./scripts/audit_cloudkit_schema.sh
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/CloudKitSchemaCompatibilityTests
```

Expected: source audit and tests pass. Do not initialize or promote CloudKit schema on a failure.

Before enrollment, a passing source audit and local schema construction may be recorded as `PASS — pre-enrollment scope`; they do not prove an entitled CloudKit configuration. After Gate E1 and Task 4B select the architecture, rerun the same suite from a host signed with the exact production container entitlement and explicitly construct the selected `.private("iCloud.com.seankeller.CardScanner")` configuration. Record the test-host path and inspected entitlements. Task 5 is complete only after that entitled row passes.

- [ ] **Step 5: Commit**

```bash
git add scripts/audit_cloudkit_schema.sh \
  TradingCardScannerTests/CloudKitSchemaCompatibilityTests.swift \
  TradingCardScanner.xcodeproj/project.pbxproj \
  docs/release/cloudkit-compatibility-audit.md \
  docs/release/phase-1-integrity-evidence.md
git commit -m "test: gate synced schema for CloudKit compatibility"
```

### Task 6: Add a stable local collection manifest and redacted digest

**Files:**
- Create: `TradingCardScanner/Services/CollectionStoreManifestStore.swift`
- Create: `TradingCardScanner/Services/CollectionStoreDigest.swift`
- Create: `TradingCardScannerTests/CollectionStoreDigestTests.swift`
- Modify: `TradingCardScannerTests/CollectionStoreContinuityTests.swift`
- Modify: `TradingCardScanner.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add failing manifest persistence tests**

Cover:

- new empty install writes one `formatVersion = 1` manifest with a generated `storeID`;
- save is atomic (`manifest.json.tmp` is never accepted as authoritative);
- reload returns the same `storeID`;
- a corrupt manifest is reported as corrupt, not interpreted as absent;
- an existing persistent store with no manifest enters `legacyAdoptionRequired`;
- legacy adoption mints exactly one ID only after the existing store opens and its digest is captured;
- retrying adoption is idempotent;
- the manifest never stores a raw CloudKit user record ID;
- a cloud-restore checkpoint is written only from Task 4's affirmative readiness result and is rejected when storeID, account fingerprint, store-file identity, or mechanism version differs;
- corrupt/missing structured-store bytes invalidate the checkpoint rather than authorizing empty state;
- attachment state transitions reject invalid regressions;
- if and only if Task 4 selected Path B, migration-state transitions reject invalid regressions such as `committed → copying`; Path 0 must not acquire unused migration behavior.

Use an injected directory URL. No unit test may write into the real Application Support directory.

- [ ] **Step 2: Implement the manifest store**

Reuse the `CollectionStoreManifest`, `StoreMigrationState`, and `CloudAttachmentState` value types defined in Task 3; do not declare a second representation or add parallel `...Raw` properties. If Path 0 passes, keep migration state inert/compatibility-only and do not build a migration engine around it. Implement only the I/O boundary in this file:

```swift
struct CollectionStoreManifestStore {
    let directoryURL: URL
    func load() throws -> CollectionStoreManifest?
    func save(_ manifest: CollectionStoreManifest) throws
}
```

Implementation requirements:

- directory: `Application Support/CardScanner/CollectionStorage/` in production;
- filename: `manifest.json`;
- encode to a sibling temporary file, synchronize/close, then replace atomically;
- use file protection appropriate for collection metadata;
- never overwrite a decodable newer `formatVersion` with an older build;
- error messages distinguish missing, corrupt, unsupported-newer-version, read failure, and write failure;
- no `UserDefaults` for store identity;
- no full UUID in ordinary logs; expose a short suffix only in an explicit user-requested diagnostic export.
- compute `storeFileIdentity` from a local, opaque creation/adoption token stored atomically beside the manifest—not from a user-visible path, mutable content digest, or inode that may change during normal SQLite operation; replace the token only when the authoritative store is genuinely replaced.

- [ ] **Step 3: Add failing digest tests**

Build two in-memory containers with the same logical rows inserted in different orders. Assert equal digests. Then mutate each material field category and assert the digest changes. Include duplicate logical identities so the digest preserves multiplicity instead of hiding a CloudKit duplicate.

Add a redaction test asserting the diagnostic representation contains none of the seeded card name, certification number, provider URL, custom artwork filename, or full store ID.

- [ ] **Step 4: Implement the digest**

Use a versioned result:

```swift
struct CollectionStoreDigest: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1
    var formatVersion: Int
    var storeIDSuffix: String
    var collectedCardCount: Int
    var totalQuantity: Int
    var priceRecordCount: Int
    var productIdentityCount: Int
    var collectionActivityCount: Int
    var inventoryEventCount: Int
    var materialSHA256: String
}

enum CollectionStoreDigester {
    static func make(
        in context: ModelContext,
        storeID: UUID
    ) throws -> CollectionStoreDigest
}
```

Canonicalization rules:

- fetch all five synced entities;
- convert every material value to a stable, versioned Codable projection;
- sort `CollectedCard` by `collectionKey` plus enough fields to preserve duplicate rows;
- sort `PriceRecord` and `ProductIdentity` by key plus payload;
- sort `CollectionActivity` by `id`;
- sort `InventoryEvent` by `idempotencyKey`, then `eventID`;
- encode dates as numeric reference-date values or fixed ISO-8601 with fractional seconds;
- encode optionals explicitly so `nil` and an empty value cannot collide;
- hash the canonical bytes with CryptoKit SHA-256;
- never include device-local model data or image bytes;
- keep raw values inside the hash input only; diagnostics expose counts and hash, not the canonical payload.

- [ ] **Step 5: Extend continuity tests**

Every Task 4 transition must now assert the same `storeID`, counts, total quantity, and material hash before/after, except where the test deliberately changes a row.

- [ ] **Step 6: Run focused tests and commit**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/CollectionStoreContinuityTests \
  -only-testing:TradingCardScannerTests/CollectionStoreDigestTests

git add TradingCardScanner/Services/CollectionStoreManifestStore.swift \
  TradingCardScanner/Services/CollectionStoreDigest.swift \
  TradingCardScannerTests/CollectionStoreContinuityTests.swift \
  TradingCardScannerTests/CollectionStoreDigestTests.swift \
  TradingCardScanner.xcodeproj/project.pbxproj
git commit -m "feat: persist canonical collection identity"
```

### Task 7: Probe the real iCloud account and protect attachment with a private anchor

**Files:**
- Create: `TradingCardScanner/Services/CloudAccountProbe.swift`
- Create: `TradingCardScanner/Services/CloudCollectionAnchorStore.swift`
- Create: `TradingCardScannerTests/CloudAccountProbeTests.swift`
- Create: `TradingCardScannerTests/CloudCollectionAnchorStoreTests.swift`
- Modify: `TradingCardScanner.xcodeproj/project.pbxproj`

Steps 1 and 3 are E0 work and must be completed against protocol seams/mocks before enrollment. Steps 2, 4, and 5 contain production CloudKit integration and cannot be accepted until Gate E1 is complete and the exact container entitlement has been inspected. The mock suite proves decision behavior; it is not evidence that the private database is reachable or correctly provisioned.

- [ ] **Step 1: Write failing account-probe tests against a protocol seam**

Define a small injectable client rather than trying to mock `CKContainer`:

```swift
protocol CloudAccountClient: Sendable {
    func accountStatus() async throws -> CKAccountStatus
    func userRecordName() async throws -> String
}

struct CloudAccountProbe: Sendable {
    let client: any CloudAccountClient
    let fingerprintSalt: Data
    func availability() async -> CloudAccountAvailability
}
```

Test every `CKAccountStatus`, errors during status fetch, errors during user-record fetch, stable fingerprint for identical record/salt, different fingerprint for another record, and absence of the raw record name in returned errors/descriptions.

- [ ] **Step 2: After E1, implement and physically smoke-test production account probing**

Production client requirements:

- use `CKContainer(identifier: "iCloud.com.seankeller.CardScanner")`;
- call `accountStatus()` before private-database access;
- call `userRecordID()` only for `.available`;
- hash `recordName` with a device-local random salt using SHA-256;
- keep the salt in Keychain under a bundle-specific service such as `com.seankeller.CardScanner.cloud-account-fingerprint`;
- persist only the hash in the local manifest;
- map `noAccount`, `restricted`, `temporarilyUnavailable`, and `couldNotDetermine` distinctly;
- treat thrown account probes as `couldNotDetermine`, not as “new account” or “no account.”

Run one entitled physical-device smoke for `.available` and one controlled unavailable/no-account state. Record only the opaque fingerprint suffix and coarse status. A simulator/mock pass cannot complete this step.

- [ ] **Step 3: Write failing anchor-store tests**

Use an injectable database protocol and cover:

- missing anchor;
- matching anchor;
- different anchor;
- first claim succeeds;
- two simultaneous first claims with different IDs result in exactly one winner;
- network/service/account temporary errors do not become “missing anchor”;
- malformed/unsupported anchor blocks attachment;
- read-after-write verifies the stored value;
- no inventory fields are ever included.

- [ ] **Step 4: After E1, implement and integration-test the private anchor**

Use one deterministic private-database record:

```swift
enum CloudCollectionAnchorSchema {
    static let recordType = "CardScannerCollectionAnchor"
    static let recordName = "canonical-collection"
    static let storeIDField = "storeID"
    static let formatVersionField = "formatVersion"
    static let createdAtField = "createdAt"
}
```

These are the required base fields. If Task 4 proves that an additional remote generation/readiness field is necessary, update this schema, its protocol tests, §2.3 if a synced marker model is required, the CloudKit compatibility audit, and the Development schema record **before** Production promotion. Do not silently add a sixth synced model or an anchor field as an implementation detail; that is an explicit architecture/schema decision. If no truthful signal can be produced within the accepted schema, stop at G4 rather than infer readiness.

Requirements:

- use the private database only;
- store `storeID` as UUID string, `formatVersion` as integer, and `createdAt` as date;
- a first claim must be conditional so two devices cannot silently overwrite one another;
- on `serverRecordChanged`, fetch and compare the winner;
- no update path changes an established nonmatching `storeID` in 1.0;
- no card/inventory/price/location content exists in this record;
- an anchor conflict returns a typed result consumed by `CollectionStoragePolicy`.

Against the Development private database, prove missing/read/claim/read-after-write, conditional first-claim conflict, malformed-version handling, and temporary network/account error classification. Never run destructive “clear all records” setup against Production; use a dedicated controlled Development account/zone and record cleanup scope.

- [ ] **Step 5: After E1, observe runtime account changes without making decisions in the callback**

Register for `CKAccountChanged` after creating the production `CKContainer`. The notification may arrive on an arbitrary queue; forward it to the main-actor bootstrap controller with a new generation token. The callback only triggers a new probe. It must not mutate SwiftData, delete credentials, generate a store ID, or infer which account appeared.

- [ ] **Step 6: Run focused tests and commit**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/CloudAccountProbeTests \
  -only-testing:TradingCardScannerTests/CloudCollectionAnchorStoreTests

git add TradingCardScanner/Services/CloudAccountProbe.swift \
  TradingCardScanner/Services/CloudCollectionAnchorStore.swift \
  TradingCardScannerTests/CloudAccountProbeTests.swift \
  TradingCardScannerTests/CloudCollectionAnchorStoreTests.swift \
  TradingCardScanner.xcodeproj/project.pbxproj
git commit -m "feat: guard collection cloud attachment by account"
```

### Task 8: Replace static storage selection with a safe bootstrap state machine

**Files:**
- Create: `TradingCardScanner/Services/CollectionStorageBootstrap.swift`
- Create: `TradingCardScanner/Views/CollectionStorageBootstrapView.swift`
- Create: `TradingCardScannerTests/CollectionStorageBootstrapTests.swift`
- Modify: `TradingCardScanner/App/TradingCardScannerApp.swift`
- Modify: `TradingCardScanner/Views/ScannerSettingsView.swift`
- Modify: `TradingCardScannerTests/UncoveredSurfaceTests.swift`
- Modify: `TradingCardScanner.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add failing orchestration tests**

Use injected manifest, account, anchor, container-factory, digest, and migration clients. Test:

- one startup generation constructs at most one authoritative container;
- stale async results from an earlier generation cannot replace a newer state;
- no account uses only the Task 4-proven local path;
- same account/matching anchor opens the CloudKit-backed store;
- new account pauses at confirmation before container attachment;
- cancel remains suspended and preserves the local storeID;
- confirm claims an empty remote anchor then opens cloud;
- a different remote anchor shows conflict and never opens either collection as merged;
- temporary account failure retries without creating a store;
- fresh empty install + available account + no anchor automatically claims/opens without confirmation;
- fresh install + existing remote anchor adopts the remote identity but remains non-authoritative while restoration readiness is checking/importing;
- zero fetched rows, successful container construction, and 120 elapsed seconds cannot move restoration to ready;
- a proven `readyEmpty` signal opens an actually empty collection, while a proven `readyPopulated` signal exposes imported rows only after their expected digest/count contract is visible;
- restoration failure exposes retry/recovery without showing ordinary empty-collection UI;
- corrupt manifest shows recovery UI and leaves store bytes untouched;
- container failure shows recovery UI and never substitutes a normal-looking empty collection;
- debug performance route remains isolated/in-memory and bypasses real collection storage;
- a mid-session `CKAccountChanged` event fences writes/refresh work before re-evaluation;
- background price refresh does not run until storage state is ready.

- [ ] **Step 2: Implement bootstrap states**

Use an explicit main-actor state machine:

```swift
enum CollectionStorageMode: String, Equatable, Sendable {
    case cloudKit
    case onDevice
}

struct AccountAttachmentRequest: Equatable, Sendable {
    var storeID: UUID
    var newAccountFingerprint: String
}

struct AccountConflictSummary: Equatable, Sendable {
    var localStoreIDSuffix: String
    var remoteStoreIDSuffix: String
}

@MainActor
final class CollectionStorageBootstrap: ObservableObject {
    enum State {
        case loading
        case restoringFromCloud(CloudRestorationReadiness)
        case ready(session: CollectionStorageSession)
        case confirmationRequired(AccountAttachmentRequest)
        case accountConflict(AccountConflictSummary)
        case temporarilyUnavailable(String)
        case recoveryRequired(String)
    }

    @Published private(set) var state: State = .loading

    func start() async
    func confirmAttachment() async
    func keepOnDevice() async
    func retry() async
}

struct CollectionStorageSession {
    let container: ModelContainer
    let storeID: UUID
    let mode: CollectionStorageMode
}
```

Keep construction I/O in injected services. `State.ready` is the only state that exposes a `ModelContainer` to `ContentView`.

`restoringFromCloud` may retain the candidate container privately inside the bootstrap service so it can observe import progress, but must not inject it into normal collection UI. The readiness observer must carry the startup generation and store identity so a late event from an abandoned container cannot make the current session ready.

- [ ] **Step 3: Give both configurations explicit identities and URLs**

Preserve two configurations in the `ModelContainer`:

- structured collection configuration for the five synced models;
- `PortfolioLocal` for the five local-only models.

Requirements:

- use explicit, stable names and URLs;
- use the Task 4-selected local/cloud transition mechanism;
- if Path 0 passed, keep the structured configuration CloudKit-backed in every account/network state and do not introduce `.none` fallback code;
- when cloud-attached, target `.private("iCloud.com.seankeller.CardScanner")` or the equivalent explicitly verified automatic selection;
- never create an unnamed local fallback whose URL may differ;
- never point two configurations at one URL;
- never relate a synced model to a local-only model;
- call `CollectionArtworkStore.migrateLegacyMappings` only after the final authoritative container is ready;
- start `BackgroundPriceRefresh`, collection normalization, and portfolio work only after readiness.
- call `PortfolioEpoch.establishIfNeeded` only after independent storage/restoration readiness; its `initialSyncGrace` is not startup evidence.

- [ ] **Step 4: Replace the static app container**

`TradingCardScannerApp` must no longer construct a global static container before an async iCloud preflight. Its root should own the bootstrap and render `CollectionStorageBootstrapView`. The ready branch injects exactly that session’s container into the existing app content.

The existing DEBUG `CollectionFinishPerformance` route must still receive an isolated in-memory `fullSchema` container and must never probe or touch CloudKit.

- [ ] **Step 5: Implement fail-closed UI states**

`CollectionStorageBootstrapView` must provide:

- loading: “Checking collection storage…”;
- cloud restoration: “Restoring collection from iCloud…” with Retry only when the selected readiness mechanism reports a recoverable failure; do not render zero cards as a completed empty collection;
- changed-account confirmation: explain that the existing on-device collection will be attached/uploaded only after confirmation;
- keep-on-device/cancel action using the proven local path;
- conflict: show that this iCloud account already contains a different CardScanner collection; offer Retry, Open Settings, and a Support link; do not offer Merge in 1.0;
- temporary unavailability: Retry and Open Settings; do not say the collection is empty;
- recovery: preserve current `StorageRecoveryView` principle that original bytes remain untouched.

Never display account fingerprint, raw CloudKit record ID, full store ID, or inventory details.

- [ ] **Step 6: Fence ongoing work on an account-change event**

Add one app-level storage generation that scanner writes, CSV imports, catalog normalization, store revision monitoring, and background refresh can compare before committing asynchronous results. At minimum:

- stop scheduling new background work;
- cancel or invalidate in-flight derived/background work;
- prevent new collection mutations while storage is not `.ready`;
- discard completions carrying an old generation;
- resume only after the user resolves the account state and a new ready session is installed.

Do not try to move a live `ModelContext` to another container.

- [ ] **Step 7: Run focused and regression tests**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/CollectionStoragePolicyTests \
  -only-testing:TradingCardScannerTests/CollectionStoreContinuityTests \
  -only-testing:TradingCardScannerTests/CollectionStorageBootstrapTests \
  -only-testing:TradingCardScannerTests/UncoveredSurfaceTests \
  -only-testing:TradingCardScannerTests/PortfolioReconciliationTests
```

Expected: all pass, including recovery and local-only portfolio behavior.

- [ ] **Step 8: Commit**

```bash
git add TradingCardScanner/App/TradingCardScannerApp.swift \
  TradingCardScanner/Services/CollectionStorageBootstrap.swift \
  TradingCardScanner/Views/CollectionStorageBootstrapView.swift \
  TradingCardScanner/Views/ScannerSettingsView.swift \
  TradingCardScannerTests/CollectionStorageBootstrapTests.swift \
  TradingCardScannerTests/UncoveredSurfaceTests.swift \
  TradingCardScanner.xcodeproj/project.pbxproj
git commit -m "feat: bootstrap one continuous collection store"
```

### Task 9: Apply the production app identity and remove the Sign in with Apple proxy

**Files:**
- Delete: `TradingCardScanner/Services/AppleAccountCredentials.swift`
- Modify: `TradingCardScanner/App/TradingCardScannerApp.swift`
- Modify: `TradingCardScanner/Views/ScannerSettingsView.swift`
- Modify: `TradingCardScanner/TradingCardScanner.entitlements`
- Modify: `TradingCardScanner/TradingCardScanner-Local.entitlements`
- Modify: `TradingCardScanner/Info.plist`
- Modify: `TradingCardScanner.xcodeproj/project.pbxproj`
- Modify: `TradingCardScannerTests/UncoveredSurfaceTests.swift`
- Modify: `docs/release/phase-1-integrity-evidence.md`

**Dependency override around enrollment:** immediately after Gate E1 becomes available, execute the external registration/capability setup and Steps 3–4 below before Task 4B. This gives the proof spike a real signed identity. Steps 1–2 depend on the Task 8/bootstrap shape and may be completed afterward. Do not wait for Task 8 to register the App ID/container, and do not claim Task 9 complete until all steps pass.

Before editing repository identifiers, verify in the Apple Developer portal/Xcode capability flow that:

- explicit App ID `com.seankeller.CardScanner` exists;
- `iCloud.com.seankeller.CardScanner` exists and is attached;
- CloudKit and Remote Notifications are enabled for the App ID;
- Development and App Store provisioning profiles resolve those exact capabilities.

Record portal/container identifiers and dates, but never credentials, team secrets, or raw account IDs.

- [ ] **Step 1: Update tests to remove the false account concept**

Delete `AppleAccountCredentialsSurfaceTests`. Replace it with tests asserting:

- Settings has no Sign in with Apple dependency or copy;
- storage status is derived from `CollectionStorageSession`/bootstrap state;
- iCloud availability is independent of app authentication;
- no app feature requires a CardScanner account in 1.0.

Run the focused test and confirm it fails while the old UI/code remains.

- [ ] **Step 2: Remove Sign in with Apple implementation**

Remove:

- `AuthenticationServices` import from Settings if nothing else uses it;
- `AccountSettingsSection` sign-in button, credential state, sign-out, and revocation checks;
- `AppleAccountCredentials.swift` from the app target and project;
- `com.apple.developer.applesignin` from the release entitlement;
- all comments saying Sign in with Apple gates CloudKit.

Settings should describe the real system iCloud state and direct the user to system Settings when action is necessary.

- [ ] **Step 3: Apply the approved bundle and CloudKit identifiers**

Update app Debug and Release build settings:

```text
PRODUCT_BUNDLE_IDENTIFIER = com.seankeller.CardScanner
```

Update the test bundle to a valid derivative such as:

```text
com.seankeller.CardScannerTests
```

Release entitlements must contain:

```xml
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.seankeller.CardScanner</string>
</array>
```

Keep the local debug entitlement empty only if the team’s local signing constraints still require it. The CloudKit integration/release configuration must use the real entitlement and must be the configuration tested for shipping.

Complete this step during Gate E1 before Task 4B. The production code can be finished later, but the entitled proof host must already use these exact identifiers.

- [ ] **Step 4: Add remote-notification background mode**

Append `remote-notification` to `UIBackgroundModes` in `Info.plist`, preserving `fetch` and `processing`. Configure capabilities/provisioning through the Apple Developer/Xcode capability flow. Do not manually hardcode an `aps-environment` value that conflicts with the provisioning profile; inspect the signed result instead.

Complete the capability/provisioning part during Gate E1. The presence of the plist mode alone is not proof that silent CloudKit change delivery is entitled.

- [ ] **Step 5: Record pre-release data compatibility impact**

Changing from `com.example.TradingCardScanner` to `com.seankeller.CardScanner` creates a different app sandbox and CloudKit container. This is acceptable before public 1.0, but existing developer/TestFlight data under the placeholder bundle does not magically migrate. Record one explicit policy in the evidence document:

- affected pre-release testers export CSV before replacing the old build and import into the production-identity build; or
- their pre-release data is intentionally disposable.

Do not claim an in-place App Store migration across bundle IDs.

- [ ] **Step 6: Inspect build settings and entitlements**

```bash
xcodebuild -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Release -showBuildSettings | \
  rg 'PRODUCT_BUNDLE_IDENTIFIER|CODE_SIGN_ENTITLEMENTS|DEVELOPMENT_TEAM|TARGETED_DEVICE_FAMILY|IPHONEOS_DEPLOYMENT_TARGET'
```

Build an entitled device/archive candidate, then inspect:

```bash
export CARD_SCANNER_BUILT_APP='the exact built CardScanner .app path reported by xcodebuild'
test -d "$CARD_SCANNER_BUILT_APP"
codesign -d --entitlements :- "$CARD_SCANNER_BUILT_APP"
```

Expected:

- bundle ID is `com.seankeller.CardScanner`;
- iCloud container is exact;
- CloudKit service is present;
- Sign in with Apple is absent;
- device families remain iPhone/iPad;
- no wildcard or placeholder identity remains.

- [ ] **Step 7: Run focused tests and commit**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/CollectionStorageBootstrapTests \
  -only-testing:TradingCardScannerTests/UncoveredSurfaceTests

git add TradingCardScanner TradingCardScannerTests \
  TradingCardScanner.xcodeproj/project.pbxproj \
  docs/release/phase-1-integrity-evidence.md
git commit -m "build: adopt production app and iCloud identity"
```

### Task 10: Add accurate in-app privacy/support surfaces and repository source content

**Files:**
- Create: `TradingCardScanner/Views/PrivacyAndSupportSettingsView.swift`
- Create: `TradingCardScannerTests/PrivacyAndSupportSurfaceTests.swift`
- Create: `docs/legal/privacy-policy.md`
- Create: `docs/legal/support.md`
- Modify: `TradingCardScanner/Views/ScannerSettingsView.swift`
- Modify: `TradingCardScanner/Info.plist`
- Modify: `TradingCardScanner/PrivacyInfo.xcprivacy`
- Modify: `TradingCardScanner.xcodeproj/project.pbxproj`
- Modify: `docs/release/phase-1-integrity-evidence.md`

- [ ] **Step 1: Inventory data flows before writing claims**

Record these current flows in the privacy policy and evidence:

- camera frames/photos are processed for scanning/centering; state whether any image leaves the device (the current scanner implementation must be inspected and the claim must match it);
- card/set/printing identifiers and search terms are sent to TCGdex, Scryfall, Pokémon TCG API, and optional JustTCG requests;
- a user-provided JustTCG key is stored in Keychain;
- structured collection models listed in §2.3 sync to the user’s private CloudKit database;
- device-local portfolio observations/closes and custom artwork do not sync;
- no advertising tracking or analytics SDK exists in 1.0;
- basic CSV export is user initiated and remains free;
- deletion behavior, retention, support contact, and how to disable iCloud/revoke access are explained.

Do not say “nothing is transmitted” because catalog/pricing queries and CloudKit sync are network transfers. Distinguish “not collected by the developer” from “never leaves the device.”

- [ ] **Step 2: Add failing URL/disclosure tests**

Tests must assert:

- `PrivacyPolicyURL` and `SupportURL` exist in the built configuration;
- both parse as HTTPS URLs;
- host is not empty, `localhost`, or a known placeholder;
- paths end in `/privacy` and `/support` respectively;
- Settings exposes both links in an easily accessible top-level category;
- Settings contains the exact custom-artwork disclosure from §2.3;
- Settings explains structured-record iCloud sync without claiming local-only data syncs;
- the app has no Sign in with Apple copy;
- the privacy manifest contains UserDefaults reason `CA92.1`;
- the privacy manifest contains file-timestamp reason `C617.1` because source reads `contentModificationDateKey` for app-container cache management.

- [ ] **Step 3: Add build-configured production URLs**

Expose `PrivacyPolicyURL` and `SupportURL` through `Info.plist` build substitutions. The release owner supplies the exact production product-domain URLs before this task can pass. The code must fail safely—hide no mandatory link and crash nowhere—if a development build lacks values, but the Release test/gate must reject missing or placeholder values.

Use a small typed boundary:

```swift
enum CardScannerExternalLinks {
    static var privacyPolicy: URL? { configuredURL(forInfoKey: "PrivacyPolicyURL") }
    static var support: URL? { configuredURL(forInfoKey: "SupportURL") }
}
```

Do not scatter string literals across views.

- [ ] **Step 4: Add the in-app Settings category**

Add a top-level Settings row labeled `Privacy & Support`. Its screen must include:

- `Privacy Policy` link;
- `Support Website` link;
- `Collection sync` explanation;
- exact custom-artwork disclosure;
- statement that Value History is device-local;
- statement that CSV export is available from Collection & Portfolio settings;
- no legal claims beyond the repository policy.

Use `Link` for ordinary HTTPS navigation and provide accessible labels/hints.

- [ ] **Step 5: Write legal/support source documents**

`docs/legal/privacy-policy.md` must include:

- effective date and app name;
- data stored on device;
- data synchronized via private CloudKit;
- provider requests and their purposes;
- no cross-app tracking/ads/analytics in 1.0;
- retention/deletion behavior;
- export/portability;
- iCloud controls/account switching;
- children/age statement if required by the final App Store age rating;
- changes/contact section.

`docs/legal/support.md` must include:

- supported app/OS scope;
- how to report a scan, identity, price, import/export, storage, or sync issue;
- instructions to include app version, OS/device, coarse error category, and redacted diagnostic export;
- warning not to send certificate IDs, full collection exports, or card images unless explicitly requested and consented;
- iCloud troubleshooting and the different-account conflict policy;
- response contact/channel supplied by the release owner.

These files are product source content, not proof that the public URLs are deployed.

- [ ] **Step 6: Correct the privacy manifest**

Add the File Timestamp required-reason category with `C617.1`, preserving UserDefaults `CA92.1`. Re-audit source before submission in case other required-reason APIs were added. Keep `NSPrivacyTracking = false` unless code/data practice changes.

- [ ] **Step 7: Deploy and verify the public pages**

After the product-domain pages are published, verify on a clean network/device:

```text
HTTPS succeeds without authentication
no redirect loop
privacy URL renders the policy content
support URL renders current contact/help content
both work from inside the exact app build
```

Capture final URLs, HTTP status, date, and screenshots in the evidence ledger. App Store Connect must use the same privacy URL.

- [ ] **Step 8: Run tests and commit**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/PrivacyAndSupportSurfaceTests \
  -only-testing:TradingCardScannerTests/UncoveredSurfaceTests

git add TradingCardScanner/Views/PrivacyAndSupportSettingsView.swift \
  TradingCardScanner/Views/ScannerSettingsView.swift \
  TradingCardScanner/Info.plist \
  TradingCardScanner/PrivacyInfo.xcprivacy \
  TradingCardScannerTests/PrivacyAndSupportSurfaceTests.swift \
  TradingCardScanner.xcodeproj/project.pbxproj \
  docs/legal docs/release/phase-1-integrity-evidence.md
git commit -m "feat: add launch privacy and support surfaces"
```

### Task 11: Close the deterministic Phase 1 integrity matrix on the current tree

**Files:**
- Modify as defects require, but expected primary files are:
  - `TradingCardScanner/Services/PortfolioEngine.swift`
  - `TradingCardScanner/Services/PriceObservationLog.swift`
  - `TradingCardScanner/Services/CollectionStore.swift`
  - `TradingCardScanner/Services/CollectionCSV.swift`
  - `TradingCardScanner/Services/ProductIdentityStore.swift`
  - `TradingCardScanner/Services/InventoryLedger.swift`
  - `TradingCardScanner/Views/ScannerViewModel.swift`
- Modify/add focused tests in:
  - `TradingCardScannerTests/OpusImplementationPlanTests.swift`
  - `TradingCardScannerTests/PortfolioReconciliationTests.swift`
  - `TradingCardScannerTests/PricingTests.swift`
  - `TradingCardScannerTests/CollectionActivityHistoryTests.swift`
  - `TradingCardScannerTests/CollectionItemKindTests.swift`
  - `TradingCardScannerTests/ImportedItemKindTests.swift`
  - `TradingCardScannerTests/CollectionKeyTests.swift`
  - `TradingCardScannerTests/VariantResolverTests.swift`
  - `TradingCardScannerTests/ProductIdentityTests.swift`
  - `TradingCardScannerTests/JustTCGContractTests.swift`
  - `TradingCardScannerTests/ScannerViewModelTests.swift`
- Modify: `docs/release/phase-1-integrity-evidence.md`

This task is a matrix-driven review, not permission to rewrite the app. Existing tests count as evidence only after they run against the current candidate. Add code only for a reproduced gap.

- [ ] **Step 1: Preserve and verify the current half-open day-boundary fix**

Confirm `PortfolioEngine` uses:

```swift
event.occurredAt >= dayStart && event.occurredAt < cutoff
```

and the corresponding fetch predicate uses `< latestCutoff`. Run:

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/OpusImplementationPlanTests/testREQ010EventAtNextDayBoundaryBelongsToFollowingDay
```

Expected: pass. If these changes are still user-owned/uncommitted, retain their authorship in a dedicated commit; do not recreate them under this task.

- [ ] **Step 2: Run exact identity and uncertainty suites**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/CollectionKeyTests \
  -only-testing:TradingCardScannerTests/VariantResolverTests \
  -only-testing:TradingCardScannerTests/GradedLabelParserTests \
  -only-testing:TradingCardScannerTests/ScannedGradedResolverTests \
  -only-testing:TradingCardScannerTests/CatalogNormalizationTests \
  -only-testing:TradingCardScannerTests/MagicTreatmentTests \
  -only-testing:TradingCardScannerTests/MagicPhysicalObjectTests
```

Required assertions include:

- exact set/collector number survives save/refetch;
- variant/finish ambiguity stays unresolved rather than defaulting;
- Pokémon print run is independent from finish and survives picker→save;
- Magic treatment/content-kind/qualifiers survive persistence and keying;
- raw, graded, certified, and sealed identities cannot collapse incorrectly;
- identity rekey/merge retains quantity and history;
- a provider product cannot bind across game/set/print-run/variant boundaries.

- [ ] **Step 3: Run quantity, graded/sealed, and import/export suites**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/CollectionActivityHistoryTests \
  -only-testing:TradingCardScannerTests/CollectionItemKindTests \
  -only-testing:TradingCardScannerTests/ImportedItemKindTests \
  -only-testing:TradingCardScannerTests/PortfolioReconciliationTests
```

Required assertions include:

- add/rescan/manual quantity adjustment/remove/undo/restore conserve quantity;
- duplicate certified items do not silently increment;
- correction legs are both present or neither is accepted;
- retry idempotency does not duplicate ledger facts;
- current CSV export→parse→apply preserves supported identity and quantity;
- graded and sealed round trips preserve their distinct fields;
- import failures remain visible/exportable and do not partially corrupt successful rows;
- unsupported/ambiguous rows do not become a confidently wrong supported identity;
- raw-card condition remains absent rather than guessed from a SKU.

- [ ] **Step 4: Run price, currency, provenance, freshness, and total suites**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/PricingTests \
  -only-testing:TradingCardScannerTests/PortfolioTrustPassTests \
  -only-testing:TradingCardScannerTests/PortfolioReconciliationTests \
  -only-testing:TradingCardScannerTests/ProductIdentityTests \
  -only-testing:TradingCardScannerTests/JustTCGContractTests
```

Required assertions include:

- EUR and other unsupported currencies do not enter USD totals;
- USD→EUR, EUR→USD, invalidation, nil-price, and valid zero transitions converge;
- equal provider timestamp with changed valid value reaches decision logic;
- strictly older provider evidence cannot displace newer valid evidence;
- a newer valid observation is not rejected by a coarser/equal provider clock;
- price source, source-variant, fetched, successful-check, and provider timestamps keep distinct semantics;
- Collection and Portfolio agree for identical facts;
- incremental/fast-path valuation converges with authoritative recomputation;
- invalid market/product identity is rejected rather than priced approximately.

- [ ] **Step 5: Run scanner-purpose and persistence rollback suites**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/ScannerViewModelTests \
  -only-testing:TradingCardScannerTests/ScanParserTests \
  -only-testing:TradingCardScannerTests/CardLatchTests \
  -only-testing:TradingCardScannerTests/ScanSubjectSuppressionTests \
  -only-testing:TradingCardScannerTests/UncoveredSurfaceTests
```

Required assertions include:

- Price Check never mutates collection/ownership history;
- Collection scanning saves only after a resolved/confirmed result;
- delayed recognition from an old purpose/session cannot commit into a new purpose;
- failed final save rolls back staged card, activity, ledger, and price mutations;
- duplicate/rapid scans honor current latch and user-confirmation policy;
- restart/refetch does not change identity, quantity, or intent semantics.

- [ ] **Step 6: Reproduce any failure before changing production code**

For each observed failure:

1. classify environment versus product;
2. if product, add the narrowest deterministic regression test;
3. run it alone and observe the expected failure;
4. implement the minimal fix in the owning service;
5. run the focused test;
6. run the affected suite;
7. record gate and root cause in the evidence ledger;
8. commit the fix independently.

Do not “fix” a statistical OCR miss by weakening uncertainty rules or forcing an expected identity.

- [ ] **Step 7: Perform persistence restart fixtures**

Using an explicit temporary persistent store rather than in-memory SwiftData:

- seed production-shaped raw, graded, sealed, imported, priced, invalidated, and corrected rows;
- save and destroy every context/container reference;
- reopen from the same URLs;
- compare counts, total quantity, logical collection projection, portfolio current total, and material digest;
- repeat after one CSV import and one identity correction.

Expected: absent new external/user facts, `persist → reload → recompute → persist` does not alter authoritative state.

- [ ] **Step 8: Update the gate table and commit**

Each integrity area in the evidence ledger must be `PASS`, `FAIL`, or `BLOCKED — environment`, with linked test names/commands. “Covered by many tests” is not an acceptable result.

```bash
git add TradingCardScanner TradingCardScannerTests docs/release/phase-1-integrity-evidence.md
git commit -m "test: certify launch-critical collection integrity"
```

### Task 12: Prove ownership-ledger completeness before using it as conflict authority

**Files:**
- Create: `docs/release/ownership-ledger-completeness-audit.md`
- Create: `TradingCardScannerTests/OwnershipLedgerCompletenessTests.swift`
- Modify only if a reproduced gap requires it:
  - `TradingCardScanner/Services/InventoryLedger.swift`
  - `TradingCardScanner/Services/CollectionStore.swift`
  - `TradingCardScanner/Services/CollectionCSV.swift`
  - `TradingCardScanner/Services/MagicTreatmentMigration.swift`
  - `TradingCardScanner/Services/PortfolioEpoch.swift`
- Modify: `TradingCardScanner.xcodeproj/project.pbxproj`
- Modify: `docs/release/phase-1-integrity-evidence.md`

This is a named authority gate. The current code can compute ledger quantities with `InventoryLedger.quantities(from:)`, but current `CollectionStore.repairQuantityMismatches` repairs in the opposite direction: it appends a new ledger event whose delta makes the ledger agree with the mutable collection projection. That behavior is useful for explicit/manual repair but does **not** prove that historical `InventoryEvent` facts are complete enough to override a CloudKit-conflicted aggregate. No production conflict test may call the ledger authoritative until this task passes.

- [ ] **Step 1: Freeze the reconstruction invariant and audit vocabulary**

Write the audit header and define:

```text
Canonical ledger = InventoryLedger.read().events after equivalent retry deduplication,
                   complete two-leg correction validation, and explicit key-alias normalization.

Reconstructed quantity(key) = sum(deltaQuantity) for canonical events mapped to key.

Ledger-complete state = no unreadable/conflicting/orphaned ledger defect, and for every
                        logical collection position reconstructed quantity equals the
                        intended committed ownership quantity.
```

The audit table must have these columns:

```markdown
| Mutation path | Production entry point | Aggregate effect | Required event/activity facts | Idempotency key owner | Transaction/rollback boundary | Alias/correction behavior | Reconstruction test | Result |
```

Classify results as `PASS`, `FAIL`, `NOT OWNERSHIP-MUTATING`, or `LEGACY BASELINE ONLY`. Do not mark a direct `quantity =`, `+=`, or `-=` assignment as a failure merely because it is direct; prove whether matching event facts are staged and committed atomically around it.

- [ ] **Step 2: Enumerate every production quantity mutation path from source**

At minimum inspect and record all call sites/assignments in:

1. ordinary scanner/catalog add and rescan through `CollectionStore.add`;
2. manual quantity adjustment through `setQuantity`;
3. graded adds through `addGraded` and `addScannedGraded`, including certified nonaggregation;
4. sealed adds through `addSealed`;
5. remove-one, remove-all, activity-scoped remove, and any bulk delete/reset path;
6. undo/reversal and `RemovedCardSnapshot` restoration/reinsertion;
7. `CollectionCSV.apply`, including insert, merge, certified duplicate, skipped/failing row, batch save, and retry;
8. identity `rekey`/`mergeCollectionRows` and alias consolidation;
9. both `recordVariantCorrection` flows and their `.from`/`.to` legs;
10. `MagicTreatmentMigration` rekey/collision merge, including `canonicalRow.quantity += sourceQuantity`;
11. `PortfolioEpoch.establishIfNeeded` for pre-ledger existing collections;
12. `repairQuantityMismatches` itself;
13. any test/debug/normalization path compiled into the release target that can persist a `CollectedCard.quantity` change.

Use `rg` to generate a source appendix, then manually trace wrappers and transaction boundaries. The audit must name the owning public/internal entry point, not only the line containing an assignment. If new paths are found, add them; this list is a minimum, not a waiver.

- [ ] **Step 3: Write failing end-to-end reconstruction tests through production entry points**

For every supported mutating row, build an isolated persistent SwiftData fixture and:

1. establish a valid initial state/epoch;
2. invoke the real production entry point;
3. commit using the real save boundary;
4. destroy and reopen the container;
5. read `InventoryLedger.read()` and fail on any defect;
6. normalize legacy/canonical aliases exactly as production reconciliation does;
7. compare `InventoryLedger.quantities(from:)` with `LogicalCollection.project` quantities;
8. rerun the same operation/retry path and prove its documented idempotency behavior;
9. inject a save/error before commit and prove both aggregate and ledger roll back together.

Special assertions:

- a correction contributes equal/opposite complete legs and never a partial net change;
- rekey/merge changes identity keys without creating or losing ownership quantity;
- certified duplicates remain one owned physical item and do not emit a second acquisition;
- import row retry cannot double event quantity;
- undo/restore references real prior events and cannot be applied twice;
- treatment migration preserves total quantity across old/new key aliases;
- an existing pre-ledger collection becomes reconstructible only through one deterministic `initialBalance` per logical position;
- an unreadable, conflicting-idempotency, or orphaned-correction ledger refuses automatic aggregate repair.

Include a mixed workflow test that performs scan add → manual adjustment → CSV merge → variant/treatment correction → remove → undo → restart, then proves the full logical projection from event facts alone.

- [ ] **Step 4: Resolve gaps with the smallest transactional fix**

For each failure:

1. preserve the failing test;
2. identify the first production boundary that owns both aggregate and ledger mutation;
3. stage a durable event/activity fact with a stable operation ID before changing aggregate quantity;
4. save once at the existing transaction boundary;
5. roll back all staged facts and aggregate changes together on failure;
6. preserve CSV/export, graded/sealed, and alias semantics;
7. rerun the single row, its retry, its rollback injection, and the mixed workflow.

Do not paper over missing history by synthesizing a new event from the conflicted aggregate during automatic sync repair. `repairQuantityMismatches` may remain an explicit user/support reconciliation tool, but rename/restrict/document it if necessary so production conflict code cannot mistake “make ledger agree with aggregate” for “rebuild aggregate from authoritative facts.”

- [ ] **Step 5: Implement and test the one permitted automatic repair direction**

Only after all supported mutation rows pass, add or select a narrowly named repair operation whose input is the defect-free canonical ledger and whose output updates the mutable aggregate projection to those quantities. Acceptance requires:

- no automatic repair when ledger defects exist;
- no automatic repair when baseline/restoration completeness is unresolved;
- deterministic alias normalization;
- no new ownership event for the repair itself, because that would change the authoritative facts being projected;
- one transaction, idempotent rerun, and restart persistence;
- explicit handling for ledger quantity zero (remove aggregate row only under the defined ownership rule, never because a remote import is incomplete);
- activity/history remains intelligible and is not fabricated as a user ownership action.

If the current model cannot rebuild safely without inventing facts, leave aggregate repair disabled, record G3/G4 failed, and stop the concurrent-same-record CloudKit claim. Do not downgrade this task to documentation-only.

- [ ] **Step 6: Run the completeness gate and dependent suites**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/OwnershipLedgerCompletenessTests \
  -only-testing:TradingCardScannerTests/CollectionActivityHistoryTests \
  -only-testing:TradingCardScannerTests/PortfolioReconciliationTests \
  -only-testing:TradingCardScannerTests/ImportedItemKindTests \
  -only-testing:TradingCardScannerTests/MagicTreatmentTests
```

Expected: every supported audit row passes reconstruction, retry, rollback, and restart checks; no ledger defect is automatically converted into certainty.

- [ ] **Step 7: Sign off the audit and commit**

The audit must include source commit, commands, named tests, discovered gaps/fixes, and an explicit conclusion:

```text
InventoryEvent is approved / not approved as automatic aggregate-repair authority
for the exact mutation paths and schema at <commit>.
```

Any later production change that adds or alters a quantity mutation path invalidates this sign-off and requires a new audit row/test before RC certification.

```bash
git add docs/release/ownership-ledger-completeness-audit.md \
  docs/release/phase-1-integrity-evidence.md \
  TradingCardScanner/Services/InventoryLedger.swift \
  TradingCardScanner/Services/CollectionStore.swift \
  TradingCardScanner/Services/CollectionCSV.swift \
  TradingCardScanner/Services/MagicTreatmentMigration.swift \
  TradingCardScanner/Services/PortfolioEpoch.swift \
  TradingCardScannerTests/OwnershipLedgerCompletenessTests.swift \
  TradingCardScanner.xcodeproj/project.pbxproj
git commit -m "test: prove ownership ledger completeness"
```

### Task 13: Add redacted, user-exportable storage and sync diagnostics

**Files:**
- Modify: `TradingCardScanner/Services/CollectionStoreDigest.swift`
- Modify: `TradingCardScanner/Views/ScannerSettingsView.swift`
- Create: `TradingCardScannerTests/CollectionSyncDiagnosticsTests.swift`
- Modify: `TradingCardScanner.xcodeproj/project.pbxproj`
- Modify: `docs/legal/support.md`
- Modify: `docs/release/phase-1-integrity-evidence.md`

- [ ] **Step 1: Write redaction and determinism tests**

Define:

```swift
struct CloudSyncDiagnosticsSnapshot: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var appVersion: String
    var buildNumber: String
    var osVersion: String
    var deviceClass: String
    var storageModeRaw: String
    var cloudAccountStatusRaw: String
    var attachmentStateRaw: String
    var storeIDSuffix: String
    var digest: CollectionStoreDigest
    var lastBootstrapErrorCategory: String?
    var generatedAt: Date
}
```

Tests must assert the JSON contains no card name, set name, collector number, certificate ID, container/account record ID, vendor credential, URL query, local artwork filename/path, or full UUID. Test the same logical store produces stable counts/hash independent of insertion order.

- [ ] **Step 2: Implement diagnostics from typed state**

Requirements:

- diagnostic values come from bootstrap state and the digester, not parsed UI text;
- error is a stable coarse category, not an `NSError` dump;
- app version/build/OS/device class are included;
- exact device model may be omitted if unnecessary;
- export is explicit and user initiated;
- do not transmit automatically;
- do not write the export permanently unless the share/file exporter requires a temporary file, and remove temporary output after completion where possible.

- [ ] **Step 3: Add Settings export**

Under `Developer & Diagnostics`, add `Export Sync Diagnostics`. Make the export available only when a store is ready; otherwise show the current coarse bootstrap state directly. Label the export as redacted and suitable for support.

- [ ] **Step 4: Verify diagnostics can investigate required failures**

Using fixtures, prove a support report can distinguish:

- local-only due to no account;
- temporary account unavailability;
- changed-account suspension;
- remote-anchor conflict;
- store recovery failure;
- divergent record counts/digest;
- app/build mismatch.

It does not need to identify which card differs. A user can separately choose to send a CSV only with explicit consent.

- [ ] **Step 5: Run tests and commit**

```bash
xcodebuild test \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -only-testing:TradingCardScannerTests/CollectionStoreDigestTests \
  -only-testing:TradingCardScannerTests/CollectionSyncDiagnosticsTests

git add TradingCardScanner/Services/CollectionStoreDigest.swift \
  TradingCardScanner/Views/ScannerSettingsView.swift \
  TradingCardScannerTests/CollectionSyncDiagnosticsTests.swift \
  TradingCardScanner.xcodeproj/project.pbxproj \
  docs/legal/support.md docs/release/phase-1-integrity-evidence.md
git commit -m "feat: export redacted sync diagnostics"
```

### Task 14: Initialize, inspect, and promote the production CloudKit schema

**Files:**
- Create: `docs/release/cloudkit-release-matrix.md`
- Modify: `docs/release/cloudkit-compatibility-audit.md`
- Modify: `docs/release/phase-1-integrity-evidence.md`

This task changes external CloudKit state. It requires the owner prerequisites in §5. Production promotion is intentionally late because Production schema is constrained to additive evolution.

- [ ] **Step 1: Re-run the compatibility gate from a clean source tree**

```bash
git status --short
./scripts/audit_cloudkit_schema.sh
```

Expected: only intentional evidence changes are present and the audit passes. Build the entitled app and rerun `CloudKitSchemaCompatibilityTests` before touching the dashboard.

- [ ] **Step 2: Initialize the Development schema with the exact model**

Install/run an entitled Development build using `iCloud.com.seankeller.CardScanner`. Exercise one insert/update for every synced model and claim the private `CardScannerCollectionAnchor`. Confirm the app remains usable with the system iCloud account available.

- [ ] **Step 3: Inspect Development schema field by field**

In CloudKit Console/Dashboard, record:

- container identifier and Development environment;
- SwiftData-generated record types for all five synced models;
- `CardScannerCollectionAnchor`, its three base fields, and any additional readiness field explicitly selected and documented by Task 4;
- field types and optionality;
- relationship/reference fields and inverse expectations;
- indexes/queryability SwiftData or the anchor needs;
- absence of local-only model record types;
- absence of custom artwork/image assets;
- absence of an unintended duplicate/legacy container.

Copy the result into `cloudkit-compatibility-audit.md` and attach screenshots outside the Markdown file if they contain account identifiers; redact before committing.

- [ ] **Step 4: Run a Development smoke before promotion**

On two clean physical-device installs signed for Development:

1. create representative data on device A;
2. wait for device B to converge;
3. compare redacted digest/counts;
4. make one change on B;
5. verify A converges;
6. confirm custom artwork does not sync and disclosure is accurate;
7. confirm local-only portfolio history does not sync and is rebuilt/represented honestly.

Any deterministic divergence or schema error returns to the owning code task before promotion.

- [ ] **Step 5: Promote Development schema to Production**

Promote only after Steps 1–4 pass. Record:

- operator;
- date/time;
- source commit SHA;
- build number used for initialization;
- exact container;
- promoted record types/fields/indexes;
- dashboard confirmation.

Do not initialize a different schema after promotion and describe it as the release schema.

- [ ] **Step 6: Prove the App Store/TestFlight environment uses Production**

Inspect the archive provisioning/entitlements and install a TestFlight build. Create a unique nonprivate test fixture, then verify it appears only in the Production environment and converges to a second TestFlight device. Development-environment success is not release evidence.

- [ ] **Step 7: Create the release matrix before executing it**

Create `docs/release/cloudkit-release-matrix.md` with columns:

```markdown
| ID | Build | Device A/OS | Device B/OS | Account state | Preconditions/digest | Action | Expected | Observed | Final A digest | Final B digest | Result | Evidence |
```

Add all Task 15 rows as `NOT RUN` before testing. Commit the blank matrix and schema record:

```bash
git add docs/release/cloudkit-compatibility-audit.md \
  docs/release/cloudkit-release-matrix.md \
  docs/release/phase-1-integrity-evidence.md
git commit -m "docs: record production CloudKit schema"
```

### Task 15: Execute the production CloudKit continuity and conflict matrix

**Files:**
- Modify: `docs/release/cloudkit-release-matrix.md`
- Modify: `docs/release/phase-1-integrity-evidence.md`
- Modify production/tests only when a reproduced defect requires a fix

Use the exact TestFlight candidate on physical devices. Simulator-only CloudKit evidence cannot pass this task.

Prerequisites: Task 4 has selected one storage/readiness architecture, Task 12 has approved `InventoryEvent` for the exact mutation paths under test, and Task 14 has promoted/verified the intended Production schema. If Task 12 did not approve automatic ledger authority, same-record quantity conflicts are expected NO-GO rows—not permission to synthesize repair events from an arbitrary aggregate winner.

- [ ] **Step 1: Establish a controlled baseline**

- both devices use the same intended iCloud account;
- both run the same TestFlight build;
- custom artwork is absent or separately noted;
- allow the store to quiesce;
- export digest/counts on both;
- verify storeID suffix, five entity counts, total quantity, and hash agree.

- [ ] **Step 2: Run availability and attachment transitions**

Execute and record separately:

1. genuinely fresh/empty install with account A available and no remote anchor: attach/claim automatically with no confirmation;
2. genuinely fresh install with account A available and an existing remote anchor: adopt automatically but show restoring until readiness is affirmative;
3. clean install with no iCloud account, create local structured data, terminate/relaunch;
4. sign into iCloud later: because local user data now exists, require confirmation, then verify the same local storeID/data remains and appears on device B;
5. temporary loss of network with local edits, then reconnect;
6. iCloud status temporarily unavailable/restricted where reproducible; no new/empty store may appear;
7. account A → account B, cancel/defer; no upload to B and local collection remains intact through the Task 4-proven suspension path;
8. account A → new empty account B, explicitly confirm; anchor is claimed once and collection uploads/converges;
9. account A → account B that already has a different anchor; app blocks automatic merge and preserves both collections;
10. return to account A; original collection identity and digest are restored/continued according to the selected store path.

- [ ] **Step 3: Run independent/offline mutation rows**

Execute:

- add different cards on A and B while one/both are offline;
- rescan/increment different existing rows;
- add raw, graded, and sealed rows;
- import a small CSV on one device;
- correct a variant/print run on one device;
- create price/product-identity updates on both;
- reconnect in controlled orders A-first and B-first.

Expected: immutable event/activity facts converge as a union; collection quantity and identities converge; final digest is arrival-order independent for the same logical facts.

- [ ] **Step 4: Run same-record conflict rows**

From the same starting digest, execute on separate devices before either receives the other change:

- both increment the same aggregate card;
- one increments while the other decrements;
- conflicting identity/variant corrections;
- two different valid price observations with ordered source clocks;
- equal source clock with changed value;
- ProductIdentity match versus negative/miss result;
- CollectionActivity `resolvedQuantity` conflict if that state is reachable.

Expected:

- no valid ownership mutation disappears;
- the Task 12-approved defect-free canonical `InventoryEvent` projection rebuilds aggregate quantity without appending synthetic conflict facts;
- conflicting identity evidence remains explicit or deterministically fails closed;
- newest valid price evidence wins according to source semantics, not upload arrival;
- duplicate logical keys are reconciled by application rules;
- final digests converge.

- [ ] **Step 5: Run delete-versus-edit and retry rows**

Execute:

- remove on A while editing/incrementing on B;
- delete a price/identity record while B refreshes it;
- interrupt the app immediately after a collection save;
- kill network during upload;
- relaunch repeatedly while CloudKit retries;
- repeat a correction operation with the same idempotency key;
- trigger simultaneous first-anchor claim from two devices.

Expected: no zombie card, silent quantity loss, duplicate ledger leg, duplicate anchor, or inconsistent activity. If platform merge behavior violates an invariant, implement a deterministic application repair and rerun the exact row plus its reverse arrival order.

- [ ] **Step 6: Run reinstall restoration**

On device B:

1. record current digest;
2. delete the app;
3. reinstall the same TestFlight build;
4. use the same iCloud account;
5. record every readiness transition and its evidence while delaying/interfering with import;
6. assert ordinary collection/empty-state UI remains unavailable while readiness is checking/importing;
7. after the proven readiness signal, export digest.

Expected:

- all structured model counts/quantity/hash converge;
- remote `storeID` is adopted;
- custom artwork is absent and accurately disclosed;
- device-local portfolio history is absent/rebuilt without being presented as synced history;
- the app never briefly presents an authoritative empty collection as restoration completes;
- no fixed timeout, including the existing 120-second portfolio grace, causes readiness;
- repeat the row against a genuinely empty remote collection and prove `readyEmpty` comes from affirmative anchor/import evidence rather than zero fetched rows.

- [ ] **Step 7: Cross-check CSV portability**

Export basic collection CSV from both converged devices. Normalize only documented nondeterministic formatting. Verify supported structured collection identity/quantity fields agree. CSV is a portability check, not a substitute for the five-model digest.

- [ ] **Step 8: Resolve every matrix failure before signing off**

For each failed row:

- reproduce with a minimal fixture/test when technically possible;
- add a failing regression test;
- fix in the owning service without broad schema change;
- rerun the row in both arrival orders;
- rerun relevant automated suites;
- update matrix from `FAIL` only with new observed evidence.

Any unresolved G4 result is automatic NO-GO.

- [ ] **Step 9: Commit completed matrix**

```bash
git add docs/release/cloudkit-release-matrix.md docs/release/phase-1-integrity-evidence.md
git commit -m "test: certify production CloudKit continuity"
```

### Task 16: Execute the frozen scanner trust and physical-device acceptance program

**Files:**
- Modify: `docs/benchmarks/trust-adversarial-benchmark.md`
- Create: `docs/benchmarks/trust-normal-release-corpus.md`
- Create: `docs/benchmarks/scanner-device-matrix.md`
- Modify: `docs/release/phase-1-integrity-evidence.md`
- Modify production/tests only for reproduced defects

- [ ] **Step 1: Run a 30–50-card measurement pilot**

Use pilot cards only to validate procedure, outcome definitions, instrumentation, timing, and ground-truth recording. Exclude pilot results from the release corpus. Freeze the final corpus and thresholds before seeing release results.

- [ ] **Step 2: Freeze the 500-card normal corpus**

Create `trust-normal-release-corpus.md` with pre-established ground truth and distribution across:

- Pokémon and Magic within actual supported scope;
- eras/sets/layouts represented in normal use;
- languages the app claims to support;
- ordinary, foil/reverse, named-treatment, print-run, graded, and sealed cases in realistic proportions;
- normal sleeves/toploaders and normal indoor lighting.

Each distinct physical card receives one primary trial under a fixed procedure. Record no more private card data than is required for reproducible internal ground truth.

- [ ] **Step 3: Apply the frozen normal-corpus rules**

Release thresholds:

```text
confidently wrong exact identity: <= 1 / 500
safe outcome (correct automatic or appropriate intervention/review): >= 99%
exact autonomous resolution on normal supported cards: >= 95%
complete no-result rate: <= 3%
```

Root-cause every confidently wrong result. Any deterministic implementation cause becomes G1/G2 and blocks release regardless of aggregate allowance.

- [ ] **Step 4: Execute the 150–250-card adversarial corpus**

Include:

- same-art reprints;
- similar collector numbers;
- 1st Edition/Unlimited and Shadowless distinctions;
- reverse/holo/Poké Ball/Master Ball cases;
- Magic reprints/treatments/content kinds;
- Japanese/English ambiguity within supported scope;
- promos, glare, sleeves/toploaders, partial obstruction, low light, and unusual supported layouts.

For two or more distinct confidently wrong results from the same stochastic failure family, require one explicit decision: mitigation, intentional intervention/abstention, supported-scope narrowing, or documented low-exposure acceptance supported by the normal corpus.

- [ ] **Step 5: Run physical iPhone scanner flows**

On a supported iPhone with the exact candidate:

- clean install and camera allow/deny/Settings recovery;
- first scan and repeated scans;
- Collection mode save/undo/duplicate handling;
- Price Check mode with proof it does not mutate collection;
- raw, graded label, and sealed flows;
- variant/finish/print-run ambiguity and manual resolution;
- offline catalog/provider failure and recovery;
- background/foreground, interruption, cold termination/relaunch;
- rapid stacked cards and stale-session fencing;
- portrait orientation and rotation transitions actually supported by iPhone UI;
- 15-minute sustained scan session with thermal/memory observation;
- time to usable result distribution.

- [ ] **Step 6: Run physical iPad scanner and adaptive UI flows**

On a supported iPad:

- repeat the critical scanner flows;
- test portrait, upside-down portrait, and both landscape orientations declared in `Info.plist`;
- verify camera preview orientation, crop/guide alignment, overlays, sheets, split/regular-width Collection navigation, Settings, import/export, and keyboard/pointer basics;
- confirm no compact-width assumption corrupts scanner purpose or save behavior.

- [ ] **Step 7: Record performance and failure categories**

Record p50/p95 time to usable result, no-result/intervention rates, thermal symptoms, and memory warnings. Throughput is not competitor-relative launch arithmetic, but a reproducible critical-flow stall/deadlock is G6.

- [ ] **Step 8: Fix only gate violations and rerun affected evidence**

Any code change invalidates affected corpus/device evidence. Do not patch the scanner after a corpus miss and retain pre-patch results. Freeze a new candidate and rerun the impacted corpus portion according to the framework.

- [ ] **Step 9: Commit benchmark records**

```bash
git add docs/benchmarks/trust-normal-release-corpus.md \
  docs/benchmarks/trust-adversarial-benchmark.md \
  docs/benchmarks/scanner-device-matrix.md \
  docs/release/phase-1-integrity-evidence.md
git commit -m "test: record scanner launch acceptance"
```

### Task 17: Complete App Store-specific product, privacy, and universal-device review

**Files:**
- Create: `docs/release/app-store-1.0-submission-checklist.md`
- Modify: `TradingCardScanner/Info.plist` only if review finds a concrete issue
- Modify: `TradingCardScanner/Assets.xcassets` only if required assets are incomplete
- Modify: `docs/release/phase-1-integrity-evidence.md`

- [ ] **Step 1: Run the Swift/iOS App Store review workflow**

Use the `swift-hig-appstore-review` skill against the exact candidate. Review:

- camera permission timing and purpose string;
- empty, loading, offline, error, recovery, and account-conflict states;
- iPhone/iPad navigation and orientation;
- Dynamic Type, VoiceOver labels/order, contrast, tap targets, Reduce Motion, and keyboard/pointer support where applicable;
- destructive collection deletion confirmation and recovery expectations;
- external links and marketplace disclosure;
- account requirement (none in 1.0);
- incomplete/debug/developer surfaces in Release;
- use of third-party trademarks/card artwork and review-note context;
- Settings clarity around iCloud and device-local data.

Only Blocker/High findings tied to launch scope are automatic implementation candidates. Triage lower findings with R1/R2/R3 and actual containment.

- [ ] **Step 2: Verify app completeness and assets**

Check:

- AppIcon has every required slot and no alpha where prohibited;
- launch screen is valid;
- display name is final and consistent;
- no placeholder text, sample collection, debug route, test credential, or development URL ships;
- camera usage description accurately covers scanning and centering;
- background modes match actual use;
- export/import document types work;
- PrivacyInfo.xcprivacy is present in the archive;
- Release uses production configuration and no `DEBUG`/performance fixtures.

- [ ] **Step 3: Complete App Store Connect privacy/metadata worksheet**

Record final answers for:

- App Privacy/data collection based on actual 1.0 behavior;
- tracking: no;
- privacy-policy URL;
- support URL;
- age rating/content declarations;
- encryption/export compliance;
- iCloud use;
- camera use;
- third-party content/marketplace links;
- free price tier and absence of IAP;
- supported devices/OS;
- review contact.

Do not copy `NSPrivacyCollectedDataTypes = []` into App Store Connect without reconciling CloudKit and provider requests against Apple’s current definitions.

- [ ] **Step 4: Prepare review notes**

Review notes must state:

- CardScanner 1.0 is free and has no login/IAP;
- Collection and Price Check scanner modes and how to reach them;
- camera permission purpose;
- structured collection data uses the user’s private iCloud database;
- custom artwork and value history are device-local;
- how to exercise CSV import/export;
- any provider key is optional and where functionality degrades without it;
- how to reproduce storage/account conflict UI if a review path exists;
- backend/catalog services required for review are available.

- [ ] **Step 5: Capture production screenshots from the candidate**

Capture current required iPhone and iPad sizes from the exact release UI. Screenshots must show real current functionality only; do not advertise Place, Verify, Collection Health, Pro, Grade/Sell, or binder-page recognition. Inspect for incorrect card identity, personal inventory, API keys, account data, or debug overlays before upload.

- [ ] **Step 6: Verify public links and support readiness**

Open both production URLs from the candidate on iPhone and iPad. Confirm support contact works and policy content matches `docs/legal`. Broken or inaccessible links are G5.

- [ ] **Step 7: Record and commit**

```bash
git add docs/release/app-store-1.0-submission-checklist.md \
  docs/release/phase-1-integrity-evidence.md \
  TradingCardScanner/Info.plist TradingCardScanner/Assets.xcassets
git commit -m "docs: complete app store submission review"
```

Do not stage asset/plist paths if they were unchanged.

### Task 18: Freeze, archive, TestFlight-test, and certify the exact release candidate

**Files:**
- Modify: `docs/release/phase-1-integrity-evidence.md`
- Modify: `docs/release/app-store-1.0-submission-checklist.md`
- No product source changes after freeze

- [ ] **Step 1: Clear every gate before naming an RC**

The evidence ledger must show:

- Phase 0 contract/scorecard frozen;
- G1–G6 pass;
- CloudKit compatibility audit pass in an entitled host;
- selected Path 0/A/B no-fork architecture pass, with rejected complexity absent from production;
- restoration-readiness proof passes for both empty and nonempty remote collections without a timeout;
- ownership-ledger completeness audit approves the exact candidate’s mutation paths and automatic repair direction;
- Production schema promoted;
- production two-device matrix pass;
- normal/adversarial scanner criteria pass;
- physical iPhone/iPad pass;
- privacy/support pages deployed and in-app links pass;
- App Store worksheet/review notes/screenshots ready;
- residual risks classified with rationale and actual mitigation where R2 is claimed.

- [ ] **Step 2: Run two clean full-suite passes from the intended RC commit**

Start from a clean worktree and one frozen SHA. Use a new derived-data path per run.

```bash
git status --short
git rev-parse HEAD
./scripts/audit_cloudkit_schema.sh

xcodebuild build-for-testing \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -derivedDataPath /private/tmp/cardscanner-rc-pass1 \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO

xcodebuild test-without-building \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$CARD_SCANNER_SIMULATOR_ID" \
  -derivedDataPath /private/tmp/cardscanner-rc-pass1 \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO
```

Repeat with `/private/tmp/cardscanner-rc-pass2`. Expected: both suites succeed with identical discovered test counts and no unexplained skip/failure. Record `.xcresult` paths and summaries.

- [ ] **Step 3: Create the signed archive from the same SHA**

```bash
xcodebuild clean archive \
  -project TradingCardScanner.xcodeproj \
  -scheme TradingCardScanner \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath /private/tmp/CardScanner-1.0.xcarchive
```

Expected: archive succeeds under the intended App Store team/profile. Record archive SHA linkage, version/build, signing certificate, provisioning profile UUID, and archive path.

- [ ] **Step 4: Inspect the actual archived app**

Inspect—not the source settings, the archive:

```bash
plutil -p /private/tmp/CardScanner-1.0.xcarchive/Products/Applications/TradingCardScanner.app/Info.plist
codesign -d --entitlements :- /private/tmp/CardScanner-1.0.xcarchive/Products/Applications/TradingCardScanner.app
find /private/tmp/CardScanner-1.0.xcarchive/Products/Applications/TradingCardScanner.app -name 'PrivacyInfo.xcprivacy' -print
```

Verify:

- bundle ID `com.seankeller.CardScanner`;
- correct version/build;
- minimum OS/device family/orientations;
- exact iCloud container and CloudKit entitlement;
- no Sign in with Apple entitlement;
- expected background modes;
- camera purpose string;
- production privacy/support URLs;
- privacy manifest bundled;
- no unexpected frameworks, debug assets, credentials, or local entitlement.

- [ ] **Step 5: Upload the archive and install the exact TestFlight build**

Do not rebuild between archive inspection and upload. After App Store processing, verify displayed bundle/version/build match the archive. Install on the matrix iPhone and iPad.

- [ ] **Step 6: Rerun the TestFlight critical smoke on both devices**

At minimum:

- clean launch with iCloud available;
- fresh empty attachment occurs automatically, while a reinstall against nonempty cloud data remains in restoring state until the proven readiness signal;
- launch with network unavailable then recover;
- scan→resolve/intervene→Collection save;
- Price Check without collection mutation;
- terminate/relaunch persistence;
- import/export;
- current pricing/portfolio consistency;
- privacy/support links;
- storage status and artwork disclosure;
- A→B structured sync and matching digest;
- custom artwork remains local;
- account-switch confirmation/conflict path;
- reinstall restoration on one device if the TestFlight build differs from the matrix build.

Expected: all pass on the exact uploaded build.

- [ ] **Step 7: Freeze the RC and invalidate changed evidence correctly**

Record the final commit SHA and build number. From this point:

- documentation-only evidence corrections may proceed if they do not change the binary;
- any source, model, schema, entitlement, build setting, privacy manifest, Info.plist, asset, or dependency change creates a new RC;
- rerun every gate affected by that change;
- never cherry-pick a “small fix” into the shipping branch while retaining old device/CloudKit/corpus evidence.

- [ ] **Step 8: Make the final GO/NO-GO decision**

GO requires all hard gates passed and no unresolved contradiction between source, Production CloudKit, public policy, metadata, and the uploaded binary. If NO-GO, name the exact failed gate and the evidence needed to clear it; do not replace the frozen rule with a subjective readiness score.

- [ ] **Step 9: Commit final evidence**

```bash
git add docs/release/phase-1-integrity-evidence.md \
  docs/release/app-store-1.0-submission-checklist.md
git commit -m "release: certify CardScanner 1.0 candidate"
```

## 8. Dependency order and safe parallelism

```text
Task 1 baseline
  ├── Task 2 Phase 0/document freeze
  └── Task 3 pure storage policy

Stage E0 — no paid enrollment required
  Task 3
    ├── Task 4A local control + Path 0/readiness harness
    ├── Task 5 source/local schema audit
    ├── Task 6 manifest + digest
    └── Task 7 protocol/mock tests

Gate E1 — owner enrollment and product identity
  Register App ID + CloudKit container + signing/capabilities
  Execute Task 9 Steps 3–4 capability/identifier setup
  Inspect the signed test host

Stage E2 — entitled proof
  Task 4B Path 0 first + restoration readiness
    ├── complete Task 5 entitled schema construction
    └── complete Task 7 production account + anchor integration
          └── Task 8 bootstrap
                └── finish Task 9 Sign in with Apple removal/settings/tests
                      ├── Task 10 privacy/support
                      ├── Task 11 deterministic integrity
                      ├── Task 12 ledger completeness authority gate
                      └── Task 13 diagnostics
                            └── Task 14 schema promotion
                                  └── Task 15 production CloudKit matrix

Task 16 scanner acceptance preparation may begin after Task 11; final execution uses the frozen RC.
Task 17 App Store review may begin after Task 10 and must finish against the RC.
Task 18 depends on every prior hard gate.
```

Safe parallelism is intentionally narrow:

- Phase 0 documentation and pure storage-policy tests may proceed independently after baseline.
- Task 4A/5-local/6/7-mock can proceed before enrollment, but none may be represented as entitled CloudKit proof.
- Privacy/support source content may be drafted while storage implementation is underway, but its final claims wait for actual data-flow verification.
- Scanner corpus preparation may proceed before CloudKit promotion, but the acceptance run must use the exact candidate.
- Production CloudKit promotion, account switching, and archive certification are sequential because each consumes the preceding artifact as evidence.

## 9. Residual-risk classification

For a finding that does not trip G1–G6, record:

1. user impact;
2. realistic launch exposure;
3. recoverability;
4. diagnosability;
5. actual containment available in this app;
6. fix/validation effort and regression risk;
7. cost of delaying first public use.

Then assign:

- **R1 — fix before launch**: benefit clearly exceeds delay/regression cost;
- **R2 — ship with actual mitigation**: a concrete tested workaround/containment exists;
- **R3 — accept and backlog**: sufficiently low impact/exposure to ship without special mitigation.

“Monitor it” is not R2 when no telemetry, remote switch, repair tool, or safe workaround exists.

## 10. Definition of done

### Phase 0 complete

- the retention hypothesis is versioned and frozen;
- event semantics, cohort, window, thresholds, falsifiers, and privacy rules are explicit;
- the active strategy/gap/release documents no longer prescribe Integrity WTP or paid 1.0;
- the scorecard can measure `repeat_verify_after_change` later without collecting private inventory details;
- Grade/Sell monetization is explicitly separate.

### App Store-critical Phase 1 complete

- no known silent material integrity defect remains in G1–G4 scope;
- one canonical local collection identity survives supported iCloud transitions;
- the selected always-cloud/reconfiguration/migration path is the simplest architecture that passed the full physical-device proof, and rejected transition complexity is absent from production code;
- fresh empty installs attach automatically, while pre-existing local user data requires confirmation before first/new-account upload;
- a changed account cannot receive the collection without explicit confirmation;
- a different remote collection is never silently merged;
- genuinely empty cloud state is separated from incomplete restoration by an affirmative readiness signal; no timeout or empty fetch makes that decision;
- all five synced models pass the named CloudKit audit;
- every supported ownership mutation passes the ledger-completeness audit before ledger facts drive automatic aggregate repair;
- Production schema is deployed and the exact TestFlight build converges on physical iPhone/iPad;
- device-local artwork/history boundaries are accurate and visible;
- privacy manifest, policy, support, and App Store declarations match the binary;
- scanner statistical and deterministic gates pass;
- two clean full suites and exact-archive/TestFlight smoke pass from one frozen SHA;
- release evidence names every result and no required gate is merely assumed.

## 11. Explicit stop conditions

Stop implementation and report the blocker rather than improvising if:

- the current user-owned changes cannot be safely preserved;
- there is insufficient disk for reproducible build/archive work and only destructive broad cleanup would free it;
- the registered App ID/container differs from the approved identifiers;
- the selected SwiftData transition cannot keep one store identity through no-account/account-change behavior;
- the one-store Path 0 experiment or its selected fallback cannot preserve local writes through no-account/offline/reconnect;
- the system can upload local data to a changed account before confirmation;
- the app cannot distinguish a genuinely empty cloud collection from an unfinished import without a timeout;
- any supported quantity mutation lacks complete durable/idempotent event facts, or a ledger defect can trigger automatic aggregate repair;
- a CloudKit schema incompatibility requires a destructive Production change;
- Production schema cannot be promoted or the archive points at Development;
- a two-device conflict loses a valid ownership mutation;
- public privacy/support URLs are unavailable;
- the exact TestFlight binary cannot be tied to the tested SHA/archive;
- a hard gate remains failed.

## 12. Implementation notes for later phases

Do not add future physical-inventory schema in this release merely to “prepare.” The correct Phase 2 holding/copy/placement migration remains the next structural plan after public 1.0. This release contributes only foundations that are independently necessary now:

- a trustworthy canonical store identity;
- proven CloudKit schema/continuity;
- redacted diagnostics;
- an accurate privacy boundary;
- a frozen retention experiment.

The future model must still avoid attaching binder/page/slot to aggregated `CollectedCard`, and future behavioral analytics must not repurpose detailed `CollectionActivity` as uploaded telemetry.

## 13. Primary references

- Apple, [Syncing model data across a person’s devices](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices): CloudKit capability/background remote notifications, schema constraints, and production promotion.
- Apple, [Creating a Core Data model for CloudKit](https://developer.apple.com/documentation/coredata/creating-a-core-data-model-for-cloudkit): no unique constraints, optional relationships with inverses, no deny delete rule, and additive Production evolution.
- Apple, [`CKContainer.accountStatus()`](https://developer.apple.com/documentation/cloudkit/ckcontainer/accountstatus%28completionhandler%3A%29): check account before private-database access and recheck after account-change notification.
- Apple, [`CKAccountChangedNotification`](https://developer.apple.com/documentation/cloudkit/ckaccountchangednotification): notification arrives on an arbitrary queue and requires a new status check.
- Apple, [`NSPersistentCloudKitContainer.eventChangedNotification`](https://developer.apple.com/documentation/coredata/nspersistentcloudkitcontainer/eventchangednotification): Core Data publishes setup/import/export event details; Task 4 must prove whether this is sufficiently observable and ordered for the exact SwiftData store before relying on it.
- Apple, [Deploying an iCloud container’s schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema): App Store builds use Production and require schema deployment.
- Apple, [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/): privacy-policy link in App Store metadata and within the app, complete/broken-link requirements, and accurate metadata.
- Apple, [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy): required iOS privacy-policy URL and accurate App Privacy responses.
- Apple, [Required-reason API: file timestamp](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype): `C617.1` for app-container file timestamp access.

## 14. Plan self-review

Before accepting this document as executable, the author verified:

- every substantive product-owner correction has a task and a hard gate;
- Phase 0 has no Integrity price/WTP threshold;
- free 1.0 has no purchase/restore implementation task;
- condition is explicitly classified from current schema reality;
- CloudKit constraints are audited before schema deployment;
- Path 0 always-CloudKit local-replica behavior is tested before any `.none`↔CloudKit transition architecture;
- local fallback/account switch cannot pass without continuity proof;
- fresh-empty automatic attachment is distinct from confirmation before uploading an existing local collection;
- Apple Developer enrollment is an explicit E1 dependency gate rather than an unexpected mid-task blocker;
- remote restoration cannot become authoritative from an empty fetch or elapsed-time heuristic;
- ledger completeness is a named gate grounded in every current production quantity mutation path;
- privacy/support links exist both publicly and in-app;
- custom artwork and value-history sync boundaries are explicit;
- current dirty-tree work is preserved;
- every production-code task begins with a failing focused test or proof gate;
- commands state expected outcomes;
- later tasks use the same type names introduced earlier;
- no Place/Verify/Reconcile/Collection Health work leaked into launch scope;
- no section contains an unresolved placeholder marker or an invented production URL/account credential.
