# CardScanner: launch monetization and product decision

Date: October 20, 2026  
Canonical repository location: `docs/plans/CARDSCANNER_LAUNCH_MONETIZATION.md`  
Status: **Owner-authorized Collector Tools implementation — October 20, 2026. Local implementation and verification status below; live product and release gates remain open.**

## 1. Purpose and launch goal

Retain the commercial intent behind the existing product so future implementation does not reopen its purpose, introduce conflicting paywalls, or expand into unrelated features.

Target the first genuine production App Store purchase by **November 2, 2026, Colorado time**. Do not restart the clock after development. App approval and customer purchases are not guaranteed. Sandbox/TestFlight transactions, promo redemptions, self-purchases and reimbursed favors do not count. A first sale demonstrates a transaction, not product-market fit, profitability or Apple's eventual cash payout.

## 2. Why the photo tool exists

Sean's firsthand account:

> “This is literally the whole reason the eBay photo splitting feature exists. I was spending so much more time taking 10 photos than taking 2 and running it through this batch processor”

The tool addresses an existing task, not an invented need to fill ten photo slots. Its value is:

1. **Less capture and editing work:** for sellers already documenting details, replace repeated photography and manual cropping with front/back captures and automatic detail views.
2. **More practical condition documentation:** make useful close-ups inexpensive in preparation time, including for lower-value cards where manual work otherwise feels disproportionate.
3. **More inspectable output:** native-resolution crops can present existing detail at a larger effective scale after marketplace resizing.

Sean's experience establishes the problem and benefit for him. It does not establish market size, universal time savings or willingness to pay among other sellers. Those are separate commercial questions, not reasons to repeatedly question the feature's existence.

## 3. Product position and differentiation

CardScanner remains a collector application, not merely a photo utility:

**Scan cards, maintain a collection you can trust, retain control of your data, and prepare photos when it is time to sell.**

Potential differentiation lies in the combined experience: correct exact-printing/finish handling, appropriate uncertainty, efficient intake, accessible collection records, portability and useful seller tools without a mandatory subscription.

Do not construct an imaginary competitor from the best features of many separate apps. Compare whole customer journeys against individual products. Conversely, putting features in one app is not by itself proof of superior integration or usability.

Competitor accuracy and speed figures are vendor claims unless independently validated. Compare exact identities, printing and finish separately; record wrong automatic saves, unresolved results, misses, quantity errors, corrections, interactions and total time to a correct collection. A small pilot is diagnostic, not justification for a universal accuracy percentage.

The longer-term collection-integrity direction remains relevant. Physical placement, reconciliation and audit systems are **not prerequisites for this launch**.

## 4. Approved initial offer

**One non-consumable “CardScanner Collector Tools” unlock, $9.99 US base price, paid once.** Includes unlimited batch listing-photo preparation/export and unlimited use of the existing guided card-centering tool, including its annotated output. No subscription, scan credits, collection caps or generic all-future-features promise.

### Free core

- Scanning, ordinary collection access and management, and identity/finish corrections.
- Basic import/export of user-owned collection information.
- Existing basic pricing within lawful provider licensing and sustainable service limits; not a promise of unlimited refreshes or perpetual third-party data service.
- Single-card photo preparation and output, so the user can inspect and use a real result before paying.

### Paid convenience

Batch preparation and export of multiple front/back pairs into organized per-card photo packs. The present workflow produces ten numbered JPEG views per completed card: full front/back views plus four overlapping detail crops from each side.

Guided centering measurement/estimation and existing annotated output use the same entitlement. Centering is not professional grading or a predicted grade. Outer/inner-frame review and explicit confirmation remain required; automatic reporting remains disabled. A one-card selection in the batch UI stays free.

Charge for batching and saved work, not access to existing collection records, correction of inaccurate identities, or retrieval of previously exported files.

