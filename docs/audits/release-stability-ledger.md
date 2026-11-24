# Release-stability audit ledger

**Status:** Initial repairs verified in focused checks. Whole-codebase review and release gates remain open — 2026-11-23.

- Worktree `/private/tmp/ScanStash-release-stability`, branch `audit/release-stability`.
- Starting commit `5800704bdb22d6b9f2a3974b7fe0143e0606b2e8`. The local `origin/main` ref and GitHub's current `refs/heads/main` agreed when isolation was established.
- Before each implementation checkpoint, verify the worktree root and branch, then inspect status and the relevant diff. Keep commits on this branch. Open the pull request against `main` only after milestone verification.
- The 2026-11-23 goal attachment caps the audit run at three hours. Preserve reviewed and pending evidence at the cutoff.

## Authorities and scope

Use the [launch contract](../release/launch-contract.md), [release follow-ups](../plans/release_followups.md), [documentation audit](../plans/documentation_audit.md), [prior launch review](launch-review-2026-11-10.md) and [current implementation checkpoint](../current-implementation-2026-11-15.md) to establish intended behavior and seed known-issue investigations. Reproduce or re-evaluate historical findings on the candidate.

The launch contract records owner and external prerequisites for provider access, policy links, hardware acceptance and distribution. Live iCloud is deferred for on-device 1.0. Review the existing code and configuration for regressions, then report unmet prerequisites with their own evidence. Finished tooling and non-distribution source remain within review scope.

## Baseline

| Gate | Candidate and evidence | Status |
| --- | --- | --- |
| iOS full target | Starting commit, Xcode 27.2 (27B52), ProfileLocal / DebugRemoteLocal, unsigned iPhone 17 Pro on iOS 27.0, `Baseline.xcresult` on T7 | Running with reproduced failures |
| iOS production build | `ReleaseBuild.log`, ProfileLocal / Release, generic iOS Simulator, Xcode 27.2. Package contains the privacy manifest, iPhone portrait and all four iPad orientations. | Passed |
| Catalog core tests | Pokémon 93 passed and 1 skipped, Magic 19 passed, One Piece 54 passed, zero failures | Passed with one skip |
| Offline script suite | `ScriptBaseline.log` hit a failing module import. `ScriptAfterDiscoveryRepair.log` completed 428 cases with 423 passed and five native-publisher skips. | Passed after RS-01; skipped cases run separately under RS-08 |
| Yu-Gi-Oh! publishing | 59 retained Python fixture cases passed. The native publisher failed to compile at baseline. `YuGiOhPublisher.log` contains five passing publisher contract cases after repair. | Publisher passed after RS-08 |
| Build and CI inputs | Xcode project, app Info.plist, privacy manifest and both entitlements passed plist validation. CI selector validator resolved all 84 XCTest selectors. All 177 Python and 18 shell sources parsed. | Passed |
| Focused app checkpoint | `Checkpoint1.log` reported 263 passed, one skip and two failures on the unsigned host. The same two Keychain tests passed with signing. `SignedCheckpoint.log` also verifies 56 Yu-Gi-Oh! app cases. | Changed behavior passed |
| Signed local fixtures | `LocalFixtures.log` reported 36 passed and one StoreKit interrupted-purchase skip. Includes Pokémon offline release, StoreKit local approval/restore and ProductIdentity Keychain tests. | Passed with one skip |
| Signed cross-module checkpoint | `CrossModule.log`, candidate `baab2639`. All 361 cases passed across Browse, ownership revision and concurrency, CSV resume, portfolio replay and daily close, pricing refresh lifecycle, and catalog delivery and activation. | Passed |
| External and device gates | Public catalog and market-feed checks returned HTTP 509 (RS-11). Configured Release privacy and support URLs are empty as documented. Physical camera/rotation, sustained lifecycle, App Store Connect and distribution acceptance remain unverified. | Open |

Artifact root `/Volumes/T7/ScanStash_ReleaseStability_20261123`. Keep raw evidence out of Git.

## Checkpoints

A checkpoint closes after tracing its production entry points through shared boundaries, representative success/failure/recovery paths, and relevant tests. Mark source, simulator, retained fixture and physical evidence separately. Update this ledger before moving to the next checkpoint.

| ID | Primary area | Workflow and boundaries | Status |
| --- | --- | --- | --- |
| 01 | App startup, navigation and settings | Opening and onboarding → tab routing → settings, support, permissions, app/scene lifecycle and accessibility. | Startup and Release config in progress |
| 02 | Storage, recovery and sync | Launch → schema and storage selection → interruption/relaunch, migrations, CloudKit readiness and session replacement. | Artwork recovery in progress |
| 03 | Camera and recognition | Permission → frames and ROI → OCR, cadence, identifier confirmation, slab capture and duplicate suppression. | In progress |
| 04 | Scan resolution and recovery | Recognition → exact catalog result → variant and print-run choice → save, correction, retries, departure and restored review. | Pending |
| 05 | Pokémon catalog and game adapters | Discovery, historical titles and numbers, exact products and variants, signed delivery, import and prices. | Signed bundle and hosting in progress |
| 06 | Magic catalog and game adapters | Scryfall discovery and pacing, historical variants, foil/treatment identity, paired objects, catalog updates and pricing. | Pending |
| 07 | One Piece catalog and game adapters | Seed/remote activation, English identity, reviewed finishes, signed updates, import, artwork and market lanes. | Recognition and activation in progress |
| 08 | Lorcana catalog and game adapters | Discovery, source normalization, reviewed identity and finishes, activation, import and pricing. | Recognition and activation in progress |
| 09 | Yu-Gi-Oh! catalog and game adapters | Set and printing identity, release activation, lookup and import, recognition and price mapping. | Printings, editions and publisher verified with fixtures. Live delivery open |
| 10 | Browse, detail and shared catalog | Game registration → search, filters, pagination, completion, artwork, exact details, manual add and sealed browse. | Search, pricing and detail in progress |
| 11 | Collection and activity | Owned presentation → edit, acquisition, correction, quantity, sale, deletion/undo and revision notifications. | Pending |
| 12 | Pricing and products | Provider and Keychain inputs → exact lookup, fallback, quotas, stale/cache states, sealed/graded quotes, refresh and offline retention. | Reference quote lifecycle in progress |
| 13 | Portfolio and durable accounting | Ledger authority → daily close, replay and current projections → movement, history and owned-value reconciliation. | Epoch and replay in progress |
| 14 | Import, export and trade | CSV validation, matching, interruption/resume and export → privacy, trade selection, valuation and review. | Trade and CSV resume in progress |
| 15 | Centering and listing photos | Pro camera/library → centering correction, review and output → listing photo crop, export, save and cancellation. | Camera and initial-guide evidence in progress |
| 16 | Purchases and paid access | StoreKit configuration → entitlement, offer, restore and paid/free access checks. | Source and local fixtures reviewed. One simulator skip and production acceptance open |
| 17 | Publisher, tooling and evidence | Curated inputs → retained tests, builders, signing, hosting, feed verification, maintenance and research harnesses. | Pending |
| 18 | Build, CI and test infrastructure | Project membership, Release declarations, CI selectors, fixtures, test reliability, packaging and external integration configuration. | In progress |
| 19 | Final cross-module verification | Recheck changed paths and actual workflows, run broad gates and reconcile all findings, skips and external limitations. | Pending |

## Findings and verification

Record an ID, severity, checkpoint, affected promise, reproducible evidence, root cause, disposition, focused regression and remaining limitations. Critical covers catastrophic loss, serious exposure or widespread failure. High covers broken core behavior, material error or corruption, or frequent crashes. Medium covers meaningful workflow failure, incorrect or misleading behavior, or functional degradation. Low covers limited practical impact.

