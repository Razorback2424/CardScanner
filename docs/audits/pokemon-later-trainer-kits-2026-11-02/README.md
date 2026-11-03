# Later Trainer Kit membership batch

**2026-11-02 — production authoring data updated; unsigned and unpublished.**

Reviewed every remaining half deck from the
[20-half-deck census](../pokemon-historical-products-2026-11-02/trainer-kit-provider-census.json).
Added the 15 complete half decks to [production publisher input](../../../publisher/catalog-input.json):
**413 numbered identities**, including 153 Energy records. These are numbered
identity additions, not new foil/finish assertions or a certification of shiny
Energy coverage. All previous 59 descriptor objects are unchanged. Total input:
74 descriptors, including 41 newly authored memberships / 794 numbered identities.

| Product family | Admitted half decks | Numbered identities |
| --- | --- | ---: |
| Diamond & Pearl Trainer Kit | Manaphy, Lucario | 23 |
| HS Trainer Kit | Gyarados, Raichu | 60 |
| Black & White Trainer Kit | Excadrill, Zoroark | 60 |
| XY Trainer Kit | Sylveon, Noivern | 60 |
| XY Trainer Kit: Bisharp & Wigglytuff | Bisharp, Wigglytuff | 60 |
| XY Trainer Kit: Latias & Latios | Latias, Latios | 60 |
| XY Trainer Kit: Pikachu Libre & Suicune | Pikachu Libre, Suicune | 60 |
| Sun & Moon Trainer Kit | Alolan Raichu only | 30 |

## Corroboration and exceptions

Every numbered identity was matched against TCGdex's English set inventory and
Bulbapedia's independently maintained numbered deck tables. These are specialist
reference catalogs, not two official manufacturer statements. The
[independent factual transcription](independent-checklists.json) retains all
16 reviewed half-deck tables, including the held Lycanroc table. The
[comparison receipts](evidence.json) retain source URLs, source hashes, detailed
card hashes, all 413 matches and the hold. The emitted
[membership candidate](membership-input.json) includes only the 15 admitted sets.

The numbered cards in later kits follow tutorial draw order. Multiple Energy
copies therefore have distinct printed numbers and provider identities; they
must not be collapsed merely because their names match. No finish or price
mapping was created for those copies.

### Riolu's physical 6/61 footer

The Lucario deck table and provider normalize Riolu as 6/11. The added signed
membership instead records the corroborated physical **6/61** footer for
`tk-dp-l-6`, preserving the provider card identity. Evidence:

- [Bulbapedia Riolu printing history](https://bulbapedia.bulbagarden.net/wiki/Riolu_(Diamond_%26_Pearl_61)) explicitly describes the Trainer Kit denominator error.
- [Face to Face Games' physical listing](https://facetofacegames.com/products/riolu-661-common-non-holo) identifies Riolu 6/61 in the DP Lucario & Manaphy product.

The independent input carries the explicit exception and both evidence URLs.
The authoring utility requires at least two source URLs for a denominator
exception and emits its provenance. Native publisher validation accepts this
through the already-supported per-card printed-denominator field. No scanner
logic or collection key was altered. A separately corrected English 6/11
physical edition is not established by a normalized catalog table and is not
invented here; further physical-printing review remains open.

### Held Lycanroc Energy records

The independent 30-card Lycanroc table identifies missing positions
**2, 3, 6–10, 17, 20, 24, 26 and 28** as **Fighting Energy**. The provider set
still contains only 18 card records. A [batch detail check](lycanroc-detail-check.json)
confirmed all 12 corresponding provider endpoints returned HTTP 404. This
resolves the identities of the gap without fabricating provider handles or
admitting a partial set as complete. `tk-sm-l` remains absent from production
input. The existing signed membership mechanism cannot manufacture the missing
provider card records; upstream backfill or separately authorized catalog
transport support is still required.

## Validation and normal signing

The complete detailed provider fixtures were combined with all earlier batches.
The existing native publisher's `validate` command passed for **41 complete
sets / 794 cards**. The [union review](native-union-review.json) classifies this
isolated candidate as `newSet`; its revision 1 is fixture-local, not production.
The Riolu member's printed denominator was explicitly checked as 61. All 794
added provider card IDs are unique, all 59 prior descriptors are unchanged, and
the Lycanroc hold is preserved.

At this meaningful data milestone, existing native membership and production
boundary regressions passed **9/9**. The already-built publisher was reused for
data validation; no iOS build was run. These checks validate authoring integrity
and publisher compatibility, not actual scanning of all 794 cards, pricing
correctness, or persisted-collection behavior. JSON counts, local documentation
links and `git diff --check` passed.

The unchanged [production workflow](../../../.github/workflows/pokemon-catalog.yml)
must rebuild the full candidate against the then-active release and use the
protected new-set signing route in the
[runbook](../../plans/pokemon_catalog_key_handling_runbook.md). Do not publish
this isolated validation fixture as a replacement catalog. No signing key was
read; no commit, push, workflow dispatch, signature or deployment occurred.
App scanner, portfolio and catalog consumer logic remain unchanged. Signed
candidate installation, device routes (including Riolu), exact physical
finishes and prices remain acceptance gates. The full English-history goal
remains active and unproven.
