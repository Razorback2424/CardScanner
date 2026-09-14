# CardScanner Collection Integrity — Reconciled Codebase Gap Analysis

**Status:** Architecture and implementation-readiness assessment; no product code was changed

**Reconciled:** September 13, 2026

**Authoritative goal:** [CardScanner Collection Integrity Strategy — Start-to-Finish Implementation Plan](<./CardScanner Collection Integrity Strategy — Start-to-Finish Implementation Plan.md>)

**Code snapshot:** repository `HEAD` `d647a79`, including the working-tree changes present on September 13, 2026. This is a historical assessment snapshot; the repository is now on `main` at `a115e4e`, where Task 1 of the active launch plan must revalidate all source claims before implementation. The older commit remains reachable for comparison.

## 1. Scope and evidence

This report reconciles three inputs:

1. the current source tree and test/documentation evidence;
2. the earlier strategic gap analyses of the scanner, collection, import/export, pricing, and portfolio architecture; and
3. the start-to-finish implementation plan linked above, which is treated here as the authoritative goal state.

This is deliberately a **codebase-only** analysis. It does not reassess market demand, pricing research, recruiting channels, or whether collectors will adopt the concept. It identifies what the software currently proves, what it partly supports, what is absent, and what must change to implement and test the strategy safely.

Where evidence conflicts, this report gives priority to:

1. live source and tests;
2. the latest trust-hardening and progress records;
3. older planning and release documents.

The working tree was already modified when this report was prepared. Those changes were preserved and were not attributed to this analysis. In particular, `PortfolioEngine.swift`, collection detail/debug fixtures, and related tests contained user work, while `docs/vision/` was untracked. This report does not claim that the recorded full-suite result covers those uncommitted changes.

## 2. Executive conclusion

CardScanner has a materially stronger starting point than a generic scanner prototype. It already has:

- distinct Collection and Price Check scan intents;
- durable collection storage and mutation history;
- an append-only inventory/economic ledger;
- CSV import and export;
- identity, variant, and price-resolution provenance;
- graded and sealed-item handling;
- portfolio projection and reconciliation machinery;
- extensive automated trust-hardening coverage.

Those capabilities support the **Scan / Import → Resolve** portion of the proposed loop. They do not yet implement the physical-integrity product.

The current application loop is essentially:

> Scan or import → store an aggregated collection record → price it → project portfolio value

The target loop is:

> Scan or import → resolve identity → represent the owned holding or copy → place it → observe it during verification → record discrepancies → reconcile intentionally → preserve evidence → repeat

The largest gap is therefore not UI. It is the absence of a physical-truth domain model with stable copy identity, placement, expected-versus-observed verification, discrepancies, reconciliation, and verification provenance.

The central architectural conclusion is:

> Collection Integrity should be implemented as a second auditable subsystem that interoperates with, but is not collapsed into, the existing collection and portfolio ledgers.

Attaching `binderName`, `page`, and `slot` directly to `CollectedCard` would fail the goal state. `CollectedCard` currently serves several roles at once: catalog snapshot, owned holding, quantity aggregate, variant record, grading record, and pricing binding. Its identity-derived `collectionKey` can be rekeyed or merged and is not a stable identifier for one physical object. It also cannot represent three copies of one printing in three placement states without duplication or quantity distortion.

The proposed strategy is feasible as an incremental evolution, but the implementation sequence matters. The lowest-risk sequence remains:

1. close and prove the remaining trust-baseline gates;
2. introduce hybrid holdings/copies and placement invariants with migration coverage;
3. make Place usable before Verify;
4. add non-mutating verification and explicit discrepancies;
5. add intentional reconciliation and durable provenance;
6. expose operational health;
7. turn imports into staged, source-aware migration sessions;
8. add structural Free/Pro entitlements and privacy-preserving behavioral instrumentation.

Binder-page recognition is intentionally **not** a present gap. The required gap is an observation model that can later accept either sequential scans or page-level observations without changing the integrity semantics.

## 3. Reconciliation with the previous analyses

The previous analyses remain directionally correct, but the authoritative implementation plan sharpens or changes several conclusions.

### What remains unchanged

- The scanner is an acquisition and intake capability, not the defensible paid boundary.
- The code is strongest in recognition, catalog normalization, pricing provenance, collection persistence, and portfolio accounting.
- Physical containers, placement, verification, reconciliation, health, and subscription entitlements do not exist.
- Existing imports reduce cold-start cost but are not yet an acquisition-grade migration experience.
- Price Check and Collection mode separation is already aligned with the casual-use principle.
- Free CSV export is already aligned with portability and should remain so.
- Binder-page computer vision should wait until sequential verification demonstrates repeated demand and speed becomes the bottleneck.

### What the final plan makes more precise

#### 3.1 Copy identity is hybrid, not universal

The earlier analysis correctly rejected a location field on an aggregate row, but a simplistic replacement of every quantity with one record per physical card would also conflict with the plan. The target must support both:

- aggregated interchangeable holdings; and
- independently managed physical copies when placement, grading, condition, provenance, or audit history makes distinction valuable.