| ID | Severity | Evidence and disposition |
| --- | --- | --- |
| RS-01 | Medium | Checkpoints 05/17/18. At the starting commit, the offline CI suite hit `IndentationError` when importing `test_certify_pokemon_finish_coverage.py`. One e-card method declaration was outside its Python test class, which made the following declaration invalid. Restoring class indentation preserves all assertions and restores discovery. 56 focused tests passed, followed by the broad script rerun above. |
| RS-02 | Medium | Checkpoint 14. Trade Review drew a comparison bar from partial totals while its verdict withheld the comparison. Reproduced on an iPhone 17 Pro simulator with `TradeAnalyzer review-partial` ($181.60 and $176.00 priced so far, pending and unavailable quotes). Candidate renders show the partial totals and pending verdict without the bar and the complete $5.60 difference with its bar and cash action. Evidence is in the `TradeBeforePartial`, `TradeAfterPartial` and `TradeAfterComplete` artifact directories. |
| RS-03 | Low | Checkpoint 14. Both trade summary artwork stacks take the last three rows, although new scans insert at index zero. With four or more distinct rows on a side the artwork previews show older rows while the latest receipt, count and totals still reflect the new scan. Recorded without a repair. |
| RS-04 | Medium | Checkpoints 02/11. A user can remove a card before delayed legacy-artwork migration. The orphan sweep could delete an aged photo while Restore remained available because only live rows and current overrides protected filenames. The repair protects recent removal snapshots. All eight artwork sweep tests passed, including restore of the card and photo after cleanup. |
| RS-05 | Medium | Checkpoints 15/18. The baseline reproduced two invalid camera test setups after `4d0b628e` added a deliberate readiness check. The fixture models readiness becoming stale before queue admission, preserving rejection/retry and immediate-stop assertions and checking that a fresh stopped shutter does nothing. All 18 camera rotation cases passed. |
| RS-06 | High | Checkpoint 15. The baseline reproduced LR03 in `CardCenteringGroundTruthTests/testInitialGuidesMatchExistingDevelopmentAnnotations`. The 2.0 percentage-point criterion failed on four retained photos, reaching 10.97 points top/bottom for IMG_0780. The paid tool requires confirmation and allows guide editing. The candidate still fails the initial-guide criterion. Root-cause review and repair remain open. |
| RS-07 | Medium | Checkpoints 04/10/12/14. Browse records a same-source confirmed miss, but Price Check and Trade could reopen the quote as current. The repair treats the older receipt as last known and rejects a replay during refresh. All 45 quote-cache tests passed, including the stored marker and replacement by a newer successful quote. |
| RS-08 | High | Checkpoints 09/17/18. The standalone publisher failed to compile because a shared catalog model used app-only `PhysicalVariant`. The projection now lives with the variant definitions in the iOS adapter. Five publisher contract cases and 56 signed app cases passed, including both Duel Terminal scan/Browse/CSV and Limited identity/quote coverage. |
| RS-09 | Medium | Checkpoints 16/18. The signed ProfileLocal host failed to load product data in three StoreKit tests. The scheme omitted the existing StoreKit configuration used by the shared Debug scheme. Referencing the same fixture restored local purchase, pending approval and restore coverage. 14 Collector Tools cases passed; one interrupted-purchase case skipped because this simulator granted the verified entitlement before issue resolution. |
| RS-10 | Medium | Checkpoints 05/18. The bundled Pokémon tests expected revision 24 after `1104b78f` installed signed revision 26. Expected revisions now come from verification of the packaged envelope. Checks still require exact activation, persistence, older-release replacement, known sets and rejection of untrusted input. All three cases passed. |
| RS-11 | High, external | Checkpoints 05/07/09/12/17. On 2026-11-23, the public Pokémon, One Piece and Yu-Gi-Oh! current pointers and the market-feed last-updated marker returned HTTP 509 on both the configured production host and documented Firebase mirror. Pokémon refresh in the simulator recorded the same result. Root cause and restoration need hosting-side evidence. Bundled fallback tests give local evidence only. |
| RS-12 | Low | Checkpoint 14. Trade Review's combined warning says all affected prices are older than today, even when a same-day quote is flagged as last known after a confirmed miss. Individual entries preserve their last-known status and the balance verdict requires current quotes. Recorded without a repair. |

### Recognition review progress

Current code supersedes the earlier [scanner module review](scanner_module_review.md) on four points. A title attempt retains its exhausted budget through the TTL, the preview and debug overlays consume the installed footer ROI, missing buffers trigger request recovery without treating an OCR failure as evidence of a card exit, and the lens probe checks reported minimum focus distance under a versioned cache key. Recognition-device timing, debug overlay/frame coherence during ROI transitions, and sustained failure behavior remain under review.

### Paid access review progress

Traced startup and foreground reconciliation, StoreKit product identity/type, purchase delivery, verification, restore, revocation and stale ownership snapshots through the offer, centering gate and listing photo archive delivery. The production build omits the owner-only paid-tool bypass. Signed local fixtures passed as described in RS-09. App Store Connect purchase, restore and interrupted purchase remain externally gated.

### Shared catalog delivery review progress

Traced HTTPS endpoint validation, redirects, transfer limits, cancellation and conditional headers through the shared transport. Traced decoded release validation, predecessor checks, two-slot writes, corruption recovery and serialized withdrawal of superseded prices through activation. The hosted endpoints are currently blocked by RS-11. Game-specific signer/activation traces and device acceptance remain open.

### Cross-module review progress

- Startup and settings. Traced opening-state handoff, scene readiness, storage generation and configured privacy/support entry points. Keychain updates the saved vendor key in place, retries indeterminate presence on later reads and separates explicit removal from background access. Confirmed owner-provisioned access remains a launch dependency. Rendered navigation, permission denial, VoiceOver and physical lifecycle remain open.
- Browse. Traced request generation, page deduplication, cursor progress, authority changes and owned-value currency eligibility. Detail add re-resolves a stale identity and retains separate saved values for owned copies. Sealed product search and exact price and ownership paths remain partly reviewed.
- CSV and portfolio. Traced security-scoped file access, validation, exclusive writes, generation fences and resume. Traced pinned epoch/time zone, half-open close boundaries, replay tie ordering and grouped correction legs. The signed checkpoint covers CSV resume, ledger completeness, concurrency and replay. Physical file-provider failures, final exported artifacts and history presentation remain open.
- One Piece and Lorcana. Traced the English One Piece identity and explicit sibling finish selection, and the Lorcana recognizer's footer and marker requirements and activation. Local activation and integration passed in the signed checkpoint. Game-specific pricing/import and artwork still need coverage.
- Listing photos. Traced temporary ownership through photo input, per-side crop, archive, reorder and share retention. The Photos save path owns its input through authorization and library commit. Review of actual Photos permissions, full-resolution memory pressure and hardware capture remains open.

### Centering accuracy investigation

The existing [centering evidence](centering-guided-repair.md) distinguishes the production guide error from DEBUG-only printed-reference tests. For the four production failures, prior overlays show both physical-cut and inner-reference disagreement. Starting Town has conflicting boundary targets across the retained annotation and supplied-layout experiment. Resolve the intended inner reference and obtain independently reviewed boundary evidence before changing selection rules. Both original tests and tolerances remain in the branch.

Re-evaluate launch review LR01–LR08 and current release follow-ups on this candidate. The final cross-module verification pass follows initial coverage and the last qualifying repair.

## Tracked file inventory

