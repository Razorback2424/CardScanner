# 2016 Red & Blue Collection ordinary-finish corrections

**Status:** four corrections authored locally, unsigned and unpublished —
2026-11-03. Checkout `a404f67470db20352b9b8f79925e2b96fe0597a9` plus this
turn's preserved evidence changes. This uses the existing owner-approved
ordinary Holo correction support; no app/Core source changed.

## Complete four-promo family

| Card | Number | Exact ordinary product | Independent foil corroboration |
| --- | --- | ---: | --- |
| Charizard EX | XY121 | 117267 | [Official Pokémon product page](https://www.pokemon.com/uk/pokemon-tcg/product-gallery/red-blue-collection-charizard-ex/) |
| Blastoise EX | XY122 | 118862 | [Official Pokémon product page](https://www.pokemon.com/us/pokemon-tcg/product-gallery/red-blue-collection-blastoise-ex/) |
| Venusaur EX | XY123 | 120701 | [Contemporary GTS Distribution product announcement](https://gogts.net/pokemon-tcg-red-blue-collection-venusaur-ex/) |
| Pikachu EX | XY124 | 123436 | [Official Pokémon product page](https://www.pokemon.com/us/pokemon-tcg/product-gallery/red-and-blue-collection-pikachu-ex/) |

The independent product descriptions explicitly identify foil promo cards.
[Fresh primary marketplace receipts](live-evidence.json) identify four ordinary
XY Promos products with exact names/numbers, `foilOnly: true` and
`normalOnly: false`. All four fresh TCGdex responses match those identities but
expose only generated standard Normal evidence. All eight reads succeeded.
The primary marketplace and independent manufacturer/distributor descriptions
corroborate each finish correction; TCGdex provides a third identity check.

Manufacturer/distributor body observations come from indexed page text, not
unobserved raw responses. GTS's direct open returned HTTP 429; it was not retried
or bypassed. No raw article hash, physical package inspection or particular
foil-pattern observation is claimed. Regional figure/oversize package differences
do not authorize additional Jumbo rows. This batch changes only the four
standard promo finish memberships and products.

## Exact authoring delta

[The review receipt](review.json) records before/after input hashes, eight fresh
responses and the four added records. Only four entries were appended to
`xyp.additionalVariants`: `variantID: holo`, exact product and three source
hosts, with `normalNeedsReview: true`. All previous 95 records and other input
fields are unchanged.

Current input has **75 descriptors and 99 protected records**: 73 Jumbo, Eevee
Cosmos, 24 ordinary Holo minimums and one price-only exclusion. These are local
authoring counts, not a global English-printing inventory. Existing Normal
holding identities remain intact and require finish review; unsupported Normal
pricing and automatic finish correction remain withheld by the approved support.

The separate [four-card Pokéween proposal](../pokemon-pokeween-stamps-2026-11-03/README.md)
is still uninstalled, awaiting support approval. Its initial 95-to-99 projection
predated this ordinary batch; adding it later would yield 103 records.

## Verification boundary

Full normal native live validation **passed** against signature-verified
production revision 19: **75 descriptors, 6,675 numbered summaries and all 99
authored records**. All 33 previous provider fingerprints are unchanged. The
secondary artwork provider was available, and all 97 existing card-art mappings
are retained exactly. Ambiguous secondary matches `tk2a`/`tk2b` remain reported;
they are not new memberships. See [validation hashes and scope](validation.json)
and the [normal native report](native-review.json).

No app/Core build or test is repeated for this data-only batch. The earlier
88 shared passes/one optional skip and 80 iOS passes retain their prior
mechanism-test scope; they are not a new cohort-specific test run.

No signing key, production signature, deployment or commit/push is used.
Physical-camera, paid-provider, artwork health and exhaustive English coverage
remain open. The prior [2017 Mythical Collections receipt](../pokemon-mythical-collections-2017-2026-11-02/README.md)
retains its earlier input hash and 95-record validation scope.
