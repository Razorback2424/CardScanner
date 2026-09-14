# CardScanner 1.0 Phase 0/1 Release Evidence

This ledger is the authoritative evidence record for the Phase 0 retention
freeze and App Store-critical Phase 1 work. An unexecuted gate is explicitly
`NOT RUN`; source inspection, a successful container construction, an empty
fetch, or an elapsed timeout is not evidence of CloudKit restoration.

## Candidate identity

- Implementation branch: `main`
- Baseline source SHA: `a115e4ee40dfaab93672e7601b358d82183df6be`
- Current candidate SHA: `d049706` — the A4a on-device transition proof
  implementation commit; it is based on the frozen A2a hardening SHA
  `8cc1ad1`.
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

## A4 §0 on-device mode-transition spike

- Run identity: `main` based on frozen A2a SHA `8cc1ad1`, iOS 26.5 simulator,
  iPhone 17 Pro (`EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86`), DebugProduction,
  with no iCloud account signed in. The permanent regression is
  `TradingCardScannerTests/CollectionStoreModeTransitionTests.swift`.
- S0: `PASS` — the real two-configuration
  `CollectionStorageBootstrapDependencies.makeContainer(paths:mode:.cloudKit)`
  constructed successfully with the private configuration and no iCloud
  account.
- S1: `PASS` — the `.none` fixture contained one row in each synced model,
  quantity `2`, and material digest
  `d39c8c27b1df9b3e7c47df33f5aa9ef9a4d43ab543cc7184d765af3f61fd2ae5` before
  and after the first `.private` open. The SQLite table list before was
  `ACHANGE, ATRANSACTION, ATRANSACTIONSTRING, ZCOLLECTEDCARD,
  ZCOLLECTIONACTIVITY, ZINVENTORYEVENT, ZLOCALARTWORKOVERRIDE,
  ZPORTFOLIODAILYCLOSE, ZPRICECHECKDAY, ZPRICEOBSERVATION, ZPRICERECORD,
  ZPRODUCTIDENTITY, ZREFERENCEQUOTE, Z_METADATA, Z_MODELCACHE, Z_PRIMARYKEY`.
  After `.private`, it was the same list plus
  `ANSCKDATABASEMETADATA, ANSCKEVENT, ANSCKEXPORTEDOBJECT,
  ANSCKEXPORTMETADATA, ANSCKEXPORTOPERATION, ANSCKHISTORYANALYZERSTATE,
  ANSCKIMPORTOPERATION, ANSCKIMPORTPENDINGRELATIONSHIP, ANSCKMETADATAENTRY,
  ANSCKMIRROREDRELATIONSHIP, ANSCKMIRROREDRELATIONSHIPSYSTEMFIELDSASSET,
  ANSCKRECORDMETADATA, ANSCKRECORDMETADATAENCODEDRECORDASSET,
  ANSCKRECORDMETADATASYSTEMFIELDSASSET, ANSCKRECORDZONEMETADATA,
  ANSCKRECORDZONEMETADATAENCODEDSHAREASSET, ANSCKRECORDZONEMOVERECEIPT,
  ANSCKRECORDZONEQUERY`; the aggregate store-artifact byte count changed from
  `172032` to `670584`.
- S2: `PASS` — `.private` → `.none` retained all five counts, total quantity
  `2`, and material digest
  `906f9f5cbe71a92b0bb34853db93de05b99d68355d655213a1d89279a544cb87` exactly.
- S3: `PASS` — the `.none` → `.none` close/reopen control retained all five
  counts, total quantity `2`, and material digest
  `53179e31c092f7563d1266c1ba9ebfb51b2887fe24791479a60a4589500f3d65`.
- S4: `PASS` — `.none` → `.private` → `.none` retained all five counts, total
  quantity `2`, and material digest
  `3483aee1bf1fb8aea73a7a6cfd8957b90604e5e5ac60a2a84044f7ec263b68af` at all
  three boundaries.
- S5: `PASS` — the structured-store URL remained unchanged and present, the
  manifest sidecar identity stayed
  `613c184ee6a368f7857899594af51946b852c5c0eec4e2ac947d7cd907639735`, and
  the digest stayed at all three boundaries with material digest
  `761635ef499933313a5e3df80dd81dbd70594bc3280889013eae7b10fa4e13ed`.
- S6: `PASS` — fixture A written in `.none` and fixture B written in
  `.private` were both present after reopening `.none`: two rows in each synced
  model, total quantity `5`, material digest
  `f2ee687cd1924e7bef41f8b9c6aefcc738054d1ce1c9aab5a3a2adeb73227c34`.
