# End-to-End Flows and Cross-Cutting Invariants

## Launch, storage, and derived-state flow

1. `AppDelegate` registers/schedules background price refresh work at launch.
2. `TradingCardScannerApp` creates the synced and local-only SwiftData configurations. CloudKit is attempted only behind the signed-in/non-local gate; creation failure falls back to local-only persistence.
3. `ContentView` runs existing-collection backfill and the local Magic treatment migration before portfolio startup.
4. Portfolio startup establishes/validates its epoch and computes from durable rows/events/price evidence.
5. The projection actor rebuilds the collection read snapshot. Deferred network Magic migration runs after that first rebuild, and the revision monitor reacts to changed card fingerprints by rebuilding derived consumers.
6. `StoreRevisionMonitor` coalesces changes, refreshes/rebuilds snapshots, recomputes portfolio, and invokes stale-price work. A controller-owned refresh uses its own terminal checkpoint/replay path.

Invariants traced:

- Sync is additive: failure to create a CloudKit store must not make local collection use crash.
- A projection or portfolio read failure is not equivalent to an empty store.
- Durable price refresh checkpoints advance only after the batch’s durable save/final checkpoint succeeds.
- A changed collection key or Magic treatment fingerprint must invalidate derived projections and portfolio results.

Evidence: `TradingCardScanner/App/TradingCardScannerApp.swift:102-149`, `TradingCardScanner/Views/ContentView.swift:166-194`, `TradingCardScanner/Services/StoreRevisionMonitor.swift:189-329`, `TradingCardScanner/Services/MagicTreatmentMigration.swift:181-207, 1883-1916`.

## Scanner flow

1. `CameraPreview` supplies frames through AVCapture.
2. `CardScanner` performs footer/title/label Vision work on serialized queues and carries a scan generation/confirmation context.
3. `ScanParser` preserves line grouping and resolves set/collector-number identity. Graded label OCR is parsed separately.
4. `CardLatch` holds a repeated identity long enough to authorize a scan and prevents the same physical encounter from being counted twice.
5. `ScannerViewModel` resolves catalog/variant/print-run/graded choices, applies user confirmation, and calls `CollectionStore` only after the policy gate allows mutation.
6. The collection mutation records the card, activity, and ledger event, then projection/revision consumers observe the durable change.

Scanner invariants:

- An ambiguous or spatially rejected frame confirms nothing.
- A completion from an invalidated generation cannot mutate current UI/destination state.
- Set code and collector number must remain paired through OCR grouping.
- A slab’s grade/certification must describe the same physical slab as the identified subject.
- A real session boundary must clear all presentation-scoped recognition evidence.

The first three are strongly supported by current source/tests. The last two are the subject of findings F-001 and F-002.

Evidence: `TradingCardScanner/Services/CardScanner.swift:1768-1805, 1966-2014, 2065-2177`, `TradingCardScanner/Views/ScannerViewModel.swift:1320-1343, 1466-1599`, `TradingCardScanner/Services/ScanParser.swift`, `TradingCardScanner/Services/CardLatch.swift`.

## Collection, import, and identity flow

`CollectionStore` creates a stable `CollectedCard.collectionKey`, writes the row, and records activity/ledger legs. `LogicalCollection.project` groups exact keys and selects one deterministic representative. `CollectionProjectionActor` joins rows with price/artwork/identity data. Browse add paths use canonical sealed/graded keys. CSV import reconstructs a key from exported fields and then inserts/merges rows.

Invariants:

- A quantity change must have a matching inventory event and collection activity.
- A certification number is non-aggregating; separate physical graded copies must remain distinct.
- A provider/catalog ID may enrich a row, but cannot silently change a physical identity without lineage/history reconciliation.
- Sealed products use the product/variant key namespace and must converge between import and Browse add paths.
- Legacy Magic aliases must be read through for history/replay and canonicalized without double-counting.

The current scan/Browse mutation paths and same-key duplicate guards are coherent. F-010, F-011, and F-012 identify boundaries where external interchange or account/store scope can violate convergence.

Evidence: `TradingCardScanner/Services/CollectionStore.swift:1759-1889, 1972-2070, 2118-2240`, `TradingCardScanner/Services/LogicalCollection.swift:75-190`, `TradingCardScanner/Services/CollectionProjectionActor.swift:111-145`, `TradingCardScanner/Services/CollectionCSV.swift:134-185, 763-815, 1163-1224`.

## Pricing and currency flow

The interactive path tries a catalog quote first, accepts only a usable USD quote as a completed Price Check, then falls back to local evidence/JustTCG. The durable refresh path resolves targets, writes append-only observations through `PriceStore`, updates the mutable `PriceRecord`, checkpoints, and replays deltas. `InventoryLedger.resolveValuation` and `PortfolioReplay` both apply the USD eligibility policy for portfolio totals.

Invariants:

- An invalid provider amount cannot overwrite the prior valid record.
- An explicit invalidation withdraws old evidence.
- A source-published timestamp can reject an older observation even if it arrived later.
- Non-USD evidence is preserved for display/provenance but cannot participate in a USD portfolio total.
- The current-value path and replay path must agree across source/currency transitions.
- “Updated metadata” and “priced amount” are distinct refresh outcomes.
- A transient provider failure should not leave an older, more specific diagnostic indefinitely masking the current state.

The first four are covered by current source and tests. F-006, F-007, F-008, and F-009 concern the remaining edge paths.

Evidence: `TradingCardScanner/Services/PriceStore.swift:782-841, 898-925`, `TradingCardScanner/Models/PriceRecord.swift:168-189, 255-261`, `TradingCardScanner/Services/PriceObservationLog.swift`, `TradingCardScanner/Services/InventoryLedger.swift:323-374`, `TradingCardScanner/Services/PortfolioReplay.swift:463-520`, `TradingCardScanner/Services/PriceCheckCoordinator.swift:82-110, 267-305, 444-505`.

## Portfolio flow

The replay snapshot builder indexes ownership and valuation as of each cutoff. Replay produces daily/live values and attribution. `PortfolioEngine` independently measures current collection value, compares it to replay attribution, emits residual defects, and publishes daily closes. `PortfolioHistoryEngine` chooses an anchor from published closes for the requested range and returns chart/accounting data.

Invariants:

- Collection and ledger quantities must agree before a close is authoritative.
- A late event with `recordedAt` after a close but `occurredAt` before its cutoff is a reconciliation, not ordinary market movement.
- A non-USD transition cannot become a synthetic withdrawal in replay or an unexplained current/replay residual.
- The history chart’s actual first point and accounting interval must match the selected range, or clearly state the available-history fallback.

F-004, F-005, and F-006 are the review exceptions found in this flow.

Evidence: `TradingCardScanner/Services/PortfolioReplaySnapshot.swift`, `TradingCardScanner/Services/PortfolioReplay.swift`, `TradingCardScanner/Services/PortfolioEngine.swift:530-570, 690-710, 753-830, 933-958`, `TradingCardScanner/Services/PortfolioHistoryEngine.swift:8-45, 127-143`, `TradingCardScanner/Models/InventoryEvent.swift:69-74`, `TradingCardScanner/Models/PortfolioDailyClose.swift:4-16, 142-153`.

## Browse, cache, and centering flow

Browse reads bundled set/card directories for offline startup, uses cache envelopes for network results, and sends selected catalog summaries to collection mutation. Centering captures an image, measures edges, lets the user adjust/rotate, and exports a composed image plus guide/metric region.

Invariants:

- A cache envelope’s timestamp must not make future-dated stale content appear indefinitely fresh.
- Browse’s ownership quantity view and Collection’s exact-key rows should converge after catalog normalization.
- If a photo rotates, guides and measurements shown/exported over that photo must remain in the same coordinate frame.

F-003 and F-013 are the confirmed boundaries. F-011 covers Browse/Collection identity convergence for legacy imported sealed rows.

Evidence: `TradingCardScanner/Services/BrowseCatalog.swift:898-909`, `TradingCardScanner/Views/CardCenteringView.swift:658-706`, `TradingCardScanner/Services/CardCenteringExport.swift:75-100`, `TradingCardScanner/Services/CollectionCatalogNormalizer.swift:147-185`, `TradingCardScanner/Services/CollectionStore.swift:2118-2157`.

## Background, lifecycle, and concurrency flow

Background price work uses dedicated refresh contexts, batch callbacks, checkpoints, and a final durable sync watermark. Foreground migration and refresh share `MagicTreatmentPriceRefreshGate`. Scanner lifecycle changes invalidate generation/recognition work and resume only through eligibility gates.

Invariants:

- A task may finish network work after cancellation, but it cannot apply stale UI/destination state.
- A refresh sync watermark advances only after the final durable checkpoint.
- Migration and pricing cannot concurrently mutate/rekey the same target identity.
- Camera/background/purpose transitions must clear or fence scanner state that could attach to a future physical encounter.

Current source strongly supports the first three; F-002 is the remaining lifecycle exception. F-001 is a data-ownership exception inside the otherwise serialized vision path.

Evidence: `TradingCardScanner/Services/JustTCGRefreshCoordinator.swift:286-319`, `TradingCardScanner/Services/PriceRefreshController.swift:874-880`, `TradingCardScanner/Services/MagicTreatmentMigration.swift:1707-1962`, `TradingCardScanner/Views/ScannerViewModel.swift:1567-1599`.

## Reconciliation pass outcome

The independent pass compared collection identity keys, pricing currency policy, portfolio replay, scanner slab state, and derived projection triggers. It produced three cross-system promotions: the PriceStore currency transition (F-006), graded CSV key reconstruction (F-010), and imported sealed/Browse identity convergence (F-011). It also retired the suspected mixed Magic projection defect: migration changes are included in the card fingerprint and the revision monitor rebuilds the projection when those changes arrive. Historical defect-review items D01-D08 were rechecked against current source and are recorded as fixed in `05-rejected-hypotheses-and-uncertainties.md`.