650 tracked sources and build/configuration files at the starting commit. Each path has a primary checkpoint. Also follow it from every production caller or test where it crosses a boundary. Checkpoint 18 inventories the app tests, with individual tests exercised alongside their corresponding workflow. The catalog package tests belong to their game checkpoint. Checkpoint 17 includes authored tooling and its tests, including the centering and Lorcana research harnesses.

Bundled catalogs, assets, retained fixtures and generated snapshots are reviewed through the code that produces, validates, installs and consumes them. Treat curated publisher inputs and manually maintained catalog policy/mapping data as review inputs for 05–10, 12 and 17. Review public verification keys, dependency/package imports and hosting routes with their trust or execution boundary. Historical docs, raw evidence, generated data and vendored implementations are outside the source-file inventory.

### 01 App startup, navigation and settings (17)

- `TradingCardScanner/App/AppDelegate.swift`
- `TradingCardScanner/App/TradingCardScannerApp.swift`
- `TradingCardScanner/Info.plist`
- `TradingCardScanner/PrivacyInfo.xcprivacy`
- `TradingCardScanner/Services/CardScannerExternalLinks.swift`
- `TradingCardScanner/Views/AppGlass.swift`
- `TradingCardScanner/Views/AppOpeningView.swift`
- `TradingCardScanner/Views/ContentView.swift`
- `TradingCardScanner/Views/ContentWidth.swift`
- `TradingCardScanner/Views/PrivacyAndSupportSettingsView.swift`
- `TradingCardScanner/Views/ProArtwork.swift`
- `TradingCardScanner/Views/ProView.swift`
- `TradingCardScanner/Views/ScannerSettingsView.swift`
- `docs/legal/bluehost-pages/privacy.html`
- `docs/legal/bluehost-pages/privacy/index.html`
- `docs/legal/bluehost-pages/support.html`
- `docs/legal/bluehost-pages/support/index.html`

### 02 Storage, recovery and sync (12)

- `TradingCardScanner/Services/BackgroundModelActor.swift`
- `TradingCardScanner/Services/CloudAccountProbe.swift`
- `TradingCardScanner/Services/CloudCollectionAnchorStore.swift`
- `TradingCardScanner/Services/CloudKitEventReadinessSource.swift`
- `TradingCardScanner/Services/CloudRestorationReadiness.swift`
- `TradingCardScanner/Services/CollectionStorageBootstrap.swift`
- `TradingCardScanner/Services/CollectionStoragePolicy.swift`
- `TradingCardScanner/Services/CollectionStoreDigest.swift`
- `TradingCardScanner/Services/CollectionStoreManifestStore.swift`
- `TradingCardScanner/TradingCardScanner-Local.entitlements`
- `TradingCardScanner/TradingCardScanner.entitlements`
- `TradingCardScanner/Views/CollectionStorageBootstrapView.swift`

### 03 Camera and recognition (10)

- `TradingCardScanner/Models/ScanSubjectMode.swift`
- `TradingCardScanner/Services/CameraCapabilities.swift`
- `TradingCardScanner/Services/CameraRotationTracker.swift`
- `TradingCardScanner/Services/CardLatch.swift`
- `TradingCardScanner/Services/CardScanner.swift`
- `TradingCardScanner/Services/GradedLabelParser.swift`
- `TradingCardScanner/Services/ScanFeedback.swift`
- `TradingCardScanner/Services/ScanParser.swift`
- `TradingCardScanner/Services/SlabFramingRegion.swift`
- `TradingCardScanner/Views/CameraPreview.swift`

### 04 Scan resolution and recovery (15)

- `TradingCardScanner/Models/ResolvedCatalogCard.swift`
- `TradingCardScanner/Models/UnverifiedReport.swift`
- `TradingCardScanner/Services/ScanSessionMetricsLog.swift`
- `TradingCardScanner/Services/ScannedGradedResolver.swift`
- `TradingCardScanner/Services/UnresolvedScanStore.swift`
- `TradingCardScanner/Services/UnverifiedReportEvaluator.swift`
- `TradingCardScanner/Services/VariantResolver.swift`
- `TradingCardScanner/Views/CardCorrectionPicker.swift`
- `TradingCardScanner/Views/CardFinishOverlay.swift`
- `TradingCardScanner/Views/ScanReviewSheet.swift`
- `TradingCardScanner/Views/ScanSessionOverlays.swift`
- `TradingCardScanner/Views/ScannerView.swift`
- `TradingCardScanner/Views/ScannerViewModel.swift`
- `TradingCardScanner/Views/UnresolvedScanDetailView.swift`
- `TradingCardScanner/Views/UnverifiedReportViews.swift`

### 05 Pokémon catalog and game adapters (52)

- `PokemonCatalogCore/Package.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/ArtworkProbe.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogBuilder.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogCandidateValidator.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogChangeClassification.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogContract.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogPublisher.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogSnapshot.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/DiscoveryPolicy.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/EnglishExclusions.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/PokemonCatalogArtworkEnricher.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/PokemonTCGProviderClient.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/ProviderFingerprint.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/ProviderModels.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/SecondaryCardMatcher.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/SecondaryProviderModels.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/SecondarySetMatcher.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/TCGdexCardArtworkResolver.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/TCGdexProviderClient.swift`
- `PokemonCatalogCore/Sources/PokemonCatalogCore/TextNormalization.swift`
- `PokemonCatalogCore/Sources/pokemon-catalog-publisher/main.swift`
- `PokemonCatalogCore/Tests/PokemonCatalogCoreTests/AdditionalVariantTests.swift`
- `PokemonCatalogCore/Tests/PokemonCatalogCoreTests/ArtworkFingerprintParityTests.swift`
- `PokemonCatalogCore/Tests/PokemonCatalogCoreTests/EnergyDescriptorTests.swift`
- `PokemonCatalogCore/Tests/PokemonCatalogCoreTests/PokemonCatalogCoreTests.swift`
- `PokemonCatalogCore/Tests/PokemonCatalogCoreTests/ProductionMembershipBoundaryTests.swift`
- `PokemonCatalogCore/Tests/PokemonCatalogCoreTests/TCGdexCardArtworkResolverTests.swift`
- `TradingCardScanner/Games/Core/TCGdexCircuitBreaker.swift`
- `TradingCardScanner/Games/Pokemon/PokemonBattleDeckFinishCatalog.swift`
- `TradingCardScanner/Games/Pokemon/PokemonCatalogAdapter.swift`
- `TradingCardScanner/Games/Pokemon/PokemonCatalogSupport.swift`
- `TradingCardScanner/Games/Pokemon/PokemonDeltaReignCatalog.swift`
- `TradingCardScanner/Games/Pokemon/PokemonGameRuntime.swift`
- `TradingCardScanner/Games/Pokemon/PokemonHistoricalCatalog.swift`
- `TradingCardScanner/Games/Pokemon/PokemonM26Catalog.swift`
- `TradingCardScanner/Games/Pokemon/PokemonPriceAdapter.swift`
- `TradingCardScanner/Games/Pokemon/PokemonRecognitionAdapter.swift`
- `TradingCardScanner/Games/Pokemon/PokemonVariantPolicy.swift`
- `TradingCardScanner/Models/TCGdexCard.swift`
- `TradingCardScanner/Services/PokemonCatalogCoordinator.swift`
- `TradingCardScanner/Services/PokemonCatalogRegistry.swift`
- `TradingCardScanner/Services/PokemonCatalogRelease.swift`
- `TradingCardScanner/Services/PokemonCatalogReleaseStore.swift`
- `TradingCardScanner/Services/PokemonCatalogRollout.swift`
- `TradingCardScanner/Services/PokemonCatalogSignatureVerifier.swift`
- `TradingCardScanner/Services/PokemonCatalogUpdateClient.swift`
- `TradingCardScanner/Services/PokemonChecklistSnapshot.swift`
- `TradingCardScanner/Services/PokemonNameMatcher.swift`
- `TradingCardScanner/Services/PokemonTCGCSVMapping.swift`
- `TradingCardScanner/Services/PokemonTCGCSVPriceService.swift`
- `TradingCardScanner/Services/SetCodeMap.swift`
- `TradingCardScanner/Services/TCGdexService.swift`