- Verdict: `GO — Option A`. S2–S6 all passed, so the shared store is safe to
  reopen with mirroring enabled or disabled. The production kill-switch can be
  removed; Option B is not warranted, and the store URL must not be split.

## A4a on-device transition implementation

- Selected implementation: `Option A`. `localOnlyTransitionProven` was
  removed from policy inputs, bootstrap dependencies, and the local-open,
  keep-on-device, and container paths. `blockUnprovenTransition` remains for
  corrupt manifests, orphaned journals, missing or mismatched store identity,
  and other actual continuity hazards.
- Entitlement decoupling: every remaining `LOCAL_ONLY_SIGNING` site is about
  the absence of a CloudKit entitlement — inert account/anchor providers,
  rejection of a CloudKit-backed configuration, or background container-mode
  selection. No remaining site decides whether reopening the shared SQLite
  store on-device is safe.
- Foreground availability: the shipping-shaped bootstrap now reaches a local
  ready session for no-account, restricted, temporarily unavailable,
  could-not-determine, fresh-install/no-account, and Keep on Device paths. The
  existing attachment bookkeeping remains unchanged: a never-attached store
  stays `neverAttached`, while an attached store opened locally becomes
  `suspended`; transient account failure does not overwrite its last attached
  account fingerprint.
- Headless availability: a persisted non-attached replica is now eligible for
  an authoritative on-device session in every build configuration. An attached
  replica still remains behind the separate G4 cloud-proof gate and returns
  `nil` until A2b proves that path.
- UI truthfulness: Settings now renders collection storage mode, iCloud account
  state, and attachment state. Temporarily unavailable local fallback has a
  distinct visibly-unverified message from no-account local storage.
- Verification: the expanded storage suite (the nine A2 storage suites plus
  the permanent mode-transition and support-surface suites) passed on the
  iPhone 17 Pro / iOS 26.5 simulator. `DebugProduction`: `113` passed,
  `0` failed, `0` skipped. `Debug`: `109` passed, `0` failed, with the five
  private-mode S1/S2/S4/S5/S6 cases explicitly skipped because the unentitled
  build cannot construct a CloudKit-backed configuration. The mode-transition
  regression itself passed all `7/7` cases under `DebugProduction`.
- A4a verdict: `GO to land the offline implementation and tests; NO-GO for
  Phase 1 certification`. A4a removes the deterministic G6 availability
  block, but it does not retire G4 or authorize automatic cloud restoration.

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
| G6 — Availability | SOURCE PASS; A4a OFFLINE PASS; EXTERNAL NOT RUN | A4a proves the shared store can be reopened on-device after `.none`/`.private` transitions and removes the compilation-coupled local-only kill-switch. Foreground no-account, restricted, temporarily unavailable, could-not-determine, fresh-install, and Keep on Device paths open locally; non-attached headless replicas can be reused. Attached populated checkpoints remain behind the separate G4 cloud-proof gate. Physical-device execution and L1–L4 remain unavailable. |

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

- Path 0 local control: `A4 §0 PASS — the permanent disk-backed S0–S6
  transition regression passed under DebugProduction; the physical-device
  E3/L1–L4 runs remain NOT RUN.`
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

## A2/A4 scope limits that remain on the Phase 1 exit checklist

- A4a proved the shared `.none`/`.private` store transition and removed the
  deterministic non-cloud availability block. It does not prove CloudKit
  restoration, account fencing, remote-generation continuity, or the physical
  E3/L1–L4 matrix. A green A4a result is not a Phase 1 exit.
- `LOCAL_ONLY_SIGNING` is now an entitlement-only build condition. The
  unentitled build still cannot construct a CloudKit-backed container or use a
  live account/anchor probe; this is separate from the proven local transition.
- The headless preflight now returns a session for a proven non-attached local
  replica. It still unconditionally returns `nil` for the attached populated
  checkpoint branch behind the G4 gate in `CollectionStorageBootstrap.swift`.
  When A2b lands, that gate must be re-evaluated or attached production
  background sessions remain unavailable even after foreground restoration is
  proven.
- A2b remains intentionally unlanded: `UnprovenCloudRestorationReadinessSource`
  is still the production default, and the live E1–E5/E9 device matrix is
  outstanding.

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
- Phase 1/release: `NO-GO — A4a removes the deterministic non-cloud block, but
  the headless attached-replica G4 gate, A2b cloud-restoration proof, physical
  device matrix, external enrollment, public-link, archive, and TestFlight
  gates remain outstanding.`
