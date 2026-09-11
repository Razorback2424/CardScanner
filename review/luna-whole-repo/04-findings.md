# Evidence-Backed Findings

## Validity rules used

Each promoted item below has a reachable source path, a concrete consequence, a stated trigger condition, current counterevidence, and a verification gap where the existing suite does not exercise the exact boundary. These are review findings, not an implementation plan. Items that did not survive this gate are in `05-rejected-hypotheses-and-uncertainties.md`.

## Summary

| ID | Area | Classification | Severity | Confidence | Status |
| --- | --- | --- | --- | --- | --- |
| F-001 | Scanner/slab identity | Data-integrity concern | Medium | High | Confirmed reachable risk |
| F-002 | Scanner lifecycle | Lifecycle/concurrency concern | Medium | High | Confirmed reachable risk |
| F-003 | Centering preview/export | Confirmed defect | Medium | High | Confirmed |
| F-004 | Portfolio history range | Confirmed defect | Medium | High | Confirmed |
| F-005 | Portfolio revision explanation | Data-integrity concern | Medium | High | Confirmed |
| F-006 | Pricing/portfolio currency transition | Data-integrity concern | High | High | Confirmed conditional control-flow divergence |
| F-007 | Interactive Price Check fallback | Confirmed defect | Medium | High | Confirmed |
| F-008 | Refresh bookkeeping | Maintainability concern | Low | High | Confirmed |
| F-009 | Pricing diagnostics | Confirmed defect | Low | High | Confirmed |
| F-010 | CSV graded identity | Data-integrity concern | High | High | Confirmed |
| F-011 | CSV/Browse sealed identity | Data-integrity concern | High | High | Confirmed conditional path |
| F-012 | Existing-collection backfill scope | Data-integrity concern | Medium | High | Confirmed conditional path |
| F-013 | Browse cache clock boundary | Performance concern | Low | High | Confirmed conditional path |
| F-014 | Primary documentation links | Maintainability concern | Low | High | Confirmed |

## F-001 — Unbound slab evidence can attach to the first later identity

**Classification:** Data-integrity concern  
**Severity:** Medium  
**Confidence:** High  
**Status:** Confirmed reachable risk; exact physical-card reproduction remains a device/test gap.

`detectSlabLabelIfDue` is intentionally allowed to OCR a label while no footer identity is bound. It records `wasUnbound` and eventually calls `applySlabLabelEvidence`, while `activateSlab` can leave `activeSlabBaseIdentifier` nil. In `updateActiveSlabPresence`, an active slab with footer text but no footer identifier returns without clearing or binding. The next identified subject is then wrapped with `activeSlab.evidence` in `handleFooterOutcome`.

Evidence: `TradingCardScanner/Services/CardScanner.swift:1966-1980, 2071-2101, 2128-2177, 1768-1800`. The existing `CardLatchTests.swift:474` test proves that unbound label evidence can activate the scanner path; it does not assert that a different subsequent physical card cannot receive that evidence.

Trigger condition: a slab label is recognized before a reliable footer identifier, then the current physical slab/card changes before the first identifier is established. The first later identifier becomes the base and receives the old grade/certification evidence. A same-printed-card but different slab is particularly difficult for the printed identity check to distinguish.

Consequence: a `ScanSubject` can carry a wrong grader, grade, or certification number into `ScannerViewModel`, and candidate resolution cannot repair provenance that was attached upstream.

Counterevidence: once a non-nil base identifier exists, a different footer identifier calls `clearActiveSlab(cause: .identityChanged)` before the subject is emitted; the behavior is therefore narrower than “any slab can leak to any card.” The source also deliberately supports label-first bootstrap, so simply disabling that path would change a stated scanner capability.

**Affected scope:** graded scanner recognition, slab provenance, and the subsequent collection insertion path.  
**Existing test coverage:** `CardLatchTests.swift:474` proves unbound label activation; no test covers a second physical identity after unbound activation.  
**Verification path:** feed a label-first sequence followed by a different card identity and inspect the emitted `ScanSubject.slab` before `ScannerViewModel` resolution.  
**Related findings:** F-002.

