# Opus Implementation Plan — Authoritative Execution Contract

Independent final review of the Luna whole-repository pass (`review/luna-whole-repo/`).
This document supersedes `review/luna-whole-repo/04-findings.md` as the driver of implementation.
Luna's artifacts remain valid as evidence and navigation aids.

---

## Objective

Eliminate three architectural root causes and nine independent defects that allow the app to
record, value, or explain a holding incorrectly:

1. **Physical-object evidence (graded slab grade/certification) can attach to the wrong card.**
2. **A holding's USD value can disappear from the current total while portfolio history keeps it**,
   producing an unexplained residual — reachable today through a first-party provider adapter.
3. **A collection row's identity is not preserved across CSV export/import, and is misparsed by at
   least one in-app consumer**, because `CollectedCard.providerID` carries two different meanings.

After implementation, each of these has a single owner, a stated invariant, and a deterministic test
that fails if the invariant is violated.

---

## Non-goals

The implementation must **not** change any of the following. Each was independently examined and
found correct or deliberate.

1. **Centering rotation behavior.** Luna F-003 is rejected (see Verified Problem Set). The guides
   are a fixed measurement reference and the photo rotates against them; that is the entire
   function of the rotation control. Do not rotate guides in `CardCenteringView` or
   `CardCenteringExport`, and do not re-run detection on manual rotation.
2. **The USD-only portfolio policy.** Do not add FX conversion, exchange-rate lookup, or any
   multi-currency total. Non-USD amounts remain excluded from the USD portfolio total.
3. **The label-first slab bootstrap capability.** `detectSlabLabelIfDue` may continue to OCR a label
   before a footer identity exists. REQ-007 constrains *binding*, not *detection*.
4. **`QuoteCache` isolation.** `QuoteCache` must remain with no path to `PriceObservationLog`,
   `PriceCheckDay`, or `PriceRecord`. This isolation was verified and is load-bearing.
5. **Existing collection keys for rows already correct in production.** No migration may rewrite the
   key of a row whose key already matches its canonical construction.
6. **The three-tier resolver precedence in `VariantResolver.resolve`** (catalog-silent → unique
   catalog → finish lock → printed label). Do not reorder.
7. **The Magic treatment/finish model** (`MagicTreatment.modelled`, `requiredFinishes`,
   `MagicFinishLock`). Out of scope for this plan.
8. **`PriceRecord.apply` accepting non-USD currencies.** Non-USD evidence must continue to be
   *stored* for display and provenance. REQ-005 governs how it is *valued*, not whether it is kept.

---

## Verified Problem Set

Every Luna finding was independently adjudicated against current source. Line references below were
confirmed by direct inspection during this review.

| Luna ID | Final status | Final home |
| --- | --- | --- |
| F-001 | MERGED-INTO-ROOT-CAUSE | RC-A → REQ-007 |
| F-002 | MERGED-INTO-ROOT-CAUSE | RC-A → REQ-008 |
| F-003 | **REJECTED** | none — see Non-goal 1 |
| F-004 | VERIFIED | REQ-009 |
| F-005 | **DOWNGRADED** (Medium → Low), reclassified | REQ-010 |
| F-006 | **VERIFIED-WITH-REVISION** (reachability upgraded) | RC-B → REQ-005 |
| F-007 | VERIFIED | REQ-006 |
| F-008 | VERIFIED | REQ-011 |
| F-009 | VERIFIED | REQ-012 |
| F-010 | MERGED-INTO-ROOT-CAUSE | RC-C → REQ-002 |
| F-011 | VERIFIED | REQ-013 |
| F-012 | **VERIFIED-WITH-REVISION** (trigger broadened) | REQ-014 |
| F-013 | VERIFIED | REQ-015 |
| F-014 | VERIFIED | REQ-016 |
| **N-001** | **NEW** | RC-C → REQ-003 |
| **N-002** | **NEW** | REQ-004 |

### RC-A — Slab evidence has no binding proof and no lifecycle-wide invalidation

`CardScanner.activeSlab` holds grade/grader/certification read from a physical slab's label. Two
independent gaps let that evidence reach a different physical object.

**A1 (Luna F-001) — unproven binding.** In `updateActiveSlabPresence`
(`CardScanner.swift:2071-2101`), when a slab is active and `activeSlabBaseIdentifier == nil`, the
code executes `self.activeSlabBaseIdentifier = footerIdentifier` for **whatever identifier arrives
first**, with no proof it belongs to the slab whose label was read. `handleFooterOutcome`
(`CardScanner.swift:1798-1801`) then staples that evidence onto the subject:
`parsed = activeSlab.map { ScanSubject(identifier: subject.identifier, slab: $0.evidence) }`.
The `.footerAbsence` mitigation only fires when `footerLines.isEmpty`; a transition where footer text
is continuously present resets `activeSlabEmptyFrames` to 0 and never clears.

**A2 (Luna F-002) — incomplete lifecycle clearing.** `clearActiveSlab` is reachable only from
`.spatialExit` (1613), `.latchRelease` (1836), `.footerAbsence` (2087), `.identityChanged` (2097),
and `.lifecycle` via `resetObservationState` (2491), which is called **only** by `endSession`.
Neither `stop()` (1012) nor `invalidateSpatialContinuity()` (1166) clears it.

The exact reachable trigger is sharper than Luna stated. `ScannerViewModel.viewDisappeared()`
(1320-1331) computes `shouldFinalize = isScannerSessionActive && recognitionEligibility.isSceneActive`.
**Backgrounding the app while the scanner tab is visible makes `isSceneActive` false**, so the
`else` branch runs `scanner.stop()` — which never clears `activeSlab`. On return, recognition resumes
without `endSession`.

**Consequence:** a wrong grader, grade, or certification number is written into a durable
`CollectedCard` row. Certification numbers are non-aggregating identity; a wrong one creates a
permanently mislabeled physical-object record.

**Severity:** Medium. **Confidence:** High (mechanically confirmed; physical reproduction is
device-pending).

### RC-B — No single owner of the "instrument leaves USD" policy

Three production sites document **mutually contradictory** policies for what happens when an
instrument's newest price evidence is not USD. Two of the three assert a behavior the third does not
implement.

1. **`InventoryLedger.resolveValuation` (`InventoryLedger.swift:340-374`)** — *implemented*: a newer
   non-USD `PriceRecord` supersedes the older observation and the instrument becomes `.unpriced`.
   Both call sites (`InventoryLedger.swift:307`, `PortfolioReplaySnapshot.swift:445`) pass
   `newestObservation` — the newest by receipt, **regardless of currency**. There is no
   "newest USD observation" selection anywhere. Every branch returns `.unpriced`.
2. **`PortfolioClose.ObservationEntry` doc (`PortfolioClose.swift:33-38`)** — asserts
   *"the current-value path deliberately falls back to that older USD record."* **This is false.**
3. **`PortfolioReplay.apply` (`PortfolioReplay.swift:468-473`)** — asserts *"Current valuation
   intentionally carries the prior USD record forward, so replay must do the same"* and implements
   `guard observation.participatesInPortfolioValue else { return }`, keeping the stale USD value.

**Reachability — Luna materially understated this.** Luna called the trigger "conditional on a
provider path delivering a non-USD successful quote." In fact `PriceProvider.cardmarketPrice`
(`PriceProvider.swift:268-287`) is a **first-party adapter purpose-built to return EUR**:

> "Cardmarket stands in only where TCGdex carries no TCGplayer figure at all — *most of the promo
> catalogue*. It is a euro price from a different marketplace, so it is returned in its own currency
> and never silently converted; **the collection layer decides what to do with a non-USD number**."

The collection layer has two layers that decide differently. `PriceStore.store`
(`PriceStore.swift:820-823`) applies the EUR price to the record with no USD gate;
`PriceObservationLog.ingest` (`PriceObservationLog.swift:216-241`) appends the observation carrying
`currencyCode` (its finiteness guard is on the magnitude, not the currency).

