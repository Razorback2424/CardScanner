# Browse Pricing Coverage — Revised Stage 4 Implementation Plan

**Implementation status — 2026-09-22:** Stage 4A is implemented in the current
working tree: Browse-only quote normalization, UTC/provider-day handling,
versioned finish descriptors, device-local per-set history, 90-day retention,
Scryfall dataset-stamp provenance, chart rendering, settings diagnostics, and
focused regression coverage are landed. The focused history, Browse, and
pricing selection passed 104/104 on the iPhone 17 Pro iOS 26.5 simulator. The
full baseline after the Phase 0 compile repair was 1,442 passed, 18 failed, and
6 skipped; the failures are existing centering, fixture, Keychain-environment,
and one legacy pricing-expectation failure, not Stage 4A failures. Phase 6.0
remains unresolved: the current TCGdex service has no supported set-level
pricing response, so pokemontcg.io remains authoritative and no TCGdex cutover
is claimed. Stage 4B remains disabled.

## Final architectural decision

Split the current Stage 4 into two separate capabilities:

**Stage 4A — Device-Local Browse Price History**

Implement now. Provider pricing is fetched directly by the user's device using the existing Browse provider paths, normalized locally, and retained in a new local-only Browse history store. ScanStash infrastructure never receives, aggregates, or redistributes those prices.

**Stage 4B — Published Browse Price Snapshots**

Remain blocked. This is the existing proposed `catalog.scan-stash.com/v1/prices/...` architecture. Do not create its publisher, hosting resources, scheduled jobs, or CDN artifacts until redistribution permission is established for the actual underlying pricing data.

This preserves the original Stage 4 objective without pretending that local history is equivalent to centrally supplied history. The original plan correctly identifies server publication as redistribution and places it behind a licensing gate.

The legal/risk rationale for 4A is therefore:

`provider → user's device → local ScanStash feature`

rather than:

`provider → ScanStash infrastructure → ScanStash users`

Do **not** describe TCGdex, Scryfall, or pokemontcg.io as conferring blanket downstream redistribution rights. TCGdex's `price-history` repository says its database is MIT-licensed, but that does not by itself establish that the live `api.tcgdex.net/v2` pricing response carries the same downstream rights or cure any upstream TCGplayer restrictions.

Likewise, TCGplayer's published API terms expressly restrict obtaining TCGplayer information from third parties that collected it through its API or automated means, as well as redistribution and several commercial uses. That upstream provenance concern remains relevant to Stage 4B regardless of which intermediary exposes the number.

---

# Phase 0 — Restore a trustworthy test baseline

This is a prerequisite to Stage 4A.

The existing test-target failure around:

`CenteringExportTests.swift:941`

and the nonexistent:

`CardCenteringMeasurement.confirmManualPlacement()`

must be resolved before implementing the persistence layer.

Do not add a dummy `confirmManualPlacement()` API simply to make the test compile.

Instead:

1. Inspect the current manual-placement API on `CardCenteringMeasurement`.
2. Inspect adjacent centering tests and the git history of the manual-placement refactor.
3. If the production behavior still exists under another API, update the stale test to exercise the current API.
4. If production functionality was accidentally removed, restore it in a separate centering fix before touching Browse pricing.
5. Run the full test target.
6. Establish the resulting pass/fail/skip count as the Stage 4A baseline.
7. Enumerate any pre-existing failures that remain after the stale compile break is repaired so Stage 4A can distinguish new regressions from existing unrelated failures.

No Stage 4A implementation should be considered complete merely because the app target builds.

---

# Phase 1 — Introduce a completely separate Browse-history domain

## 1.1 Do not modify the owned-card `PriceSnapshotStore`

`Services/PriceSnapshotStore.swift` remains the owned-collection pricing channel.

Stage 4A must not:

- insert Browse prices into `PriceSnapshotStore`;
- create `PriceObservation` rows from Browse prices;
- create or mutate `PriceCheckDay`;
- participate in `BackgroundPriceRefresh` for the owned portfolio;
- affect Portfolio valuation;
- write anything to the existing SwiftData container used by the portfolio ledger.

That separation should be enforced in code and tests.

## 1.2 Add new types

Create:

`Models/BrowsePriceHistoryModels.swift`

Define a Browse-specific market-source subset rather than persisting the existing unrestricted `PriceSource`.

```swift
enum BrowsePriceMarketSource: String, Codable, Sendable {
    case tcgplayer
    case scryfall
}
```

Do not accept `.cardmarket`, `.justTCG`, `.importedCSV`, or any other `PriceSource` into Stage 4A history.

The conversion boundary from existing pricing objects to `BrowsePriceQuote` must explicitly reject any source outside this subset. A rejected source must not create a history point.

This makes Stage 1's USD-only/source boundary structural rather than dependent on every caller remembering it.

Define a normalized Browse-specific quote:

```swift
struct BrowsePriceQuote: Sendable, Hashable {
    let printingID: String
    let setID: String
    let variant: PhysicalVariant

    let amountUSD: Double

    let marketSource: BrowsePriceMarketSource
    let transportProvider: BrowsePriceTransport

    let providerUpdatedAt: Date
    let quoteDay: BrowsePriceDay
}
```