## F-002 — Lifecycle invalidation does not clear active slab state

**Classification:** Lifecycle/concurrency concern  
**Severity:** Medium  
**Confidence:** High  
**Status:** Confirmed reachable risk.

`CardScanner.invalidateSpatialContinuity` cancels held authorization, marks the tracker lost, resets confirmation, and clears the historical attempt, but it does not clear `activeSlab`. `CardScanner.stop` also stops AVCapture without clearing recognition state. The only shown full reset is `endSession` → `resetObservationState` → `clearActiveSlab(cause: .lifecycle)`.

Evidence: `TradingCardScanner/Services/CardScanner.swift:1012-1022, 1042-1058, 1163-1174, 2487-2495`; `TradingCardScanner/Views/ScannerViewModel.swift:1320-1328, 1466-1500, 1555-1599`. The scanner source comments at `CardScanner.swift:2068-2070` state that lifecycle reset should prevent inheritance, but the corresponding invalidation path does not call the clear operation.

Trigger condition: the scanner is backgrounded, interrupted, or its purpose changes while a slab is active, and recognition later resumes without a full `endSession`. `ScannerViewModel` calls `invalidatePendingScan`, which calls `invalidateSpatialContinuity`; a non-finalizing view disappearance calls `stop`. If the next card has the same printed identity, or a footer is not yet available, identity-change clearing cannot distinguish the new physical object.

Consequence: a new encounter can inherit the prior slab’s grade/certification evidence. This is a data-integrity risk even though ordinary tab finalization does call `endSession`.

Counterevidence: normal finalized tab exit and explicit session end do clear the slab; a known different footer identity also clears it. The risk is limited to lifecycle paths that only fence recognition/spatial continuity.

**Affected scope:** scanner foreground/background, interruption, purpose-change, view disappearance, and resumed recognition.  
**Existing test coverage:** lifecycle tests cover invalidation/fencing and session reset separately; no focused assertion proves `activeSlab` is cleared for every invalidation caller.  
**Verification path:** activate slab evidence, invoke each `ScannerViewModel` invalidation path, resume recognition with a same-printed-identity new encounter, and inspect the emitted slab evidence.  
**Related findings:** F-001.

## F-003 — Centering guides stay in the unrotated coordinate frame

**Classification:** Confirmed defect  
**Severity:** Medium  
**Confidence:** High  
**Status:** Confirmed by source; visual screenshot verification at a non-zero angle is still useful evidence.

`CardCenteringImage` applies `rotationEffect` to the image only, then draws the outer and inner guide lines using the original `origin` and `fittedSize`. `CardCenteringExport.render` rotates the photo in the graphics context, restores the context, and then draws guides without applying the same transform.

Evidence: `TradingCardScanner/Views/CardCenteringView.swift:658-706`; `TradingCardScanner/Services/CardCenteringExport.swift:75-100`. The UI explicitly says “Rotates photo only” at `CardCenteringView.swift:548-550`, which establishes intent for the photo transform but does not make a guide overlay on that photo geometrically aligned.

Trigger condition: the user applies any non-zero manual rotation and inspects either the preview or exported image.

Consequence: the red/cyan measurements can be visually detached from the card edges. A user can accept or share a centering result whose guides do not describe the displayed pixels.

Counterevidence: zero-degree captures and the numeric measurement values remain internally unchanged; the source may intentionally want the measurement frame to remain unrotated. The defect is the preview/export representation and not the underlying measured integers.

**Affected scope:** centering result preview and exported image whenever manual rotation is non-zero.  
**Existing test coverage:** analyzer/measurement tests exist, but no screenshot or renderer assertion checks guide alignment after rotation.  
**Verification path:** render preview/export at a non-zero angle with known edge coordinates and compare guide pixels against the rotated card edges.  
**Related findings:** none.

## F-004 — Sparse history can display an older anchor under a newer selected range

**Classification:** Confirmed defect  
**Severity:** Medium  
**Confidence:** High  
**Status:** Confirmed by pure history control flow.

