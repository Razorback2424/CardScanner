# Production Defect Audit — Pass 2

**Status:** defect-review authority for the 2026-09-14 audit snapshot. It was
audited against `codex/scanning-workflow-review-remediation` at `a4375df` with
a dirty working tree (44 entries, all `Assets.xcassets` PNG binaries). F01–F03
source remediation was subsequently landed and focused-verified on 2026-09-19;
this audit has not been rerun against current `main`.

**Purpose:** a production-readiness defect review of the whole repository. This
is a discovery-and-diagnosis pass. No application code, tests, schemas, or
build settings were changed; this document and its index entries are the only
repository additions.

Pass 1 is preserved at
[`../legacy/defect_review_pass_1.md`](../legacy/defect_review_pass_1.md). Its
D01–D09 findings are a 2026-09-09/10 snapshot and were **not** re-reproduced
here; none of the findings below is a restatement of one of them.

## Candidate identity

| Field | Value |
| --- | --- |
| Branch | `codex/scanning-workflow-review-remediation` |
| HEAD locator | `a4375df` |
| Working tree | Dirty — 44 modified `Assets.xcassets` PNG files; no source changes |
| Production Swift | 74,309 lines |
| Test Swift | 40,084 lines |
| Build | `xcodebuild build-for-testing`, iPhone 17 Pro simulator — **PASS** |
| Full suite | 1,277 executed, 6 skipped, **40 failures**, 47.4 s |

The suite result is consistent with the count recorded in
[`../plans/documentation_audit.md`](../plans/documentation_audit.md) and
[`../../progress.md`](../../progress.md); this audit additionally triages each
failure individually rather than classifying them in aggregate (see F06).

## Result and evidence standard

Six findings: **five confirmed and one suspected**, plus lower-confidence
observations recorded separately.

Severity describes user-visible consequence. Confidence describes whether the
mechanism was demonstrated. These are independent axes, and “confirmed” does
**not** imply that a physical device, an entitled CloudKit container, a live
provider, or a second device was exercised — none was.

Classification vocabulary matches Pass 1:

- **Confirmed; reproduced** — an executed test or run demonstrates the defective
  intermediate result.
- **Confirmed; static** — a deterministic source trace with no contradicting
  runtime path.
- **Suspected** — a concrete failure path exists, but no interleaving that
  reaches it was constructed.