`printingID` must represent the stable ScanStash Browse printing identity, not merely an API request URL or transient provider record.

Define:

```swift
enum BrowsePriceTransport: String, Codable, Sendable {
    case scryfall
    case pokemonTCGIO
    case tcgdex
}
```

Keep `marketSource` separate from `transportProvider`.

For example:

TCGplayer price delivered by pokemontcg.io:

`marketSource = .tcgplayer`
`transportProvider = .pokemonTCGIO`

The equivalent TCGplayer price later delivered by TCGdex:

`marketSource = .tcgplayer`
`transportProvider = .tcgdex`

That allows the visible price series to remain continuous after a future provider cutover while still preserving provenance.

## 1.3 Define a stable, versioned series key

Do **not** persist `PhysicalVariant` directly inside the history key.

`PhysicalVariant` currently relies on synthesized `Codable`. A future field addition or encoding-shape change could change its persisted representation and silently split an existing price series.

Instead create an explicit versioned persistence descriptor.

For example:

```swift
struct BrowsePriceVariantDescriptor: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let value: String
}
```

For Stage 4A v1:

`schemaVersion = 1`

Add one canonical conversion function:

```swift
extension PhysicalVariant {
    var browsePriceHistoryDescriptorV1: BrowsePriceVariantDescriptor
}
```

The conversion must:

- explicitly map every currently supported pricing-relevant physical variant;
- produce one stable canonical string for each semantic variant;
- never use `String(describing:)`;
- never encode the raw struct automatically;
- never silently fall back to a generic `"unknown"` key.

If a new `PhysicalVariant` configuration cannot be represented by the v1 mapping, history recording must fail closed for that variant until the persistence descriptor is deliberately extended or versioned.

Create the series key as:

```swift
struct BrowsePriceSeriesKey: Codable, Hashable, Sendable {
    let printingID: String
    let variantDescriptor: BrowsePriceVariantDescriptor
    let marketSource: BrowsePriceMarketSource
}
```

Do not include `transportProvider` in this key.

Provider transport belongs on individual observations.

Add regression tests that pin the exact v1 descriptor emitted for every currently supported pricing-relevant variant. Those tests exist specifically to prevent a future `PhysicalVariant` refactor from silently changing persisted history identity.

## 1.4 Define the persisted observation

```swift
struct BrowsePriceHistoryPoint: Codable, Hashable, Sendable {
    let day: BrowsePriceDay
    let amountUSD: Double
    let providerUpdatedAt: Date
    let transportProvider: BrowsePriceTransport
}
```

Use a date-only UTC representation for `BrowsePriceDay`, not a local `Date` truncated in the user's timezone.

The uniqueness constraint is:

`series key + quote day`

There must never be two visible observations for the same pricing series on the same provider day.

---

# Phase 2 — Create `BrowsePriceHistoryStore`

Add:

`Services/BrowsePriceHistoryStore.swift`

Implement it as an `actor`, not `@MainActor`.

Its only responsibility is local Browse price-history persistence.

## 2.1 Storage location

Store files under Application Support in a dedicated namespace, for example:

`Application Support/ScanStash/BrowsePriceHistory/v1/`

Use one file per set.

Do not put these files inside the existing 5 MB / 10 MB Browse response caches.

Those existing caches are disposable performance caches with 24-hour freshness behavior. The history store is a different persistence class and must not disappear because an unrelated cache trimmer runs.

## 2.2 No CloudKit in Stage 4A

Stage 4A history is device-local.

Do not:

- add the models to the current SwiftData/CloudKit container;
- synchronize history through CloudKit;
- create a private CloudKit record type;
- upload it through any ScanStash service.

Mark the history directory as excluded from backup.

The explicit Stage 4A behavior is therefore:

**Delete/reinstall ScanStash → Browse history starts over.**

That limitation should be accepted deliberately rather than accidentally introducing another redistribution/synchronization surface.

Cloud synchronization can be separately reviewed later.

## 2.3 Set-file layout

Persist data grouped by series rather than repeating card metadata on every daily observation.

Conceptually:

```swift
struct BrowsePriceHistorySetFile: Codable {
    let schemaVersion: Int
    let game: CardGame
    let setID: String

    var lastAccessedAt: Date
    var series: [BrowsePricePersistedSeries]
}

struct BrowsePricePersistedSeries: Codable {
    let key: BrowsePriceSeriesKey
    var points: [BrowsePriceHistoryPoint]
}
```

Set `schemaVersion = 1`.

Writes must be atomic:

1. encode to a temporary file;
2. fsync/close;
3. atomically replace the previous set file.

A corrupt set file must not break the global history store. Quarantine or delete that single file, emit diagnostics, and continue.

## 2.4 Deduplication behavior

When recording a quote:

If no point exists for that series/day:

→ append it.

If the same day already exists with the same `providerUpdatedAt`:

→ no-op.

If the same day exists and the new quote has a later `providerUpdatedAt`:

→ replace that day's observation.

If the new observation is older:

→ ignore it.