`PortfolioHistoryEngine.calculate` computes `requestedStart` from the selected range, but if no published close is on or after that date it falls back to `latest.first`. It then selects all closes from that older anchor onward. `trackingBeganDate` records the fallback, but `PortfolioHistoryView` does not display it; it only shows the generic “History is being recorded” message when there are too few points.

Evidence: `TradingCardScanner/Services/PortfolioHistoryEngine.swift:8-45, 127-143`; `TradingCardScanner/Views/PortfolioHistoryView.swift:18-34, 46-72`; range chips and period labels are user-facing in `PortfolioView.swift:334-364, 544-566`.

Trigger condition: the user selects a bounded range such as 1W or 1M while the oldest close predates the requested start and there is no close inside the requested window.

Consequence: the first chart point and accounting anchor can be older than the selected period while the UI labels the result with the selected period. Market movement and range details can therefore answer a different interval than the control implies.

Counterevidence: falling back to available history may be an intentional “show something useful” policy, and the result retains `trackingBeganDate`. The current presentation does not expose that distinction, and no focused test asserts the desired behavior for an empty requested interval.

**Affected scope:** portfolio history chart, range accounting, period labels, and movement details for sparse stores.  
**Existing test coverage:** history tests cover ordinary ranges and manually supplied closes; no empty-requested-window presentation test was found.  
**Verification path:** provide closes only before a selected 1W/1M start, calculate the result, and compare the first point/accounting anchor with the range label shown by the view.  
**Related findings:** none.

## F-005 — Late inventory truth is always labeled as generic recomputation

**Classification:** Data-integrity concern  
**Severity:** Medium  
**Confidence:** High  
**Status:** Confirmed source gap in a user-facing revision vocabulary.

`InventoryEvent` records both `occurredAt` and `recordedAt`, with comments defining a late CloudKit arrival as an event that occurred before a published close but was written after it. `PortfolioRevisionReason` has a dedicated `.lateInventoryTruth` note. `PortfolioEngine.publish`, however, assigns `.recomputed` to every changed existing close and never examines event recording time or late-event state.

Evidence: `TradingCardScanner/Models/InventoryEvent.swift:69-74`; `TradingCardScanner/Models/PortfolioDailyClose.swift:4-16, 142-153`; `TradingCardScanner/Services/PortfolioEngine.swift:753-823`. The only current `.lateInventoryTruth` evidence is manually constructed in `PortfolioHistoryEngineTests.swift:554`; no publisher assertion proves that production recomputation emits it.

Trigger condition: a previously published day changes after an inventory event with `occurredAt` before the day cutoff and `recordedAt` after publication becomes visible.

Consequence: history explains a cross-device reconciliation as “recomputed from corrected inputs,” hiding the distinction between late ownership truth and an ordinary local repair. That weakens the trust/audit contract without changing the numerical close itself.

Counterevidence: the publisher comment says closed-day price backdating cannot change a day and that ownership incompleteness is the expected cause. That supports the need for the dedicated label; it does not show that the label is ever selected.

**Affected scope:** published daily-close revision metadata and the history explanation shown after late inventory synchronization.  
**Existing test coverage:** `PortfolioHistoryEngineTests.swift:554` exercises the enum/note manually; no publisher test asserts late-event classification.  
**Verification path:** publish a close, insert an event with pre-cutoff `occurredAt` and post-publication `recordedAt`, republish, and inspect the new close’s `revisionReason`/`revisionNote`.  
**Related findings:** F-012.

## F-006 — A non-USD PriceStore transition can diverge current value from replay

**Classification:** Data-integrity concern  
**Severity:** High  
**Confidence:** High  
**Status:** Confirmed control-flow divergence; the trigger depends on a provider path delivering a non-USD successful quote.

`PriceStore.store` sends the lookup to the observation log and then applies a `.price` to the mutable `PriceRecord`. `PriceRecord.apply` accepts finite nonnegative amounts and writes the supplied currency. `InventoryLedger.resolveValuation` allows a newer record to supersede an older observation, then returns unpriced when that record’s currency is not USD. The replay path normalizes non-USD observations to `amount == nil`, marks them non-participating, and returns without changing the prior replay USD state.