The main missing concept is therefore not just `PhysicalCopy`. It is an allocation relationship between an aggregate owned holding and zero or more individualized units, with conservation rules that prevent double-counting.

#### 3.2 Reconciliation is a first-class domain

The earlier description grouped verification and correction too closely. The authoritative plan requires a strict boundary:

- Verify records what was observed and surfaces disagreement.
- Reconcile records a user-authorized interpretation or correction.

This is essential because a mismatch cannot tell the application whether the database is wrong, the card is physically misplaced, or the observation is uncertain.

#### 3.3 The first complete integrity loop is Free

The paid boundary is more constrained than a generic freemium implementation. The code must allow a free user to:

> Place → Verify → discover a real discrepancy → Reconcile

Entitlements should gate scale, history, cross-container management, recurring maintenance, and workflow efficiency—not the first meaningful proof of value. This rules out implementing Verify as a monolithic Pro-only screen.

#### 3.4 Repeat verification is a product event, not just history

The decisive behavior is a second verification after a real collection change. That requires the domain model and instrumentation to relate:

- a completed verification;
- a later collection or placement mutation;
- a later verification of the same meaningful scope.

A raw count of verification sessions is insufficient.

#### 3.5 Phase 1 is stronger than the first review suggested, but not fully exited

The September trust-hardening work addressed the major known silent-integrity defects recorded in the defect audit: price observation ordering, graded printing identity, print-run grouping, durable checkpoint ordering, reconciliation cutoffs, non-USD handling, freshness revision, and graded-browse print-run propagation. The latest recorded evidence reports 980 tests with one skip and no failures, plus compile-only build success.

However, the codebase has not yet proved the plan’s Phase 1 exit criterion because important real-environment and adversarial gates remain, and the current dirty-tree changes postdate that recorded suite. The correct status is **substantially implemented, exit evidence incomplete**, not “missing” and not “done.”

## 4. Current architecture versus required architecture

### 4.1 Current system

| Current area | What the code does now | Strategic usefulness | Limitation against the plan |
|---|---|---|---|
| Scanner intent | [`ScannerViewModel`](../../TradingCardScanner/Views/ScannerViewModel.swift) distinguishes Collection and Price Check behavior | Preserves casual use and prevents Price Check from mutating ownership | No Place or Verify session context |
| Owned collection | [`CollectedCard`](../../TradingCardScanner/Models/CollectedCard.swift) stores identity, quantity, variant, grading, and pricing bindings | Mature foundation for cataloged ownership | Combines aggregate ownership and item facts; lacks stable physical-copy identity |
| Collection mutations | [`CollectionActivity`](../../TradingCardScanner/Models/CollectionActivity.swift) records user-facing adds, removes, restores, corrections, and quantity changes | Reusable audit vocabulary and operation identifiers | No placement, observation, discrepancy, or reconciliation evidence |
| Structured persistence selection | [`TradingCardScannerApp.makeContainer()`](../../TradingCardScanner/App/TradingCardScannerApp.swift) opens the five synced models through unnamed configurations (`.automatic` or `.none`) | Existing records currently live in SwiftData’s default structured-store location | No explicit URL/identity contract; a new named URL can make a pre-existing `default.store` appear fresh unless legacy discovery/adoption runs before any account, anchor, or `storeID` decision |
| Economic inventory | [`InventoryEvent`](../../TradingCardScanner/Models/InventoryEvent.swift) and [`InventoryLedger`](../../TradingCardScanner/Services/InventoryLedger.swift) support append-only portfolio accounting | Strong value/quantity integrity substrate | “Reconciliation” is ledger consistency, not physical truth |
| Identity resolution | Variant resolution, catalog normalization, graded/sealed identifiers, and candidate handling preserve meaningful provenance | Directly supports Resolve and uncertainty discipline | Resolution evidence is attached to collection/catalog workflows, not physical observations |
| Import/export | [`CollectionCSV`](../../TradingCardScanner/Services/CollectionCSV.swift) parses native and portfolio-style CSV and exports collection data | Provides a migration foothold and portability | No source-aware session, mapping review queue, original-row provenance, or per-copy placement round trip |
| Pricing | Price source, observation freshness, currency handling, and portfolio projections are modeled | Supports valuation-integrity extensions later | Not connected to physical verification and should remain separate |
| UI | Portfolio, Collection, Scan, and Centering tabs | Existing functionality can remain intact | No location setup, unplaced queue, Place, Verify, discrepancies, health, or Pro surfaces |
| Monetization | No StoreKit subscription or entitlement implementation found | None yet | Entire Phase 9 implementation is absent |
| Analytics | Performance signposts and local operational diagnostics exist | Useful for latency and reliability | No privacy-safe behavioral funnel or repeat-verification measurement |

### 4.2 Required domain boundaries

The target should distinguish at least these concepts, even if final type names differ:

| Required concept | Responsibility | Current analogue | Gap |
|---|---|---|---|
| Catalog printing | Abstract game/set/number/language/variant identity | Fields embedded in `CollectedCard`; provider records; `ProductIdentity` pricing handle | No single normalized catalog entity boundary |
| Owned holding | Quantity the user owns for a resolved or unresolved catalog identity | `CollectedCard` | Exists in aggregate form but is overloaded |
| Individually managed unit | Stable identity for a physically distinct owned object | Certified single-item behavior is a partial precedent | General stable physical-unit model absent |
| Container | Binder, box, slab case, trade binder, or temporary area | None | Entirely absent |
| Position | Optional page/row/slot within a container | None | Entirely absent |
| Placement | Expected current location of a holding allocation or physical unit | None | Entirely absent |
| Placement history | Evidence that location expectations changed | Collection mutation history only | Physical history absent |
| Verification session | Bounded attempt to compare a location’s expected and observed state | None | Entirely absent |
| Observation | Physical evidence with method, candidates, confidence, and uncertainty | Scanner recognition result | Not durable and not linked to expected physical state |
| Discrepancy | Durable unresolved disagreement | Ledger integrity reasons are economic/internal | Physical mismatch domain absent |
| Reconciliation event | Explicit user decision resolving a discrepancy | Quantity corrections/removals are partial mutation primitives | No physical decision vocabulary or atomic cross-domain operation |
| Import session/record | Source-aware staged mapping and review | One-shot CSV transaction result | Session and row-level provenance absent |
| Integrity projection | Actionable identity/location/verification/freshness summary | Portfolio projections | Physical integrity projection absent |
| Entitlement policy | Structural Free/Pro capability rules | None | Entirely absent |
| Behavioral event | Privacy-safe evidence of the validation chain | None | Entirely absent |

### 4.3 Why the existing keys are insufficient

`collectionKey` is appropriate for grouping collection facts, but it cannot become a physical identity key because it is derived from identity fields and may change when resolution improves. Existing normalization and rekey/merge workflows intentionally allow records that become equivalent to converge. A physical object must survive those changes.

The required relationship is conceptually:

```text
Catalog printing
    └── Owned holding (total quantity)
          ├── aggregate/unindividualized quantity
          └── individually managed units (stable IDs)
                └── current placement
                      ├── container
                      └── optional position
```

Verification then operates on a snapshot of expected placements and creates observations and discrepancies without directly rewriting that graph.

## 5. Required invariants before structural implementation

The implementation plan calls for explicit invariants before Milestone B. The current codebase does not yet state or test the following rules. They should become executable tests and migration assertions.

### Ownership and allocation

1. A holding’s total owned quantity is never changed merely by individualizing, placing, moving, verifying, or de-individualizing a copy.
2. Individually managed quantity plus unindividualized aggregate quantity equals the owned holding quantity.
3. One independently managed physical unit has exactly one stable internal identifier.
4. Identity correction or catalog rekeying does not replace that physical identifier.
5. Removing ownership is an explicit ownership action, never an automatic consequence of a failed verification.
6. Graded, sealed, and known per-copy records retain their distinct identity and metadata during migration.

### Placement

7. Unplaced is a valid, queryable state.
8. A physical unit has no more than one current placement.
9. A position has no more than its permitted occupancy unless a discrepancy is explicitly open.
10. Moving a card changes placement state and history, not catalog identity, owned quantity, acquisition value, or portfolio value.
11. Aggregate placement, if supported for box quantities, cannot allocate more units than the holding owns.
12. Slot conflicts are surfaced; they are not silently resolved by last-write-wins behavior.

### Verification and reconciliation

13. A verification session stores the expected-state snapshot used for comparison.
14. Expected identity may influence candidate evaluation but cannot force an observation to match.
15. A verification observation does not directly mutate ownership or placement.
16. Every material correction is an explicit reconciliation event tied to the discrepancy and user action.
17. Unresolved discrepancies survive app restart and remain actionable.
18. “Verified” means an observation agreed with expected physical state, not that the normal scanner was confident.
19. Placement timestamp, verification timestamp, and reconciliation timestamp are distinct facts.
20. Cross-domain reconciliation is atomic or recoverable: a crash cannot apply the collection mutation while losing the physical audit event, or vice versa.

### Import/export and compatibility

21. Existing aggregate records migrate to valid unplaced holdings without creating thousands of unnecessary physical-unit rows.
22. Existing supported CSV files remain importable.
23. Existing exported columns retain their meaning; new fields are additive or versioned.
24. Individually managed units and placement/provenance data can round-trip without collapsing silently into an aggregate.
25. Unknown source fields or ambiguous mappings remain available for review rather than being converted into false certainty.

### Privacy and future packaging

26. The future integrity product must allow a free user to complete one meaningful Place → Verify → discrepancy → Reconcile loop.
27. Any later packaging change cannot make owned data inaccessible or non-exportable.
28. Any later packaging change cannot delete containers, placements, history, or discrepancies.
29. Behavioral instrumentation does not upload private card identities, locations, certification numbers, or full inventory contents by default.

## 6. Phase-by-phase gap matrix