During Pokémon shadow comparison, the shadow provider must **not** write into user history. Only whichever provider is currently authoritative for Browse pricing writes history.

That prevents alternating providers from modifying the same day's user-visible history.

## 2.5 Ninety-day retention

Retain 90 provider days per set.

When writing a set:

1. determine the newest `quoteDay` represented in that set;
2. remove observations older than 89 calendar days before it;
3. remove empty series.

Do not use the device wall clock as the sole retention anchor.

This protects the store against incorrect device clocks and irregular provider updates.

## 2.6 No global hydration

Do not populate history for every Pokémon or Magic set.

History eligibility in Stage 4A is limited to:

- sets the user explicitly opens in Browse.

Browsing the game-wide set directory must not cause all sets to start accumulating price history.

Search results must not silently hydrate every set represented in those results.

A card being scanned into the collection must not automatically create Browse history unless the user independently opens that set through the Browse pricing flow.

A future favorites feature may add another explicit eligibility signal, but favorites are not part of Stage 4A and must not be assumed by this implementation.

---

# Phase 3 — Normalize provider timestamps correctly

Fetch time and price date are separate concepts.

Current cache freshness can continue using fetch time.

Historical observations must use the provider's data-update date.

Add:

`Services/BrowsePriceObservationDayResolver.swift`

Its output is:

```swift
struct ResolvedBrowsePriceDay {
    let day: BrowsePriceDay
    let providerUpdatedAt: Date
}
```

## 3.1 pokemontcg.io

The current `PokemonTCGBulkTCGPlayer` model decodes only `prices`.

Extend that model to decode the provider's existing:

`tcgplayer.updatedAt`

field from the same `select=id,number,tcgplayer` bulk response.

This is a model/decode addition, not an additional API request.

Use `tcgplayer.updatedAt` as the historical observation timestamp.

Never use the HTTP fetch timestamp in its place.

If `updatedAt` cannot be parsed:

- current price remains usable;
- do not append that price to historical storage;
- record a diagnostic gap.

### Bulk-cache migration

Existing `PokemonBulkPriceMap` cache files written before Stage 4A do not contain the new provider timestamp.

Do not allow those legacy cache files to remain valid for Stage 4A history and silently produce no history for up to the existing 24-hour cache lifetime.

Bump the Pokémon bulk-price cache schema/version as part of Stage 4A.

On first use after upgrade:

1. an old-schema bulk-price cache is treated as incompatible for the new Stage 4A path;
2. the existing bulk request is performed;
3. prices and `updatedAt` are decoded together;
4. the refreshed current-price map is cached using the new schema;
5. eligible historical observations can then be recorded immediately.

This intentionally causes a one-time bulk refresh for previously cached Pokémon sets after the Stage 4A upgrade.

It does **not** alter the ordinary 24-hour freshness policy after migration.

## 3.2 TCGdex

Use the existing TCGdex pricing-level `updated` field already decoded by `TCGdexCard`.

Do not use card metadata update timestamps.

The relevant timestamp is the price-provider timestamp associated with `pricing.tcgplayer`.

Normalize it to UTC before deriving `BrowsePriceDay`.

## 3.3 Scryfall

Do not manufacture a per-card price date from the user's fetch time.

Because the individual Scryfall card price response does not provide the same explicit per-price date, add a tiny globally cached dataset-stamp lookup.

Create:

`Services/ScryfallDatasetStampCache.swift`

Once per 24 hours at most, query Scryfall's bulk-data metadata and retain the relevant bulk dataset's `updated_at`.

Use that `updated_at` as the dataset observation stamp for Scryfall pricing fetched during that refresh window.

This stamp is explicitly an **approximation of the Scryfall dataset day**, not authoritative per-card price provenance.

Browse pricing itself arrives through the card-search pipeline, while the timestamp comes from the separately published bulk-data metadata. Those two publication pipelines can cross a refresh boundary at slightly different times, including around UTC day changes.

The intended semantics are therefore:

> This price was observed from Scryfall during the pricing cycle associated with this approximate Scryfall dataset update day.

Do not represent it internally or in diagnostics as a guaranteed exact timestamp for the individual card's marketplace price.

The existing same-day conflict rule in Phase 2.4 absorbs ordinary disagreement:

- if a later refresh for the same dataset day carries a later `providerUpdatedAt`, it replaces the earlier point;
- an older observation cannot overwrite a newer one.

If the dataset stamp cannot be obtained:

- current Scryfall pricing may still display from the existing path;
- skip the historical append for that refresh;
- do not substitute `Date()`.

That creates a missing day rather than false history.

Missing history is preferable to fabricated chronology.

---

# Phase 4 — Record history from the existing Stage 2 pipeline

Do not create another pricing fetch layer.

Stages 2 and 3 already solved the expensive request topology and retry problem. The current plan intentionally retains those mechanisms even if Stage 4 changes.

Stage 4A should attach **after successful normalization** of those existing responses.

The flow becomes:

```text
Provider request
      ↓
Existing Stage 2 response/cache
      ↓
Existing exact-finish normalization
      ↓
Current Browse price map
      ↓
BrowsePriceQuote conversion
      ↓
BrowsePriceHistoryStore.record(...)
```

