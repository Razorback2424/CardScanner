# Repository and Architecture Map

## Review boundary

Review date: 2026-09-10. Baseline: `e8497ef1fcb81fa0e72d72e6c5009272da4c35d6`, branch `scan-hardening-and-release`.

The repository is a single-target SwiftUI/SwiftData iOS application with a unit-test bundle and no external package dependencies. The shipped behavior is distributed across Swift source, Xcode build settings, plist/entitlements, bundled catalogs, generated snapshots, and the app-owned persistence/reconciliation services. Tests, scripts, plans, prior audits, and checklists were treated as evidence or hypotheses, never as proof without current source corroboration.

## Repository inventory

| Area | Current inventory | Review treatment |
| --- | ---: | --- |
| Application Swift | 105 tracked files, 62,948 lines | Exact per-file classifications in `02-coverage-ledger.md` |
| Unit-test Swift | 43 tracked files, 28,450 lines | Read as executable evidence; excluded from production-file classification |
| Magic treatment snapshot | 738 set JSON resources plus manifest | Bundled production data; schema/manifest sampled and counts reconciled |
| Pokémon checklist snapshot | 160 set JSON resources plus manifest | Bundled production data; manifest and representative records inspected |
| Magic treatment catalog | manifest, vocabulary, 1 compact catalog JSON | Bundled production data used by local migration/browse |
| Assets/configuration | asset catalog, app icon, plist, privacy manifest, two entitlements | Build/runtime boundary; release entitlements remain environment-dependent |
| Documentation | README, progress log, plans, audits, benchmarks, release framework, checklists | Historical claims challenged against current source/test evidence |
| Scripts/references | 6 scripts and 4 reference checklists | Supporting tooling and acceptance evidence; no production behavior assigned |

Visible disposable build directories are ignored and were not treated as repository source. No tracked or visible `AGENTS.md`, `CLAUDE.md`, or `GEMINI.md` exists.

## Target and build map

- Xcode project: `TradingCardScanner.xcodeproj`.
- Application target/scheme: `TradingCardScanner` / `TradingCardScanner`.
- Unit-test target: `TradingCardScannerTests`, hosted by the application.
- Configurations: Debug and Release.
- Deployment target: iOS 17.0; device families iPhone and iPad; Swift 5.0.
- Bundle identifier in both configurations: `com.example.TradingCardScanner`.
- Debug uses `TradingCardScanner/TradingCardScanner-Local.entitlements` and defines `DEBUG LOCAL_ONLY_SIGNING`.
- Release uses `TradingCardScanner/TradingCardScanner.entitlements`, which declares Sign in with Apple and CloudKit/iCloud.
- `Info.plist` declares camera access, background fetch/processing, two bundle-derived BGTask identifiers, and portrait iPhone/all-orientation iPad support.
- The Release simulator build completed successfully on 2026-09-10. This proves compilation/linking/package validation for a simulator artifact, not App Store provisioning or physical-device behavior.

## Architecture at a glance

```text
CameraPreview / AVCaptureSession
        |
        v
CardScanner (visionQueue + sessionQueue)
        | OCR footer/title/label
        v
ScanParser + GradedLabelParser + CardLatch + VariantResolver
        |
        v
ScannerViewModel (identity choice, print-run choice, graded confirmation)
        |
        +--> CollectionStore --> CollectedCard / CollectionActivity / InventoryEvent
        |          |                    |
        |          |                    +--> LogicalCollection / CollectionProjectionActor
        |          |                    +--> PortfolioReplaySnapshotBuilder
        |          |                         --> PortfolioReplay --> PortfolioEngine
        |          |                                                      |
        |          |                                                      +--> PortfolioDailyClose
        |          |                                                      +--> PortfolioHistoryEngine/View
        |          |
        |          +--> CollectionCSV import/export
        |
        +--> PriceCheckCoordinator --> PriceProvider / ProductPriceService
        |
        +--> PriceRefreshController --> PriceStore + PriceObservationLog
                                      --> JustTCG refresh lanes / ProductIdentityStore

Bundled Magic/Pokémon catalogs + BrowseCatalog cache
        |
        v
BrowseView / CatalogCardDetailView --> CollectionStore add paths

CardCenteringCameraView --> CardCenteringAnalyzer --> CardCenteringMeasurement
                                           |
                                           +--> CardCenteringView / CardCenteringExport
```

## Subsystem ownership

### App and persistence