This audit used repository-wide structural screening plus selected deep
end-to-end traces. It is **not a claim that all 74,309 production Swift lines
received equal manual scrutiny.** Coverage and remaining limitations are
recorded in [§ Coverage](#coverage-inspected-without-significant-findings) and
[§ Limits](#limits-of-this-pass). Existing release and audit claims were treated
as hypotheses, not as evidence.

## Prioritized findings

| ID | Severity | Confidence | Classification | Gate | Defect |
| --- | --- | --- | --- | --- | --- |
| F01 | Critical | High | Confirmed; static | G6 (+G4) | Fresh install with an iCloud account reaches an unrecoverable storage-bootstrap state |
| F02 | High | High | Confirmed; static | G4 + G5 | Background refresh opens a CloudKit-mirrored container for an on-device-only store |
| F03 | High | Medium | Suspected; concrete failure path | G3 | Pending-resolution guard can silently discard the user's scan answer |
| F04 | Medium | High | Confirmed; reproduced | Residual | Epoch baseline violates the activity↔ledger invariant and can pause portfolio history |
| F05 | Low | High | Confirmed; reproduced | Residual | `InventoryLedger.quantities(from:)` reports negative ownership; dead code with a stale contract test |
| F06 | Medium | High | Confirmed; reproduced | §3 verification | Duplicate project IDs kept the tracked centering corpus out of the test bundle; the corrected bundle exposes known centering assertion failures |

F03 is ranked above F04 despite lower confidence because its consequence — a
silent unrecorded scan presented as success — is a G3 collection-data-loss
class, whereas F04 withholds derived history rather than corrupting ownership.

Gate references are to
[`../release/card-scanner-1.0-go-no-go-framework.md`](../release/card-scanner-1.0-go-no-go-framework.md)
§2. Recording a gate mapping here is a defect classification, not a GO/NO-GO
determination; that decision belongs to the release framework and its owner.

---

## F01 — Fresh install with an iCloud account cannot reach the app

**Severity:** Critical **Confidence:** High **Classification:** Confirmed; static
**Gate:** G6 deterministic critical-flow availability failure, against critical
flow A (“Clean install → usable app”). Secondarily G4, because the failed
attempt durably mutates the store manifest.

**Location:** `TradingCardScanner/Services/CloudRestorationReadiness.swift:88`,
`UnprovenCloudRestorationProbe.awaitReadiness`; default binding at
`TradingCardScanner/Services/CollectionStorageBootstrap.swift:326`
(`CollectionStorageBootstrapDependencies.production(readinessSource:)`);
consumer at `CollectionStorageBootstrap.swift:1217`–`1243`, `openCloud`
readiness loop; policy entry at
`TradingCardScanner/Services/CollectionStoragePolicy.swift:437`–`441`,
`decideFresh`, and `:465`–`486`, `decideForKnownAccount`; presentation at
`TradingCardScanner/Views/CollectionStorageBootstrapView.swift:59`–`90`, `case .failed` at `:66`.
Application wiring at `TradingCardScanner/App/TradingCardScannerApp.swift:10`,
which constructs `CollectionStorageBootstrap()` with no dependency override.

**Mechanism and trigger:** The shipped dependency graph installs
`UnprovenCloudRestorationReadinessSource` by default. Its probe returns
`.failed(category: "restoration-readiness-not-proven")` unconditionally and by
design — “A missing proof is not a completed empty database.” Every policy
decision that routes to `openCloud` or `adoptRemoteCollection` therefore enters
the readiness loop, matches `case .checking…, .importing…, .failed`, sets
`state = .restoringFromCloud(readiness)`, and returns at the `if case .failed`
guard **without ever calling `installReady`**.

A fresh install on a device signed in to iCloud with anchor `.missing` takes
`decideFresh` → `.openCloud(...)`. An existing install whose manifest
fingerprint matches the current account takes `decideForKnownAccount` →
`.openCloud(...)`. Both reach the same terminal state. Because F01 blocks every
`.attached` transition, `.neverAttached` and `.suspended` are the only manifest
states a real user can hold — which is also the precondition for F02.

**Result and guards:** The user is parked permanently on “iCloud restoration
needs attention.” The only affordance is **Retry**, which calls
`bootstrap.retry()` → `start()` → the identical path → the identical failure.
Unlike `.confirmationRequired`, which offers **Keep on This Device** via
`keepOnDevice()`, the `.restoringFromCloud(.failed)` presentation has no
non-cloud continuation. The app is unusable, and no existing guard converts the
state into a local-storage fallback.

Aggravating: `openCloud` calls
`persistManifest(..., attachmentState: .attached)` at `:1194`–`:1200`, *before*
arming the probe. The failed attempt therefore durably flips the manifest to
`.attached` and is not reverted on failure, which changes later behavior
including the headless path in F02.

**Evidence:** Deterministic source trace through all four links —
default parameter, probe body, readiness loop, and view — plus confirmation
that `TradingCardScannerApp` supplies no override. `LOCAL_ONLY_SIGNING` was
checked against `project.pbxproj`: it is defined only at
`SWIFT_ACTIVE_COMPILATION_CONDITIONS` lines 1031 and 1118, so ordinary Debug and
Release builds compile the entitled branch. No simulator reproduction was
performed, because the failure requires a signed-in iCloud account and the
source path admits no alternative outcome.

**Fix and verification:** Three independent changes.

1. Do not route a policy decision to CloudKit while no readiness mechanism is
   proven. Make “readiness source is unproven” an explicit policy input that
   forces `.openProvenLocal`, or supply a real probe.
2. Independently of (1), make `.restoringFromCloud(.failed)` recoverable by
   offering the same action `keepOnDevice()` already implements. A terminal
   state whose only affordance reproduces itself is never correct, whatever the
   readiness mechanism eventually becomes.
3. Move the `.attached` manifest write to after affirmative readiness, or revert
   it on the failure path.

Verify on a simulator signed in to iCloud: delete the app, reinstall, launch,
and require that the collection opens. Add a bootstrap test that drives
`.failed` readiness and asserts the resulting state exposes a non-cloud
continuation.

**Existing coverage and missing evidence:** No test exercises the production
default. Every storage-suite test injects `FixedCloudRestorationProbe` or an
equivalent, and `usesProductionDependencies` exists specifically to keep
fixtures away from the production graph — so the very guard that protects test
provenance is what allows this wiring to ship unexercised. A test asserting the
readiness source returned by `CollectionStorageBootstrapDependencies.production()`
is missing. Entitled-device and production-container behavior remain out of
scope here and are tracked by
[`../release/cloudkit-compatibility-audit.md`](../release/cloudkit-compatibility-audit.md).

---

## F02 — Background refresh opens a CloudKit-mirrored container for an on-device-only store

**Severity:** High **Confidence:** High **Classification:** Confirmed; static
**Gate:** G4 persistence/sync continuity (an on-device-only store is attached to
an account without confirmation) and G5 privacy (collection contents leave the
device against an explicit user choice).

**Location:** `TradingCardScanner/Services/CollectionStorageBootstrap.swift:545`–`560`,
`CollectionStorageHeadlessPreflightDependencies.production` `backgroundMode`
and its `makeContainer` binding; `:621`–`655`,
`CollectionStorageHeadlessPreflight.prepare`; consumer at
`TradingCardScanner/Services/BackgroundPriceRefresh.swift:174`–`226`.

**Mechanism and trigger:** The background container mode is chosen from the
entitlement alone:

```swift
#if LOCAL_ONLY_SIGNING
let backgroundMode: CollectionStorageMode = .onDevice
#else
let backgroundMode: CollectionStorageMode = .cloudKit   // :549
#endif
```

`makeContainer` is bound to that constant. But the only path in `prepare(...)`
that reaches `makeContainer()` is gated on the opposite condition:

```swift
let useProvenLocalReplica = manifest.attachmentState != .attached   // :621
if !useProvenLocalReplica { ... return nil }                        // :623–641, always nil
guard let container = try? dependencies.makeContainer() else { ... } // :649
let mode: CollectionStorageMode = .onDevice                          // :652
```

So the container is constructed for `.neverAttached` and `.suspended` manifests
— precisely the local-only stores — using
`.private(CloudAccountProbe.containerIdentifier)` in any build that is not
`LOCAL_ONLY_SIGNING`. The session then reports `mode: .onDevice` at `:652`,
which contradicts the container it wraps.

The trigger is a `BGAppRefresh` or `BGProcessing` launch in a **fresh process**
— `mayCreateHeadlessSession` requires
`!isReady && activeStorageSession == nil && !hadSuspendedSession` — on a device
whose manifest is `.neverAttached` (no account, restricted, or iCloud
unavailable at bootstrap) or `.suspended` (the user tapped **Keep on This
Device**). Per F01, this is the only manifest state real users currently hold,
so it is the default population rather than a corner case.

**Result and guards:** SwiftData attaches the collection store to CloudKit
private-database mirroring from a background task and begins uploading
`CollectedCard`, `PriceRecord`, `ProductIdentity`, `CollectionActivity`, and
`InventoryEvent` — directly contradicting an explicit user choice. No guard
downstream re-checks the mode, because the session asserts `.onDevice`.

Secondarily, the headless path never sets
`TradingCardScannerApp.activeStorageMode`, so it retains its `.onDevice`
default. `PortfolioEpoch.establishIfNeeded(isCloudSyncing:)` is then evaluated
against a false premise, and its entire `isAwaitingInitialSync` protection —
written precisely because `CollectedCard` rows and the rows that explain them
are separate record types that can arrive in either order — is disabled on a
container that is in fact mirroring.

**Evidence:** Deterministic source trace. The comment at `:544`–`546`
(“Entitlement selection only: an unentitled background build must use the
on-device configuration”) is correct as far as it goes; the entitled branch
simply has no corresponding manifest check. `BackgroundPriceRefresh.run` was
traced to confirm the container is used for real writes (`refresh.refresh(...)`
and `PortfolioEngine().recomputeAndWait(context:)`), not merely opened.

**Fix and verification:** Give `makeContainer` a mode parameter and pass
`.onDevice` at the `useProvenLocalReplica` call site — the mode the session
already declares. A CloudKit-backed background container, if ever wanted,
belongs only inside the `.attached` branch that currently returns `nil`.
Additionally, set `TradingCardScannerApp.activeStorageMode` from the headless
session so the epoch's cloud gate is not evaluated against a stale default.

Verify by instrumenting the resolved `cloudKitDatabase` and triggering the
background task with the Xcode
`_simulateLaunchForTaskWithIdentifier` debugger command on a device whose
manifest is `.suspended`; assert `.none`.

**Existing coverage and missing evidence:** None. All seven headless tests in
`CollectionStoreContinuityTests` inject their own `makeContainer` closure, so
the production binding is never exercised — the same provenance-guard blind spot
as F01. A regression test should assert that
`CollectionStorageHeadlessPreflightDependencies.production()` yields a
non-CloudKit configuration for a non-`.attached` manifest, or the mode should be
refactored into a value a test can read directly. Whether mirroring actually
begins uploading on an entitled device was not observed and requires the
enrollment tracked by the CloudKit compatibility audit.

---

## F03 — Pending-resolution guard can silently discard the user's scan answer

**Severity:** High **Confidence:** Medium **Classification:** Suspected;
concrete failure path **Gate:** G3 if reachable.

**Location:** `TradingCardScanner/Views/ScannerViewModel.swift:2271`–`2282`,
`beginPendingResolution`; callers at `:1780` (`confirmDuplicate`), `:1906`
(`choose(_ variant:)`), `:1934` (`choose(_ printRun:)`), `:1963`
(`choose(_ candidate:)`).

**Mechanism and trigger:**

```swift
private func beginPendingResolution(requestID: UUID, operation: @escaping () async -> Void) {
    guard !isProcessingIdentification else { return }   // operation never runs
    ...
}
```

Every `choose(...)` handler clears its pending choice *before* calling this —
`pendingChoice = nil` at `:1897`, `pendingPrintRunChoice = nil` at `:1933`,
`pendingIdentityChoice = nil` at `:1962`. If the guard trips, the question has
already left the screen, the operation never runs, nothing is persisted, and
this path never reaches `resumeRecognitionIfPossible()` either.

**Result and guards:** The user taps an answer, the choice bar dismisses as if
accepted, and the card is never written. The scan is lost with a success-shaped
UI. `finishIdentificationRequest` cannot recover it, because
`activeIdentificationRequestID` still refers to the other request.

**Evidence and why it remains suspected:**
`processNextIdentificationIfPossible` guards on all four pending states being
`nil` (`:2249`–`:2254`), so the pipeline should be idle whenever a choice bar is
on screen. I traced every assignment to the four pending-state properties
(`:1439`, `:1593`, `:1753`, `:1779`, `:1786`, `:1897`, `:1924`, `:1933`,
`:1952`, `:1962`, `:2011`, `:2068`, `:2370`, `:2459`, `:2526`, `:2757`–`:2760`,
`:2877`, `:2904`, `:3134`, `:3498`) and could not construct an interleaving that
sets `isProcessingIdentification` while a choice is pending. It may be genuinely
unreachable. It is recorded because the failure mode is silent data loss on the
application's primary action, in a path with at least six interacting state
machines — `heldRepeatAuthorizationState`, `deferredHeldDuplicateOffer`,
`catalogMissVerification`, `spatialResetProofs`, `pendingDuplicateConfirmation`,
and session finalization — where an unreachability argument is expensive to keep
true across changes.

**Fix and verification:** Make the guard fail loudly rather than silently.
Either run the operation anyway with a `diagnostic(...)` record, queue it to run
when the pipeline drains, or restore the pending choice and surface a
`ScanNote`. In all three cases, stop clearing the pending choice before the
operation is known to have been accepted.

Regression test: drive `choose(_ variant:)` with `isProcessingIdentification`
forced true and assert that either the write happens or the pending choice is
restored. Neither currently holds.

**Existing coverage and missing evidence:** `ScannerViewModelTests` covers the
ordinary choose→route→commit path and the cancellation/lifecycle fixes recorded
under C-05 in the documentation audit, but no test drives a choose handler while
an identification is in flight. No physical scanning session was performed.

---

## F04 — Epoch baseline violates the activity↔ledger invariant and can pause portfolio history

**Severity:** Medium **Confidence:** High (mechanism) / Medium (production
reachability) **Classification:** Confirmed; reproduced by an existing red test.

**Location:** `TradingCardScanner/Services/PortfolioEpoch.swift:171`–`190`,
the baseline write loop; invariant at
`TradingCardScanner/Models/CollectionActivity.swift:228`–`258`,
`integrityDefects`; consumer chain at
`TradingCardScanner/Services/PortfolioReplaySnapshot.swift:284`–`288` →
`TradingCardScanner/Services/PortfolioEngine.swift:520`
(`summary.isAuthoritative = summary.defects.isEmpty`) → `:552`–`580`.
Masking dependency at
`TradingCardScanner/Services/CollectionStore.swift:493`–`599`,
`backfillExistingCollectionIfNeeded`, invoked at
`TradingCardScanner/Views/ContentView.swift:186` and `:199`.

**Mechanism and trigger:** `establishIfNeeded` writes one `initialBalance`
`InventoryEvent` per position through `ledger.record(...)` and writes **no**
`CollectionActivity`. `integrityDefects` unions activity keys with event keys
and flags any key where `Σ activity.signedQuantity != Σ event.deltaQuantity`, so
a baselined position with no activity yields `quantityMismatch` — “ledger 4,
activity 0”.

That defect reaches `computation.defects`, sets `isAuthoritative = false`, and
the engine then withholds attribution, pauses history, and publishes or revises
no close. The baseline events are durable, so the condition does not self-heal.

In production the invariant normally holds only because `ContentView`'s startup
`.task` runs `backfillExistingCollectionIfNeeded()` on the line before
`portfolio.start(...)`, and that backfill writes one `.added` activity per card
with `deltaQuantity = card.quantity`, matching the baseline event exactly.

**Result and guards:** That coupling is ordering-only and fails in three
specific ways:

1. The backfill is invoked as `try? CollectionStore(context: modelContext)
   .backfillExistingCollectionIfNeeded()`. A throwing `commit()` at
   `CollectionStore.swift:590` leaves activities unwritten, the error is
   discarded, and `portfolio.start(...)` baselines anyway on the next line.
2. The two are gated by different, independently-lived `UserDefaults` keys —
   `existingCollectionBackfillVersionKey` (per container) versus
   `portfolioEpochStartedAt` (process-wide). Clearing or diverging one does not
   clear the other.
3. `PortfolioEpoch` carries an explicit `isAwaitingInitialSync` deferral with a
   120 s grace, written because `CollectedCard` rows and the rows that explain
   them are separate record types that can arrive in either order.
   `backfillExistingCollectionIfNeeded` has **no equivalent guard** and runs
   unconditionally at view appearance. On a device receiving a CloudKit
   delivery it will synthesize `.added` activities for cards whose real activity
   rows are still in flight; when those arrive there are two activities per key
   and `integrityDefects` reports the mismatch in the other direction. Those
   rows are durable and synced.

Sub-item (3) is **not currently reachable**, because F01 blocks every CloudKit
attachment. It becomes reachable the moment F01 is fixed, which is why it is
recorded in the same finding rather than deferred.

**Evidence:** `OwnershipLedgerCompletenessTests
.testDiskBackedPreLedgerBaselineIsOneDeterministicEventAfterRestart` fails
deterministically at line 330 — confirmed by an isolated
`-only-testing` rerun (0.235 s), so it is not a load flake. Line 330 is the
`assertReconstructed(in:)` call whose four assertions all report the call-site
`#line`; `reading.defects`, `projection.defects`, and the quantity comparison
were each traced and are satisfied for this fixture, leaving
`CollectionActivity.integrityDefects` as the failing assertion.

**Fix and verification:** Write the baseline activity in the same transaction as
the baseline event, so the invariant holds by construction rather than by a
neighbour's side effect. (Teaching `integrityDefects` to exempt `initialBalance`
is the alternative, but writing the row is the honest fix — the activity log is
what the user reads.) Separately, replace the `try?` at `ContentView.swift:186`
and `:199` with a real failure path that does not call `portfolio.start(...)`
after a failed backfill, and give the backfill the same `isAwaitingInitialSync`
deferral before F01 is fixed.

Verify by running the named test unchanged; it must pass without the test adding
activities of its own.

**Existing coverage and missing evidence:** Covered — the test is already red on
this branch. What is missing is any coverage of the ordering dependency itself:
no test asserts that a failed backfill prevents epoch establishment, and no test
exercises the CloudKit arrival-order case in (3), which cannot be exercised
without the enrollment tracked by
[`../release/cloudkit-compatibility-audit.md`](../release/cloudkit-compatibility-audit.md).

---

## F05 — `quantities(from:)` reports negative ownership; dead code with a stale contract test

**Severity:** Low **Confidence:** High **Classification:** Confirmed; reproduced.

**Location:** `TradingCardScanner/Services/InventoryLedger.swift:265`–`275`,
`quantities(from:)`; test at
`TradingCardScannerTests/OwnershipLedgerCompletenessTests.swift:89`.

**Mechanism and trigger:** The reducer filters `$0.value != 0`, so a key whose
events net **negative** is retained and reported as an owned quantity. With a
correction's `from` leg (−2 on `"old"`) and `to` leg (+2 on `"new"`) as the only
input, `result["old"]` is `-2`. The test asserts `nil`.

**Result and guards:** No user impact today: a repository-wide search finds
**zero production callers** of `quantities(from:)`; it is used only by tests. The
function would report negative ownership if it were wired into a projection or
reconciliation path, and the red test is otherwise indistinguishable from real
signal (see F06).

**Evidence:** `OwnershipLedgerCompletenessTests
.testCorrectionRequiresTwoCompleteLegsToPreserveTotalOwnership` fails
deterministically — `("Optional(-2)") is not equal to ("nil")` — confirmed by
isolated rerun (0.135 s).

**Fix and verification:** Either delete the function and its test, or change the
filter to `$0.value > 0` and keep the test as the contract. Do not change the
test to expect `-2`; that would ratify negative ownership as a contract.

A second, unrelated failure in the same suite —
`testSourceInventoryNamesEveryOwnershipEntryPoint` at line 102 — reads
`URL(fileURLWithPath: "TradingCardScanner/Services/CollectionStore.swift")`,
a path relative to the test process's working directory (`/`) rather than
`$SRCROOT`. It can only pass under a runner that happens to set the working
directory to the repository root. Resolve it via `#filePath` or an injected
environment variable.

**Existing coverage and missing evidence:** Fully covered; both are test-truth
problems, not behavior gaps.

---

## F06 — Duplicate project IDs hid the committed centering corpus from tests

**Severity:** Medium **Confidence:** High **Classification:** Confirmed;
reproduced. **Gate:** §3 of the release framework — “A gate cannot be marked
clear merely because nobody happens to have noticed a problem.”

**Location:** `TradingCardScanner.xcodeproj/project.pbxproj`,
`TradingCardScannerTests/OpusImplementationPlanTests.swift`, fixture root
`TestFixtures/TradingCards/`, and the load-sensitive test at
`TradingCardScannerTests/ScannerViewModelTests.swift:654`.

**Mechanism and trigger:** Of 40 failures in the 1,277-test run:

| Suite | Failures | Cause |
| --- | --- | --- |
| `CardCenteringInvariantTests` | 19 | `Bundle.url` could not find HEIC resources in the test bundle |
| `CardCenteringGroundTruthTests` | 8 | same |
| `CenteringProfileDumpTests` | 8 | same |
| `CardCenteringCorpusManifestTests` | 1 | `Bundle.url` could not find the supplementary manifest |
| `OwnershipLedgerCompletenessTests` | 3 | F04 (1), F05 (2) — **substantive** |
| `ScannerViewModelTests` | 1 | load-sensitive flake |

The pass-2 report incorrectly concluded that the `IMG_03xx`/`IMG_07xx` HEICs
and supplementary manifest were absent from the repository. They are checked
in under `TestFixtures/TradingCards/` (57 tracked files). They were absent from
the test bundle because `project.pbxproj` reused `A0020103` for both the fixture
resource build file and `CardFinishRenderPlanTests.swift in Sources`, and reused
`B0020103` for both the fixture folder and that Swift source file. The test
group also referred to an undefined `B0020105` fixture reference. The colliding
resource build-file ID resolved to the Swift source entry, so the fixture folder
was not copied into `TradingCardScannerTests.xctest`.

`ScannerViewModelTests.testCatalogMissVerificationStillFilesUnresolvedCard`
fails at `:654` under suite load (3.976 s) and passes in isolation (1.107 s). It
waits on `model.scanAcknowledgement?.phase == .recognized` with a fixed
`waitUntil` budget that the two-frame confirmation window plus main-actor hops
exceed on a busy machine.

**Result and guards:** A genuine new failure is invisible: F04 and F05 sat
inside a 40-failure list that the current documentation characterises in
aggregate as “unrelated fixture/source-environment or signal-kill failures.”
That characterisation is accurate for the original test run's observed
intermediate failures and wrong for the substantive F04/F05 failures. The
fixture failures were caused by test-bundle wiring, not missing repository
files. The 2026-09-16 run below shows that the centering accuracy and invariant
tests now execute and expose the analyzer failures already recorded in the
[centering contract](../../review/opus-card-centering-implementation-plan.md).

**Correction and follow-up (2026-09-16):** Replaced the two colliding fixture
IDs with unique IDs and repaired the test-group reference in the project file.
The simulator build succeeded. A focused run selected the four centering
suites and produced 38 results: 28 passed, 9 test cases failed on centering
accuracy, invariant, or performance assertions, and 1 profile-dump test was canceled when
the run was intentionally stopped before more generated diagnostics could be
written into the repository. Both
`testRealFixturesAndGroundTruthAreReachableFromTheTestBundle` and
`testCorpusManifestIsCompleteAndCryptographicallyFrozen` passed; completed tests
reported no missing fixture or manifest. The nine failing test cases match the
already documented open centering failures; this was not a clean full-suite
baseline. Its interrupted result bundle is `f06-fixture-copy-20260916.xcresult`
on the external SSD. Seven diagnostic files modified by the run were preserved
there and the tracked repository copies were restored.

**Fix and remaining work:** The test-resource graph is corrected. Do not add
skip guards for the required corpus: its files are repository-owned and now
reach the test bundle. Triage the centering assertion failures against the
centering contract, redirect its diagnostic-dump outputs to external storage,
then complete the selected suites and record a clean or honestly triaged
baseline in
[`../release/phase-1-integrity-evidence.md`](../release/phase-1-integrity-evidence.md).
The `ScannerViewModel` timing flake and substantive F04/F05 findings remain
separate work.

**Existing coverage and missing evidence:** Fixture reachability and manifest
tests now exercise the packaged files. The full exact-candidate suite remains
incomplete and non-clean.

---

## Lower-confidence observations

These have a plausible mechanism but were not demonstrated, and several may be
intentional. They are recorded so they are not rediscovered as novel, not as
claims that the code is wrong.

| ID | Area | Observation | Confidence |
| --- | --- | --- | --- |
| O-01 | `CollectionStore.swift:1008` | `mergeCollectionRows` gates `PriceIdentityLineageMigration.migrate` on `itemKind != .rawCard`, so the treatment-alias merge of two raw Magic rows orphans the predecessor's `PriceRecord`/observations and the merged position reads unpriced until the next refresh. The comment at `:768`–`772` suggests this is intended. | Medium |
| O-02 | `CollectionStore.swift:2517`–`2550` | `catalogAliasCard` matches on `providerID`/`catalogProviderID`, `variantID`, and print run but not `magicTreatmentIDsRaw`, unlike the treatment-aware `uniqueCard(forAnyKey:magicTreatmentIDsRaw:)` immediately above it. Treatments derive from `providerID`, so rows sharing provider and variant should share treatments — but the asymmetry between two lookups in one function is worth confirming. | Low |
| O-03 | `ScannerViewModel.swift:2053` | `undoScan` returns `false` after a durable undo when the storage generation or session changed mid-call. `deleteRecentScan` ignores the result, so there is no user-visible bug today; a future caller that surfaces `false` as “Undo failed” would report the opposite of what happened. | Medium |
| O-04 | `Models/BrowseCatalogModels.swift` | `CatalogCardDisplayGroup.preferredSummary` can `preconditionFailure` in a Release build. `CatalogCardDisplayGrouping.groups(for:)` never produces an empty group, but the memberwise initializer is internal and unguarded. | Medium |
| O-05 | `CollectionStore.swift:906` vs `LogicalCollection.swift:184`–`191` | The merge sets `dateAdded` to `max`, while `chooseRepresentative` selects by `min`. Post-merge the representative no longer holds the oldest acquisition date, which `PortfolioEpoch` passes as `acquiredAt`. Likely harmless, since `CollectionStore.add` already sets `dateAdded = .now` on every re-add. | Low |
| O-06 | `CollectionCSV.swift:1666`, `:1677`, `:1682` | `parseRows` drops all-empty rows without counting them in `skippedRows`, and `escape()` never quotes the `;`/`\t` delimiters that `delimiter(in:)` can select on re-import. Narrow: exports always join on `,` and headers always contain commas. | Medium |
| O-07 | `JustTCGTransport.swift:269` | `perform` consumes the daily reservation before the request, so a network throw still spends quota against a 95/day free tier. Deliberate per the comment (“never optimistically in advance”), but the failure case is not refunded. | High mechanism / intentional? |

---

## Coverage: inspected without significant findings

Recorded so a later pass does not re-derive the same negative results.

- **`Models/Money.swift`** — overflow-reporting arithmetic is complete; the
  `Comparable`/`Equatable` split on `isOverflowed` is deliberate and preserves
  the total-order contract; `init?(rounding:)` bounds are conservatively
  correct at the `Int64` edge.
- **`Services/CardLatch.swift`** — duplicate suppression, absence accounting,
  `advanceObservedClock` watermark shifting, and the in-loop
  `remove(at:)`/`continue` index handling are all correct.
- **`Services/PortfolioCalendar.swift`** — DST-safe boundaries; the half-open
  day contract is correctly implemented and correctly relied upon by the replay
  loop.
- **`Services/PortfolioReplay.swift`, `PortfolioReplayEngine.run`** — the
  forward-cursor merge, tie ordering (old-basis → observation → new-basis), and
  day-closing loop are correct; no path leaves a day unclosed at `through`. The
  `Decimal` division at `:528` is guarded by `before.tenThousandths > 0`.
- **`Services/PriceStore.swift`, `authoritativeRecord`/`isPreferred`** —
  deterministic, invalidation-wins, no price-magnitude dependence.
- **`Services/CardCenteringAnalyzer.swift` force-unwraps** — every
  `.first!`/`.last!`/`[side]!` at `:1779`, `:1780`, `:1808`–`1810`, `:1876`,
  `:2930`, `:3038` was traced. `candidates(_:offset:)` provably returns at least
  one element on every path (`:2099` empty-input synthetic, `:2137` non-empty
  fallback); `innerSets` is a complete four-side literal; and
  `roundedRange`/`clamped` cannot invert given the `width > 20, height > 20`
  guard at `:471`. **No crash risk.** This is a memory-safety result only — see
  the centering contract for its current numerical failures, and F06 for the
  fixture-bundle correction that made those tests reachable.
- **Progress-percentage integer conversions** — `PriceRefreshController.swift:316`,
  `:784`, `:1719` and `CollectionCardDetailView.swift:1822` are each guarded
  against the empty/one-element divisor, so no `Int(NaN)` trap exists.
- **`Dictionary(uniqueKeysWithValues:)` call sites** — all eight verified
  key-unique, including the network-fed
  `PokemonChecklistSnapshot.from(builtSets:)`, whose virtual set ids come from
  the compiled-in print-run table in `BrowseCatalog.printRuns(forSetProviderID:)`.
- **`NotificationCenter` observers** — all five registration sites have matching
  `deinit` removal.
- **`Services/CollectionProjectionActor.swift`** — `rebuild` coalescing,
  retry/`readSucceeded` handling, and the trailing-request loop are correct.
- **`Services/PortfolioEngine.swift`** — `recomputeAndWait`'s double-await
  correctly covers the coalesced trailing replay; `applyPriceDeltas` is a
  correct incremental delta over the retained summary.
- **`Services/ScannedGradedResolver.swift`** — the `group.next()!` at `:81` is
  safe; the group always has two children.
- **The `onObservedCandidate` gate added in `0b4ac34`** — checked specifically
  for the circular dependency it resembles, namely the callback that establishes
  `catalogMissVerification` being gated on that verification already existing.
  It is **not** circular: the key is first installed by `handleLookupFailure` at
  `ScannerViewModel.swift:3327`, and latch-suppressed frames still reach the
  callback because the emission at `CardScanner.swift:1842` precedes the
  `switch decision`. The remediation recorded under C-05 is correct.
- **`Services/QuoteCache.swift`**, **`Services/JustTCGTransport.swift`** request
  construction and 429/Retry-After handling, **`Services/StoreRevisionMonitor.swift`**
  apply-generation coalescing, **`PokemonArtworkFallbacks`** local-asset mapping
  (all 18 mapped set ids have both `_logo` and `_symbol` image sets present).

## Limits of this pass

Stated so these are not mistaken for cleared areas.

- **`Services/CardScanner.swift` camera and session lifecycle.** Roughly 40
  cross-queue hops between `sessionQueue`, `visionQueue`, and the main actor;
  correctness depends on real `AVCaptureSession` and `VNTrackObjectRequest`
  timing. Not audited to the depth of the rest. Device evidence remains RF-2 and
  RF-5 in [`../plans/release_followups.md`](../plans/release_followups.md).
- **`Services/CardCenteringAnalyzer.swift` numerical correctness** (3,445
  lines). The 2026-09-16 focused run exercised the corpus and reproduced the
  already-documented accuracy, invariant, and latency failures; see the
  [centering contract](../../review/opus-card-centering-implementation-plan.md).
  The complete suite was not rerun; see F06 for the test-bundle correction.
- **`Services/MagicTreatmentMigration.swift`** (2,138 lines) — interface level
  only.
- **CloudKit semantics generally.** F01 means no code path currently attaches to
  CloudKit, so every cross-device conflict, ordering, and merge behavior in the
  five synced models is unexercised. F04(3) is one instance of a broader surface
  that activates the moment F01 is fixed.
- **`Services/PriceRefreshController.swift` fallback and graded sections**
  (~1,200 lines). The cancellation and `storageContinuation` discipline appears
  uniformly applied, but not every partial-failure interleaving was traced.
- **No physical device, entitled CloudKit container, live provider call, second
  device, or real camera** was exercised anywhere in this audit.

## Root-cause clusters

**Cluster 1 — a proven-readiness gate wired as a production default (F01, F02).**
Both follow from one decision: ship `UnprovenCloudRestorationReadinessSource`
while leaving the CloudKit code paths live. F01 is what happens when the gate
fires in the foreground. F02 is what happens in the background path, which
**bypasses the gate entirely** and constructs the CloudKit container the
foreground refused to trust. They are opposite failures of one incomplete
rollout, and they must be fixed together: repairing the readiness source alone
leaves F02, and repairing `backgroundMode` alone leaves the app unopenable.

A secondary, structural contributor is shared: the `usesProductionDependencies`
provenance guard keeps every storage fixture away from the production dependency
graph, so no test observes either production binding. The guard is correct; what
is missing is a small number of assertions *about* the production graph's
composition, which do not require constructing it.

**Cluster 2 — invariants enforced by call ordering rather than by construction
(F03, F04, O-03).** Each is a case where a correctness property holds only
because two independently-gated operations happen to run in the right order in
one `.task`, or because a defensive guard happens never to trip. The
`PortfolioEpoch` ↔ `backfillExistingCollectionIfNeeded` pair is the clearest
instance: the epoch's carefully reasoned `isAwaitingInitialSync` protection is
defeated by a neighbour that has no such protection and whose errors are
discarded with `try?`. The remedy shape is the same in all three — write the
dependent record in the same transaction, and make defensive guards fail loudly.

**Cluster 3 — mixed evidence failures (F04–F06).** The original full-suite run
combined substantive ownership-ledger failures with corpus lookup failures from
a PBX resource-ID collision. The corpus was tracked, but the resource graph
omitted it from the test bundle. The 2026-09-16 project correction made the
centering fixtures reachable and exposed the already-documented analyzer
assertion failures; the full suite has not yet been rerun. F04/F05 must remain
distinguishable from both classes of centering evidence failure.

## Where these findings are picked up

So this audit is not read once and orphaned, each finding is bound to the
execution document that owns the work:

| Finding | Picked up by |
| --- | --- |
| F01, F02 | [Launch plan](../superpowers/plans/2026-09-13-phase-0-phase-1-app-store-launch.md) §0.1.1 → Task 4, Task 8. Device confirmation is RF-7 in [`release_followups.md`](../plans/release_followups.md). |
| F03 | Launch plan §0.1.1 as scanner scope with no owning task; triage under the release framework §10 before RC. |
| F04, F05 | Launch plan §0.1.1 → Task 12, and the [ownership-ledger audit](../release/ownership-ledger-completeness-audit.md) "Known findings against this proof." |
| F06 | Launch plan §0.1.1 → Task 1, Task 11, and RF-6. |
| F02 (sequencing) | Blocks Slice B of [`price_history_chart_plan.md`](../plans/price_history_chart_plan.md) and RF-8. |

If a finding is fixed, strike it here **and** in the row above, so a closed item
cannot keep blocking a task that is now free to start.

## Re-run rule

The original findings describe `a4375df`; dated follow-ups carry later
evidence. Reproduce F01–F03 by source trace and F04/F05 by rerunning the named
tests before carrying them into a later candidate. F06's PBX resource collision
is corrected on `main` and the focused fixture reachability is verified, but the
full suite still needs a complete run against the intended candidate. When a
finding is fixed, record the fix and its regression test in
[`../../progress.md`](../../progress.md), update the gate row in
[`../release/card-scanner-1.0-go-no-go-framework.md`](../release/card-scanner-1.0-go-no-go-framework.md)
§14, and strike the finding here with a dated note rather than deleting it.

When this audit is superseded, move it to [`../legacy/`](../legacy/) with a
legacy banner per [`../AGENTS.md`](../AGENTS.md) rule 3 and update the
[documentation map](../README.md) and
[`../plans/documentation_audit.md`](../plans/documentation_audit.md).