| Strategy phase | Current status | Existing foundation | Primary codebase gap |
|---|---|---|---|
| 0 — Freeze experiment | Partial | Strategy document defines behavior and thresholds | No machine-readable experiment configuration, event taxonomy, cohort state, or repeat-verification definition |
| 1 — Trustworthy baseline | Substantially implemented; proof incomplete | Broad trust-hardening fixes and tests | Remaining device, CloudKit, concurrency, failure-injection, benchmark, and current-tree verification gates |
| 2 — Physical inventory model | Missing | Aggregate holdings and certified-item precedents | Hybrid holding/unit model, stable IDs, containers, placement, migration, invariants |
| 3 — Place | Missing | Scanner intent and collection mutation architecture | Container UI, manual placement, persistent placement session, scan-to-place, unplaced queue, undo/conflict handling |
| 4 — Sequential Verify | Missing | Existing single-card recognition pipeline | Expected-state session, observation persistence, outcomes, falsifiable prior-informed matching |
| 5 — Reconciliation | Missing | Existing ownership corrections and operation IDs | Durable discrepancy queue, explicit actions, atomic physical/ownership mutations, restart recovery |
| 6 — Verification provenance | Missing | Activity and inventory ledgers | Separate placement/verification/reconciliation evidence model and projections |
| 7 — Collection Health | Missing | Portfolio projection patterns | Integrity dimensions, freshness policy, actionable drill-downs, incremental computation |
| 8 — Migration acquisition | Early partial | CSV import/export and catalog normalization | Source adapters, staged sessions, mapping classifications, provenance, review queues, large-import resilience |
| 9 — Future packaging | Intentionally deferred for free 1.0 | No StoreKit code; portability principles | A separately approved future value/packaging experiment, after retention evidence |
| 10 — Behavioral instrumentation | Missing | Performance diagnostics only | Privacy-safe domain events and derived funnel for change → second Verify |
| 11 — Private validation | Not a code feature, but support missing | TestFlight/release infrastructure | Cohort/config hooks, consent-aware diagnostics, support bundle for integrity workflows |
| 12 — Retention experiment | Defined, future behavior | Privacy-safe scorecard and event contract | Observe repeat Verify after a qualifying change; no pricing conclusion |
| 13 — Binder-page recognition | Correctly deferred | Existing single-card CV | No present implementation requirement; keep observations method-independent |
| 14 — Deepen integrity | Future | Pricing provenance and ledger foundations | Reminders, cross-container analysis, batch workflows, reports; should wait for validation |
| 15 — Long-term moat | Future | Resolution provenance begins an evidence base | Privacy-safe correction corpus, versioned evidence semantics, feedback/learning governance |

## 7. Detailed gaps by milestone

### Milestone A — Trustworthy baseline

#### What is already real

The trust-hardening work is substantial, not aspirational. The current architecture now contains explicit handling and tests for several classes of silent error that would have contradicted an authoritative-inventory promise:

- delayed but newer price observations;
- printing identity for graded cards;
- print-run distinctions;
- non-USD exclusion from USD totals;
- price freshness and source semantics;
- portfolio/collection reconciliation boundaries;
- persistence ordering for durable checkpoints.

Variant resolution also distinguishes exact, inferred, unresolved, and user-confirmed states more honestly than a typical scanner implementation. That is a valuable foundation for the plan’s “never invent certainty” principle.

#### What prevents exit today

The remaining codebase proof gaps are:

- the manual 150–300-card adversarial trust benchmark is not recorded as completed;
- real-device scanner tests remain for OCR variability, thermal conditions, restarts, and stacked/rapid duplicate scans;
- real CloudKit-account and multi-device convergence/fault behavior remain incompletely proven;
- failure injection is not comprehensive across persistence and cross-model transactions;
- concurrent import, normalization, scanner rekeying, and migration need an explicit serialization or optimistic-version strategy;
- store/account epoch scoping needs proof so stale asynchronous work cannot mutate a replacement store;
- large-import behavior and durable-history growth require measurement;
- the current working-tree changes have not been covered by the last recorded 980-test run.

The Phase 1 exit gate should be a signed-off matrix of silent-integrity risks, not merely a green unit-test count.

#### Documentation conflict

The 1.0 go/no-go framework previously described a monetized release and
purchase/restore as launch-critical. The active launch plan now freezes a free
1.0 with no StoreKit flow; the framework must remain reconciled with that
decision before it is used as an execution gate.

### Milestone B — Physical truth model

This is the largest and highest-risk gap.

#### Current model mismatch

`CollectedCard` is described in places as representing a physical object, but normal collection flows aggregate repeated copies under a shared `collectionKey` and quantity. Certified items have narrower one-item behavior, but there is no general per-copy identifier. The model also does not durably capture condition and does not consistently elevate language to an owned-copy discriminator.

The plan requires this state to be representable without duplicating catalog identity:

> Three copies of one printing: one in Binder A/Page 3/Slot 4, one in the Trade Binder, and one unplaced.

Today the code can represent “quantity = 3” or force separate rows in special cases, but not that hybrid state coherently.

#### Required structural slice

