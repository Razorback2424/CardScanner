# ScanStash independent launch review

**Date:** 2026-11-10. **Decision:** not ready for launch.
**Candidate:** main at 2527c9b4163a4b9694e509ca245b9ca96d8ba38c plus the existing dirty working tree. All 2,353 tracked-file fingerprints still matched the start of this review before its documentation was written. No app, test, catalog, script or project source was changed.

The [launch contract](../release/launch-contract.md) remains the product authority. This is a dated assessment of the current candidate, with an [ordered implementation handoff](../plans/launch-review-handoff-2026-11-10.md). It supersedes the interrupted progress messages as evidence for the checks actually repeated here; it does not certify an archive or physical device.

The [items 2 and 4 reproduction supplement](launch-review-items-2-and-4-reproduction-2026-11-10.md) expands LR02/LR04/LR06 with exact commands and controls. It corrects the withdrawn comparison between two different Tropius printings.

## Assessment

The collection and accounting foundations are substantially stronger than an unfinished-app impression suggests. Executed ownership, CSV, pricing, scanner, marketplace-link, purchase and recovery tests passed. Persisted Browse add/Undo, quantity editing, removal/Undo and activity history also worked in the phone simulator. The recent grade/finish and portfolio/detail changes should be preserved.

The remaining work includes substantial launch prerequisites: operator-funded pricing access is absent, One Piece production acquisition is disabled, signed Pokémon delivery is unavailable, public legal/support links are empty, and the production centering proposals still fail their existing accuracy criterion. There is also an unresolved special-printing authority decision and two demonstrated accessibility layout defects. These should not be turned into a broad rewrite of the normal scanner.

The HIG pass found usable native navigation, explicit ownership actions, progress/error handling and recoverable operations in the inspected scope, but **does not pass the whole app** because of LR07/LR08 and remaining spoken/accessibility acceptance. The subsequent App Store pass is **NO-GO**, particularly for completeness, configured services, purchase acceptance and privacy-link readiness. Apple's [review guidelines](https://developer.apple.com/app-store/review/guidelines/) require a complete, testable app and accessible privacy-policy information.

## Evidence and its limits

Artifacts, build data, source fingerprints and logs are outside the repository at:

    /Volumes/T7/CodexBuilds/LaunchReview-20261110-Codex/

| Fresh verification | Outcome | Meaning |
| --- | --- | --- |
| Debug simulator build and signed build-for-testing | Passed | Current source compiles; the test host supports Keychain tests. |
| Broad Debug arm64 run, iPhone 17 Pro / iOS 27.0 | 3,225 methods: 3,202 passed, 2 failed, 21 skipped | Broad filtered evidence, not a complete-target pass. Results: BroadReview.xcresult, broad-summary.json, broad-test-tree.json and broad-method-statuses.json. |
| Four individually selected centering research gates | 0 passed, 4 failed, no skips | ResearchGateChecks.xcresult and research-summary.json. Together with the broad run, six distinct failed methods remain. |
| Pokémon / Magic / One Piece catalog packages | 88 / 18 / 46 passed; one Pokémon live check skipped | 152 passed, one skipped. Separate package logs and external scratch directories retained. |
| Offline price-feed and shared-hosting scripts | 16 feed tests and 7 namespace-restoration tests passed; hosting configuration check passed | Fresh local fixtures/mocked transports only; no production publication was performed. Logs: market-price-feeds-tests.log and catalog-hosting-restore-tests.log. |
| Release simulator compilation | Passed | Built compiler conditions contain NO_CLOUDKIT and no DEBUG, LOCAL_ONLY_SIGNING or LOCAL_COLLECTOR_TOOLS. No owner resource paths were found. This is not signing/archive/TestFlight acceptance. |
| Release built Info.plist | Inspected | Minimum OS 18.0; version 1.0/build 1; One Piece disabled and writes NO; privacy/support URLs empty. |

The broad run excluded CenteringPrintPilotTests and CenteringNativeResearchTests wholesale because of their long research workload, and CenteringProfileDumpTests because it is diagnostic output tooling. Four known failing pilot methods were then explicitly selected. No test expectation, tolerance, skip condition or product source was weakened or changed.