Evidence: `TradingCardScanner/Services/PriceStore.swift:782-841`; `TradingCardScanner/Models/PriceRecord.swift:168-189`; `TradingCardScanner/Services/InventoryLedger.swift:327-374`; `TradingCardScanner/Services/PortfolioEngine.swift:543-555, 690-710, 940-958`; `TradingCardScanner/Services/PortfolioReplay.swift:463-520`.

Trigger condition: an instrument has an existing USD price/evidence, then a newer non-USD `NormalizedPrice` reaches the full `PriceStore.store` path and supersedes the current record. There is no FX conversion policy, so the current value becomes unpriced while replay retains the old USD evidence.

Consequence: current collection valuation drops the instrument while replay retains it, and `PortfolioEngine` can emit an unexplained value residual. The same transition can also distort close/reconciliation explanations and refresh-derived portfolio state.

Counterevidence: the app deliberately excludes non-USD amounts from the USD total; `InventoryLedger` and replay both document that policy. Existing tests cover a newer non-USD observation falling back to a USD record, direct in-memory record transitions, and fast/authoritative agreement in those direct cases. They do not cover a non-USD successful quote through `PriceStore.store` followed by a full current-vs-replay recomputation.

**Affected scope:** `PriceStore`, `PriceRecord`, `PriceObservationLog`, current valuation, replay attribution, close publishing, and residual-defect reporting.  
**Existing test coverage:** fallback/direct-transition tests cover adjacent cases; the full `PriceStore.store` → SwiftData → current/replay path is not covered.  
**Verification path:** seed a USD record/observation, store a newer non-USD success through `PriceStore.store`, rebuild the authoritative snapshot, and compare current valuation with replay attribution and emitted defects.  
**Related findings:** prior D06 is rejected in `05`; F-007 concerns the interactive presentation of the same currency boundary.

## F-007 — Non-USD local evidence is presented as a current Price Check quote

**Classification:** Confirmed defect  
**Severity:** Medium  
**Confidence:** High  
**Status:** Confirmed fallback-path semantic defect.

The live catalog quote path requires `isUsableUSD`. The local fallback path does not: `evidence(from: PriceRecord)` accepts a finite effective amount and preserves `record.currencyCode`, then `present` stores and returns `.price(local.price)` with `quoteState: .current`. Thus a stored EUR/Cardmarket amount can produce a “current” Price Check result when the live USD quote is unavailable.

Evidence: `TradingCardScanner/Services/PriceCheckCoordinator.swift:82-110, 267-305, 444-485, 501-505`. The display retains the currency code, so this is not a claim that EUR is relabeled as USD; it is a state/semantics mismatch in the “completed Price Check” result.

Trigger condition: a local `PriceRecord` or reference quote has a valid non-USD currency and the catalog path fails or has no usable USD amount.

Consequence: the user sees a completed/current result even though the coordinator’s own contract says a non-USD amount is not a completed USD Price Check. Downstream UI, accessibility, or analytics that key on `quoteState` can treat it as a successful USD check.

Counterevidence: the currency is displayed and the source/live path is correctly USD-gated; no numerical conversion or silent dollar symbol substitution was found. The defect is restricted to local evidence presentation.

**Affected scope:** interactive Price Check initial presentation after live quote failure/unavailability, including quote state and downstream consumers of that state.  
**Existing test coverage:** USD gating and fallback behavior are covered separately; no focused non-USD local-evidence/state test was found.  
**Verification path:** seed a non-USD local record, make the catalog quote unusable, call `present`, and assert whether a current result is intentionally or incorrectly emitted.  
**Related findings:** F-006.

## F-008 — Null-price JustTCG hits are counted as priced changes

**Classification:** Maintainability concern  
**Severity:** Low  
**Confidence:** High  
**Status:** Confirmed bookkeeping defect; no valuation corruption.