State the price before substantial batch preparation. Preserve work on cancellation, pending purchases and recoverable failure. Use localized StoreKit pricing and restore purchases. Do not imply the unlock includes every future paid feature or ongoing external data services.

## 5. Current implementation and truthful claims

Implementation started from clean `be183f2` on October 20, 2026, after reconciling the earlier `922dc9b` review. See §10 for the current purchase behavior and verification limits.

- Listing Photos is separate from collection identity and stored scan captures. Batch inputs are existing Photos-library images selected in front/back order; pairing review, swaps and folder names are manual.
- Batch output is a ZIP. It does not create or publish marketplace listings or synchronize inventory.
- The cropper uses fixed overlapping image regions: 60% width/height for fronts and 63% for backs. It does not detect physical card corners or inspect damage.
- Processing uses full-resolution source images, not small UI previews. JPEG encoding may change to satisfy file-size limits; do not call the output universally lossless.

A well-framed source is essential. Crops cannot recover focus, reveal glare-hidden marks or replace an angled photograph of a lighting-dependent defect.

A 60% × 60% crop retains 36% of source pixels, approximately 17.3 MP from an actual 48 MP input. At equal aspect ratio and final display dimensions, existing features appear about 1.67 times larger linearly. This is a conditional scale relationship, not a measured sharpness or sales improvement. Do not assume every imported phone photo is 48 MP or every eBay display is capped at 1600 pixels.

**Safe benefit language:** create organized full-card and detail views from two well-framed photographs, reducing repeated capture/editing and making photographed condition easier to inspect.

**Do not promise:** intelligent corner detection, new photographic detail, condition grading, automatic listing, higher sale prices, fewer returns, guaranteed dispute protection or that every flaw is documented. Photographs can support disclosure; they do not guarantee a case outcome.

## 6. Competitive context and distribution

Research checked October 20, 2026:

- Collectr, Sorted and ManaBox are relevant collector-workflow comparisons. Collectr's US listing reserves unlimited scanning and data export for paid access.
- Ludex, CollX and eBay itself are relevant to casual sellers; do not restrict comparison to professional systems.
- Card Dealer Pro and Kronozio advertise integrated identification/inventory/selling workflows, with monthly entry prices of $9 and $10 respectively. Breadth does not establish measured accuracy or ease.
- Helvault's current US app offers a $9.99 lifetime scanner unlock. One-time payment is familiar, not unique.
- CardCrop offers free capture/crop and optional lifetime customization. Card Pairer advertises front/back pairing and ten-image exports; its exact paid prices and hands-on behavior were not verified. Feature overlap alone does not establish equivalent execution or a redundant product.

Initial paid-offer audience: collectors and occasional sellers who already take detail photos, or want to provide them without the repeated work. They need not migrate their entire collection to try the photo tool.

Lead with a short honest demonstration of Sean's old ten-photo process versus two-photo batch preparation, followed by the actual usable output. Measure any advertised time saving. Show the combined collection toolkit without implying automatic scan-to-list integration.

Use targeted, permission-based outreach and small seller demonstrations before paid advertising. Suggested initial operating targets are 15–20 relevant conversations and 5–10 workflow trials, not forecast conversion rates. No outreach is authorized by this document.

## 7. Launch-critical work and evidence

### Bounded code/UI pass

- Check current purchase code, then implement only missing non-consumable entitlement handling: verified purchases, pending/cancel/error states, restore, relaunch and revocation/refund behavior.
- Make free single-card output and batch preparation discoverable; the reviewed Pro entry does not explain that distinction well.
- Present clear purchase boundaries and localized price without interrupting the free scanning loop.
- Verify expected files, pairing, quality, share/export behavior and retained work around purchase interruptions.

### Bounded product checks

Use ordinary seller photographs. Check framing and useful detail views; inspect how uploaded crops actually appear to buyers; time the complete preparation/export/upload path. A ZIP finishing is not the final customer outcome. Do not publish listings or use customer accounts without authorization.

