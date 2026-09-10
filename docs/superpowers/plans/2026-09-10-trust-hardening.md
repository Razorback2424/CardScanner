# Trust Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax (- [ ]) for tracking.

**Goal:** Make delayed pricing, portfolio valuation, graded identity, and variant provenance converge on one defensible trust contract, then provide a reproducible manual benchmark record.

**Architecture:** Keep the existing GradedCardIdentity as the identity boundary. Add one pure USD eligibility rule for all portfolio valuation paths, make source-clock ordering strict only when both clocks are trustworthy, and introduce a separate VariantResolution certainty/presentation policy. Use the existing SwiftData/XCTest surfaces and DEBUG route infrastructure; do not add binder-page scanning.

**Tech Stack:** Swift, SwiftUI, SwiftData, XCTest, Xcode build-for-testing/test, iOS Simulator simctl, Markdown benchmark records.

---

## Working-tree constraints

The checkout is already on the feature branch collection-tile-footer-audit and contains user-owned uncommitted changes in collection, pricing, refresh, and test files. Preserve those changes. The current tree already includes partial implementations of the newer source-stamp rule, print-run propagation, and currency transition coverage; each must be verified and completed in place rather than reverted or recreated.

### Task 1: Establish the baseline and benchmark contract

**Files:**
- Read: progress.md
- Read: defect_review_pass_1.md
- Read: TradingCardScanner.xcodeproj/project.pbxproj
- Create: docs/benchmarks/trust-adversarial-benchmark.md
- Modify: progress.md

- [ ] **Step 1: Record the current worktree and available test destination**

Run:

~~~bash
git status --short
xcrun simctl list devices booted
~~~

Expected: the known user-owned modified files are listed, and either the configured quality simulator is booted or its UUID is available for the screenshot harness.

- [ ] **Step 2: Run the pre-change focused suites**

Run:

~~~bash
xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -only-testing:TradingCardScannerTests/PricingTests -only-testing:TradingCardScannerTests/PortfolioReconciliationTests -only-testing:TradingCardScannerTests/JustTCGContractTests
~~~

Expected: either the current baseline result is recorded, or the exact pre-existing simulator/build failure is recorded before implementation continues. Do not attribute a baseline failure to this plan.

- [ ] **Step 3: Create the benchmark recording template before feature work**

Create docs/benchmarks/trust-adversarial-benchmark.md with these exact sections:

~~~markdown
# Trust Adversarial Benchmark

Run status: Not executed — requires manual sessions in this repository.
Card count: 150–300 planned.
Games: Pokémon and Magic, using the same card cases across competitors where supported.

## Protocol

Use deliberately difficult cards: shared-art reprints, reverse holos, etched foils,
Poké Ball and Master Ball holos, 1st Edition versus Unlimited, Japanese printings,
reflective sleeves/toploaders, low light, and unusual layouts. Reset each app's
collection state between cases. Stop the clock when the correct physical card is
persisted or the app explicitly asks for information. Record whether an incorrect
candidate was caught before persistence.

## Outcome definitions

| Outcome | Meaning |
| --- | --- |
| Exact autonomous match | Correct physical card persisted with no help |
| Correct intervention | Evidence was insufficient and the app asked |
| Wrong but caught | Recognition error intercepted before persistence |
| Confidently wrong | Wrong identity silently became collection data |
| No result | Scanner abstained or failed |

## Per-case record

| Case | Game | Card/evidence | App | Outcome | Time to usable result (s) | Notes |
| --- | --- | --- | --- | --- | ---: | --- |

## Summary

| App | Exact autonomous | Correct intervention | Wrong but caught | Confidently wrong | No result | Median usable time (s) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |

## Publication check

Internal decisions may use the records above. Before publishing comparative claims,
review each competitor's terms and the provenance of every timing/result statement.
~~~

- [ ] **Step 4: Add one progress entry**

Append a short line to progress.md saying that the trust-hardening design and benchmark template were created, with the baseline test result left as the next recorded checkpoint.

### Task 2: Correct source-clock ordering without duplicating decision policy