`PriceRefreshController.applyVendorBatchHit` correctly applies identity/artwork metadata and returns `true` when `marketPriceUSD` is nil. `JustTCGRefreshCoordinator` increments `variantsUpdated` for that successful application. The controller later adds `report.variantsUpdated` to its `priced` count and marks `changedPrices` true, even though the associated `PriceRecord` remains nil.

Evidence: `TradingCardScanner/Services/PriceRefreshController.swift:2214-2297`; `TradingCardScanner/Services/JustTCGRefreshCoordinator.swift:274-319`; `TradingCardScanner/Services/PriceRefreshController.swift:850-884`. `TradingCardScannerTests/CollectionItemKindTests.swift:366-405` confirms that a null market price still backfills identity/artwork while leaving the price record nil.

Trigger condition: a matched JustTCG response has valid metadata but `variant.marketPriceUSD == nil`.

Consequence: refresh progress, “priced” counts, `changedPrices`, and potentially revision/recompute decisions report a price change for a metadata-only hit. This can make observability and user-facing refresh summaries overstate valuation coverage.

Counterevidence: the underlying metadata write is intentional and valuable, and the coordinator’s `variantsUpdated` name can be read as “variant updated” rather than “price written.” The controller’s separate `priced` variable and `changedPrices` flag make the semantic collision concrete.

**Affected scope:** fallback refresh progress, priced-count reporting, `changedPrices`, and downstream revision/recompute triggers; not the metadata or stored-price values themselves.  
**Existing test coverage:** `CollectionItemKindTests.swift:366-405` proves the null-price metadata path and nil record; no report-count assertion covers the same response.  
**Verification path:** run a one-owner null-price batch through `JustTCGRefreshCoordinator` and `PriceRefreshController`, then compare `variantsUpdated`, `priced`, and `changedPrices`.  
**Related findings:** none.

## F-009 — An invalid-provider diagnosis can mask a later ordinary failure

**Classification:** Confirmed defect  
**Severity:** Low  
**Confidence:** High  
**Status:** Confirmed diagnostic transition gap.

When `PriceStore.store` rejects an invalid quote it records `invalid_provider_quote`. A later ordinary `PriceStore.recordFailure` updates failure timestamps but does not clear that reason; `PricingDiagnostics.unpricedReason` checks `invalidProviderQuote` before falling through to general provider state. The invalid diagnosis therefore remains visible until a success or a separate unavailable path clears it.

Evidence: `TradingCardScanner/Services/PriceStore.swift:812-835, 898-925`; `TradingCardScanner/Models/PriceRecord.swift:255-261`; `TradingCardScanner/Services/PriceStore.swift:104-123`.

Trigger condition: a malformed/non-finite/unrepresentable quote is rejected, then a later attempt reaches `recordFailure` because the provider request fails before returning a normal `.unavailable` or successful amount.

Consequence: the detail UI/export says the provider returned an invalid amount even though the latest attempt failed due to transport/provider availability. The prior value remains safe, but the retry diagnosis is stale.

Counterevidence: a successful amount clears the diagnosis, and the ordinary `.unavailable` store path clears non-capability diagnoses. This is only the failure-after-invalid transition; it is not a general failure-state corruption.

**Affected scope:** `PriceRecord.lastFailureReasonRaw`, pricing diagnostics, detail UI, and diagnostic CSV after sequential provider outcomes.  
**Existing test coverage:** invalid-quote and ordinary-failure paths are covered independently; no transition test covers invalid quote followed by `recordFailure`.  
**Verification path:** persist a rejected invalid quote, call `recordFailure` for the same key, and resolve `PricingDiagnostics.unpricedReason`.  
**Related findings:** none.

## F-010 — CSV export/import is not identity-preserving for production graded rows

**Classification:** Data-integrity concern  
**Severity:** High  
**Confidence:** High  
**Status:** Confirmed for production-created graded rows.

CSV exports `provider_id` from `CollectedCard.providerID` and does not export `collectionKey`. Production `CollectionStore.addGraded` and `addScannedGraded` intentionally set `providerID` to the already-prefixed graded collection key. On import, `CollectionCSV.makeEntry` treats that field as an underlying printing ID: the UUID path calls `gradedCollectionKey` with the full graded key, and the no-UUID path prefixes it again while rebuilding the graded key. `CollectionCSV.apply` inserts using the reconstructed key.