Compare both outcomes fairly: less work for equivalent documentation, and better documentation for similar preparation effort. Do not assume a person normally uploading two images must previously have taken ten. Do not make a new large benchmark project a condition of acknowledging Sean's demonstrated benefit.

### Commercial dependencies

- Owner verifies paid-app agreements, banking/tax information and applicable commission enrollment.
- Configure the approved product and submit the first non-consumable with the app version. Validate production availability separately from sandbox success.
- Verify privacy/support pages, actual supported games, and claims in screenshots and metadata.
- Resolve provider commercial-use and export permissions. User-owned collection records and licensed provider datasets are not interchangeable.

JustTCG's published commercial entry plan is $19/month. Its terms restrict export of stored provider data as a dataset; do not promise raw price redistribution without permission or clarification. Keep Scryfall data access free and paid processing confined to users' own photographs rather than altered catalog images. This is a compliance boundary to verify, not blanket legal clearance.

At $9.99, 15% or 30% commission leaves approximately $8.49 or $6.99 before taxes, refunds, support, hosting and acquisition. Three new purchases cover a $19 monthly API bill alone. Returning lifetime buyers create no repeat unlock revenue. Track actual costs and proceeds; do not confuse a first sale with sustainable monthly income.

No invasive analytics SDK is needed for initial learning. Use observed trials and App Store reports; campaign privacy thresholds/delays mean missing campaign data is not proof of no activity. Track successful photo output separately from merely saving a scanned card.

## 8. Scope, status and change control

Not in this launch: new card games, smart corner detection, grading, automatic marketplace publishing, inventory sync, new verification systems, subscription tiers, major redesign or monetization infrastructure beyond this offer.

The October 20 user instruction authorizes this bounded implementation and local testing of the two-tool bundle. It authorizes no live purchases, provider agreements, App Store account/product changes, outreach, submission, publication, deployment, spending, commit or push.

Link this document from the existing photo-tool plan and active launch checklist. Mark conflicting old scan-cap, collection-cap or paid-basic-export proposals as superseded recommendations, without erasing historical records or claiming owner approval that has not occurred.

Keep one small status list: offer approval; payment/UI gaps; licensing/export permissions; focused acceptance; App Store submission; first genuine purchase. Update it when evidence changes. Do not repeatedly expand scope or relitigate the founder problem.

## 9. Historical checkout gap assessment — October 20, 2026

**Historical:** this pre-implementation table describes `922dc9b`, not the current source. Its batch-only proposal and paid one-pair batch boundary are superseded by §4 and §10. Retained to distinguish earlier findings from verified implementation.

Read-only review: clean `main` at `922dc9bb3d158a599e874d4a00e85297a138b6f8`,
which happens to match the attachment baseline. Source presence below is not a
passing test. No build, simulator, purchase, share/upload or provider check ran.
Competitive/pricing/terms observations above are retained dated rationale, not
freshly verified research or evidence of an agreement.

