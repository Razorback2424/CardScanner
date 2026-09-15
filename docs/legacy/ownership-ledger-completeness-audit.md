# Ownership-ledger completeness audit

> **Legacy archive — candidate audit snapshot, 2026-09-13.** This document is
> retained for provenance and is not the current ownership-ledger authority.
> Use [`../release/ownership-ledger-completeness-audit.md`](../release/ownership-ledger-completeness-audit.md)
> and the [current release ledger](../release/phase-1-integrity-evidence.md)
> for the current checkout.

Candidate: `fix/app-review-preflight` (source SHA recorded in `phase-1-integrity-evidence.md`)

Audit date: 2026-09-13

## Invariant and conclusion

Canonical ledger means `InventoryLedger.read().events` after equivalent retry deduplication, complete two-leg correction validation, and explicit key-alias normalization.

Reconstructed quantity for a logical position is the sum of `deltaQuantity` for canonical events mapped to that position.

Ledger-complete state means there is no unreadable, conflicting, or orphaned ledger defect and every reconstructed position quantity equals the intended committed ownership quantity.

Conclusion for this candidate: `InventoryEvent` is not yet approved as automatic aggregate-repair authority. The source contains strong transaction and defect-fencing behavior, and this pass adds disk-backed production-entry, restart, CSV rollback/retry, baseline, and scanner-save-failure coverage. The complete end-to-end matrix still must run on a supported iOS test host before the authority gate can be signed off. `CollectionStore.repairQuantityMismatches` remains an explicit/manual repair surface and is not used by the CloudKit bootstrap.

## Mutation-path inventory