A safe minimum design needs:

- a stable holding identifier independent of catalog resolution;
- a stable unit identifier for copies that become individually managed;
- an explicit unindividualized quantity for bulk/aggregate ownership;
- containers and optionally structured positions;
- current placement plus append-only placement events;
- explicit inventory state for temporarily unplaced, missing-under-review, or otherwise unresolved physical status;
- migration metadata/versioning and restart-safe, idempotent migration.

The exact schema can remain compact. It does not need a generic warehouse ontology. The important point is that page and slot belong to placement, not catalog identity or pricing identity.

#### Migration gap

No migration policy or fixtures currently prove:

- aggregate quantity migration;
- graded and sealed migration;
- preservation of certificate and per-copy details;
- identity rekey/merge after physical IDs exist;
- old CloudKit data loading under the new schema;
- rollback or recovery after partial migration;
- export/import compatibility across schema versions.

Milestone B should not ship until those cases are represented as fixtures and migration assertions.

### Milestone C — Place

No placement feature exists today.

#### Missing application services

- container creation, rename, archive/delete policy, and ordering;
- binder layout and lightweight box structure;
- position validation and occupancy rules;
- move/replace/unplace operations;
- undo for the last placement operation;
- conflict detection and restart recovery;
- queries for a container, page/row, physical unit, and unplaced queue.

#### Missing scanner integration

The current Collection/Price Check intent split is a good seam, but Place needs a richer captured session context:

- target container and page/row;
- next position;
- direction and skip state;
- last successful placement operation;
- pending uncertain recognition;
- behavior when an observed card already has a placement;
- behavior when the target slot is occupied.

That context must be captured at scan time, as current scan intent is, so a delayed asynchronous recognition result cannot be applied to a newly selected page or slot.

#### Missing UX

- lightweight container setup;
- manual “Move to” from a holding/copy;
- persistent “Adding to …” context;
- skip, back, replace, and undo controls;
- uncertainty resolution without losing sequence;
- a first-class unplaced queue.

The code has no rendered workflow to evaluate against the plan’s burden criterion. Milestone C therefore needs both unit/integration coverage and an actual device/simulator workflow inspection with a real binder sequence.

### Milestone D — Verify

The current scanner answers “what card is this?” It has no mode that answers “does this observation agree with what should be here?”

#### Required verification engine

- snapshot the expected positions at session start;
- accept observations sequentially;
- retain scanner candidates and contradictory evidence;
- compare expected and observed identities without forcing a match;
- classify Match, Identity uncertainty, Wrong position, Unexpected card, Expected card missing, Quantity discrepancy, and Duplicate/conflict;
- allow explicit empty-slot observations and skipped/unobserved positions;
- persist progress and resume after interruption;
- finish with a deterministic summary and discrepancy set.

#### Recognition boundary

The existing resolver can be reused only if expected state is modeled as a prior or candidate-ranking input, not as an answer override. The test suite needs negative controls proving that contradictory set number, variant, finish, language, or grading evidence prevents a false Match even when the expected slot says otherwise.

#### Future-proofing without building page CV

Verification inputs should use an observation protocol or value type that can later represent:

- sequential camera scan;
- manual confirmation;
- imported evidence where appropriate;
- future binder-page detections.

This is the only Phase 13 preparation required now.

### Milestone E — Reconcile

The app already knows how to add, remove, restore, correct, and adjust quantity, but it lacks a physical discrepancy state machine.

#### Required discrepancy lifecycle

At minimum, a discrepancy needs:

- stable identifier;
- originating verification session and observation;
- expected snapshot;
- observed evidence;
- kind and severity/impact without overstating certainty;
- open/resolved/deferred state;
- reconciliation action and timestamp;
- links to affected holding, unit, placement, or unresolved candidate;
- enough retained evidence to explain the decision later.

#### Required commands

The service layer needs explicit commands such as:

- update recorded placement;
- confirm physical card should be moved back without changing data;
- add a newly observed owned copy;
- assign an existing unit to the observed position;
- mark location unknown/temporarily unplaced;
- change catalog/variant resolution;
- leave open;
- remove ownership only through a separate confirmed ownership action.

Several commands will touch existing collection and portfolio state as well as the new physical state. They need a shared operation identifier and atomic or recoverable transaction semantics. Reusing a current low-level quantity mutation without recording the physical decision would fail the audit requirement.

### Milestone F — Provenance

Current histories are useful but semantically different:

- `CollectionActivity` describes collection mutations.
- `InventoryEvent` describes ownership/economic ledger changes.

Neither proves that a physical object was observed at a location.

The new subsystem needs separate durable evidence for:

- placement events;
- verification sessions;
- observations and method;
- identity/variant certainty at observation time;
- discrepancies;
- reconciliation decisions.

A projection can then answer “last verified here” without rewriting old events. Evidence should be append-oriented; current state can be cached as a projection and rebuilt or checked against history.

The word **verified** must not be reused for catalog confidence, successful persistence, or pricing-source validation. A type-level distinction will prevent this semantic erosion.