**Full production chain:** a Pokémon promo priced in USD is refreshed when only Cardmarket data is
present → EUR record + EUR observation → current valuation drops the card → replay keeps the old USD
→ `PortfolioEngine` emits an unexplained residual and the current total and history disagree by the
card's full value.

**Severity:** High. **Confidence:** High. **Reachability:** production, first-party, common catalogue slice.

**Note on F-007's relationship.** I hypothesized that `PriceCheckCoordinator.present`
(`PriceCheckCoordinator.swift:269-277`) triggers RC-B by writing non-USD local evidence through
`cache.store`. **I investigated and rejected this**: `cache` is `QuoteCache`
(`PriceCheckCoordinator.swift:159`), which writes only `ReferenceQuote` and is documented as having
"deliberately no path … to `PriceRecord`" (`QuoteCache.swift:4-7`). F-007 is therefore an
independent presentation defect (REQ-006), not an RC-B trigger.

### RC-C — `CollectedCard.providerID` carries two incompatible meanings

For **raw** rows, `providerID` is the underlying printing ID. For **graded and sealed** rows created
by production, `providerID` is set to the collection key itself:

- `CollectionStore.addGraded` — `providerID: key` (≈1878-1889), `row.catalogProviderID = card.providerID` (1912)
- `CollectionStore.addScannedGraded` — `providerID: key` (≈1972-1979), `row.catalogProviderID = card.providerID` (2081)
- `CollectionStore.addSealed` — `providerID: key` (2185-2188)

`catalogProviderID` is the field that actually holds the underlying printing ID.
`certifiedGradedCard` (`CollectionStore.swift:2500-2502`) already compensates by matching
`row.catalogProviderID == underlyingProviderID || row.providerID == underlyingProviderID`. Consumers
that do **not** compensate are defective.

**C1 (Luna F-010) — CSV round-trip destroys graded identity.** Export writes `provider_id` from
`card.providerID` (`CollectionCSV.swift:155`) and never exports `collectionKey`. Import's
`makeEntry` treats that field as the underlying printing ID (`CollectionCSV.swift:1163-1203`).
Worked example, Magic scanned graded row:

```
original key   graded:magic:abc-123:g:psa-10:cert:12345
exported       provider_id = graded:magic:abc-123:g:psa-10:cert:12345
import baseKey magic:graded:magic:abc-123:g:psa-10:cert:12345
reimported key graded:magic:graded:magic:abc-123:g:psa-10:cert:12345#psa|10:cert:12345
```

The UUID path drifts too: `gradedCollectionKey(underlyingPrintingID: <the graded key>, …)`.
**Mitigating fact Luna missed: the correct value is already in the export.** `catalog_provider_id`
is exported (`CollectionCSV.swift:184`) and parsed (`:929`); `makeEntry` simply does not use it for
key reconstruction. The fix is lossless and requires no new column for graded rows.

**C2 (NEW — N-001) — graded variant correction offers the wrong options.**
`CollectionCardDetailView.gradedVariantOptions` (`CollectionCardDetailView.swift:479-495`) derives
the set ID by splitting `providerID`:

```swift
setID: card.providerID.split(separator: "-", maxSplits: 1).first.map(String.init) ?? card.providerID
```

This property is used **only for graded rows**, where `providerID` is always the graded key. For a
Pokémon graded row keyed `graded:pokemon:sv08.5-074:g:psa-10`, `setID` evaluates to
`"graded:pokemon:sv08.5"` — never a real TCGdex set id. Two silent consequences:

- `PokemonVariantRules.apply` matches `rule.setIDs.contains(setID)` → the Poké Ball / Master Ball
  parallel rules **never fire** for graded rows.
- `VariantResolver.stampedVariants` builds `"\(setID)-\(cardNumber)"` → the stamped-release catalog
  **never matches**.

The graded finish-correction menu therefore omits legitimate options for exactly the rows it exists
to serve. **Severity:** Medium. **Confidence:** High (mechanically certain).
**Correct source:** `card.catalogProviderID`.

### N-002 (NEW) — Graded/sealed test fixtures contradict the production row shape

Every graded fixture in the test target constructs `CollectedCard` with a **bare printing ID** as
`providerID` (`CollectionKeyTests.swift:158` → `"sv08.5-074"`;
`PortfolioReconciliationTests.swift:900` → `"printing"`), while production always writes
`providerID == collectionKey`. No fixture anywhere reproduces the production shape.

This is not incomplete coverage — it is a fixture that **contradicts** production, and it is the
structural reason 1,005 tests pass while C1 and C2 are live. Any future `providerID`-as-key defect
is equally invisible. **Severity:** Medium (verification integrity). **Confidence:** High.

### Independent defects (verified, not merged)

| ID | Mechanism | Severity | Confidence |
| --- | --- | --- | --- |
| F-004 | `PortfolioHistoryEngine.calculate:22` — `latest.first(where: { $0.date >= requestedStart }) ?? latest.first` silently anchors outside the selected range; `selected = latest.filter { $0.date >= anchor.date }` then spans the whole history while the UI keeps the selected-range label. | Medium | High |
| F-005 | `PortfolioEngine.publish:~820` — `revisionReason: existing == nil ? nil : .recomputed`. `.lateInventoryTruth` exists in `PortfolioDailyClose.swift:12`, has user-facing copy in `PortfolioHistoryTypes.swift:147`, and is referenced **only** by `PortfolioHistoryEngineTests.swift:554`. Dead production vocabulary. Reclassified: unimplemented feature, not a defect. | **Low** | High |
| F-007 | `PriceCheckCoordinator.present:269-284` returns `quoteState: .current` for local evidence with **no USD gate**, while the branch 12 lines below (`:287-299`) documents the opposite rule and returns `.checking`. `evidence(from: PriceRecord)` (`:444-464`) and `evidence(from: ReferenceQuote)` both preserve a non-USD `currencyCode`; `ReferenceQuote.apply` (`:75-90`) has no USD gate either. | Medium | High |
| F-008 | `PriceRefreshController.applyVendorBatchHit:2265` — `guard let amount = variant.marketPriceUSD else { return true }` reports success with no price written; `JustTCGRefreshCoordinator` increments `variantsUpdated`; controller does `priced += report.variantsUpdated` (`:881`) and sets `changedPrices`. | Low | High |
| F-009 | `PriceStore.recordFailure:922-924` clears only `.noSupportedProvider`; `PricingDiagnostics.unpricedReason:112` checks `.invalidProviderQuote` before general provider state, so a stale invalid-quote diagnosis masks a later transport failure. | Low | High |
| F-011 | Legacy sealed CSV rows with no marketplace IDs get `sealed:<game>:<providerID>` (`CollectionCSV.swift:1205-1224`); `CollectionCatalogNormalizer` enriches but preserves the key; `CollectionStore.addSealed` checks only the canonical `sealed:<game>:<product.id>:<variant.id>`. Two exact-key rows for one physical product. | High | High |
| F-012 | `CollectionStore.backfillExistingCollectionIfNeeded:478-489` early-returns on `!hasLegacyActivities && hasCompletedWatermark`. **Trigger is broader than Luna stated:** `hasLegacyActivities` tests for *legacy-shaped activity rows* (`kindRaw == ""`), not for *cards missing activities*. A store containing `CollectedCard` rows with **zero** activities satisfies `!hasLegacyActivities`, so the global `UserDefaults` watermark suppresses the backfill. A store/account switch is sufficient but **not necessary** — CloudKit delivering legacy rows after the watermark is set is enough. | Medium | High |
| F-013 | `BrowseCatalog.swift:907` — `Date.now.timeIntervalSince(envelope.storedAt) < maxAge`. A future `storedAt` yields a negative age, which passes. | Low | High |
| F-014 | `README.md:7-11` links `documentation_audit.md` and `release_followups.md` at the repository root; tracked files are `docs/plans/documentation_audit.md` and `docs/plans/release_followups.md`. Verified by `ls`: both root paths do not exist. | Low | High |

### Rejected — F-003 (centering guides)

