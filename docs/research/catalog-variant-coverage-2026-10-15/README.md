# Four-game specialty-printing coverage review

**Reviewed:** 2026-10-15, `35473ed` plus existing local changes.
**Status:** Pokémon, Magic and Lorcana fixes implemented. Three One Piece
additions are validated review data; signed local activation awaits explicit
approval after automatic approval review rejected changing trusted pins.
The [coverage audit](../../audits/card-coverage-gaps-and-research.md) remains the
cross-game research authority; this directory retains this pass's exact evidence.

## Findings and implemented fixes

| Game | Inventory examined | Result |
| --- | --- | --- |
| Pokémon | Current English directory: 220 entries; bundled snapshot: 157 virtual-set entries / 146 provider IDs; 471 exact ball-pattern eligibility rows | Replaced the blanket reverse-holo rule with exact set/number eligibility. Prismatic Trainers such as 093 cannot acquire an invented Master Ball finish; Black Bolt/White Flare 079–086 remain Poké Ball only. Browse generation and scanner fallback use the same rule. Explicit newer provider evidence remains additive. Foreign/jumbo detailed records cannot add standard English choices. |
| Magic | Current Scryfall directory: 1,059 sets; seven long-code sets / 34 source records; exact PLG20/PTKDF responses and inspected promo images | Added six printed-footer mappings: two PLG20 cards and four Dragonfury cards. PLG20 physically prints `PRM`, collector `001/001`, different release labels and rarity letters, and 2020; Dragonfury prints `DTK` plus `Tarkir Dragonfury`. These map to the exact provider printing. Missing/conflicting evidence does not earn a promo identity. |
| One Piece | All 87 TCGCSV product groups: 7,462 retained source records; installed owner revision 2 and full publisher review corpus | Added separately reviewed alternate-art OP01-001, alternate-art OP01-120 and manga OP01-120 to the durable review registry, with new permanent printing/artwork UUIDs. Official English images, original-release membership, and explicit independent Foil listings agree. The validated unsigned revision-3 candidate retains every previous printing. Existing signed owner revision 2 remains installed. |
| Lorcana | Fresh LorcanaJSON: 3,556 records, all already present in the 3,582-record discovery snapshot; fresh product/price feeds for sets 1–8 | Enabled all 132 original Enchanted printings in those eight sets for normal scan/Browse/ownership/CSV and exact Holofoil pricing. Added 132 UUIDs and 132 exact price lanes. Every one of the previous 1,617 physical records remains byte-for-byte equivalent as decoded data. Current totals: 1,749 physical records, 1,748 mapped printings, 3,364 exact finish mappings. |

The Magic finding corrects the earlier handoff's implication that accepting
five-character OCR codes alone would fix PLG20. Provider set codes and printed
codes are different. A generic length-filter change would not fix these cards;
Dragonfury's printed code/number could otherwise identify its ordinary DTK card.
PT SNC's six records have token layouts despite the directory's promo metadata.
The remaining long-code sets need actual footer/layout reconciliation.

The Pokémon bundled snapshot already contains all 471 expected ball slots with
zero missing or extra ball keys. The defect was its broader resolver fallback
and the lack of that exact fallback in newly generated Browse checklists.
This pass does not remove existing user-selected finishes or rekey ownership.

## Lorcana adoption boundary

The [builder](../../../scripts/build_lorcana_market_catalog.py) accepts Enchanted
cards only for numeric original footers above 204 in sets 1–8, with the reviewed
Lava/VerticalWave pattern, normal/landscape layout, matching source/printed set,
English publisher image URL, no alternate distribution, one source candidate,
and one exact set/number/title/Enchanted-rarity market product. The single
reviewed Sword of Shan-Yu spelling difference is an exact set-8/219/title alias.
Unexpected or duplicate finish lanes remain held. Later Magma/Tinsel editions,
Epic/Iconic, promos and multiple-pattern distributions are outside this policy.