`TradingCardScannerApp` constructs two SwiftData configurations: synced collection/price/identity/activity/event models and local-only quote/history/artwork models. The app attempts CloudKit only when the sign-in/storage gate is present and falls back to local-only persistence if CloudKit container creation fails. `ContentView` owns the tab surface and starts local backfill/migration, portfolio startup, projection rebuild, deferred network migration, revision monitoring, and background refresh registration.

### Scanner and identity

`CardScanner` owns capture, Vision requests, recognition queues, spatial continuity, slab evidence, and callback emission. `ScanParser` produces ordinary card identities; `GradedLabelParser` produces slab evidence; `CardLatch` provides hold/release/duplicate authorization. `ScannerViewModel` is the main-actor policy layer that decides when an identified subject can become a catalog selection, graded selection, or collection mutation.

### Collection and history

`CollectedCard` is the durable row and stores the logical collection key, item kind, catalog/provider lineage, physical variant, grading fields, quantity, and provenance. `CollectionStore` is the mutation boundary and writes collection rows together with activities and inventory ledger events. `LogicalCollection` projects rows into positions and chooses a deterministic representative. `CollectionProjectionActor` materializes the SwiftUI read snapshot. `CollectionCSV` is the external interchange boundary.

### Pricing and provenance

`PriceRecord` is mutable current-state pricing; `PriceObservation` is append-only evidence; `PriceObservationLog` orders and de-duplicates observations; `PriceStore` reconciles the two and owns invalidation/failure diagnostics. `PriceCheckCoordinator` handles the read-only interactive quote path. `PriceRefreshController` owns catalog/fallback/graded refresh orchestration and durable checkpoints. `JustTCGRefreshCoordinator` batches fallback requests and `ProductIdentityStore`/`CollectionCatalogNormalizer` retain vendor identity and artwork metadata.

### Portfolio

`PortfolioReplaySnapshotBuilder` builds as-of valuation and ownership indexes from rows, events, observations, and records. `PortfolioReplay` reconstructs daily/live changes and attribution. `PortfolioEngine` validates collection/ledger agreement, computes current value and close candidates, emits integrity defects, and publishes `PortfolioDailyClose` revisions. `PortfolioHistoryEngine` selects the user-requested range and produces chart/accounting values.

### Browse and centering

`BrowseCatalog` owns bundled-directory reads, network search/detail, and cache envelopes. `BrowseView` and `CatalogCardDetailView` present catalog results and add paths. `CardCenteringAnalyzer` produces edge measurements; `CardCenteringView` presents manual adjustment/rotation; `CardCenteringExport` renders the photo and guides.

## Source-of-truth map

| Question | Authoritative state | Derived/read state | Boundary or risk checked |
| --- | --- | --- | --- |
| What is owned? | `CollectedCard.quantity`, `CollectionActivity`, `InventoryEvent` | `LogicalCollection`, projection snapshot, portfolio replay | Identity key drift and event reconciliation |
| Which physical printing/variant? | `CollectedCard.collectionKey`, variant/treatment/grade fields | catalog and browse summaries | CSV/provider identity reconstruction |
| What price is current? | `PriceRecord` after observation/invalidation ordering | `PriceSnapshotStore`, UI display | Currency eligibility and record/log divergence |
| What evidence was learned? | `PriceObservation` append-only log | replay attribution/current value | source timestamps, invalidation, late arrival |
| What is portfolio history? | published `PortfolioDailyClose` plus replay inputs | chart/history result | range anchoring and revision reason |
| What is cached? | cache envelope and `storedAt` | browse/quote presentation | stale/future timestamps and fallback semantics |
| Is a slab still attached? | `CardScanner.activeSlab` on the vision queue | `ScanSubject.slab` and confirmation UI | lifecycle and cross-identity carry-over |

## External and environment boundaries

- AVCapture/Vision/OCR, camera pixel format, physical card motion, device thermal behavior, and camera interruptions are not represented faithfully by the simulator.
- CloudKit delivery order, account switching, container provisioning, and multi-device late events require a physical/device-backed environment.
- TCGdex, Scryfall, JustTCG, and provider credentials/network responses are external; current tests use injected clients/fixtures and do not prove live provider behavior.
- Release bundle ownership, iCloud container ownership, Sign in with Apple capability, provisioning, and App Store signing are not proven by a local simulator build. The current project still uses the placeholder bundle identifier and a personal development team.

## Review method and independent acceleration

The parent review traced the complete source graph and current test/build evidence. Five read-only subreviews were used for independent scanner, collection, pricing, portfolio, and browse/Magic/resource exploration. Their results were reviewed against current source before promotion; no subagent wrote files, changed source, or supplied unchallenged findings. The resulting coverage and findings are in the companion artifacts, not in the subreview summaries.