Luna reported that guides stay in the unrotated frame while the photo rotates. The observation is
accurate; the conclusion is wrong. Evidence gathered this pass:

- `CardCenteringViewModel.adjustRotation` (`CardCenteringView.swift:70-73`) mutates `rotationDegrees`
  only — it **does not re-run analysis**. `analyze(...)` is invoked solely at load with
  `rotationDegrees: 0` (`:32`, `:67`).
- The export path states the contract explicitly (`CardCenteringView.swift:144-147`): *"Rotation is a
  display adjustment. It does not rerun detection and **it does not move either guide**, so the
  export uses the same visual treatment as the preview."*
- The UI states it to the user: *"Rotates photo only"* (`:547`).
- The exported filename encodes the rotation (`CardCenteringExport.filename(for:rotationDegrees:)`),
  so the artifact is self-documenting.
- Decisively: rotating the guides with the photo would make the rotation control **functionally
  useless**. The guides are the fixed reference the user rotates the card *against*.

Preview and export are mutually consistent, the measured integers are unchanged, and no user is
misled about a measurement. **This is a deliberate, documented, self-consistent design.** No change.

---

## Target Invariants

These govern implementation decisions wherever individual changes interact. Any change that violates
one is wrong even if its own test passes.

- **INV-1 (slab binding).** `ScanSubject.slab` may be non-nil only when the scanner holds positive
  evidence that the slab label and the footer identity came from the same physical object within one
  unbroken presentation.
- **INV-2 (slab lifetime).** Every code path that fences or tears down recognition — `endSession`,
  `stop`, `invalidateSpatialContinuity` — leaves `activeSlab == nil`. Clearing slab state is a
  property of *any* recognition discontinuity, not of one exit route.
- **INV-3 (single currency-policy owner).** Exactly one production symbol decides whether an
  instrument's evidence participates in the USD portfolio total. Current valuation
  (`InventoryLedger`), replay (`PortfolioReplay`), and snapshot normalization (`PortfolioEngine
  .observationEntry`) all consult it and **cannot disagree**.
- **INV-4 (current/replay agreement).** For any sequence of events and observations, an instrument
  is USD-priced in replay's ending state **iff** `InventoryLedger.resolveValuation` reports it
  priced for the same instant. A currency transition is a `pricingAdjustment`, never `market`
  movement, and never a residual.
- **INV-5 (identity preservation).** A collection row exported and re-imported with no intervening
  edit produces the **byte-identical** `collectionKey`, for every `CollectionItemKind`.
- **INV-6 (underlying-printing source of truth).** Any consumer needing a row's underlying printing
  ID reads it through one accessor. Reading `providerID` and parsing it as a printing ID is
  prohibited outside that accessor.
- **INV-7 (completed Price Check = usable USD).** A `PriceCheckResult` with `quoteState == .current`
  carries a usable USD amount. One predicate decides this for both the catalog and local paths.
- **INV-8 (fixture realism).** Any test fixture representing a graded or sealed `CollectedCard`
  constructs it through, or exactly matching, the production shape — including
  `providerID == collectionKey` and a populated `catalogProviderID`.
- **INV-9 (priced ≠ updated).** A refresh outcome counted as `priced` corresponds to a written,
  non-nil `PriceRecord` amount.
- **INV-10 (range honesty).** A history result whose first point precedes the selected range's
  requested start is labeled as an available-history fallback in the UI, not as the selected period.

---

## Requirements

### REQ-001 — Single accessor for a row's underlying printing ID

**Objective.** `CollectedCard` exposes exactly one accessor returning the underlying printing/product
ID regardless of item kind, and it is the only sanctioned way to obtain that value.

**Rationale.** RC-C. Foundation for REQ-002, REQ-003, REQ-013.

**Implementation area.** `TradingCardScanner/Models/CollectedCard.swift`. Add a computed property
(suggested `underlyingPrintingID`). Do **not** change stored properties and do **not** change what
`addGraded` / `addScannedGraded` / `addSealed` write.

**Where the value actually lives today** (verified this review — do not assume a single field):

| Item kind | Creation path | Field holding the underlying ID |
| --- | --- | --- |
| raw | `addCard` etc. | `providerID` |
| graded | `addGraded` (`:1912`), `addScannedGraded` (`:2081`) | `catalogProviderID` (`= card.providerID`) |
| sealed | `addSealed` (`:2185-2205`) | `justTCGCardID` (`= product.id`) — **`catalogProviderID` is never set on this path** |

Required resolution order: `catalogProviderID` when non-nil → `justTCGCardID` when
`itemKind == .sealedProduct` → `providerID` when `itemKind == .rawCard`. A graded or sealed row that
resolves to a value beginning `graded:` or `sealed:` indicates the accessor fell through incorrectly
and must be treated as a failure, not returned.

**Required behavior.**
- Raw row: returns the same value `providerID` returns today.
- Graded row created by `addGraded` or `addScannedGraded`: returns the value passed as
  `card.providerID` at creation (the Scryfall/TCGdex printing ID), never a string beginning `graded:`.
- Sealed row created by `addSealed`: returns the marketplace product ID, never a string beginning
  `sealed:`.
- Returns a non-empty string for every row reachable from production creation paths.

**Constraints.** No SwiftData schema change. No migration. `certifiedGradedCard`'s existing dual
match (`CollectionStore.swift:2500-2502`) must keep working unchanged.

**Dependencies.** REQ-004 must land first so the new accessor is validated against production-shaped
fixtures.

**Verification.** New unit tests that build rows through `CollectionStore.addGraded`,
`addScannedGraded`, and `addSealed` (not hand-constructed) and assert the accessor's return value.

**Existing correct precedent — do not change it.** `BrowseView.swift:361` already resolves this
correctly: `let providerID = card.catalogProviderID ?? card.providerID`. It is the pattern REQ-001
generalizes, and it independently corroborates that `catalogProviderID` is the intended
underlying-ID field. Migrate it to the new accessor if convenient, but **its current behavior must
not regress**; its prefix walk fails safe (`guard components.count > 1`, longest-prefix match against
real catalog set ids) and sealed rows are excluded by the nil-set guard.

**Completion criterion.** A test named to identify REQ-001 asserts, for one row from each of the
three production creation paths plus one raw row, that `underlyingPrintingID` equals the exact
printing/product ID supplied at creation, and that the value does **not** begin with `graded:` or
`sealed:`. Static gate:
`grep -rn "\.providerID\.split" TradingCardScanner/ | grep -v "catalogProviderID ?? "` returns
**0 matches** (currently **1**: `CollectionCardDetailView.swift:483`, which REQ-003 removes). The
gate is deliberately scoped so it cannot flag the already-correct `BrowseView` site.

---

### REQ-002 — CSV export/import preserves collection identity for every item kind

**Objective.** Export followed by import reproduces the byte-identical `collectionKey` for raw,
graded, and sealed rows created by production paths.

**Rationale.** RC-C / C1 (Luna F-010). Direct backup/restore data loss today.

**Implementation area.** `TradingCardScanner/Services/CollectionCSV.swift` — `exportHeaders`,
`export`, `makeEntry`, `apply`.

**Scope precision (verified this review — do not over-apply).** The **graded** path is broken; the
**sealed** path for production rows is **already correct** and must not be changed. `addSealed` sets
`justTCGCardID = product.id` and `justTCGVariantID = product.variantID`; export writes both; import's
`justTCGCardID` branch (`CollectionCSV.swift:1207-1214`) rebuilds
`sealedCollectionKey(productUUID: justTCGCardID, variantUUID: justTCGVariantID ?? justTCGCardID)`,
which reproduces `addSealed`'s key exactly. The sealed gap is the **missing-ID** case only, and that
is REQ-013's subject, not this requirement's.

**Required behavior.**
- `makeEntry` reconstructs **graded** keys from the underlying printing ID
  (`catalog_provider_id`, already exported at `:184` and parsed at `:929`), never from `provider_id`.