### 06 Magic catalog and game adapters (35)

- `MagicCatalogCore/Package.swift`
- `MagicCatalogCore/Sources/MagicCatalogCore/CatalogBuilder.swift`
- `MagicCatalogCore/Sources/MagicCatalogCore/CatalogCandidateValidator.swift`
- `MagicCatalogCore/Sources/MagicCatalogCore/CatalogChangeClassification.swift`
- `MagicCatalogCore/Sources/MagicCatalogCore/CatalogContract.swift`
- `MagicCatalogCore/Sources/MagicCatalogCore/CatalogPublisher.swift`
- `MagicCatalogCore/Sources/MagicCatalogCore/Policy.swift`
- `MagicCatalogCore/Sources/MagicCatalogCore/ProviderModels.swift`
- `MagicCatalogCore/Sources/MagicCatalogCore/ScryfallProviderClient.swift`
- `MagicCatalogCore/Sources/magic-catalog-publisher/main.swift`
- `MagicCatalogCore/Tests/MagicCatalogCoreTests/MagicCatalogCoreTests.swift`
- `TradingCardScanner/Games/Magic/MagicCatalogAdapter.swift`
- `TradingCardScanner/Games/Magic/MagicGameRuntime.swift`
- `TradingCardScanner/Games/Magic/MagicHistoricalRecognition.swift`
- `TradingCardScanner/Games/Magic/MagicPriceAdapter.swift`
- `TradingCardScanner/Games/Magic/MagicRecognitionAdapter.swift`
- `TradingCardScanner/Games/Magic/MagicVariantPolicy.swift`
- `TradingCardScanner/Models/MagicContentKind.swift`
- `TradingCardScanner/Models/MagicPhysicalObjects.swift`
- `TradingCardScanner/Models/MagicTreatment.swift`
- `TradingCardScanner/Services/MagicCatalogCoordinator.swift`
- `TradingCardScanner/Services/MagicCatalogRegistry.swift`
- `TradingCardScanner/Services/MagicCatalogRelease.swift`
- `TradingCardScanner/Services/MagicCatalogReleaseStore.swift`
- `TradingCardScanner/Services/MagicCatalogRollout.swift`
- `TradingCardScanner/Services/MagicCatalogSignatureVerifier.swift`
- `TradingCardScanner/Services/MagicCatalogUpdateClient.swift`
- `TradingCardScanner/Services/MagicHistoricalIndex.swift`
- `TradingCardScanner/Services/MagicRecognitionProfile.swift`
- `TradingCardScanner/Services/MagicSetSnapshot.swift`
- `TradingCardScanner/Services/MagicTokenPairingSession.swift`
- `TradingCardScanner/Services/MagicTreatmentCatalog.swift`
- `TradingCardScanner/Services/MagicTreatmentMigration.swift`
- `TradingCardScanner/Services/ScryfallBulkCardIndex.swift`
- `TradingCardScanner/Services/ScryfallRequestPacer.swift`

### 07 One Piece catalog and game adapters (31)

- `OnePieceCatalogCore/Package.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/Artwork.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/CanonicalCard.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/CatalogBuilder.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/CatalogCandidateValidator.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/CatalogChangeClassification.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/CatalogContract.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/CatalogPublication.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/CatalogSignature.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/MarketMapping.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/PhysicalPrinting.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/ProviderModels.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/ReconciliationStatus.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/SourceObservation.swift`
- `OnePieceCatalogCore/Sources/OnePieceCatalogCore/TextNormalization.swift`
- `OnePieceCatalogCore/Sources/one-piece-catalog-publisher/main.swift`
- `OnePieceCatalogCore/Tests/OnePieceCatalogCoreTests/CatalogVerificationFastPathTests.swift`
- `OnePieceCatalogCore/Tests/OnePieceCatalogCoreTests/OnePieceCatalogCoreTests.swift`
- `TradingCardScanner/Games/OnePiece/OnePieceBrowseAdapter.swift`
- `TradingCardScanner/Games/OnePiece/OnePieceCatalogAdapter.swift`
- `TradingCardScanner/Games/OnePiece/OnePieceGameRuntime.swift`
- `TradingCardScanner/Games/OnePiece/OnePieceImportAdapter.swift`
- `TradingCardScanner/Games/OnePiece/OnePiecePriceAdapter.swift`
- `TradingCardScanner/Games/OnePiece/OnePieceRecognitionAdapter.swift`
- `TradingCardScanner/Games/OnePiece/OnePieceScanProfile.swift`
- `TradingCardScanner/Services/OnePieceCatalogBootstrap.swift`
- `TradingCardScanner/Services/OnePieceCatalogCoordinator.swift`
- `TradingCardScanner/Services/OnePieceCatalogRegistry.swift`
- `TradingCardScanner/Services/OnePieceCatalogReleaseStore.swift`
- `TradingCardScanner/Services/OnePieceCatalogRollout.swift`
- `TradingCardScanner/Services/OnePieceCatalogUpdateClient.swift`

### 08 Lorcana catalog and game adapters (13)

- `TradingCardScanner/Games/Lorcana/LorcanaBrowseAdapter.swift`
- `TradingCardScanner/Games/Lorcana/LorcanaCatalogCoordinator.swift`
- `TradingCardScanner/Games/Lorcana/LorcanaCatalogRegistry.swift`
- `TradingCardScanner/Games/Lorcana/LorcanaCatalogRelease.swift`
- `TradingCardScanner/Games/Lorcana/LorcanaCatalogReleaseStore.swift`
- `TradingCardScanner/Games/Lorcana/LorcanaDiscoveryCatalog.swift`
- `TradingCardScanner/Games/Lorcana/LorcanaGameRuntime.swift`
- `TradingCardScanner/Games/Lorcana/LorcanaImportAdapter.swift`
- `TradingCardScanner/Games/Lorcana/LorcanaLocalReviewKit.swift`
- `TradingCardScanner/Games/Lorcana/LorcanaPhysicalCatalog.swift`
- `TradingCardScanner/Games/Lorcana/LorcanaPriceAdapter.swift`
- `TradingCardScanner/Games/Lorcana/LorcanaRecognitionAdapter.swift`
- `TradingCardScanner/Games/Lorcana/LorcastSourceNormalizer.swift`

### 09 Yu-Gi-Oh! catalog and game adapters (10)

- `TradingCardScanner/Games/YuGiOh/YuGiOhBrowseAdapter.swift`
- `TradingCardScanner/Games/YuGiOh/YuGiOhCandidateRelease.swift`
- `TradingCardScanner/Games/YuGiOh/YuGiOhCatalog.swift`
- `TradingCardScanner/Games/YuGiOh/YuGiOhCatalogAdapter.swift`
- `TradingCardScanner/Games/YuGiOh/YuGiOhCatalogCoordinator.swift`
- `TradingCardScanner/Games/YuGiOh/YuGiOhGameRuntime.swift`
- `TradingCardScanner/Games/YuGiOh/YuGiOhImportAdapter.swift`
- `TradingCardScanner/Games/YuGiOh/YuGiOhPriceAdapter.swift`
- `TradingCardScanner/Games/YuGiOh/YuGiOhRecognitionAdapter.swift`
- `TradingCardScanner/Games/YuGiOh/YuGiOhReleaseWire.swift`