Historical persistence must never be required for the current-price operation to succeed.

If the history write fails:

- Browse still displays current pricing;
- sorting still works;
- retry logic still works;
- emit a diagnostic;
- do not surface the storage error as a pricing-network failure.

---

# Phase 5 — Magic integration

The current Magic Stage 2 path already persists the Scryfall USD price map.

Do not replace that path.

After a successful Magic price-map refresh:

1. resolve the approximate Scryfall dataset update stamp;
2. walk the successfully normalized USD pricing entries;
3. create `BrowsePriceQuote` values;
4. record them in `BrowsePriceHistoryStore`.

Use the same exact card/finish identity already used by Browse.

Do not create history entries for unavailable finishes.

Do not translate non-USD values.

Do not infer one finish's value from another.

## Magic licensing/product rule

All Scryfall-backed Browse pricing and Scryfall-backed history must remain accessible without a subscription/IAP entitlement.

Therefore:

- current Magic Browse prices: free;
- Magic Browse price history: free;
- Magic chart access: free;
- no future Pro gate may be wrapped around the Scryfall data itself.

ScanStash can still monetize unrelated integrity, collection-management, verification, or workflow functionality.

There is currently no StoreKit, purchase, or paid-entitlement system in the codebase, so do **not** add an entitlement regression test as part of Stage 4A.

Instead:

1. record the Scryfall no-paywall requirement as a permanent product/legal constraint in the pricing architecture documentation now;
2. reference that constraint from the Browse pricing implementation where appropriate;
3. when monetization, StoreKit, subscriptions, or feature-entitlement logic is introduced later, require an automated regression test proving that free users retain access to Scryfall-derived current prices and Browse history.

No Stage 4A change should increase Magic refresh frequency beyond the existing 24-hour pricing cadence.

---

# Phase 6 — Pokémon provider architecture

Stage 4A is **not** a reason to immediately replace pokemontcg.io.

The existing Stage 2 implementation already has an important invariant:

> never borrow another finish's number.

Preserve it.

## 6.0 Establish whether a viable TCGdex bulk pricing path exists

Before treating TCGdex as a production replacement for pokemontcg.io, establish whether TCGdex can retrieve pricing at set-level efficiency.

The current code does **not** establish this.

`fetchSet` returns a `TCGdexSetCatalog` containing `TCGdexCardBrief` entries with identity/catalog fields but no pricing.

Current TCGdex pricing reaches ScanStash through per-card `fetchCard` calls.

Therefore do not assume that TCGdex can replace the existing Stage 2 bulk Pokémon price request without restoring the original one-request-per-card failure mode.

This is a hard feasibility gate.

### Investigation requirements

Determine whether the current TCGdex API offers any supported mechanism that can retrieve pricing for an entire set, or an equivalently bounded batch, without one network request per card.

Specifically investigate:

- a documented set expansion/include option;
- a set endpoint that returns full card objects with pricing rather than briefs;
- a batch-card endpoint;
- a price-specific bulk endpoint;
- a downloadable dataset suitable for client-side set extraction;
- any supported query mechanism that can return all card pricing for a known set in a small bounded number of requests.

The acceptable Stage 2 performance target remains approximately set-level retrieval, not N requests for N cards.

### Feasibility outcome A — viable bulk/set pricing exists

If a supported TCGdex mechanism can retrieve a set's pricing in a bounded number of requests comparable to the current Stage 2 behavior:

- document the endpoint and response contract;
- benchmark representative large sets;
- proceed with Phases 6.2–6.4 using that retrieval path.

### Feasibility outcome B — no viable bulk/set pricing exists

If TCGdex pricing still requires one `fetchCard` request per card:

**TCGdex is not the settled pokemontcg.io replacement.**

Do not cut production Browse pricing over to it.

Do not accept a regression from approximately 2 requests per large set back to hundreds of requests.

The long-term Pokémon migration target then remains unresolved.

Candidate directions become:

1. the MIT-licensed `tcgdex/price-history` dataset, **if** a legally and operationally acceptable delivery mechanism can be established;
2. Scrydex or another provider, accepting that this introduces cost;
3. another future provider offering set/bulk pricing;
4. Stage 4B infrastructure if redistribution licensing is eventually cleared.

The `price-history` dataset must not be treated as an automatic workaround. Efficiently delivering subsets of that dataset may require ScanStash infrastructure, which returns the design to the Stage 4B redistribution/licensing gate.

The output of Phase 6.0 must therefore be one of:

`TCGdex bulk path verified`

or:

`Pokémon successor unresolved`

—not “TCGdex is the replacement” by assumption.

## 6.1 Keep pokemontcg.io authoritative initially

Continue using the existing per-set bulk request for production Browse pricing.

After normalization, write its authoritative values into `BrowsePriceHistoryStore`.

Use its `tcgplayer.updatedAt` as the observation date.

Do not add any new feature dependency on this service.

The service is deprecated, new registration is closed, and existing API keys stop functioning on **March 1, 2027**.

Treat that as a hard migration deadline.