Evidence: `TradingCardScanner/Services/CollectionCSV.swift:134-185, 763-815, 1163-1203`; `TradingCardScanner/Services/CollectionStore.swift:1759-1765, 1878-1889, 1972-1979, 2055-2059`; `TradingCardScanner/Models/CollectedCard.swift:374-409`.

Trigger condition: export a graded row created by the production scan/Browse path and import that CSV, with or without a JustTCG variant ID.

Consequence: the imported row receives a different, often double-prefixed identity rather than merging with the original position. Activities/ledger rows are reconstructed under the drifted key, so round-trip backups can duplicate holdings or split history.

Counterevidence: raw/sealed rows and hand-built test fixtures using a bare `providerID` can round-trip; `PortfolioReconciliationTests.swift:1034-1065` proves certificate separation for that synthetic fixture shape. It does not cover the production invariant that graded `providerID == collectionKey`.

**Affected scope:** graded CSV backup/restore, collection identity, activity/ledger history, and duplicate/certificate separation.  
**Existing test coverage:** certificate separation is covered for a synthetic bare-provider fixture; production-created graded-row round-trip is not.  
**Verification path:** create a graded row via `CollectionStore.addGraded` and `addScannedGraded`, export/import, then compare original/imported keys and ledger/activity quantities.  
**Related findings:** F-011.

## F-011 — Legacy imported sealed rows can duplicate after Browse normalization

**Classification:** Data-integrity concern  
**Severity:** High  
**Confidence:** High  
**Status:** Confirmed conditional path.

When a CSV sealed row has no marketplace IDs, `CollectionCSV.makeEntry` constructs a synthetic `sealed:<game>:<providerID>` key. Later `CollectionCatalogNormalizer` can enrich the row with JustTCG product/variant metadata but deliberately preserves the existing collection key. Browse’s `CollectionStore.addSealed` constructs the canonical `sealed:<game>:<product.id>:<variant.id>` key and checks only that exact key.

Evidence: `TradingCardScanner/Services/CollectionCSV.swift:1205-1224`; `TradingCardScanner/Services/CollectionCatalogNormalizer.swift:147-185`; `TradingCardScanner/Services/CollectionStore.swift:2118-2157`; `TradingCardScanner/Models/CollectedCard.swift:411-422`; `TradingCardScanner/Services/LogicalCollection.swift` exact-key projection.

Trigger condition: import a legacy/hand-authored sealed row without `justtcg_card_id`/`justtcg_variant_id`, allow it to be normalized/enriched, then add the same product from Browse.

Consequence: the collection can hold two exact-key rows and two activity/ledger positions for one physical product. `CatalogOwnershipIndex` can aggregate them by marketplace product while the Collection projection and portfolio identity still see separate rows, making the inconsistency harder to notice.

Counterevidence: current production Browse additions write canonical product/variant IDs from the start, and current CSV exports include those IDs for rows created by `addSealed`. The finding is confined to missing-ID legacy/import input, but that is an explicitly supported import boundary.

**Affected scope:** legacy CSV sealed imports, catalog normalization, Browse ownership aggregation, Collection projection, and portfolio positions.  
**Existing test coverage:** current sealed add/artwork/null-price tests cover canonical IDs; no legacy missing-ID import → normalize → Browse convergence test was found.  
**Verification path:** import a missing-ID sealed row, normalize it with a matching product, add that product from Browse, and compare exact keys, quantities, activities, and ownership-index totals.  
**Related findings:** F-010, F-012.

## F-012 — Existing-collection activity backfill is globally watermarked, not store-scoped

**Classification:** Data-integrity concern  
**Severity:** Medium  
**Confidence:** High  
**Status:** Confirmed conditional path.

`CollectionStore.backfillExistingCollectionIfNeeded` stores one version in `UserDefaults.standard` and returns as soon as that global watermark is complete and the current context has no legacy activity rows. It does not bind the watermark to the SwiftData container, CloudKit account/store, or collection identity. The app can choose local-only or CloudKit-backed storage on a later launch.