**Files:**
- Modify: TradingCardScannerTests/PortfolioReconciliationTests.swift
- Modify: TradingCardScanner/Services/PriceObservationLog.swift:687-704

- [ ] **Step 1: Add a failing equal-stamp regression test**

Add a test beside the existing delayed-source-clock test. It must create a previous marketUpdate with amount $20, source justTCG, effectiveAt == receivedAt == t, then a synced PriceRecord with amount $30, the same source clock t, and a later local knowledge time. Assert that reconciliation returns two observations and the newer observation has $30.

~~~swift
func testEqualSourceClockAcceptsAChangedValueForDecisionRules() throws {
    let context = try makeContext()
    let sourceClock = Date(timeIntervalSince1970: 3_000)
    let learnedAt = Date(timeIntervalSince1970: 4_000)
    let record = PriceRecord(key: "equal-stamp", game: .pokemon, printingID: "p", variantID: nil)
    record.apply(NormalizedPrice(
        unitMarketPriceUSD: 30,
        currencyCode: "USD",
        source: .justTCG,
        sourceVariantID: "new",
        sourceUpdatedAt: sourceClock,
        fetchedAt: sourceClock
    ))
    context.insert(record)
    context.insert(PriceObservation(
        instrumentKey: "equal-stamp",
        kind: .marketUpdate,
        amount: money(20),
        currencyCode: "USD",
        source: .justTCG,
        sourceVariantID: "old",
        marketVariantID: nil,
        effectiveAt: sourceClock,
        receivedAt: sourceClock,
        isSourceStamped: true
    ))
    try context.save()

    let rows = PriceObservationLog(context: context)
        .reconcileSyncedRecordsAndReturnObservations(learnedAt: learnedAt)

    XCTAssertEqual(rows.filter { $0.instrumentKey == "equal-stamp" }.count, 2)
    XCTAssertEqual(
        rows.filter { $0.instrumentKey == "equal-stamp" }.max(by: { $0.receivedAt < $1.receivedAt })?.amount,
        money(30)
    )
}
~~~

- [ ] **Step 2: Run only the new test and confirm the correct failure**

Run:

~~~bash
xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -only-testing:TradingCardScannerTests/PortfolioReconciliationTests/testEqualSourceClockAcceptsAChangedValueForDecisionRules
~~~

Expected: FAIL because the current source-clock guard uses <= and rejects the equal-stamp record before PriceObservationRules.decide can append it.

- [ ] **Step 3: Implement the minimal ordering correction**

In isOutOfOrder, keep the invalidation exemption and fallback watermark unchanged. For a source-stamped record and source-stamped previous observation, change the comparison to:

~~~swift
// A strictly older provider clock is out of order. Equality is accepted on
// purpose: the provider may have coarse clock precision or reuse a timestamp
// for a changed value, and PriceObservationRules.decide must resolve the
// unchanged-versus-append policy after this ordering gate.
return sourceUpdatedAt < previous.effectiveAt
~~~

- [ ] **Step 4: Add older-stamp and invalidation counter-tests**

Add tests that assert an older source stamp is rejected even when its local receipt is newer, and that an explicit invalidation remains accepted under the exemption. Reuse the existing makeContext, money, and record/observation construction helpers; assert the final observation kind/value rather than private implementation details.

- [ ] **Step 5: Run the focused observation suite**

Run the full PortfolioReconciliationTests target. Expected: the equal-stamp test passes, the delayed-newer test passes, older-stamp and invalidation counter-tests pass, and no unrelated test regresses.

### Task 3: Collapse portfolio valuation onto one pure USD eligibility rule

**Files:**
- Modify: TradingCardScannerTests/PricingTests.swift
- Modify: TradingCardScannerTests/PortfolioReconciliationTests.swift
- Modify: TradingCardScanner/Models/PriceRecord.swift
- Modify: TradingCardScanner/Models/PriceObservation.swift
- Modify: TradingCardScanner/Services/InventoryLedger.swift
- Modify: TradingCardScanner/Services/PortfolioEngine.swift
- Modify: TradingCardScanner/Views/CollectionView.swift

- [ ] **Step 1: Add pure helper tests before changing production code**

