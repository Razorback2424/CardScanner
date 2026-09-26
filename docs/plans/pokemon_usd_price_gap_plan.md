# Pokémon USD Price Gaps — Validation and Free-Source Plan

**Status:** current proposal — 2026-09-26. Evidence and design only; no pricing
code is implemented by this document. It narrows Phase 6 of the
[Browse pricing coverage plan](browse_pricing_coverage_plan.md) for the
Mega Evolution-era gaps reported on 2026-09-26.

## Reported symptom

Browse reports no USD quote for any card in 30th Celebration or the 30th
Classic Collection. It also reports 5 unpriced slots in Pitch Black (194 of
199 priced), 5 in Chaos Rising, and 10 in Perfect Order.

## Validation

The price hosts (`api.pokemontcg.io`, `api.tcgdex.net`, `tcgcsv.com`,
`tcgplayer.com`) were blocked by the network policy of the environment used
for this audit. The evidence below therefore comes from provider **source
data** on GitHub and from the app's bundled checklist. Live response counts
still need a run from a network that can reach those hosts.

| Claim | Result | Evidence |
| --- | --- | --- |
| pokemontcg.io returns no `tcgplayer.prices` for the five sets | **Not re-verified here** | The earlier session reported 0 market values across 557 cards. Consistent with the provider's [data repository](https://github.com/PokemonTCG/pokemon-tcg-data) notice: the API goes offline on 2027-03-01, and routine card-data updates are "no longer the focus". |
| TCGdex has no TCGplayer price for 30th Celebration or the Classic Collection | **Root cause confirmed in source** | See [TCGdex set-level gap](#tcgdex-set-level-gap). |
| TCGdex offers a set-level (bulk) price path | **No — Phase 6.0 outcome B** | In `tcgdex/cards-database@a9bf1ef`, `GET /v2/{lang}/cards` maps every result through `toBrief` (id, localId, name, image). The GraphQL `Card` type has no pricing field. Pricing exists only on single-card responses. |
| TCGdex's MIT `price-history` dataset could substitute | **No** | Its last commit is 2025-06-09, before every set in this report. |
| Some Perfect Order and Chaos Rising gaps are app-side | **Confirmed: 5 of the 15 slots** | See [Phantom checklist slots](#phantom-checklist-slots). |
| Pitch Black's 5 gaps have a data cause | **Unexplained offline** | All 199 standard Pitch Black slots have a TCGplayer product ID in TCGdex source. The misses are live-pricing gaps: either TCGdex's price cache or TCGplayer has no market price for that subtype. |

### TCGdex set-level gap

TCGdex's server builds its TCGplayer price cache from **set-level** group IDs
only (`server/src/libs/providers/tcgplayer/index.ts`):

```ts
const products = sets.en
    .filter((it) => it?.thirdParty?.tcgplayer)
    .map((it) => it!.thirdParty!.tcgplayer)
// … provider.pricing.group(groupId) for each — via TCGCSV
```

Set-level `thirdParty` in `data/Mega Evolution/*.ts` at `a9bf1ef`:

| TCGdex set | id | TCGplayer group | Cards with product IDs |
| --- | --- | --- | --- |
| Perfect Order | `me03` | 24587 | 124 / 124 |
| Chaos Rising | `me04` | 24655 | 122 / 122 |
| Pitch Black | `me05` | 24688 | 120 / 120 |
| 30th Celebration | `30th` | **missing** | 157 / 161 |
| 30th Classic Collection | `30th-c` | **missing** | 30 / 30 |

The card files already carry per-variant TCGplayer product IDs. For example,
`30th Celebration/001.ts` lists `tcgplayer: 716435`. The server never fetches
those two groups, so every card in both sets returns `pricing.tcgplayer: null`.
This matches the report that no card in either set has a price.

### Phantom checklist slots

The bundled checklist includes standard slots for printings with no plain
English counterpart. TCGplayer does not price these under the set's product,
so they can never resolve:

| Set | Card | Slot | What TCGdex source lists |
| --- | --- | --- | --- |
| Perfect Order | 019 Dewgong | Normal | holo, reverse, and a **Prize Pack**-stamped normal with no TCGplayer ID |
| Perfect Order | 024 Aurorus | Normal | holo, reverse, a **set-logo**-stamped normal, and cosmos holo |
| Perfect Order | 028 Luxray | Normal | same shape as 024 |
| Perfect Order | 050 Gengar | Normal | same shape as 024 |
| Chaos Rising | 122 Mega Greninja ex | Holo | only a **gold-foil** holo (already a separate expanded slot) |

Cause: `TCGdexCard.catalogVariants` emits a plain base finish from the
`variants` booleans, and TCGdex's compiler sets those booleans from any
`variants_detailed` entry of that type, stamped or foiled.
`discriminatingStampVariants` applies only when a plain entry sits beside a
stamped one. A **lone** stamped or foiled entry therefore produces a plain slot.

That is correct for set-wide stamps: every 30th Celebration card carries
`30th-anniversary` and should stay a plain slot. It is wrong for promotional
stamps and for foil-only printings.

## Why Browse shows the gaps

1. The bulk request to pokemontcg.io (`PokemonTCGAPIService.fetchBulkPrices`)
   returns cards with no `prices`, so the bulk map is empty for the set.
2. Each slot falls back to a per-card TCGdex request (`sortPrice(for:)`):
   N requests for N cards.
3. That fallback succeeds only where TCGdex's server has cached the set's
   TCGplayer group. For 30th and 30th-c it never has.

Once pokemontcg.io goes offline on 2027-03-01, step 1 disappears for every
set, and all Pokémon Browse pricing becomes one TCGdex request per card.

## Plan (no paid subscription)

### Track A — TCGCSV set-level feed (primary fix)

[TCGCSV](https://tcgcsv.com) publishes TCGplayer's catalog and prices once a
day as static JSON, with no key or account. TCGdex's own server reads its
prices from TCGCSV (`server/src/libs/providers/tcgplayer/tcgcsv.ts`), so the
numbers match the source the app already consumes.

Endpoints (Pokémon category `3`):

- `/tcgplayer/3/groups`: sets, with `groupId`, `name`, `abbreviation`, and
  `publishedOn`.
- `/tcgplayer/3/{groupId}/products`: `productId`, `name`, and `extendedData`,
  including `Number` (for example `001/128`).
- `/tcgplayer/3/{groupId}/prices`: `productId`, `subTypeName`, `marketPrice`,
  and low/mid/high.
- `/last-updated.txt`: dataset stamp.

Design:

1. Add `TCGCSVPokemonPriceService` conforming to the existing
   `PokemonBulkPriceSource` and `PokemonSecondarySetSource` seams in
   `TradingCardScanner/Services/TCGdexService.swift`. `secondarySetID` becomes
   the TCGplayer `groupId`. `BrowseCatalog` pricing logic does not change.
2. Map each group into `PokemonCatalogSecondarySet`, with
   `abbreviation` → `ptcgoCode` and `publishedOn` → `releaseDate`. Groups
   carry no card count, so the matcher must rely on name, code, and date.
   Strip TCGplayer's series prefix (for example `ME05:`) in canonical-name
   comparison. After a match, confirm the join: at least 90% of the TCGdex
   set's local numbers must appear among the group's products, or decline
   the match.
3. Join products to cards by `extendedData.Number` → local number, with a
   `CatalogIdentityNormalization.namesMatch` check. When several products
   share a number and name (parallels, stamps), keep the one plain product.
   If more than one remains, omit the card (never borrow a price) and let the
   per-card TCGdex fallback answer it.
4. Map `subTypeName` exactly: `Normal` → `normal`, `Holofoil` → `holofoil`,
   `Reverse Holofoil` → `reverseHolofoil`, `1st Edition Holofoil` →
   `1stEditionHolofoil`. Store `1st Edition Normal` under its own key without
   widening `listingKey`. Unknown subtypes are dropped and logged to
   `PriceCoverageGapLog`. These keys match what `PokemonBulkPriceMap` already
   stores from pokemontcg.io.
5. Use `last-updated.txt` for `providerUpdatedAt`, and add a
   `BrowsePriceObservationDayResolver.tcgcsv` case. Skip a price refetch while
   the stamp is unchanged.
6. Budget: groups once a day, plus products and prices once per set open.
   That is about two requests per set, which meets Phase 6.0's bounded
   requirement and replaces the per-card fallback storm.
7. Send a descriptive `User-Agent`, as TCGdex's client does. Retry transient
   failures on the existing `dataRetryingTransientFailures` pattern.
8. Rollout: keep pokemontcg.io behind a rollback flag, and shadow-compare
   under Phase 6.3 on its six representative sets plus the five sets here.
   Cut over when the Phase 6.4 gates pass, and before 2027-03-01 regardless.

Risks and owner decisions:

- TCGCSV is a volunteer-run mirror with no SLA. The per-card TCGdex fallback
  remains the second source.
- Provenance: the [Browse pricing coverage plan](browse_pricing_coverage_plan.md)
  already records that TCGplayer's API terms restrict obtaining TCGplayer data
  from third parties that collected it by automated means. TCGCSV carries the
  same provenance as the values the app shows today through pokemontcg.io and
  TCGdex. It stays device-direct (Stage 4A). Stage 4B server redistribution
  remains blocked. **Owner sign-off is required before shipping.**

### Track B — upstream TCGdex data fix (zero app code)

Open a pull request against `tcgdex/cards-database` adding set-level
`thirdParty: { tcgplayer: <groupId> }` to `data/Mega Evolution/30th
Celebration.ts` and `30th Classic Collection.ts`. Take the group IDs from
TCGCSV `/tcgplayer/3/groups`; they were not verifiable from this audit's
environment. Once TCGdex deploys the change, the app's existing per-card
fallback prices both sets with no release. This helps immediately, but it
does not remove the per-card request cost or the 2027-03-01 dependency.

### Track C — remove phantom checklist slots

1. In `TCGdexCard.catalogVariants`, do not emit a plain base finish when every
   `variants_detailed` entry of that type carries a foil pattern, or a
   promotional stamp. Promotional stamps include `player-rewards-program`,
   `set-logo`, `gamestop`, `eb-games`, and `staff`. The stamped or foil entry
   keeps its own variant.
2. Keep set-wide stamps plain. Treat a stamp as set-wide when every card in
   the set carries it, as `30th-anniversary` does. Do not add a
   stamp-name allowlist for this.
3. Add `TCGdexCard` tests for Perfect Order 019 and 024, Chaos Rising 122, and
   30th Celebration 001. Also test a set whose parallels TCGdex types as
   `reverse` with foil patterns (for example Prismatic Evolutions), so the
   foil rule cannot remove a real plain reverse slot.
4. Regenerate the bundled checklist with the snapshot tooling, not by hand.
   Standard counts drop by one slot per removed phantom (Perfect Order
   213 → 209, Chaos Rising 203 → 202). Existing owned rows on a removed slot
   need a migration decision before regeneration.

### Already landed

`522a6bd` stops treating a failed set match or a "no quote" result as
long-lived, clears those caches on retry, and changes the copy to "No USD
quote from checked sources".

## Verification still required

- Live counts from a network that can reach the price hosts: priced / total
  standard slots per set before and after each track, and the list of
  remaining unpriced slots with the reason for each.
- Identify Pitch Black's 5, Chaos Rising's remaining 4, and Perfect Order's
  remaining 6 unpriced slots, then classify each as no market price on
  TCGplayer, TCGdex cache miss, or app mapping.
- Focused `xcodebuild` tests for any Track A or C change. Do not claim provider
  readiness from simulator evidence.