The 21 skips cover physical first-unlock protection; five entitled storage-transition checks; opt-in precision/aged-store performance; interrupted StoreKit purchase acceptance; gated live Lorcana, One Piece, Pokémon and Yu-Gi-Oh! pricing; prepared Lorcana expansion checks; and photographic/live historical Magic corpora. Exact method IDs are in the result tree. A skip contributes no passing evidence. Nine result-bundle runtime warnings concern unmounted SwiftUI state/environment reads in UncoveredSurfaceTests; those construction checks are not rendered UI acceptance. Compilation also reports existing concurrency warnings; no resulting race was demonstrated.

### Hands-on evidence

The phone used the ordinary Debug candidate for collection and Files work. Centering used a separate build with the existing LOCAL_COLLECTOR_TOOLS testing flag so no purchase was needed. That build is explicitly not distribution or entitlement evidence. No injected print-reference library was supplied for the real-photo production-analyzer check.

| Journey | Observed result |
| --- | --- |
| Browse Magic → Forest, MDD 301 → Nonfoil add | Persisted owned quantity 1. A second add showed 2; immediate Undo returned it to 1. Browse reflected the final count. |
| Owned detail → quantity → removal → Undo | Increased 1 to 2; removal confirmation named both copies; the row disappeared; Undo restored quantity 2. |
| Collection History | Recorded two +1 Browse adds and a compensating −1 Undone entry. The subsequent quantity/removal paths were also exercised. |
| Existing unsupported Tropius finish → correction editor | Offered the exact current Normal/Reverse catalog choices and retained the existing Master Ball value. No correction to that existing entry was saved. This tests the editor's catalog boundary, not independent physical finish truth. |
| CSV export → native Files Save | Saved ScanStash Collection.csv. Independent readback: 2 rows, total quantity 3, 1,093 bytes. Metadata/hash retained in csv-export-file-check.json. |
| Native Files import selection → preflight → cancellation | Selected that saved file; preview said “Adds 3 cards in 2 entries. Matching entries will be combined.” Cancelled before applying to the existing holdings. Final collection still had the original two items/three copies. Durable write/replay/resume has fresh automated evidence, including 20 CSVImportResumeTests; a completed manual import into an empty disposable store remains a candidate check. |
| Real photo IMG_0780 → centering | Input SHA-256 verified against the retained HEIC. Ratios/export were unavailable until reference confirmation. Selecting Printed border enabled the explicitly labeled geometric estimate; the actual generated PNG retained the guides, ratios and uncertainty notes. Accuracy is not accepted by this interaction result. |
| Centering native precision → keyboard Done | Entered 258.81 while the underlying adjustment still read 258.709734; Done committed approximately 258.81 and enabled Undo/Reset. This complements 47 executed passing precision tests. |
| Listing photos → Generate → inspector | Generated ten ordered, decodable JPEGs and a ZIP with the expected ten members. All JPEGs were below the existing 12 MB limit. Inspector opened and files remained present while it was open. The later inspector-return tap expired in the automation, so that return was not accepted as manual evidence. Generated pixels were labeled synthetic. |
| iPad collection → card detail → rotation | Selected detail remained the same through portrait, both landscapes and inverted portrait. All four rendered layouts were inspected. Standard and maximum-text captures use synthetic collection fixtures; this is not provider-price evidence or complete iPad workflow acceptance. |
| Maximum Dynamic Type | Inspected Collection, Portfolio, Pro and iPad detail. LR07/LR08 were reproduced. Text-size settings were restored. |

The temporary Forest holding created by this review was removed after the Undo checks. The earlier Gargantos and Tropius quantities/finishes were preserved. Native Files controls became usable after opening the phone in its separate Device Hub window; the earlier inaccessible picker was an automation limitation, not an app defect. No external share, purchase, catalog publication, device reset, commit or push occurred.

Some first captures showed an opening screen or failed the expected-input-hash check; they are not layout acceptance. Settled recaptures and the corrected, verified photo hash are the accepted artifacts. Two search-input automation attempts did not produce visible typed text; LR07 relies on observed placeholder clipping and the fixed-height source, not a claimed typing or filtering failure.

## App and system map

Every row received source/documentation inspection and a relevant executed-test or explicit evidence disposition. Inspection was risk weighted, not a claim to have read every line or independently verified every catalog product.