Add tests for finite USD, EUR exclusion, nil amount, non-finite amount, and a value that rounds into Money:

~~~swift
func testEligibleUnitPriceIsTheSingleUSDGate() {
    XCTAssertEqual(
        PortfolioPriceEligibility.eligibleUnitPrice(amount: 12.3456, currencyCode: "USD"),
        Money(rounding: 12.3456)
    )
    XCTAssertEqual(
        PortfolioPriceEligibility.eligibleUnitPrice(amount: 12.3456, currencyCode: "EUR"),
        nil
    )
    XCTAssertNil(PortfolioPriceEligibility.eligibleUnitPrice(amount: nil, currencyCode: "USD"))
    XCTAssertNil(PortfolioPriceEligibility.eligibleUnitPrice(amount: .nan, currencyCode: "USD"))
}
~~~

Add an authoritative-vs-fast-path test for a one-copy mixed-currency collection. After a USD recompute, apply an EUR delta and assert unitPrice == nil, holdingValue == nil, and currentValue == .zero; then apply a USD delta and assert the value returns. Extend it with USD→invalidation (amount == nil) and plain USD replacement.

- [ ] **Step 2: Run the new tests and verify they fail for the missing helper**

Run the two named tests. Expected: compilation/test failure because PortfolioPriceEligibility does not yet exist, not a failure caused by the test fixture.

- [ ] **Step 3: Add the pure helper next to the price model**

In PriceRecord.swift, add:

~~~swift
enum PortfolioPriceEligibility {
    static func eligibleUnitPrice(amount: Double?, currencyCode: String) -> Money? {
        guard currencyCode.caseInsensitiveCompare("USD") == .orderedSame,
              let amount else { return nil }
        return Money(rounding: amount)
    }
}
~~~

The helper must not mutate a record, convert currencies, or decide invalidation precedence.

- [ ] **Step 4: Route all eligible-value reads through the helper**

Use the helper in PriceObservation.effectiveUSDAmount, InventoryLedger.resolveValuation for both observation and record amounts, and PortfolioEngine.applyPriceDeltas. Replace CollectionView's inline USD guard with the helper while retaining its display-layer currency formatting for non-USD rows. Keep PriceRecord.display able to show a real EUR quote; only portfolio aggregation is USD-gated.

- [ ] **Step 5: Verify transition behavior and authoritative parity**

Run the focused pricing and reconciliation tests. The fast path must subtract the old holding value whenever the new helper returns nil, set both optional holding fields to nil, and leave the authoritative recompute at the same currentValue. Verify EUR→USD and USD→EUR as well as invalidation and replacement.

### Task 4: Make graded identity projections exhaustive and validate vendor products

**Files:**
- Modify: TradingCardScannerTests/JustTCGContractTests.swift
- Modify: TradingCardScannerTests/UncoveredSurfaceTests.swift
- Modify: TradingCardScanner/Services/JustTCGV2GradedClient.swift
- Modify: TradingCardScanner/Models/JustTCGMarketModels.swift if the returned graded variant needs to retain its validated printing metadata
- Modify: TradingCardScanner/Services/PriceRefreshController.swift only if binding needs an explicit validation guard

- [ ] **Step 1: Add projection and ambiguity tests**

Add tests that assert:

1. the grouping key differs for first edition versus unlimited;
2. the grouping key includes every GradedCardIdentity stored-property projection, including the catalog id and print run;
3. same name/local number with different sets is rejected;
4. 4/102 does not match 4/130;
5. a numbered request does not match a response that omits its number; and
6. a returned card/variant with a wrong game, set slug, or print-run printing is rejected before a GradedVariant is produced.

Use a reflection-backed structural test so adding a stored property without updating the explicit projection fails:

~~~swift
func testGradedIdentityProjectionNamesMatchStoredProperties() {
    let identity = GradedCardIdentity(
        name: "Charizard",
        setName: "Base Set",
        collectorNumber: "004/102",
        catalogID: "base1-4",
        pokemonPrintRun: .firstEdition
    )
    let stored = Set(Mirror(reflecting: identity).children.compactMap(\.label))
    let projected = Set(Mirror(reflecting: identity.exhaustiveProjection).children.compactMap(\.label))
    XCTAssertEqual(stored, projected)
}
~~~