### 10 Browse, detail and shared catalog (25)

- `TradingCardScanner/Games/Core/BoundedCache.swift`
- `TradingCardScanner/Games/Core/CardGameRuntime.swift`
- `TradingCardScanner/Games/Core/GameBrowseAdapter.swift`
- `TradingCardScanner/Games/Core/GameCatalogAdapter.swift`
- `TradingCardScanner/Games/Core/GameRecognitionAdapter.swift`
- `TradingCardScanner/Games/Core/GameVariantPolicy.swift`
- `TradingCardScanner/Games/Core/LegacyResolvedCard.swift`
- `TradingCardScanner/Games/Core/LoadOnce.swift`
- `TradingCardScanner/Models/BrowseCatalogModels.swift`
- `TradingCardScanner/Models/CardGame.swift`
- `TradingCardScanner/Models/CardGameRegistry.swift`
- `TradingCardScanner/Models/CatalogBrowseFilters.swift`
- `TradingCardScanner/Services/ArtworkFallbacks.swift`
- `TradingCardScanner/Services/BrowseCatalog.swift`
- `TradingCardScanner/Services/CardCatalog.swift`
- `TradingCardScanner/Services/CardShareContent.swift`
- `TradingCardScanner/Services/CatalogSetCompletion.swift`
- `TradingCardScanner/Services/CatalogSetPresentation.swift`
- `TradingCardScanner/Services/SignedCatalogReleaseStore.swift`
- `TradingCardScanner/Services/SignedCatalogUpdateClient.swift`
- `TradingCardScanner/Views/BrowseView.swift`
- `TradingCardScanner/Views/CardShareViews.swift`
- `TradingCardScanner/Views/CatalogBrowseFilterSheet.swift`
- `TradingCardScanner/Views/CatalogCardDetailView.swift`
- `TradingCardScanner/Views/CatalogSetTile.swift`

### 11 Collection and activity (19)

- `TradingCardScanner/Games/Core/CollectionAuthorizedActivationSource.swift`
- `TradingCardScanner/Models/CardVariant.swift`
- `TradingCardScanner/Models/CollectedCard.swift`
- `TradingCardScanner/Models/CollectionActivity.swift`
- `TradingCardScanner/Models/CollectionItemKind.swift`
- `TradingCardScanner/Services/CollectionCatalogNormalizer.swift`
- `TradingCardScanner/Services/CollectionProjectionActor.swift`
- `TradingCardScanner/Services/CollectionQuery.swift`
- `TradingCardScanner/Services/CollectionStore.swift`
- `TradingCardScanner/Services/CollectionWriteSerializer.swift`
- `TradingCardScanner/Services/DeterministicUUID.swift`
- `TradingCardScanner/Services/LogicalCollection.swift`
- `TradingCardScanner/Services/StoreRevisionMonitor.swift`
- `TradingCardScanner/Views/CollectionActivityLogView.swift`
- `TradingCardScanner/Views/CollectionCardDetailView.swift`
- `TradingCardScanner/Views/CollectionFilters.swift`
- `TradingCardScanner/Views/CollectionFinishDot.swift`
- `TradingCardScanner/Views/CollectionView.swift`
- `TradingCardScanner/Views/RemovalUndoBanner.swift`

### 12 Pricing and products (36)

- `TradingCardScanner/Games/Core/GamePriceAdapter.swift`
- `TradingCardScanner/Models/JustTCGMarketModels.swift`
- `TradingCardScanner/Models/Money.swift`
- `TradingCardScanner/Models/PriceObservation.swift`
- `TradingCardScanner/Models/PriceRecord.swift`
- `TradingCardScanner/Models/ProductIdentity.swift`
- `TradingCardScanner/Models/ReferenceQuote.swift`
- `TradingCardScanner/Services/BackgroundPriceRefresh.swift`
- `TradingCardScanner/Services/BrowsePriceObservationDayResolver.swift`
- `TradingCardScanner/Services/CardMarketHistoryService.swift`
- `TradingCardScanner/Services/JustTCGRefreshCoordinator.swift`
- `TradingCardScanner/Services/JustTCGSyncLedger.swift`
- `TradingCardScanner/Services/JustTCGTransport.swift`
- `TradingCardScanner/Services/JustTCGV1Client.swift`
- `TradingCardScanner/Services/JustTCGV2GradedClient.swift`
- `TradingCardScanner/Services/OwnedCatalogPrice.swift`
- `TradingCardScanner/Services/PriceCheckCoordinator.swift`
- `TradingCardScanner/Services/PriceCoverageGapLog.swift`
- `TradingCardScanner/Services/PriceFallbackQuoteResolver.swift`
- `TradingCardScanner/Services/PriceObservationLog.swift`
- `TradingCardScanner/Services/PriceProvider.swift`
- `TradingCardScanner/Services/PriceQuoteService.swift`
- `TradingCardScanner/Services/PriceRefreshController.swift`
- `TradingCardScanner/Services/PriceRefreshTargets.swift`
- `TradingCardScanner/Services/PriceSnapshotStore.swift`
- `TradingCardScanner/Services/PriceStore.swift`
- `TradingCardScanner/Services/PriceVendorCredentials.swift`
- `TradingCardScanner/Services/ProductCatalogIdentity.swift`
- `TradingCardScanner/Services/ProductIdentityStore.swift`
- `TradingCardScanner/Services/ProductPriceService.swift`
- `TradingCardScanner/Services/QuoteCache.swift`
- `TradingCardScanner/Services/TCGCSVProductPriceSource.swift`
- `TradingCardScanner/Services/TCGplayerLink.swift`
- `TradingCardScanner/Views/GradedVariantPickerView.swift`
- `TradingCardScanner/Views/PriceCheckResultView.swift`
- `TradingCardScanner/Views/SealedBrowseViews.swift`

### 13 Portfolio and durable accounting (16)

- `TradingCardScanner/Models/InventoryEvent.swift`
- `TradingCardScanner/Models/PortfolioDailyClose.swift`
- `TradingCardScanner/Models/PortfolioHistoryTypes.swift`
- `TradingCardScanner/Models/PriceCheckDay.swift`
- `TradingCardScanner/Services/InventoryLedger.swift`
- `TradingCardScanner/Services/PortfolioCalendar.swift`
- `TradingCardScanner/Services/PortfolioClose.swift`
- `TradingCardScanner/Services/PortfolioEngine.swift`
- `TradingCardScanner/Services/PortfolioEpoch.swift`
- `TradingCardScanner/Services/PortfolioHistoryEngine.swift`
- `TradingCardScanner/Services/PortfolioLaunchSnapshot.swift`
- `TradingCardScanner/Services/PortfolioReplay.swift`
- `TradingCardScanner/Services/PortfolioReplaySnapshot.swift`
- `TradingCardScanner/Views/PortfolioDebugFixtures.swift`
- `TradingCardScanner/Views/PortfolioHistoryView.swift`
- `TradingCardScanner/Views/PortfolioView.swift`

### 14 Import, export and trade (3)

- `TradingCardScanner/Games/Core/GameImportAdapter.swift`
- `TradingCardScanner/Services/CollectionCSV.swift`
- `TradingCardScanner/Views/TradeAnalyzer.swift`

### 15 Centering and listing photos (18)