## 6.2 Build one provider-neutral variant normalizer

If TCGdex remains a viable production candidate after Phase 6.0, add:

`Services/PokemonPriceVariantNormalizer.swift`

It should expose separate inputs but a common output:

```swift
func normalizePokemonTCGIO(...)
    -> [PhysicalVariant: NormalizedUSDQuote]

func normalizeTCGdex(...)
    -> [PhysicalVariant: NormalizedUSDQuote]
```

pokemontcg.io inputs include:

- `normal`
- `holofoil`
- `reverseHolofoil`
- `1stEditionHolofoil`
- `1stEditionNormal` where present

TCGdex uses a different naming vocabulary.

Map each key explicitly.

Never implement fuzzy fallback such as:

`reverse missing → use holo`

or:

`holo missing → use normal`.

An unmapped provider finish becomes `.unavailable` and enters `PriceCoverageGapLog`.

## 6.3 Shadow TCGdex before any production cutover

If Phase 6.0 establishes TCGdex as technically viable for production set-level pricing, compare its results against the still-authoritative pokemontcg.io path before changing user-visible authority.

Do **not** base this comparison only on cards for which the normal app flow happens to obtain both provider payloads.

That sample would be biased toward detail views, fallbacks, and cards whose normal bulk path already had unusual conditions.

Create an explicit developer-facing coverage-evaluation harness.

It may run manually or as a dedicated integration diagnostic, but it must not become normal production hydration.

### Required representative set sample

Use a fixed, named suite covering materially different Pokémon pricing shapes.

At minimum include:

- **Base Set** — vintage and first-edition behavior;
- **Jungle** — another vintage set with first-edition/unlimited differences;
- **Scarlet & Violet** — standard modern set structure;
- **151** — modern special-set behavior;
- **Prismatic Evolutions** — modern special/high-demand set with varied treatments;
- **Destined Rivals** — current large modern-set behavior.

Resolve and pin the corresponding provider set IDs in the coverage test configuration rather than relying on name search at runtime.

If provider naming differs, document the exact resolved IDs beside the human-readable names.

### Minimum evaluated population

For each named set:

- evaluate **all expected printing + finish combinations** if practical;
- never evaluate fewer than **100 expected printing + finish combinations** for a set containing at least 100;
- if the entire set contains fewer than 100 expected combinations, evaluate the entire set.

Sampling must not stop after the first successfully matched cards.

The evaluation population should be determined from ScanStash's authoritative catalog/variant expectations before looking at whether either provider has a price.

This prevents provider omissions from shrinking the denominator.

### Metrics per set

For each representative set, independently collect:

- total expected printing+finish combinations;
- priced by pokemontcg.io;
- priced by TCGdex;
- priced by both;
- pokemontcg.io-only;
- TCGdex-only;
- neither;
- unmappable TCGdex variant keys;
- values where both providers claim the same market source and price date but differ materially.

Do not report only one pooled cross-set percentage.

Each set must retain its own numerator, denominator, and coverage result.

The shadow comparison remains diagnostic only.

TCGdex values must not replace user-visible production values or write history until the provider is formally switched.

## 6.4 Migration acceptance gate

A TCGdex cutover is eligible for consideration only if Phase 6.0 first establishes a viable bounded set-level pricing retrieval path.

Do not cut Pokémon Stage 2 over to TCGdex until all of the following are true:

1. exact-finish unit tests exist for every supported provider key;
2. no test permits cross-finish borrowing;
3. representative modern, special-set, vintage, reverse-holo and first-edition cases are covered;
4. no systematic variant-mapping errors exist;
5. on **each individual representative set** defined in Phase 6.3, TCGdex retains at least 99% of the printing+finish combinations that the authoritative pokemontcg.io path prices;
6. no individual set may rely on pooled strength from other sets to hide a weak result;
7. the minimum sample-size requirements in Phase 6.3 were actually met for every set;
8. remaining regressions are enumerated in `PriceCoverageGapLog`;
9. the production TCGdex retrieval path preserves Stage 2's bounded per-set request behavior rather than falling back to one request per card;
10. the Browse UI behaves identically when the authoritative transport changes.

After a verified cutover:

`transportProvider` changes from `.pokemonTCGIO` to `.tcgdex`.

The visible history series does not reset because its identity is based on:

`printing + persisted variant descriptor + market source`

rather than the transport API.

If Phase 6.0 cannot establish a viable bulk TCGdex retrieval path, this cutover section remains inactive and the provider-successor decision stays unresolved.

## 6.5 Do not treat TCGdex as license-cleared Stage 4B data

TCGdex may still be usable as an on-device provider or comparison source while Stage 4B remains blocked.

The separate `price-history` repository declaring its database MIT does not eliminate the need to resolve upstream provenance before ScanStash itself republishes those values.

That distinction should be recorded in the project documentation.

---

# Phase 7 — Browse history UI

Stage 4A unlocks a real provider-history chart, but **not immediate historical parity on a fresh install**.

The original Stage 5 correctly separates current price, movement, and history.

## 7.1 Do not feed Browse history into owned history