exhaustiveProjection is an internal value projection, not a second identity type; it must carry all five stored properties and be the source for groupingKey and the comparable portions of matches.

- [ ] **Step 2: Run the new identity tests and confirm they fail against the current lossy behavior**

Run:

~~~bash
xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -only-testing:TradingCardScannerTests/JustTCGContractTests -only-testing:TradingCardScannerTests/UncoveredSurfaceTests/JustTCGV2GradedSurfaceTests
~~~

Expected: the new one-sided-number/projection/validated-product assertions fail before the production correction. Existing print-run changes in the dirty tree may make the print-run grouping assertion already pass; retain it and still verify the structural test.

- [ ] **Step 3: Implement the exhaustive projection and strict matching**

Add a private/internal projection value with fields for name, setName, collectorNumber, catalogID, and pokemonPrintRun, plus the derived vendor game. Build groupingKey from all identity fields using stable "none" markers. In matches, require canonical set compatibility in every branch and compare normalized number arrays including denominators. Treat one-sided number presence or omission as ambiguous and return false when the request has a number. Keep name normalization and the existing Pokémon/Japanese vendor-game behavior.

- [ ] **Step 4: Validate the returned product before exposing variants**

In JustTCGV2GradedClient.lookup, pass the resolved set slug into identity matching when one exists. If a known print run cannot resolve to a trustworthy set/printing projection, return .noProductMatch rather than performing an unbounded binding. Before creating each GradedVariant, require the card identity and the graded variant's declared type/printing to match the requested identity. A first-edition request must not accept an unqualified or unlimited printing; a shadowless request must not accept a first-edition printing; a missing printing is ambiguous for a known run.

The result type may retain validated printing metadata for diagnostics, but PriceRefreshController.refreshGraded must only call bind with a variant that came through this validated lookup. Add a final guard in bind if the API shape exposes enough identity to check it; a failed guard increments the existing incomplete/miss path and does not write a price or market handle.

- [ ] **Step 5: Verify picker round-trip and lookup-order independence**

Keep the existing pokemonPrintRun threading through GradedVariantPickerView, GradedSlabConfirmationView, and CollectionStore.addGraded. Add a test that constructs the confirmation view with .firstEdition, asserts the value is retained, persists a graded card, refetches it, and asserts pokemonPrintRun == .firstEdition. Add two targets in reverse input order and assert their grouping keys and mock request groups remain distinct and deterministic.

### Task 5: Add separate resolution certainty and expose provenance in detail/receipt UI

**Files:**
- Modify: TradingCardScanner/Models/CardVariant.swift
- Modify: TradingCardScanner/Views/CollectionCardDetailView.swift
- Modify: TradingCardScanner/Views/ScanSessionOverlays.swift
- Modify: TradingCardScanner/Views/ScannerViewModel.swift
- Modify: TradingCardScanner/Views/ContentView.swift
- Modify: TradingCardScanner/Views/PortfolioDebugFixtures.swift
- Modify: TradingCardScanner/Views/ScannerView.swift
- Modify: scripts/ui_build_and_shoot.sh
- Modify: TradingCardScannerTests/VariantResolverTests.swift
- Modify: TradingCardScannerTests/UncoveredSurfaceTests.swift

- [ ] **Step 1: Add failing model/presentation tests**

Add tests that pin the separate meanings:

~~~swift
func testResolutionCertaintyDoesNotReuseAutomaticRevisitSemantics() {
    XCTAssertTrue(VariantResolution.uniqueInCatalog.isAutomatic)
    XCTAssertEqual(VariantResolution.uniqueInCatalog.certainty, .catalogCertain)
    XCTAssertTrue(VariantResolution.catalogSilent.isAutomatic)
    XCTAssertEqual(VariantResolution.catalogSilent.certainty, .unresolved)
    XCTAssertFalse(VariantResolution.userConfirmed.isAutomatic)
    XCTAssertEqual(VariantResolution.userConfirmed.certainty, .userConfirmed)
}

