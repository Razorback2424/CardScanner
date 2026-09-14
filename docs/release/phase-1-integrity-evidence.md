# CardScanner 1.0 Phase 0/1 Release Evidence

This ledger is the authoritative evidence record for the Phase 0 retention
freeze and App Store-critical Phase 1 work. An unexecuted gate is explicitly
`NOT RUN`; source inspection, a successful container construction, an empty
fetch, or an elapsed timeout is not evidence of CloudKit restoration.

## Candidate identity

- Implementation branch: `main`
- Baseline source SHA: `a115e4ee40dfaab93672e7601b358d82183df6be`
- Current candidate SHA: `8cc1ad1` — the frozen A2a hardening commit.
- Marketing version/build: `1.0 (1)` at baseline; re-check before archive.
- Target: `TradingCardScanner` / `TradingCardScannerTests`
- Minimum OS: iOS/iPadOS 17.0
- Device families: iPhone and iPad (`1,2`)

## Environment and signing identity

- Evidence timestamp: 2026-09-14; refreshed after the post-review verification pass.
- Xcode: 26.6 (17F113).
- Internal filesystem free space at baseline: approximately 2.5 GiB.
- Disposable build directory: `/Volumes/Keller Family Photos/.codex-cardscanner-build`.
- Structured-store compatibility path: explicit `Application Support/default.store`
  and `PortfolioLocal.store`, preserving the pre-bootstrap SwiftData locations;
  the new `CardScanner/CollectionStorage` directory holds the manifest and
  opaque store-file identity sidecars.
- CoreSimulator status: `AVAILABLE — iOS 26.5 simulator; focused storage suites
  and the full Debug suite were executed during the remediation pass.`
- Apple Developer / App ID / CloudKit enrollment: `NOT RUN — owner-controlled
  prerequisite; exact production identity has not been supplied or inspected.`
- Production signing identity and provisioning profile: `NOT RUN`.

## Pre-plan checkout

- A2a started from a clean `main` checkout at `1ed7223`; no unrelated
  working-tree changes were present or folded into this implementation.
- The two planning documents referenced by the prior ledger remain outside the
  A2a change set.

## Automated baseline

- `git diff --check`: PASS on the implementation working tree.
- Branch/HEAD inspection at A2a start: PASS; clean `main` at `1ed7223`.
- `xcodebuild -version`: PASS; recorded above.
- `xcodebuild build-for-testing`: `BLOCKED — the external disposable derived
  data path was used, but actool could not connect to CoreSimulatorService and
  the host had no discoverable simulator runtime.`
- Production and test source typechecks: `PASS` using Swift 5 mode with the
  Debug and Release conditional paths, plus the complete XCTest source set.
  The app-level storage-generation fence covers scanner writes, CSV import,
  catalog normalization, store-revision/derived-state work, background price
  refresh, and Magic treatment migration; stale continuations and refresh gates
  are discarded after account/store invalidation.
- XCTest source module check: `PASS` — all `TradingCardScannerTests/*.swift`
  typechecked against the freshly emitted app module; this is compile evidence,
  not a substitute for XCTest execution.