Evidence: `TradingCardScanner/Services/CollectionStore.swift:402-404, 467-525`; `TradingCardScanner/App/TradingCardScannerApp.swift:102-149`; `TradingCardScanner/Services/PortfolioEpoch.swift:147-203`; `TradingCardScanner/Services/PortfolioReplaySnapshot.swift:281-316`.

Trigger condition: one storage context completes the backfill, then a different local/CloudKit store or account context is selected on a later launch and contains pre-existing collection rows without activities.

Consequence: the second store can skip its activity backfill. Portfolio epoch/replay can then see collection quantities without authoritative acquisition events, leaving history incomplete or non-authoritative.

Counterevidence: a user normally stays on one persistent store, and the app intentionally selects storage per launch rather than switching a live container. The risk requires a store/account transition or independently delivered legacy data; it is not a same-store every-launch failure.

**Affected scope:** first-launch migration/backfill, local-vs-CloudKit storage selection, collection activities, portfolio epoch establishment, and history authority.  
**Existing test coverage:** idempotent backfill and epoch tests cover one context; no test binds the watermark to two sequential storage contexts.  
**Verification path:** complete backfill in one local context, open a second legacy-containing context with the same defaults, and inspect whether missing activities are created before epoch/replay.  
**Related findings:** F-005, F-011.

## F-013 — Future-dated browse cache envelopes are treated as fresh

**Classification:** Performance concern  
**Severity:** Low  
**Confidence:** High  
**Status:** Confirmed conditional cache behavior.

`CatalogCacheStore.load` declares a cache fresh when `Date.now.timeIntervalSince(envelope.storedAt) < maxAge`. A future `storedAt` produces a negative age and therefore passes the freshness test. There is no future-skew rejection or clamp in this cache loader.

Evidence: `TradingCardScanner/Services/BrowseCatalog.swift:898-909`. Existing future-timestamp coverage in `BrowseFeatureTests.swift:2520-2532` targets a different `BrowseCatalogStore.markRefreshSucceeded` path, not this `CatalogCacheStore` envelope loader.

Trigger condition: a persisted browse envelope is written with a clock-future timestamp, for example after device clock correction or malformed/imported cache data.

Consequence: stale Browse search/set data can be accepted as fresh until wall-clock time catches up, delaying a refresh and making content appear current longer than the configured maximum age.

Counterevidence: normal same-device writes use the current clock, and the trigger requires clock skew or persisted corruption. No general cache invalidation failure was found.

**Affected scope:** Browse cache freshness and offline search/set presentation.  
**Existing test coverage:** a future-timestamp test exists for `BrowseCatalogStore.markRefreshSucceeded`, not this `CatalogCacheStore.load` branch.  
**Verification path:** load an envelope with `storedAt` later than `Date.now` and a bounded max age, then inspect `isFresh` and the refresh decision.  
**Related findings:** none.

## F-014 — README points to missing root-level audit documents

**Classification:** Maintainability concern  
**Severity:** Low  
**Confidence:** High  
**Status:** Confirmed repository documentation defect.

The primary README links `documentation_audit.md` and `release_followups.md` as if they were at the repository root. The tracked files are under `docs/plans/`, so those links resolve to nonexistent paths from the README location.

Evidence: `README.md:7-11`; actual files: `docs/plans/documentation_audit.md` and `docs/plans/release_followups.md`.

Trigger condition: a reader follows either current-checkpoint/release-validation link from the repository README.

Consequence: the first-party navigation path to the current evidence and release gates is broken, increasing the chance that historical progress notes are mistaken for current proof.

Counterevidence: the documents exist and are internally useful when opened by their tracked paths; this does not affect app runtime.

**Affected scope:** repository onboarding and navigation to current review/release evidence.  
**Existing test coverage:** no repository link checker was found; the path mismatch is directly visible from tracked file locations.  
**Verification path:** resolve both Markdown links from the README’s repository-root location.  
**Related findings:** none.
