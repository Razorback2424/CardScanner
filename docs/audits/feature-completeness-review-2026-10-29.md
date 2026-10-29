# Feature completeness review — 2026-10-29

**Base:** `b03a74f`, initially clean checkout. **Status:** scoped source/data
review complete; remediation is in progress in the working tree. The findings
below describe the reviewed base; verified changes are recorded separately.
This review follows the
Yu-Gi-Oh! history omission and checks capability reachability per game instead
of treating a shared service or a passing regression selection as feature parity.

The review traced normal/local versus distribution registration; scanner and
graded-pricing gates; catalog/Browse admission; quote sources and market history;
offline Magic lookup; CSV/storage/export boundaries; pricing Settings; and
purchase/privacy/support entry points. Bundled scope was recomputed from JSON.
External provider guidance was read on this date. There were no authenticated
price requests, credential reads, physical-device runs or distribution builds.
A focused native characterization of FC05 is recorded below; earlier test totals
are not verification of this review.

## Findings and dispositions

### Remediation progress

| Finding | Current working-tree change | Verification / remaining work |
| --- | --- | --- |
| FC05 | History recognizes the normal Lorcana discovery wrapper's reviewed physical registry. | Three native tests pass: normal catalog/collection history, unsupported finish and withdrawn cache, plus existing research and in-flight remapping controls. No live-provider coverage claim. |
| FC02 | Expired modern printing entries remain available during provider outages, preserving their original retrieval date. README separates recognition vocabulary from full-card resolution. | All 22 `MagicContentKindTests` pass, including a 90-day-old disk entry, unseen offline card, identity rejection, token/art routing and existing cache checks. The bounded cache is not a full offline database. |
| FC04 | Settings names JustTCG and explains history/graded/sealed requirements, the gap-filling toggle, Keychain recovery and shared allowance. | Debug/local build passes. No-key standard/accessibility-size screens were inspected. Saved-key rendering and save/remove interaction remain unverified. |
| CSV recovery clarity | Storage Settings explicitly distinguishes inventory transfer from full recovery. | Standard/accessibility-size screens and scrolling were inspected. A complete archive/restore feature is not implemented. |
| FC01 / YGO quote freshness | Static daily-delivery implementation is in progress; direct TCGCSV app requests have been removed. | Client provenance/endpoint checks and publisher/restore contracts have focused evidence. Final native selections, complete capture, deployment/readback and endpoint activation remain open. |
| FC03 / release and coverage gates | Open. | Work continues; the changes above do not close these findings. |

Native evidence for this remediation is retained under
`/Volumes/T7/CodexBuild/FeatureCompletenessFixes-20261029/`. App/test source
changes are uncommitted. A failed first offline test exposed transport error
translation; the fallback now handles `ScryfallError.providerUnavailable` and
continues to reject definitive catalog/identity errors. Tests are rerun after
the correction; the passing totals above refer to the corrected implementation.

The final broader native selection passed **54 tests, zero failures, six skips**:
the full Lorcana pricing and Magic content-kind classes plus the One Piece
mapping control. Three Lorcana live-provider and three externally staged
candidate tests deliberately skipped because their opt-ins/workspaces were
absent. An initial selection used the YGO source filename as the class name;
those cases were not discovered and are not counted. An explicit rerun of
`YuGiOhMarketHistoryTests` then passed **all six cases, zero failures/skips**.
The exact raw English/USD/condition/printing uniqueness filter now applies to
Lorcana and One Piece as well as YGO; the normal-runtime Lorcana response fixture
puts foreign and graded rows before its valid raw row. Existing mapping,
withdrawal and in-flight tests pass with this shared filter.

Screenshot details and limits are recorded in the
[Settings checklist](../../references/pricing_settings_success_checklist.md).
No real credential was read or changed. Source builds still emit existing
concurrency warnings; this is not a warning-free or release-readiness claim.

### Daily price delivery — implementation in progress

The replacement is a scoped static feed on the existing host. It does not add a
general query backend or use JustTCG allowance for routine group quotes.
[The publisher](../../scripts/market_price_feeds.py) retains source bodies once
per upstream daily build, exports only reviewed product/finish lanes and retains
the original server capture dates. The current bundled scope yields 608 YGO
groups / 46,303 products / 59,965 lanes, three Pokémon groups / 196 products,
48 One Piece groups / 2,367 products, and eight Lorcana groups / 1,748 products /
3,364 lanes. These are price request scopes, not new physical admission or
complete coverage claims.

