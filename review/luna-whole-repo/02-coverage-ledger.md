# Demonstrable File Coverage Ledger

## Rules

Every tracked production Swift file is listed exactly once below. `REVIEWED-DEEP` means the file was inspected at symbol/control-flow level and used in the flow, invariant, or finding review. `REVIEWED-CONTEXT` means the file was inspected for its public contract, callers, persistence/network/UI boundary, and interactions, with detailed behavior delegated to the owning subsystem files. `DEVICE-DEPENDENT` means the source was inspected, but an important runtime conclusion still requires physical-device or OS-scheduler evidence. The generated asset-symbol source emitted by Xcode is not tracked and is excluded from this ledger.

Tracked production inventory: 105 Swift files: 69 `REVIEWED-DEEP`, 29 `REVIEWED-CONTEXT`, and 7 `DEVICE-DEPENDENT`. Tracked test inventory: 43 Swift files. No production Swift file is left as `NEEDS-FOLLOWUP`.

## REVIEWED-DEEP

### App

- `TradingCardScanner/App/TradingCardScannerApp.swift`

### Models

- `TradingCardScanner/Models/CardVariant.swift`
- `TradingCardScanner/Models/CollectedCard.swift`
- `TradingCardScanner/Models/CollectionActivity.swift`
- `TradingCardScanner/Models/InventoryEvent.swift`
- `TradingCardScanner/Models/Money.swift`
- `TradingCardScanner/Models/PortfolioDailyClose.swift`
- `TradingCardScanner/Models/PortfolioHistoryTypes.swift`
- `TradingCardScanner/Models/PriceCheckDay.swift`
- `TradingCardScanner/Models/PriceObservation.swift`
- `TradingCardScanner/Models/PriceRecord.swift`
- `TradingCardScanner/Models/ProductIdentity.swift`
- `TradingCardScanner/Models/ReferenceQuote.swift`

### Services

- `TradingCardScanner/Services/BrowseCatalog.swift`
- `TradingCardScanner/Services/CardCatalog.swift`
- `TradingCardScanner/Services/CardCenteringAnalyzer.swift`
- `TradingCardScanner/Services/CardCenteringExport.swift`
- `TradingCardScanner/Services/CardLatch.swift`
- `TradingCardScanner/Services/CollectionCSV.swift`
- `TradingCardScanner/Services/CollectionCatalogNormalizer.swift`
- `TradingCardScanner/Services/CollectionProjectionActor.swift`
- `TradingCardScanner/Services/CollectionQuery.swift`
- `TradingCardScanner/Services/CollectionStore.swift`
- `TradingCardScanner/Services/GradedLabelParser.swift`
- `TradingCardScanner/Services/InventoryLedger.swift`
- `TradingCardScanner/Services/JustTCGRefreshCoordinator.swift`
- `TradingCardScanner/Services/JustTCGSyncLedger.swift`
- `TradingCardScanner/Services/JustTCGV2GradedClient.swift`
- `TradingCardScanner/Services/LogicalCollection.swift`
- `TradingCardScanner/Services/MagicTreatmentCatalog.swift`
- `TradingCardScanner/Services/MagicTreatmentMigration.swift`
- `TradingCardScanner/Services/PortfolioCalendar.swift`
- `TradingCardScanner/Services/PortfolioClose.swift`
- `TradingCardScanner/Services/PortfolioEngine.swift`
- `TradingCardScanner/Services/PortfolioEpoch.swift`
- `TradingCardScanner/Services/PortfolioHistoryEngine.swift`
- `TradingCardScanner/Services/PortfolioReplay.swift`
- `TradingCardScanner/Services/PortfolioReplaySnapshot.swift`
- `TradingCardScanner/Services/PriceCheckCoordinator.swift`
- `TradingCardScanner/Services/PriceFallbackQuoteResolver.swift`
- `TradingCardScanner/Services/PriceObservationLog.swift`
- `TradingCardScanner/Services/PriceProvider.swift`
- `TradingCardScanner/Services/PriceQuoteService.swift`
- `TradingCardScanner/Services/PriceRefreshController.swift`
- `TradingCardScanner/Services/PriceSnapshotStore.swift`
- `TradingCardScanner/Services/PriceStore.swift`
- `TradingCardScanner/Services/ProductCatalogIdentity.swift`
- `TradingCardScanner/Services/ProductIdentityStore.swift`
- `TradingCardScanner/Services/ProductPriceService.swift`
- `TradingCardScanner/Services/ScanParser.swift`
- `TradingCardScanner/Services/ScannedGradedResolver.swift`
- `TradingCardScanner/Services/SlabFramingRegion.swift`
- `TradingCardScanner/Services/StoreRevisionMonitor.swift`
- `TradingCardScanner/Services/TCGdexService.swift`
- `TradingCardScanner/Services/VariantResolver.swift`

### Views

- `TradingCardScanner/Views/BrowseView.swift`
- `TradingCardScanner/Views/CardCenteringView.swift`
- `TradingCardScanner/Views/CatalogCardDetailView.swift`
- `TradingCardScanner/Views/CollectionActivityLogView.swift`
- `TradingCardScanner/Views/CollectionCardDetailView.swift`
- `TradingCardScanner/Views/CollectionView.swift`
- `TradingCardScanner/Views/ContentView.swift`
- `TradingCardScanner/Views/GradedVariantPickerView.swift`
- `TradingCardScanner/Views/PortfolioHistoryView.swift`
- `TradingCardScanner/Views/PortfolioView.swift`
- `TradingCardScanner/Views/PriceCheckResultView.swift`
- `TradingCardScanner/Views/ScanReviewSheet.swift`
- `TradingCardScanner/Views/ScannerViewModel.swift`
- `TradingCardScanner/Views/SealedBrowseViews.swift`