Reuse chart rendering concepts from `PriceHistoryChartView`, but do not construct `PriceObservation` objects to satisfy it.

Preferred implementation:

Add:

`BrowsePriceHistoryChartModel`

and, if necessary:

`BrowsePriceHistoryChartView`

Share low-level visual helpers with the existing chart, but keep the data models separate.

## 7.2 Chart requirements

Display a chart only when at least two distinct provider observation days exist.

One observation:

> Price history starts as this set is refreshed.

Two or more:

show the available history.

## 7.3 Irregular history must remain irregular

Never interpolate missing days.

If points exist on:

Sep 22
Sep 23
Sep 27
Sep 28

render:

Sep 22 → Sep 23

and separately:

Sep 27 → Sep 28

Do not draw a continuous line from Sep 23 to Sep 27.

Build contiguous `ChartSegment`s where adjacent `BrowsePriceDay` values differ by exactly one day.

Each segment renders independently.

This also means calculated trend indicators must not pretend a missing seven-day sample is a seven-day continuous series.

## 7.4 History metadata

Under or near the chart, expose concise provenance/freshness information such as:

`8 observations since Sep 22`

or:

`History available from Sep 22`

The UI should distinguish:

- provider price date;
- local cache freshness.

A value fetched today but last updated by the provider yesterday is still yesterday's market observation.

For Scryfall, the underlying day is the approximate dataset day defined in Phase 3.3 rather than an exact per-card price timestamp.

## 7.5 Current price behavior remains unchanged

Current price should continue coming from the Stage 2 current-price cache.

History storage must not become the canonical current-price source.

That prevents a missed history write from making current Browse pricing disappear.

---

# Phase 8 — Do not claim Stage 4A fully unlocks movement

Revise the earlier statement that 4A unlocks “most of Stage 5.”

More precise status:

**Current price** — already enabled by Stage 2.

**History chart** — enabled progressively by Stage 4A.

**Movement pill** — remains on the separate provider/statistics path currently described in Stage 5.

Do not silently replace the JustTCG-backed movement calculation with a homemade percentage from sparse local observations in this phase.

A future local-derived movement feature could be considered separately once enough history exists, but it would need rules for irregular dates and should be labeled as ScanStash-calculated rather than provider-supplied movement.

---

# Phase 9 — Refresh and hydration policy

The app must not become a systematic full-dataset collector.

## Set opening

When the user opens a set:

1. immediately load existing current prices from the Stage 2 disk cache;
2. load local history from `BrowsePriceHistoryStore`;
3. render both without waiting for network;
4. if the current-price cache is older than its existing freshness threshold, run the existing price refresh;
5. after the provider response succeeds, update the current cache;
6. append eligible normalized quotes to local history;
7. refresh the chart model.

## Stage 4A eligibility

A set becomes eligible for Stage 4A history only when the user explicitly opens that set in Browse.

There is no favorites prerequisite and no favorites-driven refresh path in Stage 4A because no favorites feature currently exists.

If a future favorites feature is implemented, its interaction with Browse history should be designed separately rather than being implicitly assumed here.

## Set directory

Opening the Pokémon or Magic set-directory screen does not fetch prices for every set.

## Search

Global search does not cause history hydration for every returned card/set.

## Portfolio

Portfolio background pricing does not populate Browse history incidentally.

---

# Phase 10 — Diagnostics

Extend the existing pricing diagnostics rather than making failures invisible.

Add a Browse-history diagnostics section reporting:

- number of sets with local history;
- total local history bytes;
- oldest retained provider day;
- newest retained provider day;
- corrupt-file recovery count;
- skipped history writes because provider timestamp was missing;
- deduplicated observation count;
- Pokémon shadow-provider coverage summary;
- provider variant keys that could not be mapped.

Continue using `PriceCoverageGapLog` for unpriced `printing + finish` combinations.

Do not mix local Browse-history diagnostics into the owned portfolio price-refresh diagnostics.

---

# Phase 11 — Tests

Create focused tests before enabling the history UI.

## `BrowsePriceHistoryStoreTests`

Cover:

- first observation persists;
- same series/day/provider timestamp is idempotent;
- newer observation on the same provider day replaces the earlier value;
- older same-day response cannot overwrite newer data;
- day 91 prunes day 1;
- separate finishes remain separate;
- separate market sources remain separate;
- transport migration from pokemontcg.io to a future replacement transport does not create a second visible series;
- unsupported `PriceSource` values cannot become Browse history;
- corrupt set file does not destroy other sets;
- history store does not interact with `PriceSnapshotStore`;
- deleting history leaves portfolio pricing untouched.

## `BrowsePriceVariantDescriptorTests`

Pin the exact v1 persisted descriptor produced for every currently supported pricing-relevant `PhysicalVariant`.

Verify:

- equivalent semantic variants always produce the same descriptor;
- adding unrelated runtime metadata cannot alter the descriptor;
- unsupported/unrepresentable variant configurations fail closed;
- persisted identity does not depend on synthesized `PhysicalVariant.Codable`.

## `BrowsePriceObservationDayResolverTests`

Cover:

- pokemontcg.io `YYYY/MM/DD`;
- TCGdex timestamp normalization where applicable;
- UTC boundary around midnight;
- Scryfall bulk `updated_at`;
- Scryfall stamp is treated as approximate dataset provenance rather than a per-card timestamp;
- missing/invalid timestamp returns no historical observation rather than fetch-date fallback.

## Pokémon bulk-cache migration tests

Verify:

- a pre-Stage-4A bulk cache without `updatedAt` is treated as old schema;
- the old cache triggers one provider refresh;
- the refreshed cache stores both current pricing and provider update metadata;
- subsequent reads obey the normal 24-hour cache policy;
- current pricing remains available if historical timestamp parsing later fails.

## `PokemonPriceVariantNormalizerTests`

Carry forward all current exact-finish Stage 2 cases and add replacement-provider fixtures if Phase 6.0 identifies a viable provider.

Assert specifically:

- normal never fills holo;
- holo never fills reverse;
- reverse never fills normal;
- first-edition never borrows unlimited;
- unknown provider keys generate a gap rather than being guessed.

## `PokemonPricingCoverageComparatorTests`

If TCGdex remains a viable candidate after Phase 6.0, verify:

- every named representative set is evaluated separately;
- the denominator comes from expected ScanStash printing+finish combinations;
- minimum per-set sample requirements are enforced;
- overlap metrics;
- TCGdex-only;
- legacy-only;
- neither-provider coverage;
- unmapped finish;
- duplicate provider records;
- pooled coverage cannot satisfy a failed per-set threshold;
- comparison never changes production output.

## Chart tests

Verify:

- one point produces insufficient-history state;
- two consecutive points produce one line segment;
- a missing date breaks the segment;
- 90-day retention renders correctly;
- stale current price does not alter historical timestamps.

## Future monetization test requirement

Do not add a StoreKit/entitlement test in Stage 4A because the application has no paid-entitlement system today.

Record a mandatory future test requirement alongside the Scryfall no-paywall product rule:

When monetization or entitlement infrastructure is introduced, its test suite must prove that users without a paid entitlement retain access to Scryfall-derived:

- current Browse prices;
- per-finish Magic pricing;
- local Browse price history.

## Network behavior tests

Verify that:

- opening one set hydrates only that set;
- set-directory browsing does not issue price-history hydration calls;
- search results do not hydrate unrelated sets;
- re-opening within freshness limits performs no unnecessary provider request;
- Low Power Mode behavior remains unchanged;
- history writes do not trigger provider calls themselves.

Finally run:

- focused pricing tests;
- Browse tests;
- persistence tests;
- full app test target.

Compare the results against the Phase 0 baseline rather than requiring unrelated pre-existing failures to disappear.

---

# Phase 12 — Stage 4B remains a hard gate

Do not implement the original server artifacts yet:

`v1/prices/<providerSetID>.json`

Do not create:

- AWS publisher jobs;
- Firebase publisher jobs;
- scheduled provider harvesting;
- CDN price directories;
- server-side historical price databases.

The app architecture should nonetheless leave a future insertion point.

Future precedence can be:

```text
licensed Stage 4B snapshot
        ↓ if unavailable/stale
existing Stage 2 direct device provider fetch
        ↓
local Stage 4A history accumulation
```

But that first layer remains nonexistent until the licensing gate clears.

## Written permission questions

For every provider whose values would be published by ScanStash, obtain written confirmation covering all of these actions:

1. ScanStash infrastructure may retrieve the pricing data.
2. ScanStash may normalize it by card and physical variant.
3. ScanStash may cache it server-side.
4. ScanStash may redistribute the resulting value to ScanStash end users.
5. ScanStash may retain one observation per day.
6. ScanStash may distribute 30-/90-day historical series.
7. The use is allowed in a commercial application.
8. Required source attribution/linking is identified.
9. Any free-access/paywall restrictions are identified.
10. Permission covers the actual upstream marketplace data represented in the provider response.

For TCGdex specifically, ask whether the MIT license attached to `tcgdex/price-history` is intentionally meant to authorize commercial downstream redistribution of the relevant TCGplayer/TCGCSV-derived pricing observations.

For Scryfall, ask explicitly whether a normalized per-card daily market-price file served by ScanStash is permissible value-added use or prohibited republication/proxying.

For Scrydex, do not assume the successor relationship gives redistribution rights. Its terms must be evaluated separately.

Until those answers exist, Stage 4B stays disabled.

---

# Phase 13 — Revise the JustTCG/shared-cache wording

Replace the current implication that Browse's catalog-provider route eliminates the licensing question.

The new architectural statement should be:

> Browse does not depend on the JustTCG shared-pricing cache. Its live pricing path retrieves provider data directly on the user's device and retains limited device-local Browse history. Those device paths remain subject to each provider's terms, rate limits, attribution requirements, upstream provenance and service lifespan. Server-side redistribution of provider-derived pricing is independently gated by Stage 4B and requires permission for the actual pricing data, not merely technical API access.

That preserves the separation the current document intended at lines 30–45 while making the licensing distinction precise.

---

# Phase 14 — Pokémon deprecation milestone