- `TradingCardScanner/Models/CardCenteringBoundaryEvidence.swift`
- `TradingCardScanner/Models/CardCenteringMeasurement.swift`
- `TradingCardScanner/Models/CardCenteringSpatialMeasurement.swift`
- `TradingCardScanner/Services/CardCenteringAnalyzer.swift`
- `TradingCardScanner/Services/CardCenteringExport.swift`
- `TradingCardScanner/Services/CardCenteringPixelKernels.c`
- `TradingCardScanner/Services/CardCenteringPixelKernels.h`
- `TradingCardScanner/Services/CardCenteringPrintReference.swift`
- `TradingCardScanner/Services/CardCenteringReviewRenderer.swift`
- `TradingCardScanner/Services/EbayListingPhotoExport.swift`
- `TradingCardScanner/Services/EbayQuadrantCropper.swift`
- `TradingCardScanner/Services/ListingPhotoLibrarySaver.swift`
- `TradingCardScanner/Views/CardCenteringCanvas.swift`
- `TradingCardScanner/Views/CardCenteringReviewSheet.swift`
- `TradingCardScanner/Views/CardCenteringView.swift`
- `TradingCardScanner/Views/CenteringCameraView.swift`
- `TradingCardScanner/Views/EbayListingPhotosView.swift`
- `TradingCardScanner/Views/ListingPhotoInspectorView.swift`

### 16 Purchases and paid access (3)

- `CollectorTools.storekit`
- `TradingCardScanner/Services/CollectorToolsStore.swift`
- `TradingCardScanner/Views/CollectorToolsOfferView.swift`

### 17 Publisher, tooling and evidence (205)

- `.firebaserc`
- `.firebaserc.example`
- `docs/research/lorcana-real-card-corpus/minimum-acceptance/source-package/gate_audit.py`
- `docs/research/lorcana-real-card-corpus/minimum-acceptance/source-package/test_gate_audit.py`
- `docs/research/lorcana-real-card-corpus/source-package/build.py`
- `docs/research/lorcana-real-card-corpus/source-package/make_acceptance.py`
- `docs/research/lorcana-real-card-corpus/source-package/validate_corpus.py`
- `firebase.json`
- `review/centering-harness/baseline_main.swift`
- `review/centering-harness/bottom_edge_continuity.py`
- `review/centering-harness/boundary_gap_probe.py`
- `review/centering-harness/build_print_reference.py`
- `review/centering-harness/chroma_border_transition_probe.py`
- `review/centering-harness/color_region_probe.py`
- `review/centering-harness/corpus_main.swift`
- `review/centering-harness/corpus_review.py`
- `review/centering-harness/design_reference_batch.py`
- `review/centering-harness/edge_annotation_audit.py`
- `review/centering-harness/gt_tool.py`
- `review/centering-harness/local_reference_patches.py`
- `review/centering-harness/local_transition_controls.py`
- `review/centering-harness/local_transition_probe.py`
- `review/centering-harness/measure_path_alternatives.py`
- `review/centering-harness/measure_reference_candidate.py`
- `review/centering-harness/meta_main.swift`
- `review/centering-harness/multi_hypothesis_boundary_probe.py`
- `review/centering-harness/multi_hypothesis_controls.py`
- `review/centering-harness/multi_hypothesis_validation.py`
- `review/centering-harness/native_patch_probe.py`
- `review/centering-harness/native_research_report.py`
- `review/centering-harness/native_review_packet.py`
- `review/centering-harness/outer_seeded_inner.py`
- `review/centering-harness/paired_path_measurement.py`
- `review/centering-harness/perimeter_identity_research.py`
- `review/centering-harness/physical_background_counterexample.py`
- `review/centering-harness/physical_border_identity_counterexample.py`
- `review/centering-harness/physical_border_identity_probe.py`
- `review/centering-harness/reconcile_edge_estimators.py`
- `review/centering-harness/reference_candidate_gate.py`
- `review/centering-harness/reference_fragment_controls.py`
- `review/centering-harness/reference_fragment_corroboration.py`
- `review/centering-harness/reference_frame_proposal.py`
- `review/centering-harness/reference_profile_probe.py`
- `review/centering-harness/reference_warp_control.py`
- `review/centering-harness/register_print_reference.py`
- `review/centering-harness/run_corpus.sh`
- `review/centering-harness/run_meta.sh`
- `review/centering-harness/run_selective_candidate.py`
- `review/centering-harness/run_sensitivity.sh`
- `review/centering-harness/score_path_transfer.py`
- `review/centering-harness/score_photo_bands.py`
- `review/centering-harness/selective_path_measurement.py`
- `review/centering-harness/selective_stability.py`
- `review/centering-harness/sensitivity_main.swift`
- `review/centering-harness/shadow_transition_probe.py`
- `review/centering-harness/test_edge_annotation_audit.py`
- `review/centering-harness/track_bottom_boundary.py`
- `review/centering-harness/track_card_paths.py`
- `review/centering-harness/uniform_border_probe.py`
- `scripts/audit_catalog_coverage.py`
- `scripts/audit_catalog_variant_coverage.py`
- `scripts/audit_cloudkit_schema.sh`
- `scripts/audit_game_boundaries.sh`
- `scripts/audit_magic_set_products.py`
- `scripts/audit_one_piece_coverage.py`
- `scripts/audit_one_piece_live_artwork.py`
- `scripts/audit_pokemon_finish_repairs.py`
- `scripts/audit_pokemon_jumbo_family.py`
- `scripts/audit_pokemon_jumbo_products.py`
- `scripts/audit_pokemon_promo_residuals.py`
- `scripts/audit_pokemon_retail_variants.py`
- `scripts/audit_pokemon_signed_membership.swift`
- `scripts/audit_pokemon_signed_scope.py`
- `scripts/audit_pokemon_tcgcsv.py`
- `scripts/audit_set_pricing.py`
- `scripts/bind_one_piece_promo_entries.py`
- `scripts/build_lorcana_browse_prices.py`
- `scripts/build_lorcana_discovery_catalog.py`
- `scripts/build_lorcana_market_catalog.py`
- `scripts/build_magic_historical_index.py`
- `scripts/build_magic_historical_title_vocabulary.py`
- `scripts/build_magic_printing_families.py`
- `scripts/build_one_piece_catalog.py`
- `scripts/build_one_piece_printing_rarities.py`
- `scripts/build_yugioh_catalog.py`
- `scripts/build_yugioh_publisher.sh`
- `scripts/capture_lorcana_sources.py`
- `scripts/capture_lorcana_tcgcsv.py`
- `scripts/capture_one_piece_products.py`
- `scripts/capture_pokemon_tcgcsv.py`
- `scripts/capture_yugioh_price_receipt.py`
- `scripts/catalog_exceptions.py`
- `scripts/catalog_health_export.py`
- `scripts/catalog_release_preflight.py`
- `scripts/centering_done_diagnostics.py`
- `scripts/centering_ui_build_and_shoot.sh`
- `scripts/certify_one_piece_coverage.py`
- `scripts/certify_pokemon_finish_coverage.py`
- `scripts/compare_centering_profiles.py`
- `scripts/derive_pokemon_legacy_finishes.py`
- `scripts/derive_pokemon_unnumbered_energy.py`
- `scripts/discover_one_piece_products.py`
- `scripts/fixtures/yugioh/test_builder.py`
- `scripts/fixtures/yugioh/test_printing_family.py`
- `scripts/generate_magic_treatment_catalog.sh`
- `scripts/generate_magic_treatment_snapshot.sh`
- `scripts/generate_pokemon_snapshot.sh`
- `scripts/install_releaselocal_on_iphone.sh`
- `scripts/inventory_magic_historical_scope.py`
- `scripts/iphone_releaselocal_install.py`
- `scripts/magic_treatment_snapshot_generator.swift`
- `scripts/market_price_feeds.py`
- `scripts/normalize_one_piece_sources.py`
- `scripts/one_piece_eb05_retail.py`
- `scripts/one_piece_pinned_keys.py`
- `scripts/one_piece_tcgcsv_capture.py`
- `scripts/prepare_one_piece_acceptance_samples.py`
- `scripts/prepare_one_piece_eb05_market.py`
- `scripts/prepare_one_piece_hosting.py`
- `scripts/prepare_one_piece_local_review.py`
- `scripts/prepare_one_piece_owner_update.py`
- `scripts/prepare_one_piece_prb01_market.py`
- `scripts/prepare_one_piece_prb02_market.py`
- `scripts/prepare_pokemon_membership_batch.py`
- `scripts/prepare_pokemon_pop_membership.py`
- `scripts/prepare_pokemon_sve_energy.py`
- `scripts/publish_one_piece_local.py`
- `scripts/reconcile_lorcana_promo_distributions.py`
- `scripts/reconcile_magic_historical_pilot.py`
- `scripts/reconcile_one_piece_event_stamps.py`
- `scripts/reconcile_one_piece_fixed_foil_products.py`
- `scripts/reconcile_one_piece_launch_products.py`
- `scripts/reconcile_one_piece_promo_tiers.py`
- `scripts/reconcile_one_piece_retail_printings.py`
- `scripts/reconcile_one_piece_tcgcsv_sources.py`
- `scripts/reconcile_yugioh_release_names.py`
- `scripts/render_launch_mark.py`
- `scripts/resolve_one_piece_errata_holds.py`
- `scripts/resolve_one_piece_reprint_appearances.py`
- `scripts/restore_catalog_hosting_site.sh`
- `scripts/restore_pokemon_catalog_releases.sh`
- `scripts/review_one_piece_base_market_mappings.py`
- `scripts/run_app_tests.sh`
- `scripts/stage_magic_historical_corpus.py`
- `scripts/tests/test_catalog_coverage_audit.py`
- `scripts/tests/test_catalog_exceptions.py`
- `scripts/tests/test_catalog_health_export.py`
- `scripts/tests/test_catalog_hosting_restore.py`
- `scripts/tests/test_catalog_release_preflight.py`
- `scripts/tests/test_centering_done_diagnostics.py`
- `scripts/tests/test_certify_one_piece_coverage.py`
- `scripts/tests/test_certify_pokemon_finish_coverage.py`
- `scripts/tests/test_ci_test_selections.py`
- `scripts/tests/test_derive_pokemon_legacy_finishes.py`
- `scripts/tests/test_derive_pokemon_unnumbered_energy.py`
- `scripts/tests/test_iphone_releaselocal_install.py`
- `scripts/tests/test_lorcana_discovery_catalog.py`
- `scripts/tests/test_lorcana_market_catalog.py`
- `scripts/tests/test_lorcana_promo_distributions.py`
- `scripts/tests/test_magic_catalog_workflow.py`
- `scripts/tests/test_magic_historical_corpus.py`
- `scripts/tests/test_magic_historical_index.py`
- `scripts/tests/test_magic_historical_reconciliation.py`
- `scripts/tests/test_magic_historical_title_vocabulary.py`
- `scripts/tests/test_magic_printing_families.py`
- `scripts/tests/test_magic_publication_environment.py`
- `scripts/tests/test_market_price_feeds.py`
- `scripts/tests/test_normalize_one_piece_sources.py`
- `scripts/tests/test_one_piece_acceptance_samples.py`
- `scripts/tests/test_one_piece_base_market_mappings.py`
- `scripts/tests/test_one_piece_coverage.py`
- `scripts/tests/test_one_piece_eb05_market.py`
- `scripts/tests/test_one_piece_errata_holds.py`
- `scripts/tests/test_one_piece_event_stamps.py`
- `scripts/tests/test_one_piece_fixed_foil_products.py`
- `scripts/tests/test_one_piece_hosting.py`
- `scripts/tests/test_one_piece_live_artwork.py`
- `scripts/tests/test_one_piece_pinned_keys.py`
- `scripts/tests/test_one_piece_prb01_market.py`
- `scripts/tests/test_one_piece_prb02_market.py`
- `scripts/tests/test_one_piece_printing_rarities.py`
- `scripts/tests/test_one_piece_product_discovery.py`
- `scripts/tests/test_one_piece_product_pipeline.py`
- `scripts/tests/test_one_piece_promo_tiers.py`
- `scripts/tests/test_one_piece_retail_printings.py`
- `scripts/tests/test_one_piece_tcgcsv_catalog.py`
- `scripts/tests/test_one_piece_workflow.py`
- `scripts/tests/test_pokemon_tcgcsv_audit.py`
- `scripts/tests/test_publish_one_piece_local.py`
- `scripts/tests/test_reconcile_yugioh_release_names.py`
- `scripts/tests/test_set_pricing_audit.py`
- `scripts/tests/test_yugioh_official_rarity_placeholders.py`
- `scripts/tests/test_yugioh_publisher.py`
- `scripts/ui_build_and_shoot.sh`
- `scripts/ui_screenshot_simctl.sh`
- `scripts/update_mee_snapshot.py`
- `scripts/verify_ci_test_selections.py`
- `scripts/verify_magic_publication_environment.sh`
- `scripts/verify_pokemon_catalog_hosting_config.sh`
- `scripts/verify_pokemon_subset_products.py`
- `scripts/verify_pokemon_yellow_a_products.py`
- `scripts/yugioh_catalog_publisher.swift`
- `scripts/yugioh_edition_galleries.py`
- `scripts/yugioh_legacy_inventory.py`
- `scripts/yugioh_official_inventory.py`