## REVIEWED-CONTEXT

### App

- `TradingCardScanner/App/AppDelegate.swift`

### Models

- `TradingCardScanner/Models/BrowseCatalogModels.swift`
- `TradingCardScanner/Models/CardCenteringMeasurement.swift`
- `TradingCardScanner/Models/CollectionItemKind.swift`
- `TradingCardScanner/Models/JustTCGMarketModels.swift`
- `TradingCardScanner/Models/MagicContentKind.swift`
- `TradingCardScanner/Models/MagicPhysicalObjects.swift`
- `TradingCardScanner/Models/MagicTreatment.swift`
- `TradingCardScanner/Models/TCGdexCard.swift`

### Services

- `TradingCardScanner/Services/AppleAccountCredentials.swift`
- `TradingCardScanner/Services/JustTCGTransport.swift`
- `TradingCardScanner/Services/JustTCGV1Client.swift`
- `TradingCardScanner/Services/MagicSetSnapshot.swift`
- `TradingCardScanner/Services/PokemonChecklistSnapshot.swift`
- `TradingCardScanner/Services/PriceRefreshTargets.swift`
- `TradingCardScanner/Services/PriceVendorCredentials.swift`
- `TradingCardScanner/Services/QuoteCache.swift`
- `TradingCardScanner/Services/ScanFeedback.swift`
- `TradingCardScanner/Services/SetCodeMap.swift`
- `TradingCardScanner/Services/TCGplayerLink.swift`

### Views

- `TradingCardScanner/Views/AppGlass.swift`
- `TradingCardScanner/Views/CardFinishOverlay.swift`
- `TradingCardScanner/Views/CollectionFilters.swift`
- `TradingCardScanner/Views/CollectionFinishDot.swift`
- `TradingCardScanner/Views/ContentWidth.swift`
- `TradingCardScanner/Views/PortfolioDebugFixtures.swift`
- `TradingCardScanner/Views/RemovalUndoBanner.swift`
- `TradingCardScanner/Views/ScanSessionOverlays.swift`
- `TradingCardScanner/Views/ScannerSettingsView.swift`

## DEVICE-DEPENDENT

These files were reviewed at source/control-flow level, but the material runtime behavior they own also requires hardware or OS-scheduler evidence. They are not unresolved review work; `06-device-and-environment-validation.md` records the exact external gates.

- `TradingCardScanner/Services/BackgroundPriceRefresh.swift` — BGTask scheduling, suspension, and background execution window.
- `TradingCardScanner/Services/CameraCapabilities.swift` — physical camera capability/pixel-format behavior.
- `TradingCardScanner/Services/CameraRotationTracker.swift` — device orientation/rotation observation.
- `TradingCardScanner/Services/CardScanner.swift` — AVCapture/Vision throughput, physical framing, and slab OCR behavior.
- `TradingCardScanner/Views/CameraPreview.swift` — live AVCapture preview/session presentation.
- `TradingCardScanner/Views/CenteringCameraView.swift` — camera capture and orientation behavior for centering.
- `TradingCardScanner/Views/ScannerView.swift` — camera-facing scanner surface and real-device interaction.

## Non-Swift production and supporting inventory

The following are not part of the 105-file Swift classification but were inspected as shipped inputs or supporting evidence:

- Build graph/configuration: `TradingCardScanner.xcodeproj/project.pbxproj`, `project.xcworkspace/contents.xcworkspacedata`, `xcshareddata/xcschemes/TradingCardScanner.xcscheme`.
- App configuration: `TradingCardScanner/Info.plist`, `TradingCardScanner/PrivacyInfo.xcprivacy`, `TradingCardScanner/TradingCardScanner.entitlements`, `TradingCardScanner/TradingCardScanner-Local.entitlements`.
- Asset catalog: `TradingCardScanner/Assets.xcassets/` (20 tracked files including the icon PNG and 19 JSON descriptors).
- Bundled data: 738 Magic snapshot set JSON files, 160 Pokémon snapshot set JSON files, both manifests, and the Magic compact catalog manifest/vocabulary/data.
- Supporting documentation: `README.md`, `progress.md`, all tracked `docs/`, and all tracked `references/`.
- Supporting scripts: all six tracked `scripts/` files.

## Exclusion ledger

| Inventory | Classification | Reason |
| --- | --- | --- |
| 43 files under `TradingCardScannerTests/` | `EXCLUDED-NONPRODUCTION` | Executable review evidence, not shipped application source |
| `docs/`, `references/`, `scripts/`, root `progress.md`, and historical diff | `EXCLUDED-NONPRODUCTION` | Supporting process/tooling/history; inspected where they state current behavior |
| `.codex_build*` and `/tmp/TradingCardScannerLuna*` outputs | `EXCLUDED-GENERATED` | Disposable build products and test result bundles outside tracked source |
| Xcode-emitted `GeneratedAssetSymbols.swift` | `EXCLUDED-GENERATED` | Build-generated source, not tracked or hand-maintained |
| Xcode/Swift/system dependencies | `EXCLUDED-THIRD-PARTY` | Not repository-owned code |

The coverage is complete for relevant production source. Data/configuration coverage is explicit above; individual generated resource files are grouped by manifest-backed inventory rather than repeated as source classifications.