Track the pokemontcg.io shutdown as an explicit release dependency:

**Hard external date: March 1, 2027.**

The provider should be removable before that date, not on that date.

Add a source-level deprecation comment adjacent to the pokemontcg.io client configuration containing:

- shutdown date;
- reference to the Phase 6.0 replacement feasibility gate;
- the currently selected successor only **after** a successor has actually cleared that gate;
- reference to the shadow coverage comparator if TCGdex remains the evaluated candidate.

Do not hard-code “TCGdex is the replacement” into that comment before Phase 6.0 establishes a viable bulk retrieval architecture.

Do not add an automatic date-triggered shutdown to production code.

A server date/time bug should not disable pricing.

Cut over only after a replacement has satisfied:

- bounded retrieval performance;
- exact-finish correctness;
- representative per-set coverage;
- operational readiness.

Then retain the old provider implementation behind a temporary rollback flag until confidence is established.

Remove the legacy path and API credential only after the replacement has been proven.

If TCGdex fails the Phase 6.0 feasibility gate, the migration task remains explicitly unresolved rather than accepting a one-request-per-card regression.

---

# Explicit non-goals for Stage 4A

Stage 4A does not:

- create complete historical pricing immediately after install;
- backfill prior months of market history;
- guarantee that every calendar day is present;
- make JustTCG unnecessary for its specialized statistics;
- establish server redistribution rights;
- turn TCGdex into a legally preferred provider;
- assume TCGdex is technically capable of replacing the existing Pokémon bulk-pricing path;
- sync Browse history between devices;
- alter owned-card portfolio history;
- globally prefetch every card/set;
- introduce a favorites system;
- hide Scryfall pricing/history behind Pro.

Those constraints are part of the design, not shortcomings to work around silently.

---

# Final execution order

Implement in this order:

**0. Repair the existing test-target compile failure and establish the regression baseline, including any pre-existing failures.**

**1. Add Browse price-history models, the restricted Browse market-source enum, stable v1 variant descriptors, and UTC/provider-day normalization.**

**2. Add the isolated `BrowsePriceHistoryStore` with 90-day retention, atomic persistence and no CloudKit.**

**3. Extend Pokémon bulk-cache decoding to retain `tcgplayer.updatedAt`, bump the cache schema, and hook pokemontcg.io and Scryfall's existing Stage 2 results into history recording.**

**4. Add Browse-history diagnostics.**

**5. Add the Browse history chart with explicit gap rendering.**

**6. Record the Scryfall no-paywall constraint as a permanent product requirement and defer its automated entitlement regression test until monetization infrastructure exists.**

**7. Run Phase 6.0 and determine whether TCGdex actually has a viable bulk/set-level pricing path.**

**8A. If TCGdex passes Phase 6.0, introduce the provider-neutral variant normalizer and the explicit representative-set coverage evaluation.**

**8B. If TCGdex fails Phase 6.0, leave pokemontcg.io authoritative and treat the successor provider as unresolved while evaluating the Stage 4B dataset path, Scrydex, or another bulk-capable provider.**

**9. Perform any Pokémon provider cutover only after the replacement satisfies bounded retrieval performance, exact-finish correctness, and the per-set coverage gate.**

**10. Keep Stage 4B untouched until written licensing clearance exists.**

---

# Definition of done

Stage 4A is complete only when all of these are true:

- the full test target shows **no regressions against the Phase 0 baseline**, with any unrelated pre-existing failures explicitly enumerated;
- `PriceSnapshotStore`, `PriceObservation` and `PriceCheckDay` remain untouched by Browse history;
- Browse histories survive ordinary app restarts;
- reinstall intentionally resets them;
- no ScanStash server receives provider price observations;
- exactly one historical point can exist per pricing series/provider day;
- persisted history identity uses the explicit versioned Browse variant descriptor rather than synthesized `PhysicalVariant.Codable`;
- only approved Browse USD market sources can enter the history store;
- pokemontcg.io historical timestamps are decoded from provider data, and legacy timestamp-less bulk caches are migrated through the schema bump;
- price dates come from provider/dataset update timestamps rather than ordinary fetch time;
- Scryfall's history timestamp is documented and treated as an approximate dataset-day stamp rather than exact per-card provenance;
- missing dates remain visible gaps;
- retention is independently managed at 90 days;
- directory-wide hydration does not occur;
- Stage 4A eligibility is based only on sets the user actually opens in Browse;
- the Scryfall no-paywall requirement is documented as a permanent product constraint, with the automated access test deferred until monetization infrastructure exists;
- current-price behavior and Stage 2 sorting do not regress;
- TCGdex is not treated as the Pokémon successor unless Phase 6.0 establishes a viable bounded set-level pricing path;
- any TCGdex coverage evaluation uses the fixed representative-set suite, satisfies the minimum per-set population, and evaluates the 99% threshold separately for every set rather than on pooled results;
- pokemontcg.io has a concrete replacement process before March 1, 2027, even if the successor itself remains unresolved after Phase 6.0;
- Stage 4B remains technically and operationally disabled.

That is the revised version I would implement.
