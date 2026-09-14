# CardScanner 1.0 Phase 0/1 Release Evidence

This ledger is the authoritative evidence record for the Phase 0 retention
freeze and App Store-critical Phase 1 work. An unexecuted gate is explicitly
`NOT RUN`; source inspection, a successful container construction, an empty
fetch, or an elapsed timeout is not evidence of CloudKit restoration.

## Candidate identity

- Implementation branch: `fix/app-review-preflight`
- Baseline source SHA: `a115e4ee40dfaab93672e7601b358d82183df6be`
- Current candidate SHA: working tree on `fix/app-review-preflight`; record the
  final commit SHA before archive.
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

## User-owned pre-plan changes

These working-tree changes existed before implementation began and remain
unstaged unless explicitly listed in a later commit:

- `docs/superpowers/plans/2026-09-13-phase-0-phase-1-app-store-launch.md`
- `docs/vision/collection-integrity-codebase-gap-analysis.md`

They were not reset, overwritten, or folded into a product-code change.

## Automated baseline

- `git diff --check`: PASS on the implementation working tree.
- Branch/HEAD inspection: PASS; `main` at `a115e4e` before the implementation
  branch was created.
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
- Full test suite: `EXECUTED — 1,205 tests; 45 failures at the pre-remediation
  baseline and 43 with these fixes. The remaining failures are pre-existing and
  unrelated: centering-corpus/fixture suites, three source-path-reading tests
  that resolve relative to `/` under `xcodebuild`, a `CollectionSyncDiagnostics`
  date-encoding-strategy mismatch, and two tracked
  `OwnershipLedgerCompletenessTests` assertions. Storage-suite failures: zero.`

## Current remediation-pass verification

- Debug no-signing `build-for-testing`: `PASS` — app and XCTest sources compile
  with the Debug `LOCAL_ONLY_SIGNING` path; no new warnings were introduced.
- Release no-signing app-target build: `PASS` — the production no-flag branch
  compiles.
- Focused storage XCTest execution: `PASS` — 59 tests, 0 failures across
  `CollectionStoragePolicyTests`, `CollectionStoreContinuityTests`,
  `CollectionStorageBootstrapTests`, `CloudCollectionAnchorStoreTests`, and
  `CloudRestorationReadinessTests`.
- Full Debug XCTest execution: `EXECUTED` — 1,205 tests; 45 failures at
  baseline and 43 with these fixes, with zero failures in the storage suites.
- Release no-flag XCTest coverage: `FOLLOW-UP REQUIRED` — Release does not set
  `ENABLE_TESTABILITY`, so `@testable import TradingCardScanner` cannot resolve
  the Release module. Add a `DebugProduction` configuration with testability
  enabled and without `LOCAL_ONLY_SIGNING`; do not change shipping Release.

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
| G4 — Persistence/sync continuity | SOURCE FAIL/PARTIAL; EXTERNAL NOT RUN | Source now rejects cached-empty authority, requires a current anchor generation for cached populated state, separates absent/journal/identity-corrupt replicas, rotates identity at physical store replacement before container construction, keeps readiness authority checkpoint-only, validates anchor claim readback, and fences same-process headless reuse without constructing a non-authoritative second container. The production restoration observer/readiness mechanism, live remote-generation semantics, and entitled physical-device matrix remain unproven. |
| G5 — Privacy/compliance | SOURCE PASS; PUBLIC LINK/ASC NOT RUN | Privacy manifest, source disclosures, Settings surface, and redacted diagnostics are implemented; final URLs and App Store metadata remain owner inputs. |
| G6 — Availability | SOURCE PARTIAL; RUNTIME PARTIAL | Fresh-process background storage now requires a persisted proven tuple, current anchor/generation validation, and a live generation fence; while G4 readiness is unproven, matching populated checkpoints are validated then skipped without constructing a non-authoritative container. Active foreground sessions are reused and transitions skip safely. Full-suite Debug XCTest ran but was not clean; physical-device execution remains unavailable. |

## CloudKit compatibility audit

- Source prohibition audit: `PASS — scripts/audit_cloudkit_schema.sh`.
- Local five-model schema construction: `SOURCE PASS; RUNTIME NOT RUN —
  direct source typecheck passed; runtime construction awaits a supported host.`
- Entitled host/container construction: `BLOCKED — external enrollment`.
- Production schema field-by-field audit: `BLOCKED — external enrollment`.

## CloudKit production schema

- Development schema initialization: `BLOCKED — external enrollment`.
- Development schema inspection: `BLOCKED — external enrollment`.
- Production promotion: `BLOCKED — external enrollment`.

## CloudKit continuity and two-device matrix

- Path 0 local control: `NOT RUN`.
- Legacy unnamed-store discovery: `NOT RUN`.
- Restoration-readiness observability: `SOURCE FAIL — the production dependency
  remains `UnprovenCloudRestorationReadinessSource`; the required event observer,
  empty/nonempty handshake, row-visibility boundary, live remote-generation
  update protocol, and entitled-device proof are not complete. The source guard
  is deliberately fail-closed.`
- Entitled account/anchor proof: `BLOCKED — external enrollment`.
- Physical iPhone/iPad two-device convergence: `BLOCKED — physical devices
  and external enrollment required`.

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

`NO-GO — source-level restoration readiness and ledger-authority work is not yet
complete, and runtime evidence is unavailable. The release cannot be certified
until the selected storage architecture and live remote-generation protocol are
proven on entitled devices, the restoration mechanism is implemented, the
production ledger matrix executes, and the external enrollment, public-link,
archive, and TestFlight gates run against one frozen SHA.`