The existing YGO candidate workflow prepares the feed from the same bounded
daily capture. Start/end markers bind the raw YGO bodies to a stable upstream
build, so the feed does not download those groups twice. Other group responses
are retained in the per-build cache. Failed/mixed captures do not write a hosting
candidate. An index binds every output path, size and SHA-256; restoration checks
it before the complete-site publishers can deploy. Existing catalog namespaces
are restored unchanged. The new price namespace uses a five-minute CDN cache,
with JSON content types on its extensionless product/price resources.

App transports now require a configured HTTPS mirror, block the upstream origin,
reject redirects in the default session and reject missing, mixed, future or
24-hour-old capture metadata. CDN downloads cannot manufacture a new price date
or satisfy a withdrawal freshness watermark with an older server capture.
Existing saved values remain available. YGO's new daily source retains the dated
bundle for offline initial valuation; a fresh missing lane does not borrow a
different edition or old quote, and identity mismatches/cancellation do not fall
back. History retains its independent authenticated JustTCG path.

**Activation is not complete:** `TCGCSV_PRICE_BASE_URL` is deliberately empty
until the prepared feed is published and read back. Consequently uncached
mirror-backed quotes are unavailable in the current intermediate build; no app
request falls back to the upstream provider. Publishing is a distinct protected
job in the existing hosting environment. It is disabled for scheduled runs until
the owner activates `MARKET_PRICE_FEEDS_ACTIVE`, and a manual publication needs
the explicit workflow input. No workflow was dispatched, production endpoint
configured, service account changed or deployment performed in this worktree.
Keep the existing owner-controlled publication/rights gates open. After approved
readback, the app endpoint is the existing trusted host's `/market-prices/v1`
namespace; that configuration and real per-game acceptance remain required.

### FC05 — Normal-app Lorcana raw-card history cannot resolve its reviewed mapping

**Newly surfaced functional defect. Severity: Major. Risk: Likely Question.
Confidence: High; reproduced in a native simulator characterization.**

