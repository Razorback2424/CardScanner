# 2017 Mythical Collections ordinary-finish corrections

**Status:** authored locally, unsigned and unpublished — 2026-11-02.
This is a follow-up to the [broader coverage ledger](../pokemon-broad-coverage-2026-11-02/README.md),
using its owner-approved ordinary-finish support. No app or Core source changed
in this batch.

## Complete product-family review

The contemporary [PokéBeach release report](https://www.pokebeach.com/2017/01/volcanion-magearna-mythical-collections-releasing-next-week-photos)
identifies six foil promos in the Volcanion box and seven in the Magearna box.
Its collector numbers and foil descriptions corroborate the independent primary
TCGplayer metadata for all 13 cards. TCGdex supplies a third identity check.

| Number | Card | TCGplayer product | Box |
| --- | --- | --- | --- |
| XY185 | Volcanion | 127139 | Volcanion |
| XY186 | Magearna | 127138 | Magearna |
| XY187 | Celebi | 127129 | Volcanion |
| XY188 | Shaymin | 127136 | Magearna |
| XY189 | Victini | 127137 | Volcanion |
| XY190 | Manaphy | 127134 | Magearna |
| XY191 | Keldeo | 127133 | Volcanion |
| XY192 | Mew | 127135 | Magearna |
| XY193 | Meloetta | 152950 | Magearna |
| XY194 | Darkrai | 127130 | Volcanion |
| XY195 | Jirachi | 127132 | Volcanion |
| XY196 | Genesect | 127131 | Magearna |
| XY197 | Arceus | 127128 | Magearna |

The [fresh, price-free receipts](live-evidence.json) retain all 26 successful
provider/product responses, source URLs and raw-response SHA-256 hashes. Every
TCGplayer response identifies an ordinary Pokémon card in XY Promos, with its
exact number, `foilOnly: true` and `normalOnly: false`. Every TCGdex response
identifies the same name and number but supplies only generated standard Normal
evidence. These checks do not establish a particular foil pattern.

The manufacturer's archived sell-sheet PDF returned HTTP 403. It was not
downloaded or visually inspected, and does not count as a corroborating source.
The release report's text was reviewed; its photo gallery was not independently
inspected. Its reported six-card Volcanion contents control this cohort, rather
than an unverified generic seven-card packaging claim.

## Authoring delta and behavior

Added exactly 13 `holo` records to `xyp.additionalVariants`, each with its exact
product, three evidence hosts and `normalNeedsReview: true`. The earlier 82
records and every other input field are unchanged. This yields **75 descriptors
and 95 protected records**: 73 Jumbo, one Eevee Cosmos, 20 ordinary Holo minimums
and one price-only exclusion. These are authoring counts, not a count of every
physical printing in the universe.

The existing approved consumer exposes Holo while preserving historical Normal
holding identities, requiring finish review and withholding unsupported Normal
pricing and automatic finish correction. No guessed Normal deletion, foil
pattern, stamp, edition, Jumbo, release-date or inventory change is included.

## Validation boundary

Full normal native live validation **passed** against signature-verified
production revision 19: 75 descriptors, 6,675 numbered summaries and all 95
authored records. All 33 prior provider fingerprints are unchanged. See the
[validation receipt](validation.json), [native report](native-review.json) and
[source/delta review](review.json) for hashes and scope.

The secondary artwork provider recovered during this run. All **97** existing
card-art mappings survive exactly (30 Classic, three BW and 64 SM), so the
earlier outage omission does not affect this candidate. It also carries 40 MEP
and 19 SVP mappings from the existing normal enrichment path. This is mapping
continuity evidence; public URL health and image correctness remain separate.
The report retains ambiguous secondary matches `tk2a` and `tk2b` without
claiming new physical memberships from them.

This data-only batch reuses the prior milestone's **88 passing shared
tests, one optional skip and 80 passing iOS tests**; those tests were not rerun
for these 13 data records. They are mechanism evidence, not physical-camera or
paid-provider acceptance for this cohort.

The [earlier implementation receipt](../pokemon-broad-coverage-2026-11-02/implementation.json)
retains its original 82-record input hash and test scope. No signing key,
production signature, commit, push or deployment is involved. Exhaustive English
coverage, saved-only link reconciliation and artwork URL health remain open.