| Offer requirement | Classification and source evidence | Smallest remaining action |
| --- | --- | --- |
| Entry and free-single/paid-batch discovery | **Present in source:** [ProView](../../TradingCardScanner/Views/ProView.swift) links to Listing Photos; [EbayListingPhotosView](../../TradingCardScanner/Views/EbayListingPhotosView.swift), `Mode` and `body`, expose Single card and Batch. **Missing:** free/paid explanation, one-time-unlock wording and price. | Explain free single-card output and the approved batch-only unlock at entry and before substantial batch preparation. Keep scanning, collection access/corrections and basic portability free. |
| One non-consumable and purchase lifecycle | **Missing:** no StoreKit import, product loading, purchase/verified transaction handling, current-entitlement query, transaction-update listener, restore or revocation handling found in app/test/project source; no `.storekit` file found. | Add one batch entitlement with verified success, pending/cancel/error, restore, launch reconciliation and update/revocation handling. Unverified or revoked purchases must not unlock new batch work; previously exported files remain usable. **Requires runtime/owner verification:** sandbox lifecycle and production product availability. |
| Upfront localized price, work retention and batch gating | **Missing:** no StoreKit localized price or entitlement guard in `startBatch`, `processBatch` or batch export UI in [EbayListingPhotosView](../../TradingCardScanner/Views/EbayListingPhotosView.swift). Both modes currently run without payment. Pair selection/swaps/names are view state; `.onDisappear` cancels processing and removes artifacts. Existing processing cancellation is not purchase cancellation handling. | Load/display StoreKit price before batch preparation; check the entitlement at batch processing/export boundaries, including a one-pair use of Batch. Keep free single output available. Purchase UI must retain selected pairs, swaps, names and prepared work through dismissal, pending and recoverable failure; avoid triggering existing disappearance cleanup. Entitlement relaunch recovery does not require a new persistent draft feature. **Requires runtime verification:** interruptions, retries and revocation while the screen is open. |
| Native-resolution ten-view output | **Present in source:** [EbayListingPhotoExport](../../TradingCardScanner/Services/EbayListingPhotoExport.swift), `processSide`/`decodeNativeImage`, decodes at source dimensions with orientation applied, crops source pixels and separates small previews; compatible upright JPEG bytes are retained only within the byte budget. Other output uses JPEG quality steps, without dimension reduction. [EbayQuadrantCropper](../../TradingCardScanner/Services/EbayQuadrantCropper.swift) intentionally uses fixed 0.60/0.63 ratios. | No crop/quality change identified for this offer. **Requires runtime verification:** actual dimensions, orientation, useful framing, ten filenames, large inputs and resulting quality. Native resolution does not mean universally lossless or recovered detail. |
| Export and marketplace handoff | **Present in source:** view toolbar shares single ZIP or ten individual URLs, or saves to Photos through [ListingPhotoLibrarySaver](../../TradingCardScanner/Services/ListingPhotoLibrarySaver.swift); batch shares a ZIP of per-card folders. Export service uses native file coordination to archive. View copy warns Photos loses filenames. **Requires runtime verification:** share destinations, temporary-file lifetime and the user's complete upload/buyer-view path. | Exercise Files/AirDrop/share, unzip and manual marketplace upload with authorization later. There is no automatic upload/listing integration in this path; no new upload feature is needed. Do not equate ZIP completion with completed marketplace use. |
| Provider licensing and exported fields | **Requires owner/later verification:** local code cannot establish commercial permissions. [CollectionCSV](../../TradingCardScanner/Services/CollectionCSV.swift), `exportHeaders`, includes provider/catalog IDs, names, image/thumbnail URLs and JustTCG IDs; diagnostic export includes price/source/listing and retained quote fields, and portfolio history exports market contributions. Photo output operates on user photos independently of catalog identity. | Owner confirms commercial provider plans/permissions and allowed fields across basic, diagnostic and history exports. Review JustTCG stored-data/export restrictions, Scryfall free-access boundaries, and applicable catalog/artwork rights; public endpoints and API keys are not permission. Change only fields proven incompatible after that review, preserving lawful user-owned portability. |
| App Store prerequisites | **Requires owner verification:** no local source proves account enrollment, paid-app agreements, banking/tax, commission eligibility, product configuration/approval or production availability. | Owner approves offer, supplies approved product identity, resolves account/agreements, configures one non-consumable and submits it with the appropriate app version; verify production separately from sandbox. Existing privacy/support publication and distribution gates remain open. No account actions are authorized here. |

## 10. Collector Tools implementation — October 20, 2026