[appDefaults](../../TradingCardScanner/Games/Core/CardGameRuntime.swift#L294)
registers `LorcanaDiscoveryCatalog.bundledMarket.runtime`, whose
[catalog](../../TradingCardScanner/Games/Lorcana/LorcanaDiscoveryCatalog.swift#L254)
is the discovery wrapper itself. The history request's
[mapping resolver](../../TradingCardScanner/Services/CardMarketHistoryService.swift#L101)
only recognizes `LorcanaCatalogAdapter`. Consequently the normal raw-card
request retains no exact product/finish mapping, cache reads return empty and
`history(for:)` throws `noListing` before HTTP, even when the physical card has a
reviewed marketplace mapping. A valid API key cannot repair this path. Sealed
history uses a separate exact-listing path and is not included in this finding.

The existing
[Lorcana history test](../../TradingCardScannerTests/LorcanaPricingTests.swift#L355)
constructs `LorcanaGameRuntime`, the research runtime, which does expose the type
the resolver recognizes. That test was included in the earlier 149-test YGO
selection. It did not establish normal-registration Lorcana history acceptance.

**Recommended fix:** resolve the current discovery wrapper's reviewed physical
registry through the same exact mapping and withdrawal checks, then add a
regression using `bundledMarket.runtime` for both collection and catalog detail.
Keep the research-runtime test as a separate control. Do not bypass catalog
authority or substitute stored vendor handles. This audit records the defect;
it does not modify production behavior.

**Native evidence:** a temporary test used the real bundled market catalog and
one of its admitted, reviewed physical mappings. With identical card/finish
inputs, `bundledMarket.runtime` produced a nil product and empty lookups;
`LorcanaGameRuntime` produced the reviewed product/finish. The normal-runtime
service then threw `noListing` before transport. The characterization and the
existing research-runtime control both passed: **two tests, zero failures/skips**.
The characterization deliberately asserts the current defective outcome; these
passes are reproduction evidence, not history-feature acceptance. Its source
patch, log and xcresult are retained externally in
`/Volumes/T7/CodexBuild/FeatureCompleteness-20261029/`. The temporary test was
removed after recording evidence; app and test source match the reviewed base.

### FC01 — Direct TCGCSV device pricing conflicts with current provider guidance

**Newly surfaced cross-game issue. Severity: Major. Risk: Likely Question.
Confidence: High** for the request-path/guidance mismatch; actual enforcement
and any separate permission are unverified.

[TCGCSVProductPriceSource](../../TradingCardScanner/Services/TCGCSVProductPriceSource.swift#L145)
uses the device's URLSession to retrieve `tcgcsv.com/tcgplayer/...` products and
prices. Normal
[Lorcana](../../TradingCardScanner/Games/Lorcana/LorcanaPriceAdapter.swift#L8)
and [One Piece](../../TradingCardScanner/Games/OnePiece/OnePiecePriceAdapter.swift)
quotes use it. The separate
[Pokémon TCGCSV service](../../TradingCardScanner/Services/PokemonTCGCSVPriceService.swift#L20)
also downloads directly from the device for its mapped subset.

The provider's current [usage guidelines](https://tcgcsv.com/docs) explicitly
prohibit requests directly from user-facing applications and prescribe ingestion
into a separate stored data source. Per-device daily caching and pacing do not
resolve that architectural mismatch. This affects reliability and permission to
depend on the service; no claim that users have already been blocked is made.

**Recommended fix:** resolve this across all active consumers through approved
daily ingestion/delivery or another permitted provider path. Preserve exact
product/finish checks, source timestamps and offline retention. This review does
not authorize deployment, purchasing, or starting the deferred shared-cache
project. The earlier YGO correction removed this device path for only one game;
that safeguard was not applied consistently to the other consumers.

### FC02 — Magic's offline promise exceeds the implemented lookup guarantee

**Newly surfaced claim/behavior mismatch. Severity: Major. Risk: Advisory.
Confidence: High** for the source behavior; offline device experience was not run.

[README](../../README.md#L55) says Magic scanning works on first launch and
offline because the set vocabulary is bundled. Full card resolution still
requires metadata beyond that vocabulary.
[MagicCatalogAdapter](../../TradingCardScanner/Games/Magic/MagicCatalogAdapter.swift#L240)
uses a resolved-card cache, then fetches the card from Scryfall on a miss. Its
[cache](../../TradingCardScanner/Games/Magic/MagicCatalogAdapter.swift#L327)
expires entries after 24 hours and caps storage at 512 modern printings.
[ScryfallService](../../TradingCardScanner/Services/TCGdexService.swift#L685)
performs the HTTP lookup. The bundled Magic seed contains sets, not a complete
offline card database. HTTP caching can help previously fetched requests; it
cannot establish a first-use offline guarantee.

**Why it matters:** offline footer recognition can succeed while adding that
previously unseen card cannot complete. A previously scanned card also lacks an
unconditional offline guarantee after cache expiry/eviction.

**Recommended fix:** state the current boundary explicitly: bundled recognition
vocabulary, with card lookup dependent on available cached data or connectivity.
If durable offline acquisition is required, retain validated identity/finish data
under an explicit offline contract, separately from quote freshness, and verify
first-use, expired-cache and token/historical cases. Never infer identity or a
fresh price to conceal an offline miss.

### FC03 — Graded pricing has three-game gaps with an unexplained disabled action

**Newly surfaced capability/UI gap. Severity: Major. Risk: Advisory.
Confidence: High** from registration and gate traces.

[Pokémon](../../TradingCardScanner/Games/Pokemon/PokemonGameRuntime.swift) and
[Magic](../../TradingCardScanner/Games/Magic/MagicGameRuntime.swift) register
`.gradedPricing`. The active
[Lorcana](../../TradingCardScanner/Games/Lorcana/LorcanaDiscoveryCatalog.swift#L250),
[One Piece](../../TradingCardScanner/Games/OnePiece/OnePieceGameRuntime.swift) and
[Yu-Gi-Oh!](../../TradingCardScanner/Games/YuGiOh/YuGiOhGameRuntime.swift)
registrations do not. Thus these three games cannot use the normal exact graded
listing picker, and
[ScannedGradedResolver](../../TradingCardScanner/Services/ScannedGradedResolver.swift#L71)
returns unavailable before contacting the provider.

[Catalog detail](../../TradingCardScanner/Views/CatalogCardDetailView.swift#L210)
still renders **Add Graded Copy**, disabling it through the capability check
without a game-specific explanation. Recording an unbound slab is a separate
path; this finding does not claim all slab recognition/storage is absent.

**Recommended fix:** expose the supported-game boundary and explain or omit the
unavailable action. Add per-game provider identity/edition/finish acceptance
before enabling graded pricing; changing the capability bit alone is unsafe.

### FC04 — Pricing-key setup describes only a fraction of what requires it

**Newly surfaced onboarding/clarity gap; BYOK architecture was already known.
Severity: Minor. Risk: Advisory. Confidence: High.**

[Settings](../../TradingCardScanner/Views/ScannerSettingsView.swift#L827)
places the API key under **Price Fallback** and describes it as optional extra
coverage for cards absent from TCGdex/Scryfall. The same key is necessary for
uncached JustTCG history, graded prices and provider-backed sealed actions.
[History](../../TradingCardScanner/Services/CardMarketHistoryService.swift#L383)
uses the authenticated transport independently of the fallback toggle. Turning
off *fallback* is not a global network/provider switch; this is not classified
as a violation of that preference.

**Recommended fix:** name and describe provider setup by the features it enables,
including history and graded/sealed coverage. Explain what the toggle controls,
credential recovery and shared quota use. Preserve user-owned Keychain storage;
do not embed a developer secret. The
[existing backend plan](../plans/shared_pricing_cache_plan.md) already records
the BYOK/commercial decision, so this is not a newly discovered missing backend.

## Five-game capability matrix

These are source/data facts, not new live-provider or camera acceptance.
“Present” means a reachable implementation in the stated scope.

| Game | Scan/Browse/raw ownership | Current quotes and refresh | Individual history | Graded pricing | Sealed |
| --- | --- | --- | --- | --- | --- |
| Pokémon | Present within catalog/physical-variant scope; uncached lookups can need network | Provider routes plus mapped TCGCSV subset/fallback; FC01 applies | JustTCG key and exact listing required | Enabled; live coverage unverified here | Enabled; provider/key coverage applies |
| Magic | Present; offline boundary is FC02 | Scryfall/fallback routes; source/listing availability applies | JustTCG key and exact listing required | Enabled; live coverage unverified here | Enabled; provider/key coverage applies |
| One Piece | Owner local build admits signed bundled scope; checked-in distribution configuration disables registration | Exact mapped TCGCSV route in enabled local build; FC01 applies | Exact reviewed mapping and key required in enabled build | Not enabled | Enabled in owner local scope |
| Lorcana | 3,582 discovery rows; physical manifest has 1,749 records only across sets 1–8 | 1,748 physical records have 3,364 mapping lanes; FC01 applies | Broken for reviewed raw cards in normal registration: FC05; research-runtime test does not establish app support | Not enabled | 177 bundled discovery products; price/listing coverage remains separate |
| Yu-Gi-Oh! | 46,542 catalog records, 46,303 with explicit supported membership before runtime-family admission checks | Dated bundled quotes; live quote refresh unavailable | Newly implemented exact product/edition history; key/live coverage needed | Not enabled | Not enabled |

### Reconfirmed scope/release gaps — not new discoveries

| Gap | Current evidence and prior disposition | Required next step |
| --- | --- | --- |
| Lorcana sets 9–14 cannot be added through reviewed physical acquisition | 1,460 discovery rows across those six sets, zero physical-manifest records there. Detail gives a review-required reason. No optional `browse-prices.json` is bundled. The [five-game launch review](../release/five-game-launch-readiness-2026-10-23.md#3-released-lorcana-coverage) already made expansion or an explicit scope decision a launch gate. | Complete evidence-backed identity/finish/mapping review, or explicitly approve narrower launch scope and disclose it before the detail dead end. Discovery counts are not a certified physical-printing denominator. |
| One Piece local/distribution parity | [appDefaults](../../TradingCardScanner/Games/Core/CardGameRuntime.swift#L317) uses an owner-runtime path under `LOCAL_ONLY_SIGNING`. [Production configuration](../../Config/OnePieceCatalogProduction.xcconfig) remains disabled with writes `NO`; the [bootstrap](../../TradingCardScanner/Services/OnePieceCatalogBootstrap.swift#L200) returns no module in disabled mode. Already recorded in the five-game release authority. | Validate approved signing/data/acquisition and actual distribution registration before promising five-game parity. Retain the existing owner approval gates. |
| Yu-Gi-Oh! current valuation freshness | The history repair supplies an independent series. [BundledPriceSource](../../TradingCardScanner/Games/YuGiOh/YuGiOhPriceAdapter.swift#L6) still reads snapshot values; the checked-in catalog capture is 2026-10-23. | Establish approved periodic quote delivery or another exact live quote source; keep history and valuation provenance separate. |
| Full app-level backup/restore | [CSV export](../../TradingCardScanner/Services/CollectionCSV.swift#L219) transfers inventory metadata; it does not archive separate history, observations or custom-artwork bytes. The [privacy/storage view](../../TradingCardScanner/Views/PrivacyAndSupportSettingsView.swift) confirms local-only storage. This limit was already stated in [reviewer notes](../release/lorcana-app-review-notes.md#L31). OS device backup was not evaluated. | Explain inventory-transfer versus full-recovery scope in Settings. A complete app archive/restore feature requires a separate product decision; CSV tests do not certify it. |
| Privacy/support publication | Checked-in [build settings](../../TradingCardScanner.xcodeproj/project.pbxproj) leave both URL settings empty; the settings screen shows unavailable text. The owner previously deferred publication/configuration. | Preserve that deferral during development; close before submission. Apple's [guidelines](https://developer.apple.com/app-store/review/guidelines/#privacy) require an accessible privacy-policy link. |
| StoreKit distribution evidence | [CollectorToolsStore](../../TradingCardScanner/Services/CollectorToolsStore.swift) contains verified delivery, entitlement/update handling and Restore. No App Store Connect account or real purchase was checked in this pass. | Verify actual product availability, localized price, purchase/restore and reviewer access in the distribution candidate. Do not label the source implementation missing. |

## HIG quality pass, then App Store risk pass

| HIG category | Review result |
| --- | --- |
| Navigation/information architecture | FC03 identifies an unexplained unavailable action. Other navigation was source-traced at entry points, not newly rendered. |
| Clarity/feedback | FC05 shows unavailable history despite an admitted mapping; FC02/FC04 identify offline/setup expectations that exceed the explanation provided. |
| Controls/touch | No new hit-target or gesture finding established; no new touch test performed. |
| Visual hierarchy/accessibility | Existing styles/labels inspected at affected controls; larger text, VoiceOver and screenshot acceptance remain unverified in this pass. |
| Platform/layout resilience | No new iPad/orientation finding established; those configurations were not run. |

App Store risk scan: broken normal-app raw history (FC05), provider-permission
architecture (FC01), declared game scope
versus the distribution binary, legal/support configuration and real IAP access
need release evidence. Camera/photo descriptions, privacy manifest and a StoreKit
purchase/restore implementation exist. No first-party account creation was found
in the reviewed entry paths, so a missing account-deletion screen is not asserted.
Source existence does not certify privacy metadata, purchase delivery or hardware
behavior. See Apple's [completeness and third-party-service guidance](https://developer.apple.com/app-store/review/guidelines/).

## Fix-first and submission checks

**Release blockers for the advertised scope:** repair normal Lorcana history if
it is offered; establish a permitted provider-access path for FC01; close the
existing legal/support and actual distribution-game gates before submission.
Real IAP availability also needs candidate evidence. These are scoped readiness
conditions, not a claim that Apple has rejected the app or that the owner has
authorized the previously deferred publication work.

1. Repair FC05's normal-registration history path and verify it through the
   actual catalog wrapper, including mapped, unmapped and withdrawn listings.
2. Resolve FC01's provider-access mismatch across all three consumers; obtain the
   permitted path before investing in more direct-device pricing coverage.
3. Fix FC03/FC04's capability and setup explanations, and FC02's offline promise.
4. Make an explicit scope decision for Lorcana later sets and graded parity;
   complete the approved One Piece distribution path before a five-game claim.
5. Preserve the owner-controlled publication deferrals until authorized, then
   verify URLs, provider commercial access and StoreKit in the actual candidate.

Before submission, exercise at least one successful and one unavailable case per
supported game for scan → physical choice → save → reopen → price/refresh →
history; repeat with no key and offline conditions. Use real provider responses
for listing coverage and actual distribution configuration for game availability.
Verify CSV inventory transfer separately from any full-recovery promise.

Open evidence: provider permission or permitted replacement for FC01; actual
per-game listing coverage; cold/offline device behavior; graded expansion scope;
physical cards and accessibility; distribution/IAP/legal-page acceptance. These
are not inferred green from this audit or earlier test totals.

## Reproducible checks performed

A read-only Python census decoded the bundled Lorcana discovery/physical JSON and
asserted: 3,582 discovery rows; 1,749 physical rows; physical set codes exactly
1–8; 1,460 discovery rows in sets 9–14; 1,748 physical rows with mappings; 3,364
mapping lanes; and the checked-in disabled One Piece production mode. All seven
assertions passed. The optional Lorcana Browse-price resource is absent. The
Yu-Gi-Oh! seed census separately counted 46,542 records and 46,303 with explicit
membership under the loader's recorded fields. Runtime family admission remains
an additional check, not bypassed by these counts.

At the audit-only checkpoint, application code, credentials, collection data,
deployment and release configuration were unchanged. The remediation changes and
their current verification/activation limits are recorded above. Documentation
links and whitespace are checked separately.