### Milestone G — Collection Integrity dashboard

No physical health projection or screen exists.

The target should compute transparent dimensions rather than one opaque score:

- identity completeness;
- unresolved variant count/rate;
- placed quantity versus owned quantity;
- verification coverage by time window;
- open discrepancies by type;
- unresolved import records;
- containers never verified or meaningfully stale.

Each dimension must be backed by a query that produces its actionable queue. This is not just a dashboard view; it requires efficient projections and invalidation when identity, quantity, placement, verification, reconciliation, or import state changes.

For large collections, calculating these dimensions by scanning every event on every render will not be acceptable. The portfolio projection/cache patterns are reusable, but physical integrity needs its own revisioning and consistency checks.

Freshness policy should initially report elapsed time and simple configurable bands. It should not infer that old evidence is false.

### Milestone H — Migration wedge

#### What exists

CSV import/export already supports:

- a native CardScanner-like shape;
- a portfolio-style shape;
- quantity aggregation;
- transactional insertion/merge accounting;
- catalog normalization after import;
- basic portability.

That is a useful transport layer.

#### What is absent

The import is not yet a staged migration domain. It lacks:

- an import session identifier and lifecycle;
- explicit source application and source-version detection;
- preservation of original row fields;
- imported source identifiers;
- mapping confidence, candidate list, and explanation;
- user correction history;
- confidently mapped / needs review / possible conflict / unresolved classifications;
- a durable review queue;
- resumability and cancellation for thousands of records;
- post-import handoff into placement and authority-building.

`CollectionCatalogNormalizer` has internal matched/unmatched behavior, but the current collection import flow does not expose that status as a user-reviewable result. Silent enrichment is not equivalent to trustworthy migration.

#### Adapter gap

There are no verified, named adapters for Collectr, TCGplayer, Dex, or ManaBox. Generic parsing should not be labeled as support for those products until representative export fixtures establish their actual schemas, variants, identifiers, conditions, languages, grades, and failure cases.

#### Export gap

Basic export is already free, which is aligned. It must evolve so new physical data can be exported without breaking older aggregate consumers. At minimum, export needs either a versioned richer format or linked holding/unit/placement files that preserve stable IDs and uncertainty. A flattened file that silently loses individualized units or audit state would contradict the portability promise.

### Milestone I — Future packaging decision

No StoreKit implementation was found, intentionally. The free 1.0 release has
no purchase, restore, paywall, or entitlement flow. A future packaging design
must follow the retention experiment and preserve data access/export.

#### Future architectural requirement

Entitlement checks should live behind a capability policy, not be scattered as ad hoc view conditions. The policy needs to answer questions such as:

- Can this user create another container?
- Can this user start a whole-collection verification?
- Can this user retain or browse historical sessions?
- Can this user use fast scan-to-place?
- Can this user see cross-container queues or reminders?

It should not answer “can the user access their data?” with no after a subscription lapse.

#### Future free-loop requirement

Automated tests must prove that Free can complete a meaningful integrity loop and export all owned data. Pro tests should prove structural scale/efficiency benefits without corrupting or hiding previously created state after downgrade.

#### Pricing dependency

The current settings flow relies on users supplying a JustTCG key, and the repository’s shared-pricing-cache plan records that a commercial shared-price experience still needs app-owned operational infrastructure. This does not block the first physical model slice, but it is a code/operations dependency for promising broadly available current pricing in a free commercial product.

### Milestone J — Behavioral validation

The app has performance instrumentation, but not product-behavior instrumentation.

The strategy’s retention validation chain requires privacy-safe events for:

- import start/completion and mapping classes;
- container creation;
- first and meaningful placement counts;
- Verify start/completion;
- discrepancy discovery and reconciliation;
- later collection or placement change;
- second verification of the relevant scope after that change;
- a later collection or placement change;
- a repeat Verify after that change.

These should be domain events or derived counters with versioned semantics. `CollectionActivity` should not be uploaded as analytics: it contains detailed private collection behavior. Prefer on-device aggregation and transmit only coarse counts, durations, funnel state, and error categories where possible.

The most important derived event needs a precise definition, for example:

> A completed verification of a container or meaningful location, followed by an ownership/placement change relevant to that scope, followed by another voluntarily initiated completed verification after the change.

Without that relation, the app cannot distinguish repeated tapping from evidence of the recurring job.

### Milestone K — Decision gate

The decision gate is primarily strategic, but code must make its evidence trustworthy. Required support includes:

- stable event definitions across releases;
- app/schema version attached to aggregates;
- exportable aggregate experiment summaries;
- latency and abandonment measurement for Place, Verify, and Reconcile;
- observation-method timing so “sequential Verify is too slow” can be distinguished from identity failures or setup friction.

Do not add binder-page CV merely because sequential verification exists. Add it only if the measured repeated-use cohort encounters observation speed as the limiting factor.

## 8. Cross-cutting engineering gaps

### 8.1 Concurrency and stale intent