- **Offer approval:** user authorized the $9.99 US one-time two-tool bundle. This narrowly replaces the earlier batch-only proposal. The founder rationale in §2 is unchanged.
- **Product identity:** `com.seankeller.CardScanner.collectorTools`, defined by `CollectorToolsStore.productID`, matches the verified app bundle prefix `com.seankeller.CardScanner`. [Local configuration](../../CollectorTools.storekit) is a non-consumable at 9.99 in the US storefront; it creates no live product.
- **Entitlement:** one shared StoreKit 2 store, compatible with iOS 17. Launch and foreground query verified on-device current entitlements; an app-lifetime update listener reconciles verified deliveries and finishes handled intended transactions. Duplicate deliveries repeat reconciliation without creating exports. Completed empty reconciliation removes obsolete ownership. Product lookup is independent and cannot revoke ownership. No UserDefaults ownership flag or backend exists.
- **Purchase/restore:** shared compact offer uses `Product.displayPrice`; unavailable product information offers retry without an invented price. Cancellation, pending, failure and verification failure report status; purchase/restore requests cannot overlap. Restore alone calls `AppStore.sync()` explicitly. No automatic authentication prompts are requested by launch/foreground reconciliation.
- **Boundaries:** multi-card Prepare and processing entry check entitlement; ZIP transfer rechecks ownership when the share system requests the file. Both single mode and one pair in Batch remain free. Every existing centering entry goes through the same guarded view. Pro itself and unrelated free utilities remain accessible. Pro's Collector Tools action keeps the offer/restore reachable. Centering includes an estimation disclaimer in the offer, measurement UI and annotated report; detection, ratios, reference logic and frame confirmation are unchanged.
- **Work:** purchase presentation has its own sheet flag and never changes photo-selection generations, pairs, swaps, names or outputs. Ownership changes never trigger preparation or sharing. Existing input/navigation cancellation fences remain responsible for stale-work rejection. Entitlement recovers after relaunch; unfinished photo drafts are still view state, with no process-death draft-recovery claim. Refunds do not delete collections, source photographs or prior exports.
- **Verification:** seven isolated entitlement/share-authorization tests passed on macOS using the unchanged repository service and transferable definitions in a temporary SwiftPM harness. Coverage: loading/free single, cancel/pending/failure/unverified/unrelated delivery, both-tool unlock, repeat taps, duplicate delivery after revocation, restore/recreation, fetch failure/localized price, out-of-order reconciliation and share-time access. This is state-logic evidence, not an iOS purchase or draft-retention check. The real local `SKTestSession` purchase/relaunch/restore/refund/two-card ZIP test is added but has not run.

### Focused acceptance blocker

The final `xcodebuild build-for-testing` succeeded with scheme `TradingCardScanner`, configuration `Debug`, generic iOS Simulator destination, and `CODE_SIGNING_ALLOWED=NO`, compiling the app and test host for arm64/x86_64 against iOS 17 deployment. Generated build/cache data is on the external SSD under `CodexBuilds/CollectorTools-20261020/`. Project plist, StoreKit JSON/identifier consistency, relative documentation links and `git diff --check` pass. This is an unsigned simulator build, not an archive or physical-device result.

Xcode 27.1 (`27A9275`) requires CoreSimulator `1174.9.2`, while this machine's installed/running service is `1171.7.0`. `xcodebuild` disables simulator device support and cannot resolve even an already booted iOS simulator destination. The installed `simctl` wrapper invokes Xcode first-launch setup before listing devices and stalled; querying the existing service directly worked, but did not resolve Xcode's mismatch. No simulator data was erased; system repair remains outside this pass. The focused `CollectorToolsTests`, existing `EbayQuadrantCropperTests`, `CenteringExportTests` and `CardCenteringSurfaceTests` invocation therefore executed **zero tests**. Local StoreKit, representative purchased ZIP inspection, rendered guided-centering/frame-confirmation/annotated-output smoke, purchase-sheet work retention, background/navigation interruptions and rendered accessibility checks remain unverified until the toolchain is compatible. The added integration test is not a substitute for a passing run.

HIG source review: **Verdict RISK** until rendered checks run. Platform controls, readable text styles and retained navigation pass source review. Top issues: unverified Dynamic Type/VoiceOver presentation and interruption behavior. Minimal follow-up: run the existing flow with the local configuration and the checks below; no redesign is required by this review.