func testReceiptProminenceKeepsRoutineCatalogAnswersQuiet() {
    XCTAssertEqual(VariantResolution.uniqueInCatalog.receiptProminence, .quiet)
    XCTAssertEqual(VariantResolution.deterministicSetRule.receiptProminence, .quiet)
    XCTAssertEqual(VariantResolution.finishLock.receiptProminence, .attention)
    XCTAssertEqual(VariantResolution.userConfirmed.receiptProminence, .attention)
    XCTAssertEqual(VariantResolution.catalogSilent.receiptProminence, .attention)
}
~~~

Add receipt-model tests that the stored resolution is carried into a ScanReceipt and is not reconstructed from variantLabel.

- [ ] **Step 2: Run the new tests and verify the missing certainty API fails**

Run the named tests in VariantResolverTests and UncoveredSurfaceTests. Expected: compile/test failure because certainty, receiptProminence, and the receipt resolution field are not yet present.

- [ ] **Step 3: Add the certainty and prominence policy beside isAutomatic**

In VariantResolution, add a documented Certainty enum with .catalogCertain, .contextualEvidence, .userConfirmed, and .unresolved. Map unique/deterministic catalog results to .catalogCertain, finish-lock/printed-label results to .contextualEvidence, user-confirmed results to .userConfirmed, and imported/catalog-silent results to .unresolved. Add a small ReceiptProminence enum and derive .quiet only for the two routine catalog cases; all other cases use .attention. Leave isAutomatic unchanged.

- [ ] **Step 4: Render one honest provenance value on card detail**

Add a compact VariantProvenanceLabel in an existing view file and place it in CollectionCardDetailView.identityBlock. When a variant exists, render "<finish> · <resolution label>". When the catalog is silent and no variant exists, render "Finish not published"; for other missing data render "Finish unresolved · <resolution label or Imported>". Keep the existing finish/treatment/grade rows and CardFinishOverlay logic intact; this is an additional explanation, not a new resolver.

- [ ] **Step 5: Render graded receipt provenance**

Add resolution: VariantResolution? to ScanReceipt, pass candidate.resolved.resolution from ScannerViewModel, and preserve it in updating(price:). Keep a safe default only for old DEBUG/test fixtures. In ScanReceiptCard, show the finish/provenance text in a quiet caption for .quiet and an orange, accessible attention label for .attention. Keep the existing receipt copy and undo action unchanged. The attention label must state the reason through resolution.label; it must not invent a numeric confidence score.

- [ ] **Step 6: Add deterministic provenance routes and screenshot arguments**

Add DEBUG-only TrustCardDetail and TrustScanReceipt routes. Parse an optional fourth argument in scripts/ui_build_and_shoot.sh as -ui_debug_state <VariantResolution.rawValue>. Seed one card/receipt for catalogSilent, finishLock, userConfirmed, and uniqueInCatalog; use actual CollectionCardDetailView navigation for detail and actual ScanReceiptCard rendering for receipts. Route catalogSilent to a missing finish, finishLock to a known finish with the lock resolution, userConfirmed to a known finish with user confirmation, and uniqueInCatalog to a single catalog finish.

- [ ] **Step 7: Run the UI build/capture loop and inspect every artifact**

Before each capture, read progress.md and append one short loop update. Run:

~~~bash
./scripts/ui_build_and_shoot.sh TradingCardScanner com.example.TradingCardScanner TrustCardDetail catalogSilent
./scripts/ui_build_and_shoot.sh TradingCardScanner com.example.TradingCardScanner TrustCardDetail finishLock
./scripts/ui_build_and_shoot.sh TradingCardScanner com.example.TradingCardScanner TrustCardDetail userConfirmed
./scripts/ui_build_and_shoot.sh TradingCardScanner com.example.TradingCardScanner TrustCardDetail uniqueInCatalog
./scripts/ui_build_and_shoot.sh TradingCardScanner com.example.TradingCardScanner TrustScanReceipt catalogSilent
./scripts/ui_build_and_shoot.sh TradingCardScanner com.example.TradingCardScanner TrustScanReceipt finishLock
./scripts/ui_build_and_shoot.sh TradingCardScanner com.example.TradingCardScanner TrustScanReceipt userConfirmed
./scripts/ui_build_and_shoot.sh TradingCardScanner com.example.TradingCardScanner TrustScanReceipt uniqueInCatalog
~~~