The current scanner already benefits from captured intent, but physical workflows create more asynchronous hazards. Recognition may finish after the user changes container, page, slot, collection store, or verification session. Every result must carry the session, target position, expected-state revision, and store/account epoch it was created under. Stale results should be rejected or routed to explicit review, never applied to the latest UI selection.

### 8.2 CloudKit conflict semantics

The persistence stack cannot rely on database uniqueness constraints to protect physical positions. Simultaneous edits across devices can create:

- two units in one exclusive slot;
- one unit in two locations;
- a verification against an obsolete expected snapshot;
- competing reconciliations.

These conflicts should become explicit integrity discrepancies with deterministic projection rules. Silent last-write-wins would violate the product thesis.

### 8.3 Atomicity across ledgers

Ownership, placement, verification, and pricing are distinct facts, but some user actions span domains. The code needs an operation coordinator or recoverable transaction pattern so multi-model updates can be retried idempotently. Existing operation/idempotency patterns are a strong precedent, but the physical subsystem needs its own contracts.

### 8.4 Performance and storage growth

The target cohort may import thousands of cards and create many observations. Before public validation, the code needs budgets and tests for:

- migration time and memory;
- container/page query latency;
- scan-to-place throughput;
- verification checkpoint frequency;
- discrepancy projection latency;
- event/history growth over repeated verification;
- CloudKit record volume and sync recovery;
- integrity dashboard recomputation.

Retention/compaction must preserve audit meaning. Old raw media can have a different retention policy from durable observation facts.

### 8.5 Diagnostics and supportability

An authoritative system needs enough local diagnostics to explain failures without exposing inventory contents. Integrity operations should have correlation IDs across scanner result, placement event, verification observation, discrepancy, reconciliation, and existing ownership mutations. A redacted support export should include versions, counts, states, and error categories—not card names or precise physical locations unless the user explicitly includes them.

### 8.6 Naming and semantic separation

The code already uses “integrity” and “reconciliation” for portfolio/ledger consistency. The new physical domain will otherwise create ambiguous types and UI copy. Names should make the scope explicit, such as `LedgerIntegrityIssue` versus `PhysicalDiscrepancy`, and `PortfolioReconciliation` versus `PhysicalReconciliation`.

## 9. Test and evidence program required by the plan

The existing test investment is a major asset. The new work should extend its invariant-heavy style.

### Model and migration tests

- aggregate quantity to hybrid holding migration;
- zero, one, and many individualized units;
- graded, sealed, conditioned, and unresolved variants;
- identity rekey/merge with stable unit IDs;
- interrupted migration and idempotent restart;
- old and new CSV round trips;
- CloudKit decoding of old schema records;
- no ownership/value changes caused by placement migration.

### Placement tests

- slot capacity and conflicts;
- move, replace, unplace, and undo;
- active placement session navigation;
- uncertain scan preserves sequence;
- delayed scan result cannot target a newly selected position;
- app restart restores coherent progress;
- multi-device conflicting moves surface a discrepancy.

### Verification negative controls

- expected card cannot force a contradictory printing match;
- finish, language, grade, and print-run contradictions remain visible;
- wrong-position and duplicate-placement detection;
- missing/empty/unobserved distinctions;
- aggregate quantity discrepancies;
- interrupted/resumed sessions;
- verification creates no implicit ownership or placement mutation.

### Reconciliation tests

- every action produces the intended physical event;
- ownership removal requires explicit confirmation/action;
- crash between cross-domain writes is recoverable;
- repeated command is idempotent;
- unresolved discrepancies survive restart;
- conflicting reconciliation across devices remains explainable.

### Future packaging tests

- the free product completes the first meaningful loop;
- any later packaging preserves view/export access and data;
- any later purchase/restore behavior is specified only in its own approved
  release plan.

### Rendered workflow tests

For Place, Verify, Reconcile, and Health, code correctness is insufficient. Each milestone needs simulator/device walkthroughs using realistic binder and box sequences, accessibility checks, interruption/restart tests, and measured step counts. The acceptance question is whether the workflow reduces bookkeeping, not whether every screen can technically be reached.

## 10. Documentation and roadmap reconciliation

The authoritative strategy should now govern near-term roadmap decisions, but several repository documents still describe the older product shape.

| Document/area | Current mismatch | Required reconciliation |
|---|---|---|
| `README.md` | Positions the product chiefly around scanning/intake, collection, and portfolio | Add the integrity thesis once implementation begins; keep current-state claims honest until then |
| `docs/release/card-scanner-1.0-go-no-go-framework.md` | Previously assumed monetized 1.0 and purchase/restore gating | Keep the free 1.0 persistence/sync gates separate from any future packaging experiment |
| `docs/plans/documentation_audit.md` | Older test counts and pre-hardening architecture snapshot | Supersede counts with latest verified run and link the new vision/gap report |
| `docs/plans/release_followups.md` | Contains real-device/provider follow-ups | Retain and promote silent-integrity gates into Milestone A exit evidence |
| `docs/plans/shared_pricing_cache_plan.md` | Records future commercial pricing infrastructure | Keep as a dependency for scalable free pricing, not as the collection-integrity domain design |
| Existing uses of “integrity” and “reconciliation” | Primarily mean economic ledger consistency | Qualify names and docs to distinguish portfolio integrity from physical collection integrity |

