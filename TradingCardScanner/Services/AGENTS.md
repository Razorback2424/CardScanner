# Services Guide

**Scope:** `TradingCardScanner/Services/`. Also follow [`../AGENTS.md`](../AGENTS.md).

This directory is flat (no feature subfolders). Use the task map to find the owner before editing.

## Task map

| Task | Start with |
| --- | --- |
| Add, remove, correct, restore, or import owned cards | `CollectionStore`, `CollectionWriteSerializer`, `InventoryLedger`, `CollectionCSV` |
| Owned quantities | `LogicalCollection`, `CollectionProjectionActor` |
| Select or refresh current prices | `PriceStore`, `PriceRefreshController`, `OwnedCatalogPrice` |
| Startup and storage transitions | `CollectionStorageBootstrap`, `CollectionStoragePolicy`, `StoreRevisionMonitor` |
| Portfolio history | `PriceObservationLog`, `PortfolioReplay`, `PortfolioClose` |
| Scanner acceptance | `CardScanner`, `CardCatalog`, `CardLatch`, `VariantResolver`, and `Views/ScannerViewModel` |
| Background database work | `BackgroundModelActor` |

## Contracts to preserve

1. **Serialized ownership writes.** `CollectionWriteSerializer.perform` runs a synchronous body on a fresh context with explicit save/rollback. Never put an `await` inside the body and never nest `perform` (it asserts). Respect the lock order documented at the top of the file, and pick the `Timeout` that matches the caller (`.mainThread` on the UI thread, `.immediate` for publication retries, `.wait` in the background).
2. **Whole ownership operations.** An ownership change must stay consistent with its inventory ledger and user-facing activity history. Reuse the existing `CollectionStore` operation that already records those consequences instead of writing rows piecemeal.
3. **Price identity vs. price amount.** Moving a price key or its history is a structural write: use `CollectionWriteSerializer.withPriceIdentityExclusivity` and `PriceRefreshController.suspendPasses`. Changing an amount is not a reason to bypass that mechanism or to invent a new one.
4. **Logical ownership.** Several physical rows can legitimately share one `collectionKey` (offline adds on two devices, then CloudKit sync). Answer "how many do I own" from `LogicalCollection`, never from the first fetched row.
5. **Revalidate async results before saving.** A provider or analysis result must not recreate a removed owner, overwrite a later correction, or write into an obsolete storage session.
6. **One owned-price policy.** Browse and Collection consume the `OwnedCatalogPrice` decision; do not add an independent "newest price" rule.
7. **Background execution.** Build `@ModelActor` workers through `BackgroundModelActor.makeBackground`. Constructing an actor off the main thread alone did not keep SwiftData work off the UI thread on a real device. Only the actor and `Sendable` results cross back to the UI.
8. **Historical meaning.** A repaired mapping, provider restatement, failed lookup, or unavailable price keeps its actual meaning in portfolio history; never backfill it as a real observation or a zero.

## Two stores, not one transaction

Production keeps ownership and local pricing/artwork in two SQLite files (see `CollectionStorageBootstrap`). SwiftData cannot commit across them atomically. Writes within one store should be atomic; operations spanning both must be **recoverable** if the process stops between writes. Do not design a change that assumes a cross-store transaction.

## Verification routing

Pick the suites for the contract you touched (exact class names: [`../../TradingCardScannerTests/AGENTS.md`](../../TradingCardScannerTests/AGENTS.md)):

- Ownership, ledger, activity → `OwnershipLedgerCompletenessTests`, `OwnershipConcurrencyStressTests`, `CollectionStoreContinuityTests`, `CollectionActivityHistoryTests`; CSV import → `CSVImportResumeTests`
- Price identity or structural writes → `RefreshStructuralWriteTests`, `PriceRefreshLifecycleTests`
- Storage transitions and launch actors → `CollectionStorageBootstrapTests`, `CollectionStoreModeTransitionTests`, `LaunchModelActorTests`
- Portfolio history → `PortfolioReplayEngineTests`, `PortfolioCloseTests`, `PortfolioLedgerTests`, `PortfolioReconciliationTests`
- Scanner acceptance → `CardLatchTests`, `VariantResolverTests`, `ScannerViewModelTests`

Find the actual test files with `grep -rl "class <Name>" TradingCardScannerTests` before relying on a filename.

## Game-specific branches

Do not add new `case .pokemon` / `case .magic`-style branches to central services; route the decision through a game adapter (see [`../Games/AGENTS.md`](../Games/AGENTS.md)).