| Area and customer journey | Systems traced | Verification and remaining boundary |
| --- | --- | --- |
| Startup, returning collection, tabs and recovery | App/TradingCardScannerApp, ContentView, AppOpeningView, bootstrap/session binding and deferred catalog preparation | Startup/readiness/session tests pass; phone relaunch and iPad opening/navigation inspected. No minimum-OS, real-device first-unlock or upgrade receipt. |
| Live raw/slab scanning and Price Check | CardScanner → recognition adapters/ScanParser → rolling confirmation/CardLatch → CardCatalog → print/finish choice → ScannerViewModel → writer or price-only result | All 142 executed ScannerViewModelTests pass, with latch/parser/registry coverage. Price Check remains separate from ownership. Real camera, glare, thermal and sustained-stack behavior were not reproduced here. |
| Five-game capability admission | CardGameRuntimeContainer, game descriptors/adapters, activation sources, import and price authorities | Integration/activation tests and three packages pass in executed scope. Pokémon/Magic have graded capabilities; Lorcana and Yu-Gi-Oh! support reviewed ordinary ownership, with capability-specific limits. Local One Piece availability is not production enablement. Freeze exact families/languages/capabilities in the manifest. |
| Special printings, editions, treatments and slabs | VariantEvidence/VariantResolver, Pokémon minima/overlays, Magic treatments and historical choices, Lorcana physical UUIDs, Yu-Gi-Oh! product/edition membership, GradedLabelParser/ScannedGradedResolver | Exact identity and contradictory-evidence tests pass; current finish correction inspected. Independent physical coverage and LR06 remain open. Do not infer completeness from a single published finish or a price lane. |
| Browse, search, sets, completion and sealed products | BrowseCatalog and game browse adapters → CatalogSetPresentation/completion → card/graded/sealed detail | Live Magic browse/add checked; pagination/search/cancellation/activation tests pass. iPad split selection/rotation inspected. LR07; complete live directory/price/artwork census and device price-sort timing remain open. |
| Ownership, quantities, removal, Undo, sales/trades and activity | CollectionStore → CollectionWriteSerializer → inventory events/activity → LogicalCollection/projection; background detail/activity writers | Executed integrity/concurrency/history tests pass; 97 activity tests pass. Add/edit/remove/Undo/history manually verified. Sale/trade and custom-artwork workflows have source/automated coverage, not a new full manual acceptance pass. |
| CSV and diagnostics transfer | ScannerSettingsView → security-scoped read → CollectionCSV plan → serialized per-row durable writes → ledger replay markers → export/projection | Native export/save/readback and import preflight/cancel checked. Currency, identity conflicts, partial failure, resume and replay tests pass. Large interrupted Files imports and cross-device transfer remain candidate checks. CSV is correctly described as inventory transfer, not full history/artwork backup. |
| Storage, schema, deletion and asynchronous work | Synced/local schema partition, manifest/file identity, CollectionStorageGeneration, BackgroundModelActor, exclusive writes | Executed storage/migration/continuity tests pass; fresh-context writes, rollback, stale-session guards and recoverable two-store boundaries inspected. No destructive deletion of existing review collections. Physical data-protection/failure-recovery acceptance remains. Live iCloud sync is deferred by the launch contract. |
| Current prices and freshness | PriceQuoteService/game adapters → TCGdex/Scryfall/shared daily feed/JustTCG → PriceStore/OwnedCatalogPrice → snapshots/UI | Executed exact-identity, currency, invalidation, source-date and failure-retention checks pass. Mapped Pokémon feed spot check works. LR01 and LR06; broad live coverage and paid-provider acceptance remain. |
| Feed publication and shared catalog hosting | market_price_feeds.py → scoped product/lane snapshots and capture receipts → gated workflow → full-site namespace restoration → hosted readback | Source/CI traced; 23 offline script tests and hosting configuration check pass. Mixed builds, old capture relabeling, corruption and unsafe/incomplete restoration are rejected in tested cases. Live schedule/environment settings, paid-source permissions and the next real publication remain operator acceptance; LR04 is not closed by fixture tests. |
| Portfolio value, flows, market movement and charts | InventoryLedger/PriceObservationLog → replay/closes/history engine → Portfolio and card contribution; separate CardMarketHistoryService series | Current related tests pass, including single-close/live-day and flat/unavailable-provider cases. iPad synthetic detail displayed its portfolio contribution separately from market history. No provider series is accepted as portfolio backfill. Aged-store/device timing is unverified. |
| TCGplayer destinations | TCGplayerLinkBuilder plus exact product/variant mapping and guarded marketplace backfill | All 24 link tests pass. Product-only HTTPS destinations and no name-search fallback inspected; links were exposed on live Magic and owned detail. This is not a manual validation of every marketplace product or a successful storefront checkout/redirect test. |
| Artwork and sharing | CatalogCachedImage/fallbacks, local overrides, CardShareContent/CardShareViews, share/export lifetime management | Executed image/share/fallback/cancellation tests pass; source safeguards and listing output inspected. Missing artwork recovery is preserved. Native external share delivery and large-photo memory remain acceptance work. |
| Card centering | Decode/orient/working/native transforms → analyzer/edge evidence → guide editing/precision → explicit reference confirmation → export | Real-photo route, typed Done and actual PNG checked. LR03; five DEBUG-only failed research methods are separate. Physical calibration, representative photos and device interaction remain open. |
| Listing-photo tools | Single/batch pairing → detached crop/encode/ZIP → inspector → Files/Photos/share; entitlement recheck on delivery | Ten-file single-card output inspected, including names, decodability, dimensions and archive structure. Local tests include a twenty-image batch archive. Real camera/48 MP memory, permissions, batch interruption and native delivery are not certified. |
| Collector Tools purchase and restoration | StoreKit client → verified currentEntitlements/updates → independent ownership/product-price state → gated actions/delivery | Fourteen executed purchase tests pass, including local StoreKit purchase/restore/refund and pending approval. One interruption test skips. No real sandbox/TestFlight or App Store Connect evidence; the unlocked UI build is not a purchase test. |
| Background refresh and performance | BGTask scheduling/headless preflight, refresh suspension, quotas/pacing/cancellation, projection/revision monitoring and signposts | Executed lifecycle/structural-write tests pass. Source keeps expensive ownership work in background writers and progress in leaf views. No new Release-device p95, sustained thermals, 5,000-row import or OS-scheduled overnight receipt. Existing [hang investigation](../plans/hang-inspection-plan.md) remains the measurement authority. |
| Security, privacy, legal and release packaging | Keychain, redirect guards, bounded signed transfers, revision/signature validation, PrivacyInfo, permissions, entitlements, xcconfigs and built plist | Source and executed guards inspected; Release compilation/readback checked. LR01/LR02/LR04/LR05; distribution signing, source/artwork rights, privacy declarations after backend integration and submission materials remain open. There is no app account-creation journey to invent or retrofit. |