- The sealed `justTCGCardID` branch is left unchanged. Only the sealed **fallback** branch
  (`:1216-1223`, no marketplace IDs) is in scope here, and only to the extent of the
  double-prefix rule below.
- Where `catalog_provider_id` is absent (older exports), the importer must not double-prefix: if
  `provider_id` already carries a namespace prefix (`graded:` / `sealed:`), treat it as an already-
  formed collection key rather than as an underlying ID. This is what prevents the verified
  `graded:magic:graded:magic:…` mangling shown in RC-C / C1.
- **Recommended and preferred:** append a `collection_key` column to `exportHeaders` and, when
  present and non-empty, use it verbatim as the row's key. This makes INV-5 structural rather than
  derivational. The importer must remain tolerant of its absence.
- CSV import remains tolerant of every currently-importable file. Adding a column must not break
  parsing of files lacking it.

**Constraints.** Must not change keys produced for rows that already round-trip correctly today
(raw rows; sealed rows carrying marketplace IDs). Must not alter `CollectionStore` creation paths.
Treatment-qualified Magic keys must survive unchanged.

**Dependencies.** REQ-001, REQ-004.

**Verification.** New integration tests: create rows via `addGraded`, `addScannedGraded`, `addSealed`,
and a raw add; `export`; `apply` the document into a **fresh** context; compare keys and quantities.
Plus a fixture of an older export lacking the new column.

**Completion criterion.** A test asserts that for **all four** production creation paths
(`addCard`-style raw, `addGraded`, `addScannedGraded`, `addSealed`), the imported `collectionKey` is
`==` the original, imported `quantity` is `==` the original, and the fresh context contains exactly
**one** row per original row (no duplicate, no split). A second test asserts a `collection_key`-less
document still imports with unchanged keys. A third test asserts the sealed round-trip key is
**unchanged from the pre-implementation value**, proving the working sealed path was not disturbed.

---

### REQ-003 — Graded variant options derive from the underlying printing ID

**Objective.** `CollectionCardDetailView.gradedVariantOptions` produces the same option list a
correctly-identified raw row of the same printing would produce.

**Rationale.** RC-C / C2 (N-001). Today the graded finish-correction menu silently omits Poké Ball /
Master Ball and stamped-release options for every graded Pokémon row.

**Implementation area.** `TradingCardScanner/Views/CollectionCardDetailView.swift:479-495`.
Replace the `providerID.split` derivation with a set ID derived from REQ-001's accessor.

**Required behavior.**
- For a graded Pokémon row whose underlying printing is in a set covered by
  `PokemonVariantRules.all` (`sv08.5`, `sv10.5b`, `sv10.5w`) and whose persisted variant is
  `.reverse`, the returned options include `.pokeBall` and `.masterBall`.
- For a graded row whose underlying printing has a `PokemonStampedReleaseCatalog` entry, the stamped
  variant appears in the returned options.
- For a graded row with no applicable rule, the returned options are unchanged from today.

**Constraints.** Do not widen the list to `PhysicalVariant.selectable`; the persisted row's finish
remains the only catalog fact this offline surface may use. Do not re-add 1st Edition after
`excludingFirstEditionPseudoFinish`.

**Dependencies.** REQ-001.

**Verification.** New unit tests over `gradedVariantOptions` (extract the derivation into a testable
function if the view property is not directly reachable) with a graded row built by
`addScannedGraded` from an `sv08.5` reverse-holo printing.

**Completion criterion.** A test asserts the option list for that row **contains** `.pokeBall` and
`.masterBall`; and a second asserts the derived set ID `== "sv08.5"` exactly (not a string containing
`"graded"`).

---

### REQ-004 — Production-shaped graded and sealed test fixtures

**Objective.** The test target has a shared fixture helper that produces graded and sealed
`CollectedCard` rows matching production exactly, and the fixtures relied on by identity tests use it.

**Rationale.** N-002. This is the structural reason RC-C survived 1,005 passing tests. It must land
**before** REQ-002 and REQ-003 so those requirements are validated against reality.

**Implementation area.** `TradingCardScannerTests/` — a shared helper (suggested
`ProductionRowFixtures.swift`). Prefer helpers that call `CollectionStore.addGraded` /
`addScannedGraded` / `addSealed` against an in-memory container over hand-constructed rows.

**Required behavior.**
- The helper returns rows with `providerID == collectionKey` and a populated `catalogProviderID`
  for graded and sealed kinds, matching `CollectionStore`'s output field-for-field.
- Identity/round-trip/reconciliation tests that assert on graded or sealed keys use the helper.

**Constraints.** **Do not delete or weaken any existing assertion.** Where an existing test depends
on the bare-`providerID` shape, keep it and add a production-shaped counterpart alongside it; a
synthetic-shape test is still valid as a test of the synthetic shape. Any existing assertion that
must change requires an explicit written justification in the evidence table.

**Dependencies.** None. **First requirement to implement.**

**Verification.** A meta-test asserting the helper's output matches a row produced by the
corresponding `CollectionStore` method on every field compared by the identity tests.

**Completion criterion.** A test asserts, for graded and sealed rows, `row.providerID ==
row.collectionKey` **and** `row.catalogProviderID != nil` **and** `row.catalogProviderID !=
row.collectionKey`; and at least the tests at `CollectionKeyTests.swift:158` and
`PortfolioReconciliationTests.swift:900` have production-shaped counterparts.

---

### REQ-005 — One owner for the non-USD transition policy; replay agrees with current

**Objective.** An instrument whose newest evidence is non-USD becomes unpriced in **both** current
valuation and replay, and the transition is attributed as a pricing adjustment.

**Rationale.** RC-B (Luna F-006). Highest-severity verified problem; reachable through
`PriceProvider.cardmarketPrice`.

**Decision (do not re-litigate).** Make **replay agree with current valuation** — i.e. a non-USD
transition *de-prices* the instrument everywhere. Rejected alternative: making current valuation
carry the last USD forward. Reasons: (a) `InventoryLedger` already implements de-pricing and
documents the user-facing contract *"the collection total already excludes those copies and says
so"*; (b) carrying a stale USD forward would value a portfolio on evidence the provider has replaced,
which is the same dishonesty REQ-006 removes from Price Check; (c) de-pricing is the behavior the
user already sees in the collection total, so replay is the side that is out of step.

**Implementation area.**
- `TradingCardScanner/Services/PortfolioReplay.swift:468-473` — the
  `guard observation.participatesInPortfolioValue else { return }` early return.
- `TradingCardScanner/Services/PortfolioClose.swift:30-47` — `ObservationEntry` doc comments.
- `TradingCardScanner/Services/PortfolioEngine.swift:940-957` — `observationEntry(from:)`.
- `TradingCardScanner/Services/InventoryLedger.swift:323-375` — extract the policy predicate.

**Required behavior.**
- A single production symbol answers "does this evidence participate in the USD total". All three
  sites above consult it. (`PortfolioPriceEligibility.eligibleUnitPrice` is the natural home.)
- A non-USD observation superseding a USD-priced instrument produces `new == nil`, contributing to
  `pricingAdjustment` with magnitude `oldPrice × quantity`. It must contribute **zero** to `market`
  and must not set `hasEligibleMarketMovement`.
- A later USD observation for the same instrument re-prices it symmetrically, again as
  `pricingAdjustment`, not `market`.
- `PortfolioEngine`'s residual for this scenario is exactly `Money.zero`.
- Every comment asserting that current valuation carries a prior USD record forward is corrected to
  describe actual behavior.

**Constraints.** Non-USD amounts remain stored in `PriceRecord` and `PriceObservation` for display
and provenance (Non-goal 8). `.explicitInvalidation` handling is unchanged. No FX conversion.
Do not alter `recordSupersedes`.