This report does not modify those documents because they contain historical and release-specific context. They should be updated intentionally when the implementation roadmap is accepted.

## 11. Recommended bounded implementation sequence

The authoritative Milestones A–K are sound. From the live codebase, the safest concrete slicing is:

### Slice A1 — Close the trust evidence matrix

- run the current full suite against the reconciled tree;
- finish the adversarial benchmark and real-device/provider gates;
- document remaining accepted risks explicitly;
- revise stale release monetization assumptions.

### Slice B1 — Add stable holdings without UI

- define hybrid allocation invariants;
- introduce stable holding/unit identities and schema versioning;
- migrate fixtures in memory and on disk;
- prove collection and portfolio totals remain unchanged.

### Slice B2 — Add containers and placement core

- implement minimal binder and box containers;
- add positions, current placement, unplaced state, and append-only placement events;
- cover conflicts, rekeying, restart, and CloudKit projection behavior.

### Slice C1 — Manual Place

- create/manage containers;
- move a unit or allocated copy to a position;
- expose the unplaced queue;
- render and test the real workflow.

### Slice C2 — Scan-to-Place

- add captured placement-session context;
- implement advance, skip, back, replace, undo, and uncertainty handling;
- measure throughput and abandonment.

### Slice D1 — Verification evidence core

- create expected-state snapshots, sessions, and observations;
- compare without mutating;
- implement outcome classification and negative controls.

### Slice D2 — Sequential Verify UI

- start/resume/complete a location verification;
- support empty and skipped positions;
- show trustworthy results and persist interruption state.

### Slice E — Reconciliation

- add durable discrepancies and explicit command choices;
- coordinate physical and ownership mutations idempotently;
- produce a concise completion summary and remaining queue.

### Slice F/G — Provenance and operational health

- finish auditable projections;
- expose transparent, actionable dimensions;
- validate performance at target collection sizes.

### Slice H — One excellent source-aware import

- select one real source from user demand;
- build fixtures, session/provenance model, staged mapping, and review;
- then add a second adapter only after the first is robust.

### Slice I/J — Retention evidence, then future packaging

- implement the frozen privacy-safe event semantics before cohort validation;
- observe repeat Verify after a qualifying physical change;
- only after that evidence, write a separate packaging plan if warranted.

Each slice should preserve existing scanner, Price Check, collection, pricing, portfolio, import/export, graded, and sealed behavior. Large speculative rewrites are unnecessary if the new domains are introduced behind explicit services and projections.

## 12. Explicit non-gaps and frozen work

The following are not missing prerequisites for the first experiment and should not dilute implementation:

- binder-page recognition;
- additional TCG breadth unrelated to a chosen import cohort;
- marketplace or social features;
- generalized warehouse modeling;
- insurance reports;
- household/shared collections;
- QR hardware workflows;
- automated grading as a wedge;
- seller-specific tooling;
- new generic portfolio dashboards;
- sophisticated price anomaly detection.

Current scanner, portfolio, graded/sealed, import/export, and pricing features should remain. “Frozen” means stop horizontal expansion, not remove working breadth.

## 13. Final reconciled gap statement

CardScanner is currently a capable digital collection and valuation system with unusually serious provenance and ledger foundations. It can ingest cards, retain resolved and unresolved identity information, record ownership changes, and project value. That is meaningful completion of the front half of the strategy.

It is not yet a verified system of record for a physical collection because it cannot durably answer:

- Which independently managed physical thing is this?
- Where should it be?
- What was actually observed there?
- How did the observation differ from expectation?
- What did the user decide that difference meant?
- When was the resulting state last physically verified?
- Did the collector return to do that job again after the collection changed?

Closing those gaps requires nine major code capabilities:

1. hybrid aggregate/individualized holdings with stable physical IDs;
2. containers, positions, placement, and an unplaced state;
3. scan-to-place session orchestration;
4. falsifiable expected-versus-observed verification;
5. durable discrepancies and explicit reconciliation;
6. separate physical provenance and integrity projections;
7. source-aware staged migration with reviewable uncertainty;
8. structural Free/Pro entitlements that preserve the first full loop and data portability;
9. privacy-safe instrumentation that proves—or disproves—repeat verification after real drift.

The present architecture can support this evolution, especially through its scanner intent handling, identity-resolution provenance, append-only ledgers, operation IDs, projections, and tests. The implementation should reuse those patterns, not conflate their semantics. Portfolio truth, catalog truth, expected physical placement, and observed physical reality are related facts, but they are not interchangeable.

The next engineering decision should therefore be the Milestone B domain contract and migration invariants, after Milestone A’s remaining evidence gates are closed. If that boundary is designed correctly, Place, Verify, Reconcile, Health, migration, and monetization can be added as bounded vertical slices. If it is reduced to location fields on today’s aggregate record, every later phase will inherit ambiguity that directly undermines the trust promise.