[Ravensburger's Enchanted announcement](https://www.disneylorcana.com/en-US/news/enchanted-reveal)
documents alternate artwork, numbers above 204 and Inkwash foiling.
The existing publisher artwork/footer observations and independent exact product
metadata establish individual joins. Price amounts never establish a finish.
The [adoption receipt](lorcana-enchanted-adoption.json) preserves every added
printing/source/product join and all eight fresh product/price response hashes.
Artwork bytes and quote amounts are not bundled by this change.

## Remaining discrepancy ledgers

- [Pokémon sets absent offline](pokemon-sets-absent-offline.csv): 74 directory
  entries, including 15 digital Pocket entries explicitly identified by the
  provider's Pocket-series inventory. The remaining 59 include promos, POP,
  retailer/product exclusives, trainer kits, jumbo and specialty sets. Absence
  from an offline checklist does not prove a missing live catalog route;
  some have existing recognition/import/pricing support. Release, region and
  per-printing variant coverage still need reconciliation. Printed stamps,
  corrected editions and distributions lack a complete independent denominator.
- [Magic long-code exceptions](magic-long-code-sets.csv): seven source sets,
  with reviewed mappings distinguished from unresolved printed identities.
  This is a set-directory comparison, not a fresh all-printings/treatment crawl.
  Existing serialized, etched, token/art, historical and treatment support was
  inspected but is not newly certified as exhaustive.
- [One Piece unmatched market products](one-piece-unmatched-products.csv):
  5,095 source products without an exact installed market association, including
  122 presales. Examples include 710 alternate-art, 47 manga, 536 prerelease,
  573 release-event, 104 judge and 292 winner/champion listings. These are
  source classifications, not counts of missing distinct physical printings.
  Unpriced known cards, duplicate listings, DON!!, nonstandard objects and
  unreviewed language/distribution/finish identities require separate decisions.
  The three reviewed additions remain unpriced and pending local activation.
- [Lorcana discovery-only records](lorcana-discovery-only.csv): 1,833 records
  still lack reviewed physical ownership, including 108 later Enchanted,
  108 Epic, 12 Iconic and 319 Special records. Quest, promo, event, oversized,
  errata, autograph and serialized distributions retain their explicit physical
  review requirements. Discovery completeness is not ownership completeness.

All One Piece physical-family completeness flags remain false. The new Zoro
and Shanks records become explicit distinct choices in the review runtime;
the new acquisition guard prevents an automatic save from bypassing those known
siblings. The existing runtime still resolves a sole verified English printing
without requiring its family-completeness flag. That is an important limit:
false completeness flags alone do not prevent the installed catalog from
selecting a base card when an uncataloged alternate exists. This pass preserves
that existing sole-verified policy while adding the three verified alternatives;
broader family reconciliation remains necessary. Primary artwork is paired visually
with exact market thumbnails, while retailer text supplies finish evidence.
The [three-printing receipt](../../../OnePieceCatalogCore/ReviewCorpus/english-stress/special-printings-review.json)
retains the independent URLs, hashes, UUIDs, printed numbers and decisions.

## Reproduction and verification

The [offline audit tool](../../../scripts/audit_catalog_variant_coverage.py)
regenerates the CSVs and [summary](summary.json) from retained public responses:

```sh
python3 scripts/audit_catalog_variant_coverage.py \
  --magic-sets "$CAPTURE/magic-sets.json" \
  --one-piece-products "$CAPTURE/onepiece-market/one_piece_catalog.json" \
  --lorcana-cards "$CAPTURE/lorcana-allCards.json" \
  --pokemon-sets "$CAPTURE/pokemon-sets.json" \
  --pokemon-pocket-series "$CAPTURE/pokemon-pocket-series.json" \
  --output docs/research/catalog-variant-coverage-2026-10-15
```

Public input sources: [Scryfall directory](https://api.scryfall.com/sets),
[TCGdex English sets](https://api.tcgdex.net/v2/en/sets),
[Pocket series](https://api.tcgdex.net/v2/en/series/tcgp),
[Bandai original release](https://en.onepiece-cardgame.com/cardlist/?series=569101),
[independent exact English printing/finish listings](https://coretcg.com/Products/0/68/3188/Romance-Dawn?l=144&stockStatus=0),
[TCGCSV One Piece groups](https://tcgcsv.com/tcgplayer/68/groups),
[LorcanaJSON English data](https://lorcanajson.org/files/current/en/allCards.json),
[TCGCSV Lorcana groups](https://tcgcsv.com/tcgplayer/71/groups), and
[Wizards' PLG20 distribution announcement](https://wpn.wizards.com/en/news/announcing-love-your-local-game-store-promotion).

Verified publisher tests pass **46/46**; offline Python tests pass **95/95**.
The final Pokémon follow-up passes **211/211**, including pricing, exact purchase
links, Browse slots, variant resolution and collection keys, with a finalized
`Pokemon-Final.xcresult` on the SSD volume. All 132 Enchanted source joins also
reproduce against fresh feeds, preserving every prior physical record.

The finalized complete affected simulator selection passes **467 tests**, zero
failures, with **three deliberate live-only skips** across 470 cases. It covers
all changed game paths, the 132 Enchanted records, the full One Piece review
corpus, picker/acquisition behavior, Browse, CSV, catalog keys, Magic treatments
and parser ambiguity. It runs `TradingCardScanner-DebugRemoteLocal` on iOS 27;
`Regression-Final.xcresult` finalized with `TEST SUCCEEDED` and exit zero under
`/Volumes/JourneyVisualAudit/CodexBuilds/CatalogCoverage-20261015/`.
The separate Pokémon 211-case replay uses iOS 26.5. These are overlapping
selections, not additive app-test totals or a full-target run.

Intermediate runs exposed stale compiled fixture loaders after separating new
evidence files, an artwork opt-in leak in the added records, the missing
automatic-acquisition recheck, outdated set-count expectations and a standard-art
fixture that chose an arbitrary sibling. The evidence layout, records, guard
and fixture selection were corrected before the final green run. Failed-run
diagnostic collection was interrupted only after its tests ended; the final run
disabled that collection and finalized normally. An initial unavailable
simulator destination also recovered after Xcode rediscovered installed runtimes.
These are source/data and simulator checks. Physical optical accuracy,
provider/artwork rights, production publication, CloudKit and release readiness
remain separate from this review.

Public captures, original Lorcana baseline, final mapping receipt and the validated
unsigned One Piece candidate are retained under external
`CodexBuilds/CatalogCoverage-20261015/PublicSources/`. The
[candidate receipt](one-piece-candidate.json) records its exact payload digest;
it is not a signed release. Existing owner seed and public pins are unchanged.