### Owner setup and review

1. Once the local Xcode/CoreSimulator installation is compatible, run `CollectorToolsTests`, `EbayQuadrantCropperTests`, `CenteringExportTests` and `CardCenteringSurfaceTests` on an iOS simulator. The StoreKit test loads the configuration directly from the test bundle; it requires no account or live product.
2. For interactive testing, select `CollectorTools.storekit` under Scheme → Run → Options → StoreKit Configuration. Check successful purchase, cancel, pending/Ask to Buy approval, failure, restore and refund through Xcode's transaction manager. Confirm selected pairs, swaps, folder names and prepared files survive offer dismissal, backgrounding and returning. Confirm a later approval only enables a fresh explicit action, and navigation/input changes reject stale exports.
3. Inspect and unzip a purchased multi-card pack (ten ordered JPEGs per card), use free single output in both workflows, and smoke-test guided frame review/confirmation plus annotated output. Check localized price and unavailable/retry UI, Dynamic Type and VoiceOver. Never treat local success as proof of production availability.
4. Separately, owner creates the exact non-consumable identifier in App Store Connect with the approved US base price, localization and review screenshot, and submits it with the appropriate app version. Verify paid-app agreements, banking/tax setup and applicable commission enrollment. No account/product actions were performed here.

### Remaining launch dependencies

- Provider commercial-use permissions and pricing-data export rights, including allowed basic/diagnostic/history fields and catalog/artwork terms, remain unresolved owner gates.
- Privacy/support publication, truthful supported-game claims, metadata, physical-device and applicable CloudKit/ownership, archive/TestFlight and App Review/distribution gates remain separate. Simulator source/build evidence closes none of those gates.
- Live product creation/approval, production availability and the first genuine production purchase remain unverified. Target: **November 2, 2026, Colorado time**, with no guaranteed outcome.

## Sources and code references

- [Photo-tool plan](pro_tab_ebay_listing_photos_plan.md)
- [Crop implementation](../../TradingCardScanner/Services/EbayQuadrantCropper.swift)
- [Photo export implementation](../../TradingCardScanner/Services/EbayListingPhotoExport.swift)
- [eBay image requirements](https://www.ebay.com/help/selling/listings/pictures-videos/picture-requirements?id=4148) and [EPS processing](https://developer.ebay.com/DevZone/XML/docs/Reference/ebay/UploadSiteHostedPictures.html)
- [eBay seller returns and appeals](https://www.ebay.com/help/selling/seller-hub/using-seller-hub?id=4079)
- [Collectr US listing](https://apps.apple.com/us/app/collectr-tcg-collector-app/id1603892248), [Sorted FAQ](https://tcgsorted.com/faq), [ManaBox](https://manabox.app/)
- [Ludex memberships](https://www.ludex.com/membership/), [CollX](https://www.collx.app/), [eBay Scan to List](https://www.ebay.com/help/selling/listings/creating-managing-listings/scan-list-tool?id=5279)
- [Card Dealer Pro](https://www.carddealerpro.com/), [Kronozio pricing](https://kronozio.com/pricing)
- [Helvault US listing](https://apps.apple.com/us/app/helvault-mtg-scanner/id6451158920), [CardCrop US listing](https://apps.apple.com/us/app/cardcrop/id6799758825), [Card Pairer](https://cardpairer.com/) (indexed first-party claims; live page timed out)
- [JustTCG pricing](https://justtcg.com/pricing), [commercial use](https://justtcg.com/docs/commercial-use), [terms](https://justtcg.com/terms), [Scryfall API rules](https://scryfall.com/docs/api)
- [Apple non-consumable configuration](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/), [submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase), [Small Business Program](https://developer.apple.com/app-store/small-business-program/), [campaign reporting](https://developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links)