- Historical full test suite: `EXECUTED — 1,205 tests; 45 failures at the
  pre-remediation baseline and 43 in the prior remediation pass. That run was
  not the A2a acceptance run; its unrelated failures included centering
  corpus/fixture suites, source-path-reading tests, the diagnostics date
  strategy mismatch, and two tracked ownership-ledger assertions. The
  diagnostics mismatch is corrected in the A2a test set below.

## Current remediation-pass verification

- Debug no-signing `build-for-testing`: `PASS` — app and XCTest sources compile
  with the Debug `LOCAL_ONLY_SIGNING` path; no new warnings were introduced.
- DebugProduction `build-for-testing`/test build: `PASS` — the production
  entitlements and bundle identity are retained while the compiler receives
  `DEBUG` without `LOCAL_ONLY_SIGNING`.
- Release no-signing app-target build: `BLOCKED ON HOST CAPACITY` — the
  current hardening candidate reached the final `lipo` step, but the host had
  only 165 MiB free. The prior A2a candidate's Release compile passed; rerun
  this check after reclaiming build-cache space before archive.
- A2a storage-suite execution: `PASS` — the same nine CloudKit/storage suites
  ran under both configurations: `CloudAccountProbeTests`,
  `CloudCollectionAnchorStoreTests`, `CloudKitSchemaCompatibilityTests`,
  `CloudRestorationReadinessTests`, `CollectionStorageBootstrapTests`,
  `CollectionStoragePolicyTests`, `CollectionStoreContinuityTests`,
  `CollectionStoreDigestTests`, and `CollectionSyncDiagnosticsTests`.
  `Debug`: 94 tests, 0 failures. `DebugProduction`: 95 tests, 1 explicit
  entitlement-gated skip, 0 failures.

## A2 §0 event-correlation spike

- Run identity: `main` at `1ed7223`, iOS 26.5 simulator, iPhone 17 Pro
  (`EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`), with the real production CloudKit
  entitlements and `LOCAL_ONLY_SIGNING` removed for the temporary test run.
- Procedure: a `NotificationCenter` observer for
  `NSPersistentCloudKitContainer.eventChangedNotification` was registered
  before constructing the real two-configuration container through
  `CollectionStorageBootstrapDependencies.makeContainer(paths:mode:.cloudKit)`;
  the process then observed the store for 20 seconds.
- Observed: `2` notifications, both with event identifier
  `54AB2C5E-4048-44C6-A645-2AA250F316A0`, setup type (`rawValue: 0`), and
  store identifier `07398AAA-9DE6-4FBD-8C44-A73A1C091B89`. The first was
  in-progress (`endDate = nil`, `succeeded = false`, no error); the second was
  completed with `succeeded = false` and an error. The set of distinct
  `storeIdentifier` values had cardinality `1`.
- Verdict: `GO for A2a` correlation implementation. The singleton rule is
  demonstrated for this process shape; a second distinct store identifier
  must fail closed. This is not A2b restoration evidence: the simulator had
  `CKAccountStatusNoAccount`, and no successful import event was observed.

## A2a production restoration-readiness proof

- Contract: `PASS` — the one-shot source is replaced by an armed,
  notification-backed probe; arming occurs before `makeContainer`, and a
  `defer` cancels the probe on every exit path, including throwing container
  construction. Cancellation is idempotent and `deinit` removes observers.
- Reducer: `PASS` — events are redacted to UUID/type/store identifier/start and
  end dates/success/error category, bounded to 64 retained events, and reduced
  only after a successful completed import plus a fresh post-import visibility
  snapshot. Setup/export, empty fetches, failed/in-progress imports, wrong
  stores, stale generations, and multiple singleton identifiers cannot
  authorize readiness; there is no timeout, clock, or elapsed-time path.
- Re-entry and visibility: `PASS` — a scripted bootstrap progression from
  checking to importing to ready requires three sequential readiness calls; the
  probe retains one `AsyncStream` iterator. The default visibility snapshot
  counts rows across all five synced models (`CollectedCard`, `PriceRecord`,
  `ProductIdentity`, `CollectionActivity`, and `InventoryEvent`), so a
  history-only collection is not treated as empty merely because it has zero
  cards. `allowReadyEmpty` remains disabled by default pending A2b proof.
- Anchor/checkpoint: `PASS` — the non-empty anchor generation is threaded from
  the authoritative anchor read into the request and persisted checkpoint;
  missing generations fail closed, and the readiness enum no longer carries a
  second generation value. `currentMechanismVersion` is `3`, so mechanism-2
  checkpoints are rejected by the existing checkpoint policy.
- Production default: `INTENTIONALLY UNPROVEN` —
  `UnprovenCloudRestorationReadinessSource` remains the default until A2b
  enrollment and the device matrix prove the event/readiness contract.
- A2a verdict: `GO to land the production-shaped implementation and tests;
  NO-GO for automatic cloud restoration and Phase 1 release certification.`

## Phase 0 document freeze

- Retention contract: `PASS — frozen in
  docs/experiments/collection-integrity-v1-retention-contract.md`.
- Privacy-safe scorecard: `PASS — frozen in
  docs/experiments/collection-integrity-v1-scorecard.md`.
- Strategy/release/website reconciliation: `PASS — active documents now
  describe a free 1.0 and the canonical /support route; commit pending.`
- Phase 0 behavioral observations: `NOT RUN — future cohort activity.`

## Deterministic integrity gates G1–G6

| Gate | Status | Evidence |
| --- | --- | --- |
| G1 — Identity | SOURCE PASS; RUNTIME PARTIAL | Full Debug XCTest execution ran 1,205 tests but is not clean because of the documented unrelated failures; no storage-suite failures occurred. |
| G2 — Valuation | SOURCE PASS; RUNTIME PARTIAL | Full Debug XCTest execution ran 1,205 tests but is not clean because of the documented unrelated failures; no storage-suite failures occurred. |
| G3 — Quantity/data | SOURCE PASS; RUNTIME PARTIAL | Full Debug XCTest execution ran 1,205 tests but is not clean because of the documented unrelated failures; no storage-suite failures occurred. |
| G4 — Persistence/sync continuity | SOURCE PARTIAL; A2a PASS; EXTERNAL NOT RUN | Source now rejects cached-empty authority, requires a current anchor generation for cached populated state, separates absent/journal/identity-corrupt replicas, rotates identity at physical store replacement before container construction, keeps readiness authority checkpoint-only, validates anchor claim readback, and fences same-process headless reuse without constructing a non-authoritative second container. The armed reducer is covered by deterministic tests, but production remains on the unproven source and live remote-generation/entitled-device matrix evidence is still missing. |
| G5 — Privacy/compliance | SOURCE PASS; PUBLIC LINK/ASC NOT RUN | Privacy manifest, source disclosures, Settings surface, and redacted diagnostics are implemented; final URLs and App Store metadata remain owner inputs. |
| G6 — Availability | SOURCE PARTIAL; A2a STORAGE PASS | Fresh-process background storage now requires a persisted proven tuple, current anchor/generation validation, and a live generation fence; while G4 readiness is unproven, matching populated checkpoints are validated then skipped without constructing a non-authoritative container. Active foreground sessions are reused and transitions skip safely. Physical-device execution remains unavailable. |

## CloudKit compatibility audit

- Source prohibition audit: `PASS — scripts/audit_cloudkit_schema.sh`.
- Local five-model schema construction: `RUNTIME PASS — the real two-
  configuration container constructed on the iOS 26.5 simulator; setup events
  were observed and the singleton store identifier was recorded above.`
- Entitled host/container construction: `BLOCKED — external enrollment`.
- Production schema field-by-field audit: `BLOCKED — external enrollment`.

## CloudKit production schema

- Development schema initialization: `BLOCKED — external enrollment`.
- Development schema inspection: `BLOCKED — external enrollment`.
- Production promotion: `BLOCKED — external enrollment`.

## CloudKit continuity and two-device matrix

- Path 0 local control: `NOT RUN`.
- Legacy unnamed-store discovery: `NOT RUN`.
- Restoration-readiness observability: `§0 PASS; A2a SOURCE/TEST PASS — the
  observer receives SwiftData-backed CloudKit events and resolves the proven
  singleton process shape; the reducer, post-import row-visibility boundary,
  anchor-generation checkpoint threading, and lifecycle fencing are covered by
  deterministic tests. The production dependency remains
  `UnprovenCloudRestorationReadinessSource` until A2b; live account/remote-
  generation semantics and entitled-device proof are not run.`
- Entitled account/anchor proof: `BLOCKED — external enrollment`.
- Physical iPhone/iPad two-device convergence: `BLOCKED — physical devices
  and external enrollment required`.

## A2 scope limits that remain on the Phase 1 exit checklist

- `localOnlyTransitionProven` remains hardcoded `false` outside
  `LOCAL_ONLY_SIGNING`. Consequently no-account, restricted-account,
  iCloud-unavailable, and “Keep on Device” launches remain blocked in
  production. A green A2 result proves only the cloud path; it is not a Phase 1
  exit.
- The headless preflight still unconditionally returns `nil` behind its G4
  gate in `CollectionStorageBootstrap.swift` (the gate comment is near the
  populated-checkpoint branch). When A2b lands, that gate must be re-evaluated
  or production background sessions remain unavailable even after foreground
  restoration is proven.

## Scanner normal/adversarial evidence

- 30–50-card measurement pilot: `NOT RUN`.
- Frozen 500-card normal corpus: `NOT RUN`.
- 150–250-card adversarial corpus: `NOT RUN`.

## iPhone and iPad rendered/device checks

- Exact candidate iPhone smoke: `NOT RUN`.
- Exact candidate iPad smoke: `NOT RUN`.
- Camera/provider/foreground recovery: `NOT RUN`.

## Privacy, support, and App Store metadata

- In-app Privacy & Support surface: `SOURCE PASS — top-level Settings category
  and exact artwork disclosure are present.`
- Privacy manifest source audit: `PASS — UserDefaults CA92.1 and File Timestamp
  C617.1 are present.`
- Public privacy URL: `BLOCKED — final product domain not supplied.`
- Public support URL: `BLOCKED — final product domain/contact channel not supplied.`
- App Store Connect privacy worksheet: `NOT RUN`.

## Archive and TestFlight binary inspection

- Release archive: `NOT RUN — signing/enrollment and disk prerequisites.`
- Archive entitlement inspection: `NOT RUN`.
- Exact TestFlight upload/install smoke: `NOT RUN`.

## Residual risks and R1/R2/R3 decisions

- R1: canonical-store/account/readiness proof must be complete before claiming
  automatic iCloud restoration.
- R1: the privacy/support production URLs and final signed entitlements must
  match the shipped binary.
- R2/R3 decisions: `NOT MADE`; do not classify an unresolved hard gate as a
  residual risk.

## Final GO/NO-GO sign-off

- A2a: `GO — implementation, correlation spike, and both production-shaped
  storage test runs are complete.`
- A2b: `NOT RUN — E1–E5 and E9 remain NOT RUN in
  docs/release/cloudkit-release-matrix.md; enrollment, exact signed candidate,
  and iPhone/iPad proof are required before swapping the production default.`
- Phase 1/release: `NO-GO — the non-cloud transition remains deliberately
  blocked, the headless G4 gate remains, and external enrollment, public-link,
  archive, and TestFlight gates are outstanding.`
