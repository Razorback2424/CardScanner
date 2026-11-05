# Black & White promo family and adjacent Sylveon Collection

**Status:** full current provider/product census completed; four ordinary Holo
corrections authored locally — 2026-11-03. Checkout
`a404f67470db20352b9b8f79925e2b96fe0597a9` plus preserved earlier changes.
No app/Core source changed. The [comprehensive ledger](../pokemon-broad-coverage-2026-11-02/README.md)
remains the overall authority; this bounded audit does not establish exhaustive
English-printing or paid-pricing coverage.

## Complete current provider and product comparison

All **101 current BW provider cards** were read successfully. Each exposes one
generated standard Normal object, without Holo flags or a detailed TCGplayer
handle. [Provider directory](provider-set.json) and [card receipts](provider-cards.json)
retain identities and response hashes. Existing app code has the BW promo footer
route; this is a finish-evidence gap, not proof of 101 missing base cards.

The public marketplace discovery group supplied 148 product IDs. All **148
primary identity reads succeeded** after one transient timeout for 83852 was
retried and retained in its receipt. These are price-free identity reads. Of
these, **140 products cover 99 distinct BW numbers**; eight are prerelease/staff
versions of ordinary expansion cards, not extra BW Black Star memberships.
See [primary product receipts and discovery links](products.json).

[Conservative exact name/number comparison](comparison.json) finds 72 ordinary
product matches: 60 foil-only and 12 Normal-only. It strips only a terminal
`- BWxx`; parenthetical number/Supporter/Team Plasma descriptors remain unmatched
leads, not absent products. Matching is not physical admission: many foil-only
products represent named patterns rather than a separate plain Holo printing.
The 12 Normal-only products also disprove a blanket set-wide Holo correction.

## Applied ordinary corrections

| Physical card | Exact ordinary TCGplayer product | Independent foil corroboration |
| --- | ---: | --- |
| Mewtwo-EX BW45 | 87430 | Original TPCI Legendary EX Tin sell sheet |
| Darkrai-EX BW46 | 84707 | Original TPCI Legendary EX Tin sell sheet |
| Rayquaza-EX BW47 | 88646 | Original TPCI Legendary EX Tin sell sheet |
| Sylveon XY04 | 89729 | Official Sylveon Collection product description |