| Mutation path | Production entry point | Aggregate effect | Required event/activity facts | Idempotency key owner | Transaction/rollback boundary | Alias/correction behavior | Reconstruction test | Result |
|---|---|---|---|---|---|---|---|---|
| Scanner raw add/rescan | `ScannerCollectionWriter.add` → `CollectionStore.add` | insert or increment `CollectedCard.quantity` | acquire event and added activity; staged price | scanner operation IDs | writer save; rollback on failed final save | catalog aliases resolved before price staging | `CollectionActivityHistoryTests`, `ScannerViewModelTests`, disk/restart coverage in `OwnershipLedgerCompletenessTests` | LEGACY BASELINE ONLY — execution NOT RUN |
| Manual quantity adjustment | `CollectionStore.setQuantity` | set target quantity; emits delta | adjustment activity and ledger delta | operation ID owned by store path | collection context save | exact collection key | `CollectionActivityHistoryTests`, disk/restart coverage in `OwnershipLedgerCompletenessTests` | LEGACY BASELINE ONLY — execution NOT RUN |
| Graded add | `CollectionStore.addGraded` | insert/increment graded identity | acquire/duplicate facts; certification identity | certified identity and operation ID | collection context save | certification prevents silent aggregation | `CollectionItemKindTests`, `ImportedItemKindTests`, disk/restart coverage in `OwnershipLedgerCompletenessTests` | LEGACY BASELINE ONLY — execution NOT RUN |
| Scanned graded add | `CollectionStore.addScannedGraded` | insert unresolved graded row | acquisition fact with unresolved provider variant | operation ID | collection context save | remains unresolved rather than guessed | `ScannerViewModelTests`, `GradedLabelParserTests`, disk/restart coverage in `OwnershipLedgerCompletenessTests` | LEGACY BASELINE ONLY — execution NOT RUN |
| Sealed add | `CollectionStore.addSealed` | insert/increment sealed product identity | acquire activity and ledger event | operation ID | collection context save | product identity stays distinct from raw card | `CollectionItemKindTests`, `ImportedItemKindTests`, disk/restart coverage in `OwnershipLedgerCompletenessTests` | LEGACY BASELINE ONLY — execution NOT RUN |
| Remove one/all | `CollectionStore.remove` / `remove(activity)` | decrement or delete aggregate row | removed activity, reversal/lineage facts, snapshot | operation ID and activity ID | collection context save | removal snapshot preserves identity | `CollectionActivityHistoryTests`, `PortfolioReconciliationTests`, disk/restart coverage in `OwnershipLedgerCompletenessTests` | LEGACY BASELINE ONLY — execution NOT RUN |
| Undo scan/removal | `ScannerCollectionWriter.undo`, `CollectionStore.restore` | inverse delta or restoration | inverse ledger legs and restored activity | inverse operation ID | writer/context rollback boundary | preflight rejects missing/partial lineage | `ScannerViewModelTests`, `CollectionActivityHistoryTests`, disk/restart coverage in `OwnershipLedgerCompletenessTests` | LEGACY BASELINE ONLY — execution NOT RUN |
| CSV insert/merge | `CollectionCSV.apply` | insert, merge, or preserve duplicate | `recordExisting` event and activity | import row/idempotency key | isolated import context and batch save | alias and certified duplicate rules are explicit | `ImportedItemKindTests`, `CollectionActivityHistoryTests`, disk rollback/retry coverage in `OwnershipLedgerCompletenessTests` | LEGACY BASELINE ONLY — execution NOT RUN |
| Identity rekey/merge | `CollectionStore.rekey`, `mergeCollectionRows` | move/merge aggregate rows without changing ownership total | existing events/activities rewritten to canonical key | existing event IDs | caller-owned save boundary | treatment aliases and snapshots checked before rewrite | `MagicTreatmentTests`, `CollectionKeyTests` | LEGACY BASELINE ONLY — execution NOT RUN |
| Variant correction | `CollectionStore.recordVariantCorrection` | move quantity from old identity to new identity | exactly one correction `.from` and `.to` leg plus activity | shared correction operation ID | staged in writer/context transaction | partial correction is rejected by ledger read | `VariantResolverTests`, `CollectionActivityHistoryTests`, mixed disk workflow in `OwnershipLedgerCompletenessTests` | LEGACY BASELINE ONLY — execution NOT RUN |
| Magic treatment migration | `MagicTreatmentMigration` | rekey/merge rows and quantity | existing lineage must remain reconstructible | migration-scoped state | migration save boundary | collisions require compatible treatment/ledger facts | `MagicTreatmentTests` | LEGACY BASELINE ONLY — execution NOT RUN |
| Existing-collection epoch | `PortfolioEpoch.establishIfNeeded` | no ownership mutation; creates baseline facts | one deterministic `initialBalance` per logical position | epoch baseline key | epoch save boundary | strict ledger read before baseline | `PortfolioReconciliationTests`, disk/restart coverage in `OwnershipLedgerCompletenessTests` | LEGACY BASELINE ONLY — execution NOT RUN |
| Explicit mismatch repair | `CollectionStore.repairQuantityMismatches` | adjusts aggregate to ledger or appends repair event per legacy behavior | defect classification required | repair operation ID | explicit user/support action | not an automatic CloudKit conflict authority | `OwnershipLedgerCompletenessTests` | LEGACY BASELINE ONLY — execution NOT RUN |

## Source appendix

The review covered all direct ownership mutation call sites found with `rg` in `CollectionStore.swift`, `CollectionCSV.swift`, `MagicTreatmentMigration.swift`, `PortfolioEpoch.swift`, `ScannerCollectionWriter`, and the collection views. The current source also contains disk-backed mixed-workflow, item-kind, CSV retry/rollback, baseline, and scanner-save-failure tests in `OwnershipLedgerCompletenessTests`; they typecheck but have not executed on a supported host. Non-ownership collection operations such as filter-set removal, cache eviction, price-record deletion, and artwork-file deletion are not ledger mutation paths.

## Required acceptance run

The following must run against the current candidate before changing any result above to `PASS`:

```text
xcodebuild test -only-testing:TradingCardScannerTests/OwnershipLedgerCompletenessTests
xcodebuild test -only-testing:TradingCardScannerTests/CollectionActivityHistoryTests
xcodebuild test -only-testing:TradingCardScannerTests/PortfolioReconciliationTests
xcodebuild test -only-testing:TradingCardScannerTests/ImportedItemKindTests
xcodebuild test -only-testing:TradingCardScannerTests/MagicTreatmentTests
```

Each supported row must pass a persistent save → destroy → reopen → reconstruct cycle, a retry/idempotency check, and a rollback injection. An unreadable, conflicting-idempotency, or orphaned-correction ledger must refuse automatic aggregate repair.