**⚠ Sanctioned test change.** `PortfolioReplayEngineTests.swift:~200-243`
(`…pricingAdjustment == .zero`, *"a non-USD observation cannot withdraw the USD fallback value"*,
`currentValue == usd(10)`) asserts the behavior this requirement deliberately reverses. It **must**
be updated to expect `pricingAdjustment == usd(-10)` and `currentValue == .zero`, and its message
rewritten to state the new contract. This is a policy change, **not** a weakening: the test becomes
*stronger* because it will then be cross-checked against `resolveValuation` by the new INV-4 test.
This is the **only** pre-existing test this plan authorizes changing; the evidence table must record
it explicitly with this justification.

**Dependencies.** None. Independent of REQ-001..004.

**Verification.** Deterministic. New test asserting INV-4 directly: for a scripted sequence
(USD observation → EUR observation via full `PriceStore.store`), assert that
`InventoryLedger.resolveValuation` and the replay ending state **agree** on priced/unpriced and on
amount. Plus a full-SwiftData scenario per Luna's handoff challenge.

**Completion criterion.** A test named to identify REQ-005 performs: seed a USD price through
`PriceStore.store`; publish/compute; store a newer **EUR** `NormalizedPrice` through the real
`PriceStore.store`; recompute. It asserts **all** of:
1. `InventoryLedger.valuation(forPriceKey:)` returns `.unpriced`;
2. replay's ending state has no USD price for that instrument;
3. `attribution.market == .zero`;
4. `attribution.pricingAdjustment == -(oldUnitPrice × quantity)`;
5. `attribution.unexplained == .zero`;
6. `PortfolioEngine` emits **zero** residual defects for the run.

---

### REQ-006 — A completed Price Check requires a usable USD amount

**Objective.** `PriceCheckResult.quoteState == .current` is returned only for a usable USD amount,
on both the catalog and local-evidence paths.

**Rationale.** F-007. `PriceCheckCoordinator.present:269-284` returns `.current` with no USD gate
while `:287-299` documents the opposite rule twelve lines below.

**Implementation area.** `TradingCardScanner/Services/PriceCheckCoordinator.swift` — the
`localEvidence` branch at `:269-284`; reuse `isUsableUSD` (`:501-505`).

**Required behavior.**
- Non-USD local evidence (from `PriceRecord` **or** `ReferenceQuote`) no longer yields
  `quoteState: .current`. It takes the `.checking` path at `:287-299`, which already schedules the
  one permitted background refresh.
- USD local evidence behaves exactly as today, including `shouldAutoRefresh: Self.isStale(local)`.
- The non-USD amount and its currency remain visible to the user as local evidence; this requirement
  changes the **state**, not whether the number is shown.

**Constraints.** Do not change `QuoteCache` isolation (Non-goal 4). Do not change `ReferenceQuote
.apply`'s willingness to cache a non-USD quote. Do not change the live catalog path.

**Dependencies.** None.

**Verification.** New unit tests on `present` with a seeded non-USD `PriceRecord`, and separately a
non-USD `ReferenceQuote`, with the catalog quote unusable.

**Completion criterion.** A test asserts that with non-USD local evidence and an unusable catalog
quote, the returned `quoteState == .checking`; and a companion test asserts that with USD local
evidence the returned `quoteState == .current`. Both must be present — the second prevents the fix
from over-applying.

---

### REQ-007 — Slab evidence binds only with continuity proof

**Objective.** Unbound slab evidence cannot attach to an identity the scanner has not proven belongs
to the same physical presentation.

**Rationale.** RC-A / A1 (Luna F-001). Satisfies INV-1.

**Implementation area.** `TradingCardScanner/Services/CardScanner.swift:2071-2101`
(`updateActiveSlabPresence`) and `:1798-1801` (`handleFooterOutcome`).

**Required behavior.**
- Late binding (`activeSlabBaseIdentifier == nil` → adopt `footerIdentifier`) is permitted **only**
  while the scanner holds unbroken presentation continuity with the frame the label was read from.
  Suggested mechanism: stamp the label evidence with the tracker/encounter identity at
  `applySlabLabelEvidence` time and require that identity still be current at binding time.
- If continuity has been lost or the tracker identity has changed since the label was read, the slab
  is cleared (a new clear cause is appropriate) and the subject is emitted **without** slab evidence.
- Label-first bootstrap continues to work when continuity holds (Non-goal 3): a label read, then a
  footer identity on the same continuous presentation, still produces a slab-bearing subject.

**Constraints.** Must not regress `CardLatchTests.swift:474`. Must not make a genuine slab
unscannable. Once a non-nil base identifier exists, existing `.identityChanged` behavior is unchanged.

**Dependencies.** Coordinate with REQ-008 — both touch `activeSlab` lifetime; implement REQ-008
first so the clearing primitive exists.

**Verification.** Deterministic unit tests driving `CardScanner`'s recognition entry points with
scripted outcomes. No camera required.

**Completion criterion.** A test feeds: (1) a slab label with no footer identity, (2) a continuity
break, (3) a footer identity for a **different** printing — and asserts the emitted `ScanSubject`
has `slab == nil`. A second test feeds label → footer identity with continuity intact and asserts
the emitted `ScanSubject.slab` carries the original grade and certification number. Both required.

---

### REQ-008 — Every recognition-discontinuity path clears slab state

**Objective.** `activeSlab` is nil after `endSession`, `stop`, and `invalidateSpatialContinuity`.

**Rationale.** RC-A / A2 (Luna F-002). Satisfies INV-2. Concrete trigger: backgrounding while the
scanner tab is visible routes `viewDisappeared` to `scanner.stop()`.

**Implementation area.** `TradingCardScanner/Services/CardScanner.swift` — `stop()` (`:1012`),
`invalidateSpatialContinuity()` (`:1166`). Both already dispatch to `visionQueue`, where
`clearActiveSlab` belongs.

**Required behavior.**
- `stop()` clears `activeSlab` (and the associated `activeSlabBaseIdentifier`,
  `activeSlabEmptyFrames`, grace/hint state) on the vision queue.
- `invalidateSpatialContinuity()` does the same.
- Existing clear causes and their behavior are unchanged; a new cause may be added for
  attribution/diagnostics.
- No path re-enters the slab recovery state as a result of these clears.

**Constraints.** Must not stop the camera in `invalidateSpatialContinuity` (it is a recognition
fence, not a session boundary). Must not regress existing lifecycle/fencing tests. Must not clear
slab state on an ordinary `pauseRecognition`, which is not a discontinuity.

**Dependencies.** None. Implement before REQ-007.

**Verification.** Deterministic unit tests. Additionally, a structural test is required (see
completion criterion) because a future teardown path would silently reintroduce the defect.

**Completion criterion.** A test activates slab evidence, then for **each** of `endSession()`,
`stop()`, and `invalidateSpatialContinuity()` (each from a fresh activated state) drains the vision
queue and asserts that a subsequently identified subject has `slab == nil`. All three assertions must
be present and passing.

---

### REQ-009 — History discloses an available-history anchor

**Objective.** When the chart's first point precedes the selected range's requested start, the UI
says so.

**Rationale.** F-004. Satisfies INV-10.

**Implementation area.** `TradingCardScanner/Services/PortfolioHistoryEngine.swift:8-45` (the result
already carries `trackingBeganDate`); `TradingCardScanner/Views/PortfolioHistoryView.swift:18-72`;
range/period labels in `PortfolioView.swift:334-364, 544-566`.

**Required behavior.**
- `PortfolioHistoryResult` distinguishes "anchored inside the requested range" from "anchored at the
  oldest available close because the requested window was empty". If `trackingBeganDate` already
  encodes this unambiguously, expose it; otherwise add an explicit flag.
- When the fallback anchor is used, `PortfolioHistoryView` displays copy naming the actual covered
  interval. The existing "History is being recorded" message is not sufficient — it is shown for a
  different condition (too few points) and does not state the interval mismatch.
- Numeric values, the anchor selection, and the point series are **unchanged**. This is a disclosure
  requirement, not a calculation change.

**Constraints.** Do not change the fallback policy itself — showing available history is correct.
Do not change `accountingInterval` values.

**Dependencies.** None.