The complete three-card Legendary EX Tin family is corroborated by exact primary
marketplace names/numbers/Holo-only flags and the original manufacturer
[sell sheet](https://cdn.pidgi.net/images/6/69/Legendary_EX_Tins_sell_sheet.pdf),
whose downloaded bytes and rendered full page were inspected. Hash and source
observations are in [the review receipt](review.json). Pokumon's individual
histories distinguish their ordinary Mirror finish from Cosmos tin printings;
no new Mirror variant or EX-wide finish inference is introduced.

The adjacent [fresh Sylveon identity/product reads](sylveon-adjacent.json) and
[official foil-family description](https://www.pokemon.com/uk/pokemon-tcg/product-gallery/bw-sylveon-collection/)
corroborate XY04. The official description was inspected in indexed text; direct
extraction contained only an iframe. The distributor-hosted Sylveon PDF was
available to web text extraction but direct download returned 403; it was not
bypassed, rendered locally or assigned a raw-body hash. No physical package,
four-card image inspection or precise named-pattern price acceptance is claimed.

Four protected records were added using approved support: `holo`, exact products
and `normalNeedsReview: true`. All previous **112 records and all other parsed
input values remain unchanged**. The BW descriptor was expanded from its compact
line to attach three records; no unrelated descriptor was reformatted. Input
now has **75 descriptors / 116 protected records**, including **41 ordinary
Holo minimums**, 73 Jumbo, Eevee Cosmos and one price-only exclusion. Existing
Normal holdings retain their identity and require review rather than automatic
conversion. Of the original 155 XY signals, 34 exact pairs are now admitted and
121 remain; the three BW additions are outside that XY census.

## Eight named Cosmos candidates and exact review support

The rest of the Sylveon Collection is a complete eight-card Cosmos family:
BW87 Leafeon, BW88 Flareon, BW89 Vaporeon, BW90 Glaceon, BW91 Jolteon,
BW92 Espeon, BW93 Umbreon and BW94 Eevee. [Per-card products and pattern review](sylveon-cosmos-review.json)
cross-check exact primary products with the indexed CGC registry's numbered
Cosmos entries and an independent release history. The direct CGC registry
extraction did not contain its rows; no raw-row hash or graded-photo inspection
is claimed. Manufacturer text confirms foil cards but does not identify Cosmos.

These eight are **not installed** as generic Holo substitutes. Existing signed
support accepts Cosmos membership, but `normalNeedsReview` is restricted to
ordinary Holo additions. The minimal support proposal is to permit that existing
review flag on a reviewed Cosmos record and carry the same Normal-choice hold
through identified and saved-card pricing/links. Preserve all holding keys,
quantities and provenance. Do not infer a second plain Holo printing or silently
retain generated Normal as confirmed physical evidence. This is a proposed
validation/consumer extension, not an authorization or a code change.

Other 2012 EX, EX Power and Team Plasma tin promos remain named-pattern review
leads. In particular, the exact EX Power BW61–63 histories label Cosmos; their
foil-only marketplace products alone do not justify plain Holo records. Staff,
Worlds, ranking, Tinsel, Cracked Ice and smooth/pixel Cosmos cohorts need their
own exact identities/products and independent sources.

## Two canceled physical identities

BW77 Pikachu and BW78 Raichu appear in the provider's 101-card list, but are the
only two BW numbers absent from the reviewed marketplace group. Absence alone
is not proof. Independent contemporary reports from
[PokéBeach](https://www.pokebeach.com/2014/07/lost-bw77-and-bw78-promo-cards-finally-revealed)
and [Bulbanews](https://bulbanews.bulbagarden.net/wiki/Promos_BW77,_BW78_listed_on_Pok%C3%A9mon.com)
explicitly report the canceled physical promos and temporary official digital
image publication. Those observations distinguish digital images from an English
physical release. They are recorded as corroborated cancellation findings,
without deleting any catalog row or holding.

Current `membershipRecognition` requires all upstream IDs, so a 99-member list
cannot safely filter the two. The concrete minimal support proposal is an
optional protected descriptor array `excludedCards`, with exact `providerCardID`,
`canonicalName` and at least two independent evidence URLs per entry. Validate
names/IDs against the source, prohibit contradictory additional-variant records,
and apply exclusions to catalog/checklist/lookup/refresh availability. Keep raw
provider fingerprints unchanged and require protected signing review, cache and
withdrawal handling. Existing holdings must remain recoverable and explicitly
unverified; do not delete/rekey them or change portfolio calculations. Do not
disable the entire BW scan route or invent a finish to carry a base-card
exclusion. No such schema or consumer extension has been implemented.

## Verification boundary

The first normal native live validation stopped on unrelated upstream HTTP 503
for `sv05-141`. Its terminal failure is retained. A single retry against the same
signature-verified production revision 20 **passed**: 75 descriptors, 6,675
numbered summaries and all 116 authoring records. All 95 active corrections and
75 provider fingerprints remain exact. [Validation hashes](validation.json) and
the [native report](native-review.json) retain actual attempt/artifact scope.

[Artwork continuity](artwork-continuity.json) remains a publication hold: of 238
active mappings, 226 remain exact and 12 McDonald's 2011 mappings disappear.
No mappings change, and 25 new McDonald's 2021 mappings bring the candidate to
251. The earlier [XY tin candidate](../pokemon-xy-tin-families-2026-11-03/README.md)
had a different 67-missing/four-changed result; neither run proves URL health.
Do not reuse either run's continuity claim for the other's candidate. No manual
payload patch or signing was performed. The latest input hash is
`2010e87686f36bdc712d3a4f461945da17287818b11292b3923f05299ac4ba32`.

No app/Core build/test was repeated for this data-only batch. Previous mechanism
test counts retain their original scope. No signing key, deployment, commit/push,
physical-camera or paid-provider acceptance is used or claimed.