### 18 Build, CI and test infrastructure (130)

- `.github/workflows/catalog-coverage-tests.yml`
- `.github/workflows/catalog-health-audit.yml`
- `.github/workflows/ios-release-gate.yml`
- `.github/workflows/ios-static-analysis.yml`
- `.github/workflows/magic-catalog.yml`
- `.github/workflows/market-price-feed-tests.yml`
- `.github/workflows/one-piece-catalog.yml`
- `.github/workflows/one-piece-eb05-artwork-audit.yml`
- `.github/workflows/pokemon-catalog.yml`
- `.github/workflows/yugioh-catalog.yml`
- `.gitignore`
- `.xcodebuildmcp/config.yaml`
- `Config/MagicCatalogProduction.xcconfig`
- `Config/OnePieceCatalogProduction.xcconfig`
- `Config/PokemonCatalogDebugLocal.xcconfig`
- `Config/PokemonCatalogProduction.xcconfig`
- `Config/PokemonCatalogStaging.xcconfig`
- `TradingCardScanner.xcodeproj/project.pbxproj`
- `TradingCardScanner.xcodeproj/project.xcworkspace/contents.xcworkspacedata`
- `TradingCardScanner.xcodeproj/xcshareddata/xcschemes/TradingCardScanner-DebugProduction.xcscheme`
- `TradingCardScanner.xcodeproj/xcshareddata/xcschemes/TradingCardScanner-DebugRemoteLocal.xcscheme`
- `TradingCardScanner.xcodeproj/xcshareddata/xcschemes/TradingCardScanner-ProfileLocal.xcscheme`
- `TradingCardScanner.xcodeproj/xcshareddata/xcschemes/TradingCardScanner.xcscheme`
- `TradingCardScannerTests/AppOpeningTests.swift`
- `TradingCardScannerTests/ArtworkOrphanSweepTests.swift`
- `TradingCardScannerTests/BoundedCacheTests.swift`
- `TradingCardScannerTests/BrowseFeatureTests.swift`
- `TradingCardScannerTests/BrowseFilterTests.swift`
- `TradingCardScannerTests/BrowsePresentationTests.swift`
- `TradingCardScannerTests/BrowsePriceHistoryTests.swift`
- `TradingCardScannerTests/CSVImportResumeTests.swift`
- `TradingCardScannerTests/CameraRotationTests.swift`
- `TradingCardScannerTests/CardFinishMotionSourceTests.swift`
- `TradingCardScannerTests/CardFinishRenderPlanTests.swift`
- `TradingCardScannerTests/CardGameForwardCompatibilityTests.swift`
- `TradingCardScannerTests/CardLatchTests.swift`
- `TradingCardScannerTests/CardShareContentTests.swift`
- `TradingCardScannerTests/CatalogNormalizationTests.swift`
- `TradingCardScannerTests/CenteringExportTests.swift`
- `TradingCardScannerTests/CenteringNativeResearchTests.swift`
- `TradingCardScannerTests/CenteringReviewTests.swift`
- `TradingCardScannerTests/CenteringSpatialMeasurementTests.swift`
- `TradingCardScannerTests/CloudAccountProbeTests.swift`
- `TradingCardScannerTests/CloudCollectionAnchorStoreTests.swift`
- `TradingCardScannerTests/CloudKitSchemaCompatibilityTests.swift`
- `TradingCardScannerTests/CloudRestorationReadinessTests.swift`
- `TradingCardScannerTests/CollectionActivityHistoryTests.swift`
- `TradingCardScannerTests/CollectionItemKindTests.swift`
- `TradingCardScannerTests/CollectionKeyTests.swift`
- `TradingCardScannerTests/CollectionQueryTests.swift`
- `TradingCardScannerTests/CollectionStorageBootstrapTests.swift`
- `TradingCardScannerTests/CollectionStoragePolicyTests.swift`
- `TradingCardScannerTests/CollectionStoreContinuityTests.swift`
- `TradingCardScannerTests/CollectionStoreDigestTests.swift`
- `TradingCardScannerTests/CollectionStoreModeTransitionTests.swift`
- `TradingCardScannerTests/CollectionSyncDiagnosticsTests.swift`
- `TradingCardScannerTests/CollectorToolsTests.swift`
- `TradingCardScannerTests/DetailDeletionRenderTests.swift`
- `TradingCardScannerTests/EbayQuadrantCropperTests.swift`
- `TradingCardScannerTests/GradedLabelParserTests.swift`
- `TradingCardScannerTests/HistoricalAttemptBoundTests.swift`
- `TradingCardScannerTests/HistoricalCatalogRequestTests.swift`
- `TradingCardScannerTests/HistoricalTitleCaptureTests.swift`
- `TradingCardScannerTests/ImportedItemKindTests.swift`
- `TradingCardScannerTests/Info.plist`
- `TradingCardScannerTests/JustTCGContractTests.swift`
- `TradingCardScannerTests/LaunchModelActorTests.swift`
- `TradingCardScannerTests/LorcanaCatalogActivationTests.swift`
- `TradingCardScannerTests/LorcanaDiscoveryCatalogTests.swift`
- `TradingCardScannerTests/LorcanaIntegrationTests.swift`
- `TradingCardScannerTests/LorcanaOwnershipTests.swift`
- `TradingCardScannerTests/LorcanaPhysicalCatalogTests.swift`
- `TradingCardScannerTests/LorcanaPricingTests.swift`
- `TradingCardScannerTests/LorcastSourceNormalizerTests.swift`
- `TradingCardScannerTests/MagicCatalogActivationTests.swift`
- `TradingCardScannerTests/MagicCatalogBootstrapTests.swift`
- `TradingCardScannerTests/MagicContentKindTests.swift`
- `TradingCardScannerTests/MagicHistoricalIndexTests.swift`
- `TradingCardScannerTests/MagicPhysicalObjectTests.swift`
- `TradingCardScannerTests/MagicRecognitionProfileTests.swift`
- `TradingCardScannerTests/MagicTokenPairingSessionTests.swift`
- `TradingCardScannerTests/MagicTreatmentSnapshot.swift`
- `TradingCardScannerTests/MagicTreatmentSnapshotTests.swift`
- `TradingCardScannerTests/MagicTreatmentTests.swift`
- `TradingCardScannerTests/OnePieceAvailabilityTests.swift`
- `TradingCardScannerTests/OnePieceIntegrationTests.swift`
- `TradingCardScannerTests/OpusImplementationPlanTests.swift`
- `TradingCardScannerTests/OwnershipConcurrencyStressTests.swift`
- `TradingCardScannerTests/OwnershipLedgerCompletenessTests.swift`
- `TradingCardScannerTests/PokemonCatalogSliceBTests.swift`
- `TradingCardScannerTests/PokemonCatalogSliceCTests.swift`
- `TradingCardScannerTests/PokemonCatalogSliceDTests.swift`
- `TradingCardScannerTests/PokemonCatalogSliceFTests.swift`
- `TradingCardScannerTests/PokemonCatalogTests.swift`
- `TradingCardScannerTests/PokemonClassicCollectionArtworkTests.swift`
- `TradingCardScannerTests/PokemonTCGCSVPriceTests.swift`
- `TradingCardScannerTests/PortfolioCloseReference.swift`
- `TradingCardScannerTests/PortfolioCloseTests.swift`
- `TradingCardScannerTests/PortfolioHistoryEngineTests.swift`
- `TradingCardScannerTests/PortfolioLedgerTests.swift`
- `TradingCardScannerTests/PortfolioNameCleaningTests.swift`
- `TradingCardScannerTests/PortfolioReconciliationTests.swift`
- `TradingCardScannerTests/PortfolioReplayEngineTests.swift`
- `TradingCardScannerTests/PortfolioTrustPassTests.swift`
- `TradingCardScannerTests/PriceRefreshLifecycleTests.swift`
- `TradingCardScannerTests/PricingTests.swift`
- `TradingCardScannerTests/PrivacyAndSupportSurfaceTests.swift`
- `TradingCardScannerTests/ProductCatalogIdentityTests.swift`
- `TradingCardScannerTests/ProductFallbackTests.swift`
- `TradingCardScannerTests/ProductIdentityTests.swift`
- `TradingCardScannerTests/ProductionRowFixtures.swift`
- `TradingCardScannerTests/QuoteCacheTests.swift`
- `TradingCardScannerTests/RefreshStructuralWriteTests.swift`
- `TradingCardScannerTests/ScanParserTests.swift`
- `TradingCardScannerTests/ScanSessionMetricsLogTests.swift`
- `TradingCardScannerTests/ScanSubjectSuppressionTests.swift`
- `TradingCardScannerTests/ScannedGradedResolverTests.swift`
- `TradingCardScannerTests/ScannerViewModelTests.swift`
- `TradingCardScannerTests/SignedCatalogReleaseStoreTests.swift`
- `TradingCardScannerTests/SlabEvidenceConfirmationWindowTests.swift`
- `TradingCardScannerTests/SlabFramingRegionTests.swift`
- `TradingCardScannerTests/StoreRevisionMonitorTests.swift`
- `TradingCardScannerTests/SwiftDataConcurrencyCharacterizationTests.swift`
- `TradingCardScannerTests/TCGplayerLinkTests.swift`
- `TradingCardScannerTests/UncoveredSurfaceTests.swift`
- `TradingCardScannerTests/UnresolvedScanStoreTests.swift`
- `TradingCardScannerTests/UnverifiedReportTests.swift`
- `TradingCardScannerTests/VariantResolverTests.swift`
- `TradingCardScannerTests/WholeCardHistoricalCaptureTests.swift`
- `TradingCardScannerTests/YuGiOhIntegrationTests.swift`
