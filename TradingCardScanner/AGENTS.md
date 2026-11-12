# App Source Guide

**Scope:** `TradingCardScanner/` (the app target). The root [`AGENTS.md`](../AGENTS.md) still applies; child guides in `Services/`, `Models/`, `Views/`, and `Games/` govern their directories.

## Before editing

Decide which kind of change this is, then start in the owning directory:

| Change | Owner |
| --- | --- |
| Presentation, navigation, input handling | `Views/` |
| Persisted fields, identity keys, money, provenance | `Models/` |
| Ownership writes, pricing, storage, history, scanning pipeline | `Services/` |
| A decision that differs by game | `Games/` adapter for that game |
| Bundled catalogs and snapshots (`*CatalogSeed/`, `*Snapshot/`, `MagicTreatmentCatalog/`, …) | Their generator in [`scripts/`](../scripts/AGENTS.md); do not hand-edit generated output |

## Cross-directory rules

- **Storage session.** Use the active session and container from `CollectionStorageBootstrap`. Work started for an older storage session must not publish into a newer one; preserve the existing session checks.
- **Ownership writes.** Change owned quantities only through the existing `CollectionStore` operations, which run inside `CollectionWriteSerializer`. A view or game adapter must not write ownership rows directly.
- **Concurrency.** Pass `Sendable` value snapshots across actor boundaries. Live SwiftData models and `ModelContext`s stay with the actor or context that fetched them. Background database work uses the `BackgroundModelActor` construction (see `Services/AGENTS.md`).
- **Project membership.** The Xcode project lists files explicitly (no synchronized folders). A new source or resource file must be added to the correct target in `TradingCardScanner.xcodeproj`, or it is silently absent from the build or bundle.
- When a change crosses directories, read each affected child guide and the matching test routing in [`TradingCardScannerTests/AGENTS.md`](../TradingCardScannerTests/AGENTS.md).

## Feature maps

Two features span several directories; start from all of these files (`.swift` unless shown), not just the one named in the task.

| Feature | Models | Services | Views |
| --- | --- | --- | --- |
| Scanner acceptance | `CardVariant`, `ResolvedCatalogCard`, `ScanSubjectMode` | `CardScanner`, `CardCatalog`, `CardLatch`, `VariantResolver` (plus the game's recognition adapter) | `ScannerViewModel`, `ScannerView`, `ScanReviewSheet` |
| Card centering | `CardCenteringMeasurement`, `CardCenteringSpatialMeasurement`, `CardCenteringBoundaryEvidence` | `CardCenteringAnalyzer`, `CardCenteringPixelKernels.c`, `CardCenteringExport`, `CardCenteringReviewRenderer` | `CardCenteringView`, `CardCenteringCanvas`, `CardCenteringReviewSheet`, `CenteringCameraView` |

Centering research and acceptance evidence live in [`review/`](../review/AGENTS.md).