**Verification.** Engine unit test plus a view-model-level assertion on the rendered disclosure.

**Completion criterion.** A test supplies closes **only** at dates before a selected 1W range's
requested start, calls `calculate`, and asserts (a) the result flags the fallback anchor, (b) the
first point's date `<` `requestedStart`, and (c) the view layer's disclosure text for that result is
non-nil and distinct from the too-few-points message.

---

### REQ-010 — Late inventory truth is classified when it occurs

**Objective.** `PortfolioRevisionReason.lateInventoryTruth` is assigned by production when a
republished close changed because of an event recorded after publication but occurring before the
cutoff.

**Rationale.** F-005 (downgraded to Low; reclassified as unimplemented feature). Today the case is
unreachable in production — the enum case and its user-facing copy at
`PortfolioHistoryTypes.swift:147` are dead.

**Implementation area.** `TradingCardScanner/Services/PortfolioEngine.swift:~753-823` — the
`revisionReason: existing == nil ? nil : .recomputed` assignment.

**Required behavior.**
- When republishing an existing close, the publisher examines contributing `InventoryEvent`s. If at
  least one has `occurredAt <= close.cutoff` **and** `recordedAt > existing.publishedAt` (the prior
  revision's publication instant), the new revision's reason is `.lateInventoryTruth`.
- Otherwise `.recomputed`, exactly as today.
- Numeric close values, revision numbering, and publication behavior are unchanged.

**Constraints.** Must not reclassify ordinary local recomputation. If the prior revision's
publication instant is not available on the model, prefer adding it over guessing from `date`.

**Dependencies.** None. Lowest priority of the behavioral requirements.

**Verification.** Deterministic publisher test.

**Completion criterion.** A test publishes a close, inserts an `InventoryEvent` with `occurredAt`
before the cutoff and `recordedAt` after publication, republishes, and asserts the new close's
`revisionReason == .lateInventoryTruth`. A companion test asserts an ordinary recomputation with no
late event still yields `.recomputed`. Both required.

---

### REQ-011 — "Priced" counts only written prices

**Objective.** Refresh reporting distinguishes a metadata-only vendor hit from a written price.

**Rationale.** F-008. Satisfies INV-9.

**Implementation area.** `TradingCardScanner/Services/PriceRefreshController.swift:2265`
(`applyVendorBatchHit`) and `:881` (`priced += report.variantsUpdated`);
`TradingCardScanner/Services/JustTCGRefreshCoordinator.swift:274-319`.

**Required behavior.**
- The apply result distinguishes "identity/artwork applied, no price" from "price written".
- `JustTCGRefreshCoordinator`'s report carries both counts separately.
- The controller's `priced` accumulates only price-written outcomes; `changedPrices` is set only
  when a price was actually written.
- Metadata/artwork backfill behavior is **unchanged** — the null-price path must keep applying
  identity and artwork (`CollectionItemKindTests.swift:366-405` must keep passing).

**Constraints.** Must not suppress the metadata write. Must not change batching, checkpointing, or
the sync watermark.

**Dependencies.** None.

**Verification.** Deterministic test through the coordinator and controller with a null-price batch.

**Completion criterion.** A test runs a one-owner batch whose `variant.marketPriceUSD == nil` and
asserts: the identity/artwork fields **are** written, the resulting `PriceRecord` amount is `nil`,
the controller's `priced` count is `0`, and `changedPrices` is `false`. A companion test with a
non-nil price asserts `priced == 1` and `changedPrices == true`.

---

### REQ-012 — A later ordinary failure clears a stale invalid-quote diagnosis

**Objective.** `PricingDiagnostics.unpricedReason` reflects the most recent attempt's failure mode.

**Rationale.** F-009.

**Implementation area.** `TradingCardScanner/Services/PriceStore.swift:898-925` (`recordFailure`),
which today clears only `.noSupportedProvider`.

**Required behavior.**
- `recordFailure` clears a previously recorded `.invalidProviderQuote` reason, so the diagnosis
  describes the latest attempt.
- `.noSupportedProvider` clearing behavior is unchanged (it already clears, deliberately).
- The prior valid price value is untouched — this changes only `lastFailureReasonRaw`.

**Constraints.** Do not change the `.unavailable` store path, which already clears non-capability
diagnoses for its own documented reason. Do not clear the capability stamp written by
`PriceStore`'s capability-gap path.

**Dependencies.** None.

**Verification.** Deterministic unit test.

**Completion criterion.** A test stores a rejected invalid quote (asserting
`lastFailureReasonRaw == PricingDiagnosticReason.invalidProviderQuote.rawValue`), calls
`recordFailure` for the same key, and asserts `PricingDiagnostics.unpricedReason` no longer returns
`.invalidProviderQuote`. A companion test asserts the stored price amount is unchanged across both
calls.

---

### REQ-013 — Imported sealed rows converge with Browse-added rows

**Objective.** A legacy sealed row lacking marketplace IDs, once enriched with product/variant
metadata, occupies the same collection identity as the same product added from Browse.

**Rationale.** F-011. One physical product must not become two positions.

**Implementation area.** `TradingCardScanner/Services/CollectionCatalogNormalizer.swift:147-185`
(which deliberately preserves the key today) and/or `CollectionStore.addSealed`
(`:2118-2157`, which checks only the canonical key). Choose one owner:
- **Preferred:** normalization rekeys the synthetic `sealed:<game>:<providerID>` row to the canonical
  `sealed:<game>:<product.id>:<variant.id>` once both IDs are known, reusing the existing rekey /
  lineage machinery (`PriceIdentityLineageMigration`, ledger/activity rekey used by
  `MagicTreatmentMigration`) so activities, ledger events, and price keys follow.
- **Alternative:** `addSealed` also probes for a synthetic-key row matching the product and merges.

**Required behavior.**
- After normalization, exactly **one** `CollectedCard` exists for the product.
- Quantities are summed, not duplicated; activity and ledger history is preserved and addressable
  under the surviving key.
- `CatalogOwnershipIndex` totals and the Collection projection agree on the quantity.
- Rows that already carry canonical IDs are untouched.

**Constraints.** Must not merge two genuinely distinct sealed products. Must not lose acquisition
history. Rekeying must be atomic with respect to ledger/activity rows — a partial rekey is worse than
the duplicate.

**Dependencies.** REQ-001, REQ-004.

**Verification.** Integration test across import → normalize → Browse add.

**Completion criterion.** A test imports a sealed CSV row with **no** `justtcg_card_id` and no
`justtcg_variant_id`, normalizes it against a matching product, then calls `addSealed` for that
product, and asserts: total `CollectedCard` count for the product `== 1`; that row's `quantity ==`
the sum of both additions; the ownership-index total for the product `==` the same number; and the
collection activities for the product sum to that quantity.

---

### REQ-014 — Backfill precondition tests the condition the backfill repairs

**Objective.** The existing-collection activity backfill runs whenever collection rows lack
activities, regardless of a previously set global watermark.

**Rationale.** F-012, with the broadened trigger established in this review: the cheap precondition
tests for *legacy-shaped activity rows* (`kindRaw == ""`), not for *cards missing activities*, so a
store whose rows have **zero** activities satisfies `!hasLegacyActivities` and is skipped.

**Implementation area.** `TradingCardScanner/Services/CollectionStore.swift:467-525`.

**Required behavior.**
- The early return additionally requires that no `CollectedCard` lacks a corresponding
  `CollectionActivity`. A cheap check is acceptable (e.g. compare `fetchCount` of cards against the
  count of distinct activity collection keys) provided it cannot return "complete" while a card has
  no activity.
- **Preferred, and additionally required if cheaply achievable:** scope the watermark to the active
  persistent store / container identity rather than a bare `UserDefaults.standard` key, so a
  different store cannot inherit another's completion.
- Idempotence is preserved: a store whose rows all have activities performs no writes and no commit.

**Constraints.** Must not make every launch perform a full fetch-and-compare of all rows when the
collection is large and already complete — the guard must stay cheap enough for launch. Must not
create duplicate activities for rows that already have them.

**Dependencies.** None.

**Verification.** Deterministic tests over two sequential in-memory contexts sharing defaults.

**Completion criterion.** A test completes the backfill in context A, then opens context B containing
`CollectedCard` rows and **zero** `CollectionActivity` rows with the same `UserDefaults`, runs the
backfill, and asserts context B gains exactly one `added` activity per card with
`deltaQuantity == card.quantity`. A companion test asserts a second run over the now-complete
context B performs **no** writes (activity count unchanged).

---

### REQ-015 — Future-dated cache envelopes are not fresh

**Objective.** A cache envelope stamped in the future is treated as stale.

**Rationale.** F-013.

**Implementation area.** `TradingCardScanner/Services/BrowseCatalog.swift:907` —
`let isFresh = maxAge.map { Date.now.timeIntervalSince(envelope.storedAt) < $0 } ?? true`.

**Required behavior.** Freshness requires a non-negative age within `maxAge`. A negative age (future
`storedAt`) is not fresh. The `maxAge == nil` ("always fresh") case is unchanged. The cached value is
still returned — only `isFresh` changes, so offline presentation is unaffected.

**Constraints.** Do not delete or rewrite the envelope. Do not change `BrowseCatalogStore
.markRefreshSucceeded`, which has its own future-timestamp handling and its own test at
`BrowseFeatureTests.swift:2520-2532`.

**Dependencies.** None.

**Verification.** Deterministic unit test on the loader.

**Completion criterion.** A test loads an envelope with `storedAt == Date.now + 3600` and a
`maxAge` of 600 and asserts `isFresh == false` and the returned value is non-nil. A companion test
with `storedAt == Date.now - 60` asserts `isFresh == true`.

---

### REQ-016 — README links resolve

**Objective.** Both primary navigation links in `README.md` resolve to tracked files.

**Rationale.** F-014.

**Implementation area.** `README.md:7-11`.

**Required behavior.** `documentation_audit.md` → `docs/plans/documentation_audit.md`;
`release_followups.md` → `docs/plans/release_followups.md`. Verify the `progress.md` link in the same
paragraph resolves; correct it if it does not.

**Constraints.** Do not move or rename the target documents. Do not edit historical links inside
archived plan documents.

**Dependencies.** None.

**Verification.** Static path resolution.

**Completion criterion.** For every Markdown link target in `README.md`, `test -e <resolved path>`
succeeds. Record the command and its output in the evidence table.

---

## Test and Validation Design

### Deterministic gates (pass/fail; no judgment)

All of REQ-001 … REQ-016 are deterministic. Every completion criterion above is a concrete
assertion. Classification by validation type:

| Type | Requirements |
| --- | --- |
| New unit tests | 001, 003, 005, 006, 007, 008, 009, 010, 011, 012, 014, 015 |
| New integration tests (SwiftData, multi-subsystem) | 002, 005, 013, 014 |
| Test-infrastructure change | 004 |
| Static / build validation | 001 (grep gate), 016 |
| Existing tests that must keep passing unchanged | `CardLatchTests.swift:474` (REQ-007), `CollectionItemKindTests.swift:366-405` (REQ-011), `BrowseFeatureTests.swift:2520-2532` (REQ-015), `PortfolioReconciliationTests.swift:1034-1065` (REQ-002/004) |

### Stochastic measurement

**This plan introduces no performance requirement and no stochastic gate.** Luna promoted no
complexity finding, and this review found none. Cold-launch, 8 Hz tracking, projection coalescing,
and live-refresh profiles remain device measurement items in
`review/luna-whole-repo/06-device-and-environment-validation.md` and are explicitly **not**
blockers for any REQ here.

The one guard against a performance regression is stated as a constraint, not a metric: REQ-014's
backfill precondition must not perform a full row-by-row comparison on every launch of a large,
already-complete collection. If the implementer cannot satisfy this with a cheap count comparison,
they must record the chosen approach and its cost in the evidence table rather than silently
accepting a launch-time scan.

### Sanctioned pre-existing test changes

Exactly **one** is authorized: `PortfolioReplayEngineTests.swift:~200-243`, under REQ-005, with the
justification recorded there. Any other change to a pre-existing assertion is a violation of the
Definition of Done and must be reported as blocked rather than performed.

---

## Physical-Device Validation

These cannot be honestly proven in simulator or unit tests. Mark them **DEVICE-PENDING**; they do
**not** block any REQ's implementation or its automated completion criterion.

### DEV-01 — Slab evidence does not cross physical objects (REQ-007, REQ-008)

- **Setup.** iPhone running a Debug build. Two graded slabs, *ideally of the same printing* with
  different certification numbers (the hardest case for identity-change clearing), plus one raw card
  of that printing.
- **Sequence A (binding).** Present slab 1 so its label is read before the footer is legible. Before
  any footer identity resolves, swap to slab 2 **without** letting the footer band go empty (slide
  laterally, keeping text in the band). Continue until a scan is authorized.
- **Sequence B (lifecycle).** Activate slab 1's label. Background the app (home gesture) while the
  scanner tab is visible. Return to the foreground. Present the raw card. Scan.
- **Observe.** The grade and certification number written to the collection row.
- **Pass rule.** In Sequence A, the recorded row carries either slab 2's certification or no slab
  evidence — **never** slab 1's certification on slab 2's identity. In Sequence B, the raw card's row
  carries **no** slab evidence. Repeat each sequence **5 times**; any single failure fails the gate.
- **Depends on.** REQ-007, REQ-008.

### DEV-02 — Cardmarket EUR transition in the wild (REQ-005)

- **Setup.** Device with network. A Pokémon promo card whose TCGdex entry carries a Cardmarket price
  and no TCGplayer figure (the `PriceProvider.cardmarketPrice` path).
- **Sequence.** Add the card while a USD price is available. Force a refresh once the provider
  returns only the Cardmarket figure. Open the portfolio and the history chart.
- **Observe.** Current total, history value at the same instant, the card's pricing diagnostic, and
  any residual defect surfaced.
- **Pass rule.** Current total and history agree; the change is attributed as a pricing adjustment,
  not market movement; **zero** residual defects reported.
- **Note.** If a qualifying live card cannot be located, record the gate as DEVICE-PENDING-BLOCKED
  with the search performed. REQ-005's automated criterion stands on its own.
- **Depends on.** REQ-005.

### DEV-03 — CloudKit legacy delivery and backfill (REQ-014)

- **Setup.** Two devices on one iCloud account, CloudKit-backed store.
- **Sequence.** Complete the backfill on device A. Introduce collection rows lacking activities
  (restore a pre-activity backup, or install an older build, add cards, then upgrade). Allow sync to
  device B. Launch device B.
- **Observe.** Whether device B creates the missing activities before portfolio epoch establishment.
- **Pass rule.** Every synced card has at least one `added` activity, and portfolio history is
  authoritative (no epoch warning).
- **Depends on.** REQ-014.

### DEV-04 — Carried forward unchanged from Luna

The external boundaries in `05-rejected-hypotheses-and-uncertainties.md` (physical camera/OCR rates,
CloudKit account switching, live provider schemas, release signing, performance) and the procedures
in `06-device-and-environment-validation.md` remain open and are **not** superseded by this plan.

---

## Regression Protection

Before the Pursue Goal run may be declared complete:

1. **Full suite.** `xcodebuild test` over the whole test target. Baseline is **1,005 executed,
   1 skipped, 0 failures**. Post-implementation: **0 failures**, executed count `≥ 1,005` plus the
   new tests. A decrease in executed count must be explained in the evidence table.
2. **Release simulator build.** `xcodebuild -configuration Release` for the simulator destination
   must succeed, matching Luna's recorded baseline.
3. **Targeted suites that must remain green, named explicitly** (these guard behavior this plan
   deliberately does not change): `CardLatchTests`, `VariantResolverTests`, `MagicTreatmentTests`,
   `PricingTests`, `PortfolioReconciliationTests`, `PortfolioHistoryEngineTests`,
   `PortfolioReplayEngineTests`, `CollectionItemKindTests`, `CollectionKeyTests`, `QuoteCacheTests`,
   `BrowseFeatureTests`, `CollectionQueryTests`, `ScannerViewModelTests`.
4. **Flow rechecks** (must be reasoned about explicitly and recorded, even where automated):
   - scan → resolve → collection mutation → activity/ledger → projection;
   - refresh → observation → record → current valuation → replay → close publication;
   - CSV export → import → projection → portfolio position;
   - Browse add → ownership index → collection projection;
   - launch → backfill → epoch → first projection.
5. **Behavior that must be bit-for-bit unchanged:** centering preview and export rendering; Magic
   treatment/finish vocabulary and the 5,150-entry catalog; `VariantResolver` precedence; the
   collection key format for rows already canonical; `QuoteCache`'s isolation from `PriceRecord`.
6. **`git diff --check`** passes; no temporary derived-data or build artifacts are committed.

---

## Implementation Order

Ordered by real dependency and by the principle that a requirement's validation must be trustworthy
when it lands.

**Phase 1 — Verification foundation (must be first).**
1. **REQ-004** — production-shaped fixtures. Everything in RC-C is currently invisible *because* the
   fixtures are wrong. Landing this first means REQ-001/002/003/013 are validated against reality
   rather than against the same fiction that hid the defects. Expect REQ-004 to surface failures in
   existing tests; those failures are the finding, not a regression.

**Phase 2 — RC-C, the identity root cause.**
2. **REQ-001** — the accessor. Foundation for all of RC-C.
3. **REQ-002** — CSV identity preservation (highest user-facing data loss in this group).
4. **REQ-003** — graded variant options. Small, and its correctness is obvious once REQ-001 exists.
5. **REQ-013** — sealed convergence. Last in this phase because it is the only one requiring a
   rekey/lineage migration, and it benefits from REQ-001/002 being settled.

**Phase 3 — RC-B, the valuation root cause.** Independent of Phase 2; may proceed in parallel.
6. **REQ-005** — currency-policy ownership. Do this before REQ-006 so the policy predicate exists
   and REQ-006 can consult the same notion of "usable USD".
7. **REQ-006** — Price Check USD gate.

**Phase 4 — RC-A, the scanner root cause.** Independent of Phases 2–3.
8. **REQ-008** — lifecycle clearing. **Before** REQ-007: it establishes the clearing primitive and
   the "any discontinuity clears" invariant that REQ-007's binding rule leans on. Doing REQ-007 first
   would build a binding-proof mechanism on top of state that still survives teardown.
9. **REQ-007** — binding proof.

**Phase 5 — Independent defects.** No interdependencies; ordered by descending value.
10. **REQ-014** — backfill precondition (history authority).
11. **REQ-011** — priced-count semantics.
12. **REQ-009** — history range disclosure.
13. **REQ-012** — diagnostic clearing.
14. **REQ-015** — cache future skew.
15. **REQ-010** — late inventory truth (lowest severity; a feature completion).
16. **REQ-016** — README links.

**Cross-phase notes.**
- Phases 2, 3, and 4 touch disjoint subsystems and cannot conflict.
- REQ-005 and REQ-011 both touch refresh-adjacent reporting but at different layers
  (valuation policy vs. count bookkeeping); implement REQ-005 first and re-run REQ-011's
  completion criterion afterward.
- REQ-002 and REQ-013 both touch `CollectionCSV`; REQ-002 first, then re-run its completion
  criterion after REQ-013 lands.

---

## Global Definition of Done

**Binding.** The Pursue Goal run may not be declared complete until every item below is satisfied and
evidenced. Implementing a majority of the plan is not completion.

1. Every `REQ-001` … `REQ-016` is implemented, or explicitly classified as externally blocked with
   the blocking cause named. Only `DEV-01` … `DEV-04` may be **DEVICE-PENDING**; **no REQ may be.**
2. Every requirement's individual completion criterion has been executed against the current
   repository and its literal result recorded — not inferred, not assumed from a related test.
3. All required new automated tests exist and pass. Each new test is traceable to the REQ it proves
   (by name or by an in-file comment naming the REQ ID).
4. All pre-existing tests pass, **except** the single sanctioned change in
   `PortfolioReplayEngineTests` under REQ-005, which must be recorded with its justification.
5. The full regression suite in **Regression Protection** passes: `0` failures, executed count
   `≥ 1,005` plus new tests.
6. Release simulator build succeeds.
7. **No acceptance criterion in this plan has been weakened, deleted, skipped, reinterpreted, or
   rewritten to make implementation easier.** If a criterion proves wrong or impossible, stop and
   report it as blocked with evidence — do not adjust it.
8. **No test has been weakened, deleted, `XCTSkip`-ed, or had an assertion removed merely to make
   the implementation pass.** The one sanctioned change under REQ-005 is a policy reversal that makes
   the test stricter, and is the only permitted exception.
9. All ten target invariants (INV-1 … INV-10) hold in the final implementation. Each is individually
   reconciled and recorded.
10. A cross-requirement reconciliation has been performed: for each pair of requirements touching a
    shared file or subsystem (REQ-002/REQ-013; REQ-005/REQ-006; REQ-005/REQ-011; REQ-007/REQ-008;
    REQ-001/REQ-002/REQ-003/REQ-013), the earlier requirement's completion criterion has been
    **re-executed** after the later one landed, and the result recorded.
11. Every flow listed in **Regression Protection** item 4 has been rechecked and the recheck recorded.
12. Physical-device requirements are preserved as **DEVICE-PENDING** with the exact manual
    instructions from the **Physical-Device Validation** section copied into the final report. They
    must not be marked passed, and their absence must not be used to mark any REQ complete or
    incomplete.
13. No unresolved automatable work remains. Any `TODO`, stub, or "follow-up" introduced during the
    run is either resolved or recorded as a named, justified blocked item.
14. The implementation agent produces an **evidence table** mapping every `REQ-001` … `REQ-016` and
    every `DEV-01` … `DEV-04` to: implementation (files and symbols changed) · tests/validation
    (test names and commands) · literal result · completion status
    (`COMPLETE` / `BLOCKED` / `DEVICE-PENDING`). The table must also record: the REQ-005 test change
    with its justification; any existing assertion that changed under REQ-004 with its justification;
    and the REQ-014 backfill-guard approach and its launch cost.
15. **Immediately before declaring the Pursue Goal complete, the implementation agent must re-read
    this entire plan from disk** (`review/opus-implementation-plan.md`) and perform a fresh,
    requirement-by-requirement completion audit against the current repository state — not against
    its own memory or summary of the run. Any requirement that cannot be re-evidenced at that moment
    is not complete. This step exists because the run is expected to span context compaction; a
    summary of earlier work is **not** acceptable evidence.

**Explicit anti-shortcut clauses.** Each of the following would satisfy a naive reading of some
criterion above while leaving the original problem unfixed. Each is prohibited.

- Adding a `collection_key` CSV column (REQ-002) **without** fixing `makeEntry`'s graded/sealed
  reconstruction. Older exports lack the column and must still import correctly.
- Satisfying REQ-005 by special-casing the test's instrument, by clamping the residual, or by
  suppressing the residual defect rather than making replay and current valuation agree.
- Satisfying REQ-007 by disabling label-first bootstrap entirely. Both of its assertions —
  the negative **and** the positive — must pass.
- Satisfying REQ-008 by clearing slab state inside `pauseRecognition`, which is not a discontinuity,
  instead of in `stop` and `invalidateSpatialContinuity`.
- Satisfying REQ-006 by gating the local path so aggressively that USD local evidence stops returning
  `.current`. The companion assertion exists to catch this.
- Satisfying REQ-014 by removing the watermark entirely and re-scanning every row on every launch.
- Satisfying REQ-004 by deleting or rewriting the existing synthetic-fixture tests instead of adding
  production-shaped counterparts beside them.