## Prioritized findings

Priorities set implementation order. A product/integration gap is distinguished from a demonstrated runtime defect. “Reject Risk” identifies an App Store concern, not a prediction of Apple's decision.

### LR01 — Promised pricing still requires a customer key

**P1 / Major · Contract gap · App Store: Reject Risk for promised incomplete functionality · Confidence: High.**

[JustTCGTransport](../../TradingCardScanner/Services/JustTCGTransport.swift) requires PriceVendorCredentials before constructing authenticated requests; [Settings](../../TradingCardScanner/Views/ScannerSettingsView.swift) explicitly requests the customer's own key for history, graded listings and provider-backed sealed prices. The ordinary phone UI reproduced that message. There is no operator-managed access layer in this checkout.

This contradicts the adopted paid-JustTCG launch requirement. It does not mean every raw price is broken: existing Scryfall, TCGdex and reviewed daily-feed paths are distinct and should remain intact.

**Verify:** fresh distribution install with no customer key → supported raw history, graded and sealed journeys; currently they require setup. Implement bounded app-feature access with server-held credentials, quota/error/cancellation handling and honest coverage. Preserve local price provenance and portfolio accounting. The paid-tier [terms](https://justtcg.com/terms) and [commercial-use guidance](https://justtcg.com/docs/commercial-use) permit consumer display and server-side caching; the proposed interface/export policy must avoid becoming a raw data redistribution service. Provider selection is already made; active tier, budget and actual integration are still needed.

### LR02 — Production does not enable the contracted fifth game

**P1 / Major · Release configuration gap · App Store: Likely Question if five games are advertised · Confidence: High.**

[OnePieceCatalogProduction.xcconfig](../../Config/OnePieceCatalogProduction.xcconfig) and the built Release plist both specify disabled rollout and NO collection writes. [CardGameRuntime](../../TradingCardScanner/Games/Core/CardGameRuntime.swift) has separate local owner/review routes, explaining why One Piece appears in Debug without proving distribution readiness.

The 2026-11-10 follow-up moved the dedicated signing workflow to `macos-15`. A fresh Release simulator build reports `disabled`, an empty origin, empty pins and writes `NO`. Production signing, signed seed packaging, hosted readback and activation are gated by the [owner setup](../release/one-piece-production-setup-2026-10-23.md).

**Verify:** install the actual Release candidate and exercise One Piece scan/Browse/explicit printing → save → reopen → price → Undo/CSV. Supply the approved signed production catalog and dedicated trust configuration, enable only the approved capability scope and verify stale/held selections still fail closed. Do not copy local owner bypasses into Release or silently remove One Piece from the promised launch.

### LR03 — Production centering proposals fail the frozen initial-guide criterion

**P1 / Major · Demonstrated acceptance failure · App Store: Advisory; paid-tool reliability concern · Confidence: High for the existing criterion.**

[CardCenteringGroundTruthTests](../../TradingCardScannerTests/OpusImplementationPlanTests.swift#L1935) calls the ordinary analyzer and compares native-mapped proposals with existing reviewed development annotations. The unchanged 2 percentage-point criterion fails on IMG_0347, IMG_0348, IMG_0351 and IMG_0780; worst top/bottom discrepancy is approximately 10.9664 pp. This is one failed method containing multiple assertions, not six independent production bugs. These annotations are not independently calibrated physical metrology.

The real IMG_0780 capture also makes the proposed boundary choice reviewable. Editing and export worked, and [canReportRatios](../../TradingCardScanner/Models/CardCenteringMeasurement.swift#L1082) correctly requires confirmation, an available reference and valid geometry. Those guards do not establish accurate initial proposals.

**Focused reproduction:** run the TradingCardScanner scheme's signed Debug tests on an available iOS simulator with `-only-testing:TradingCardScannerTests/CardCenteringGroundTruthTests/testInitialGuidesMatchExistingDevelopmentAnnotations`, retaining derived data and the result bundle on the external SSD. This is the ordinary-path failure; the supplied-layout failure is `CenteringBoundaryResolverExperimentTests/testSuppliedLayoutRecoversReviewedBoundaryRegions`. The four separately rerun research methods are `CenteringPrintPilotTests/testFoilGengarNativeFrameTransferResearch`, `testReferenceLibraryDevelopmentCorpusSelectsFoilGengar`, `testPrismaticPrintUsesColorIdentityAndNativePhotoEdges` and `testUnrelatedPhotosFallBackAndLatencyStaysWithinBudget`.

**Likely cause:** physical-cut/printed-reference proposal selection and boundary identity, rather than a demonstrated universal coordinate-conversion error. Reproduce the unchanged method and inspect native overlays against the intended boundary before changing algorithms. Preserve manual editing and uncertainty, and do not weaken annotations/tolerances or force the DEBUG print-reference experiment into production. Resolve the existing boundary-definition disagreement where necessary before judging a new detector.

Five other failed methods concern supplied-layout, foil Gengar, Prismatic right-edge and assisted-latency research. Their injected-reference path is DEBUG-only under the current [reachability disposition](centering-guided-repair.md#release-reachability-disposition--2026-11-10). Fresh focused results still fail, including 11.949 px against a 4 px right-edge limit and approximately 0.825 s against a 0.8 s upper-median budget. They are retained failures, not five additional shipping-path defects.

### LR04 — Signed Pokémon production delivery outage

**P1 / Major · Hosted revision 22 restored · Routine publication and app acceptance open.**

[Production configuration](../../Config/PokemonCatalogProduction.xcconfig) selects remote-authority at catalog.scan-stash.com. The configured /v1/current.json endpoint returned HTTP 404 during this review. [PokemonCatalogCoordinator](../../TradingCardScanner/Services/PokemonCatalogCoordinator.swift#L90) retains a persisted or bundled registry, so this was not a demonstrated launch crash or wholesale Browse outage. It does prevent a working production update round trip.

#### Revision 22 recovery follow-up — 2026-11-10

GitHub Actions completed the revision 22 Firebase release at **2026-11-05 14:47:10 UTC**. Firebase history shows 89 Pokémon files in that version. The next retained Hosting release at **2026-11-08 01:12:09 UTC**, made by the GitHub catalog deploy service account, omitted `v1/`. The Yu-Gi-Oh! price job had already logged the namespace as absent at 01:11:32 UTC. The retained history establishes the first recorded release without the namespace and leaves the cause of the earlier 404 unresolved. [Pokémon publication run](https://github.com/Razorback2424/CardScanner/actions/runs/42047496404), [Yu-Gi-Oh! price run](https://github.com/Razorback2424/CardScanner/actions/runs/42432145390).

Fresh GETs at **2026-11-10 22:28:03 UTC** returned 404 for `/v1/current.json` on both the configured domain and the Firebase origin. `/v1/releases/22/catalog-release.json` also returned 404 on the configured domain. The two `/market-prices/v1/tcgplayer/3/24722/` feed paths (`products` and `prices`) returned 200 with matching source metadata. Responses are retained on the SSD in `CodexBuilds/launch-findings-2026-11-10/endpoint-checks/`. The revision 22 candidate was downloaded to `CodexBuilds/launch-review-2026-11-10-pokemon-rev22/` on the same SSD and all four manifest hashes passed.

The catalog and price-feed workflows now use `macos-15` after the `macos-14` runner cancellations. The Pokémon workflow fails on a 404 at both pointer reads. Initial publication requires a manual dispatch with `bootstrap=true`. A post-merge dispatch with `publish=false` checks the hosted runner and fixture validation job. [Pokémon workflow](../../.github/workflows/pokemon-catalog.yml).

The follow-up review extended the Pokémon pointer requirement to Magic and price publication. Shared restoration requires the verified active immutable release and a valid copy of the published price namespace. The price workflow can supply a validated replacement feed. Only the manual Pokémon bootstrap passes the exception for an absent Pokémon pointer. [Shared restoration](../../scripts/restore_catalog_hosting_site.sh).

**Production recovery verified at 2026-11-11 00:02 UTC.** Restored all 89 catalog files from the November 5 release into a Hosting version that preserved all 1,338 live files and the live serving configuration. The preview and both live hosts returned byte-identical pointer and immutable envelopes that verified as revision 22 against the production pin. The price index and both sampled feeds returned 200 and matched their pre-release bytes. Receipts and readbacks are on the SSD in `CodexBuilds/launch-findings-2026-11-10/revision22-recovery/`.

The merged `macos-15` workflow passed fixture validation. After the additional shared-hosting guards merge, verify the next routine Pokémon publication with `bootstrap=false`. Accept no catalog change or a signed revision 23 continuing the same lineage. Verify offline startup on the saved generation and rejection of signature, schema and rollback failures. [Hosted runner validation](https://github.com/Razorback2424/CardScanner/actions/runs/42921403387).

### LR05 — Privacy and support links remain empty in the built app

**P1 / Major · Known submission prerequisite · App Store: Reject Risk for missing privacy access · Confidence: High.**

[Production xcconfig](../../Config/PokemonCatalogProduction.xcconfig) leaves CARD_SCANNER_PRIVACY_URL and CARD_SCANNER_SUPPORT_URL empty. Both are empty in the fresh Release Info.plist; [Privacy & Support](../../TradingCardScanner/Views/PrivacyAndSupportSettingsView.swift) therefore has no usable destinations.

This remains the owner's deliberately deferred publication task, not a newly introduced code bug. Publish the approved pages, configure the actual candidate, open both in the installed app and reconcile privacy text/manifest/store disclosures after operator-managed pricing is implemented. [Apple 5.1.1](https://developer.apple.com/app-store/review/guidelines/#privacy) requires the in-app and store privacy-policy links. No account-deletion feature is required merely because the app stores an on-device collection.

### LR06 — Pokémon singleton certainty requires certified coverage

**P1 / Major · Demonstrated behavior · App Store: Advisory · Coverage certification open.**

[VariantResolver](../../TradingCardScanner/Services/VariantResolver.swift#L240) can automatically return `uniqueInCatalog` for a Pokémon singleton with explicit membership and `physicalCoverageVerified` false. The existing regression asserts this behavior. [Acquisition test](../../TradingCardScannerTests/VariantResolverTests.swift#L1070).

The owner chose to certify complete finish lists in the shipped data and preserve zero-tap acquisition for certified singletons. The app now derives Pokémon coverage from the bundled exact lists and honors any open signed Normal review. Live and cached provider records supply membership. The set report compares numbered checklist slots and known minimums with the corresponding TCGplayer products and subtypes. Certification requires matching exact finishes or a cited resolution for each discrepancy and closure of each Normal review. Market listings establish the reported membership evidence. Physical or retail records resolve conflicts. [Coverage resource](../../TradingCardScanner/PokemonChecklistSnapshot/finish-coverage.json), [certification tool](../../scripts/certify_pokemon_finish_coverage.py).

Obsidian Flames uses group `23228`. Run `python3 scripts/certify_pokemon_finish_coverage.py report sv03 --group 23228` to generate its report and the matching receipt under `docs/research/pokemon-finish-coverage/captures/`. Edit only `resolutions` before running `python3 scripts/certify_pokemon_finish_coverage.py certify sv03`. Commit the receipt with the reviewed report. Older drafts need a report with a capture receipt. Preserve their citations when transferring resolutions. [Pokémon TCGplayer group directory](https://tcgcsv.com/tcgplayer/3/groups).

Certification validates each standard finish against the bundled Pokémon vocabulary and requires active signed standard memberships. Signed Jumbo variants are added separately at acquisition and excluded from standard checklist slots. Fixture coverage exercises the Obsidian Flames Charizard ex `sv03-125`, removed market-only evidence, and unknown finish IDs. [Standard finish vocabulary](../../TradingCardScanner/PokemonChecklistSnapshot/finish-coverage-variants.json), [signed Jumbo regression](../../TradingCardScannerTests/VariantResolverTests.swift#L396).

The first pass compared 4,433 cards across 24 bundled Mega Evolution and Scarlet & Violet sets. It flagged 618 conflicts, with at least one in every set. Pitch Black review found 12 additional listings across 10 card numbers outside its main group, including non-holo deck exclusives and retail stamps. The receipt-bound draft adds a fifth cited resolution for Marshadow `040/084`, whose Cosmos Holo blister printing supplements its Normal and Reverse Holofoil listings. Five Pitch Black rows still need exact lists. The updated draft and receipt are on the SSD in `CodexBuilds/launch-findings-2026-11-10/FinishCoverageReviewBound/`. [Pokémon retail stamp announcement](https://press.pokemon.com/en/MEDIA-ALERT-Mega-Darkrai-ex-and-Mega-Zeraora-ex-Debut-in-Pokemon-TCG-M), [reviewed Marshadow evidence](../../TestFixtures/TradingCards/PokemonCatalogCoverageAudit/reported-parallel-review.json).

**Correction after detailed reproduction:** the saved Tropius shown in the review capture is Pitch Black 001, not 30th-005. Comparing that editor with product 716439 / 30th-005 was invalid and is withdrawn. The current TCGdexCard projection explicitly supplies Holo for the reviewed 30th mapping despite the upstream Normal flag. This sample does not establish an app finish-mapping defect. The resolver policy finding above stands independently.

The result's metadata is stronger than membership alone: `uniqueInCatalog` maps to `catalogCertain`, with the label “Only variant printed” and quiet receipt prominence. See the [detailed reproduction supplement](launch-review-items-2-and-4-reproduction-2026-11-10.md) for the exact input, control cases and evidence boundaries; it also expands LR02/LR04.

The certificate currently contains zero of the 146 distinct bundled sets. Complete each set's review and regenerate any changed slots before removing the incomplete-Pokémon singleton exception. The final launch check requires certification for every manifest entry, matching raw Browse slots and no duplicate minimums. Verify certified zero-tap acquisition and the explicit choice for an uncertified printing on a disposable store.

### LR07 — Collection search clips accessibility text

**P2 / Minor · Demonstrated UI defect · App Store: Advisory · Confidence: High.**

[collectionSearchField](../../TradingCardScanner/Views/CollectionView.swift#L870) applies scalable body text inside a fixed 36-point height. The outer 44-point minimum increases the target but does not grow the inner field. At accessibility-extra-extra-extra-large, the placeholder is visibly cropped in both phone Collection and the iPad sidebar. Accepted captures: phone-collection-accessibility.png and iPadCollection/detail-accessibility.png.

**Verify:** maximum Dynamic Type → Collection → inspect placeholder and then a focused typed query. Let the field grow with its text and vertical padding, retaining a comfortable touch target and the current debounce/query behavior. Do not cap Dynamic Type or shrink the user's text to conceal the failure. No search-result correctness failure was demonstrated.

### LR08 — Portfolio movement heading fragments at maximum text size

**P2 / Minor · Demonstrated UI defect · App Store: Advisory · Confidence: High.**

The nested horizontal header in [PortfolioView](../../TradingCardScanner/Views/PortfolioView.swift#L686) competes with its info control and See all action. With the largest text size, “month” breaks into “mont” and “h” and the heading consumes excessive vertical space. The scrolled phone-portfolio-accessibility-scrolled.png capture reproduces the cramped-heading concern from the interrupted pass; it does not prove that earlier pass referred to this exact heading.

**Verify:** Portfolio → 1M → largest Dynamic Type → scroll to What changed. Use an adaptive vertical arrangement for the heading and actions while preserving readable full text, access to the explanation and See all navigation. Check other ranges and a populated movers list. No accounting or contributor-selection rewrite is indicated.

## Findings already addressed or not established

- Grader word/number contradictions, the game-wide finish-correction picker, disabled-fallback warning tone, sparse detail history, duplicate single-copy totals, Add/Undo placement and the owned-card portfolio/provider movement mismatch have current fixes and passing executed coverage. Do not reopen them solely from old reports. Physical slab glare, real purchases and live provider acceptance remain separate.
- Version/build are present in ordinary Settings in the current candidate. The launch contract's older S15.05 “only in a diagnostics export” observation is historical; full candidate usability acceptance is still pending. NO_CLOUDKIT is also separated from the local owner/testing flags in Release.
- No new demonstrated ownership data loss, duplicate mutation, wrong marketplace destination or crash was found in the inspected/executed scope. This is a bounded result, not a claim of absence throughout every input and device.
- The older same-count revision-baseline concern, historical UI hangs and large-store costs remain reproduction/measurement work. Source suspicion alone is not a mandate to replace the projection, cache, scanner or persistence architecture. Follow the current [hang investigation](../plans/hang-inspection-plan.md) on the repaired candidate.
- Live CloudKit convergence is outside the adopted on-device 1.0 scope. It must not be silently reintroduced as a launch dependency, nor inferred to work from local storage tests.

## Proposed launch finish line

The [handoff](../plans/launch-review-handoff-2026-11-10.md) turns these findings into bounded work packages. Launch requires:

1. Contracted pricing works on a fresh customer install with no customer key; exact identity, freshness, outage/quota behavior and permitted exports are verified.
2. The five-game support manifest matches the installed distribution build, including approved One Piece acquisition, working catalog delivery and explicit unsupported families.
3. Production centering satisfies the frozen applicable accuracy and interaction requirements. Any owner-approved change to scope/claims must be explicit; a research exclusion or a manual-confirm button cannot silently waive an applicable failure.
4. LR07/LR08 and any newly reproduced critical-journey defects are fixed and independently recaptured. All applicable integrity and interaction checks pass without lowered standards.
5. A frozen candidate completes the contract's J01–J12 journeys on representative iPhone/iPad and minimum/latest supported OS, including real camera/repeated copies, interruption/offline/recovery, Files import/export, custom artwork/sharing, large-photo/batch tools, spoken VoiceOver and sustained-use responsiveness.
6. Sandbox/TestFlight purchase/restore/pending/refund/interruption, first-unlock/on-device continuity, archive/signing, licensed sources/artwork, published legal/support pages and truthful store metadata have actual candidate receipts.

DEBUG-only reference research, new sync, new games, speculative caching/architecture changes and expansion beyond the declared support manifest can follow later. Existing in-scope device hang reports require a current reproduction or evidence-backed disposition before acceptance. No release date estimate is justified until pricing integration, production activation and centering work are bounded.