Inspect artifacts/ui-latest.png after each command. Confirm finish plus provenance is visible on detail, attention states are readable on receipts, catalog-silent admits missing publication, and routine unique-in-catalog provenance stays small/quiet. Confirm no clipping, overlap, safe-area, or accessibility-label regression in the metadata/state used by the route.

### Task 6: Add the trust invariants as regression barriers

**Files:**
- Modify: TradingCardScannerTests/PortfolioReconciliationTests.swift
- Modify: TradingCardScannerTests/PricingTests.swift
- Modify: TradingCardScannerTests/JustTCGContractTests.swift
- Modify: TradingCardScannerTests/VariantResolverTests.swift
- Modify: TradingCardScannerTests/UncoveredSurfaceTests.swift

- [ ] **Step 1: Add the fast/authoritative and Collection/Portfolio parity tests**

Use one mixed collection with at least one USD and one EUR record. Compute the authoritative valuation, apply all committed deltas through PortfolioEngine.applyPriceDeltas, and assert equal currentValue. Assert Collection's shownValue uses the same helper and equals the Portfolio total for the same projected rows. Cover USD→EUR, EUR→USD, USD→invalidation, and plain replacement.

- [ ] **Step 2: Add async arrival-order determinism**

Build two equivalent sets of price records/observations with identical provider chronology but reverse arrival order. Reconcile both in fresh in-memory containers and assert the selected observation value, kind, and final valuation are equal. Include equal source clocks with conflicting values so the test proves order is resolved by source chronology plus PriceObservationRules.decide, not by local receipt order alone.

- [ ] **Step 3: Add uncertainty and external-product barriers**

Assert an uncertain VariantResolution remains uncertain when copied into ResolvedVariant, RecentScan, ScanReceipt, and the persisted CollectedCard; no projection may turn catalogSilent into uniqueInCatalog. Assert a wrong-set/wrong-number/wrong-print-run vendor response produces no authoritative handle/value and that only validated products reach the binding path.

- [ ] **Step 4: Run all affected test classes**

Run:

~~~bash
xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86' -only-testing:TradingCardScannerTests/PricingTests -only-testing:TradingCardScannerTests/PortfolioReconciliationTests -only-testing:TradingCardScannerTests/PortfolioLedgerTests -only-testing:TradingCardScannerTests/JustTCGContractTests -only-testing:TradingCardScannerTests/VariantResolverTests -only-testing:TradingCardScannerTests/UncoveredSurfaceTests
~~~

Expected: every invariant and targeted case passes with no skipped test introduced by this work.

### Task 7: Final build, full suite, and benchmark handoff

**Files:**
- Modify: progress.md
- Modify: docs/benchmarks/trust-adversarial-benchmark.md only with real manual results, if the user supplies them

- [ ] **Step 1: Build the app for testing**

Run:

~~~bash
xcodebuild build-for-testing -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86'
~~~

Expected: exit code 0 and no new compiler warnings from the changed files.

- [ ] **Step 2: Run the full suite**

Run:

~~~bash
xcodebuild test -project TradingCardScanner.xcodeproj -scheme TradingCardScanner -configuration Debug -destination 'platform=iOS Simulator,id=EB1F0EB1-9B40-4FDA-B8D3-AEEF76909C86'
~~~

Record the exact total, passed, failed, and skipped counts. Compare against the baseline and explain any difference; do not report a pass from a partial target.

- [ ] **Step 3: Perform the final screenshot capture and inspection**

Run one final capture for each provenance route/state, inspect the latest PNGs, and verify the checklist from swiftui-ui-screenshot-loop: hierarchy, typography, contrast, no clipping/overlap, safe areas, toolbar/tab bar, and the explicit provenance/quietness requirements.

- [ ] **Step 4: Update progress and benchmark status honestly**

Append final build/test/screenshot evidence to progress.md. Keep the benchmark document marked as not executed unless real competitor sessions have been performed; never fabricate comparative outcomes.

