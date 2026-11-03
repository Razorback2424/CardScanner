# Residual historical promo audit

**2026-11-02 — investigation evidence only; no production catalog change.**

Reviewed all eight still-unconfigured provider groups from the earlier missing
offline checklist census, plus all seven original expansion cards in the W
promo family. The [price-free live receipts](evidence.json) contain source URLs,
source-byte hashes, set/card metadata and detailed quote product IDs. All 15
public requests completed successfully. Reproduce with the
[read-only utility](../../../scripts/audit_pokemon_promo_residuals.py).

## W-stamp coverage and pricing findings

The standalone `wp` directory entry declares seven cards but returns **zero**
card records. The seven W-stamped cards are nevertheless represented as detailed
objects on their original expansion identities:

| Provider card | Name | Number | W detail stamp |
| --- | --- | --- | --- |
| base2-60 | Pikachu | 60/64 | wotc |
| base3-50 | Kabuto | 50/62 | wotc |
| base4-63 | Wartortle | 63/130 | wotc |
| base5-19 | Dark Arbok | 19/82 | wotc |
| base5-32 | Dark Charmeleon | 32/82 | w-promo |
| gym1-54 | Misty's Psyduck | 54/132 | wotc |
| gym2-37 | Brock's Vulpix | 37/132 | wotc |

The [independent W promo history](https://bulbapedia.bulbagarden.net/wiki/W_Promotional_cards)
corroborates this seven-card stamped family and its source expansions. The
existing catalog decoder separates stamped objects when the detailed records
distinguish them. Therefore an empty standalone `wp` response does **not** prove
seven missing card identities. Do not manufacture a duplicate `wp-1`–`wp-7`
family or replace the original collector fractions with ordinal `/7` numbering.
Actual scanner, edition and price acceptance is a separate gate.

Five W detail records lack a TCGplayer product handle. Two others reuse the
ordinary card's handle:

- `gym1-54` W detail: TCGplayer **87539**, also used by the ordinary detail.
  The [TCGplayer primary listing](https://www.tcgplayer.com/product/87539/pokemon-gym-heroes-mistys-psyduck?Language=all)
  identifies Gym Heroes Misty's Psyduck. TCGplayer separately lists the
  [W Stamped promo](https://www.tcgplayer.com/search/pokemon/product?page=1&productLineName=pokemon&q=Misty%27s+Psyduck+%5BW+Stamped%5D&setName=product&view=grid).
- `gym2-37` W detail: TCGplayer **83986**, also used by the ordinary detail.
  The [Gym Challenge price guide](https://www.tcgplayer.com/categories/trading-collectible-card-games/pokemon/price-guides/gym-challenge)
  lists the ordinary printing. Exact independent replacement-product evidence
  is still required before assigning a corrected W binding.

Both W detailed quote objects also use the reused product IDs under
`1st-edition` and `unlimited` keys. Those quote keys are retained in the receipt
without numeric prices. This is not a live paid-provider test or proof that a
wrong price was displayed to a user. Source inspection shows the exact-product
fallback can accept a stamped detail's third-party handle; the reused IDs are
therefore actionable pricing-isolation findings, rather than evidence to merge
stamped and ordinary printings. No replacement handle is installed from an
aggregator or inferred from a similar card name.

## All eight residual groups

| Provider group | Returned / declared cards | Disposition |
| --- | --- | --- |
| miscp | 1 / 1 | Ancient Mew has special printed text/numbering; do not invent a readable modern fraction or prefix. |
| basep | 53 / 53 | Bare-numbered Wizards promos require physical-numbering recognition review; `/53` is not established by the set count. |
| wp | 0 / 7 | Original expansion records contain all seven W details; review stamping/edition/product coverage there. |
| jumbo | 0 / 160 | Empty aggregation, not proof of 160 absent physical cards; sizes also occur under standard set identities. Existing Jumbo transport/consumer gap remains. |
| sp | 0 / 10 | No member records; hold pending actual English sample-card evidence and a supported identity representation. |
| np | 40 / 40 | Bare-numbered Nintendo promos need the same physical-numbering review; `/40` must not be fabricated. |
| rc | 0 / 25 | The bundled `bw11` checklist already contains 25 distinct `bw11-RC…` identities. Existing subset routing maps RC/25 to bw11; do not duplicate them solely because `rc` is empty. |
| tk-sm-l | 18 / 30 | Previously verified twelve missing Fighting Energy endpoints remain held; see the [Trainer Kit receipt](../pokemon-later-trainer-kits-2026-11-02/README.md). |

Earlier census wording of 205 physical provider sets meant **205 non-Pocket
directory entries**, not 205 independently verified distinct physical releases.
Empty aggregation/alias entries demonstrate why directory counts and missing
offline rows cannot certify physical-printing completeness.

## Required scope decision and remaining work

The owner's active instruction permits catalog updates through normal signing
and prohibits underlying scanner/portfolio/catalog logic changes. The current
signed set descriptor and human input have no transport for per-card finish,
size, edition or product-binding overrides. A signed fingerprint requests a
provider refresh; it cannot replace incorrect physical metadata or product IDs.
This is verified in
[`CatalogContract.swift`](../../../PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogContract.swift),
[`ProviderModels.swift`](../../../PokemonCatalogCore/Sources/PokemonCatalogCore/ProviderModels.swift)
and the [signing runbook](../../plans/pokemon_catalog_key_handling_runbook.md).

A scope decision was requested: permit minimal signed catalog-data schema and
consumer support, or retain the current no-logic-change restriction. No such
change is assumed authorized while the question is pending. The requested
Charizard variant display label remains **Jumbo**, not Lenticular.

All previously authored 794 memberships remain intact and unsigned/unpublished.
This turn did not alter production input, app code, saved holdings or pricing
bindings. No build/test milestone was warranted for this read-only investigation.
The audit utility ran successfully; JSON integrity, counts, local links and
`git diff --check` were checked. Global English physical-printing, scanner and
exact-price completeness remains unproven.
