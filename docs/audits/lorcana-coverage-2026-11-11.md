# Lorcana catalog coverage

**Status** — 2026-11-12 English bundle and verification, based on `7daef56`

## Coverage

The published gallery contained 3,556 English cards and two Ink Drop supplies.
All 3,556 card IDs, printed identifiers, and 6,436 finish declarations matched
the November 8 LorcanaJSON capture after normalizing spacing and D23 number
padding. The discovery bundle contains the 3,556 cards, 39 supplemental
observations, and 188 sealed products.
[Publisher gallery](https://cards.disneylorcana.com/en-US/?set=set3).

The physical bundle contains 3,426 reviewed printings in 3,420 complete footer
families. All 1,749 original printing records were preserved. The release
inventory checks the numbered English cards in all 14 expansions, including
Fabled's zero, Attack of the Vine's denominator of 207, and the five lettered
Dalmatian artworks. The two shared Rise of the Floodborn footers open a
printing choice. Bucky uses the visible ink cost and Ward text. Elsa uses
the branch above the horse's head. Each choice retains its own product and
finish evidence.
[Product archive](https://disneylorcana.com/en/product-archive/),
[publisher errata](https://www.disneylorcana.com/en-US/news/july2024-errata/),
[Elsa artwork correction](https://www.beckett.com/news/a-guide-to-disney-lorcana-erratas-cards/).

Both Curator’s Collections, the numbered D23 and early TFC promo runs, and
the 12 prerelease cards from Attack of the Vine! and Hyperia City have their
own product and finish identities. Browse and recognition preserve the
actual D23 footer forms, including `1TFC` and `01/D23`. The gift-set
printings distinguish standard and oversized copies. CSV import accepts the
literal and normalized D23 footers for the same exact printing UUID.
[Heroines release](https://www.disneylorcana.com/en-GB/news/2026/06/curators-collection-heroines),
[Beauty and the Beast release](https://disneylorcana.com/en/news/2026/10/timeless-tales-and-totally-rockin-tunes/),
[card renders](https://cardgamer.com/guides/lorcana-beauty-and-the-beast-collection-card-gallery/),
[D23 2026](https://www.disneylorcana.com/en-GB/news/2026/06/d23),
[Into the Inklands gift set](https://www.ravensburger.co.uk/en-GB/pdp/11098295).

The three Quest decks contribute 103 numbered scenario cards, verified
against the gallery art and finish declarations. Disastrous Sandstorm keeps
the published `20/35 EN Q2` and stays unpriced because the market record lists
`19/35`. Challenge Year 2 covers the released numbers 1–18. The foil Headless
Horseman at `13/C2 EN 10` comes from the published card face and the official
Championship prizes. Its market counterpart at `17/C2 EN 10` belongs to the
nonfoil printing.
[Deep Trouble](https://www.disneylorcana.com/en-GB/product/deep-trouble),
[Palace Heist](https://disneylorcana.com/en/product/palace-heist/),
[Great Hunny Rescue](https://disneylorcana.com/en/product/great-hunny-rescue/),
[Championship prizes](https://disneylorcana.com/en/news/2026/03/disney-lorcana-challenge-championships-information/),
[13/C2 published card face](https://www.cardtrader.com/uploads/blueprints/image/410430/show_410430-the-headless-horseman-cursed-rider-13-c2-foil-lorcana-challenge-promos.png).

Nine Challenge Year 1 cards are addable. Five have nonfoil editions absent
from the gallery's finish declarations. The discovery producer retains the
original declarations for comparison and attaches separate evidence for each
nonfoil edition. The serialized Mickey at `5/C1` remains browse-only.
[Challenge launch](https://disneylorcana.com/en/news/2024/03/challenge-announcement/),
[Challenge finish inventory](https://lorcanaplayer.com/set/challenge-set-1/),
[World Championship prizes](https://www.disneylorcana.com/en-GB/news/2025/06/2025-6-watch-worlds-on-twitch),
[Infinity Weekend nonfoil](https://www.disneylorcana.com/en-GB/news/2025/10/2025-10-prizes-and-promos).

The publisher gallery declares three variants for each of the 16 multi-foil
printings. Each has three separately selectable finishes. The retained
marketplace data and a scoped publisher replay match the exact product,
collector number, and lane for all 6,288 finish mappings. For three Whispers
in the Well cards, retailer labels and the marketplace subtype names still
leave the two foil quotes unresolved. The audit CSV lists the 169
discovery-only rows, which include promos and unnumbered Quest components.
[Publisher gallery](https://cards.disneylorcana.com/en-US/?set=set10),
[Whispers in the Well market feed](https://tcgcsv.com/tcgplayer/71/24414/products).

The November 12 price deployment from `03fcf38` expanded Lorcana from eight
to 20 production groups. The readback matched all 6,288 reviewed product
names, collector numbers, finish lanes, and quote values to the same TCGCSV
build. The provider returned an amount for 6,278 lanes and null for ten.
[Production workflow](https://github.com/Razorback2424/CardScanner/actions/runs/43305432065),
[production price index](https://catalog.scan-stash.com/market-prices/v1/index.json).

All 1,373 indexed files matched on both production hosts. The shared mirror
served six Pokémon, 48 One Piece, and 612 Yu-Gi-Oh! groups and preserved every
previously published group and product. The Yu-Gi-Oh! differences matched
reviewed edition corrections and the vendor's absent or null quote rows.
The verification receipts are in
`CodexBuilds/LorcanaCatalogGoal-20261111/ProductionPriceFeed-20261112`
on the external SSD.

## Live simulator acceptance

All three live pricing acceptance tests passed with zero skips on the
November 12 working tree at `c52d16f`, using `TradingCardScanner-ProfileLocal`
Debug on iOS 27.1. The all-mapping test used a fresh feed cache. A separate
production readback matched all 6,288 product and finish pairs, amounts,
and server capture times. The test now checks the capture time against the
app's freshness window.

The normal app's Scan receipt and Browse detail agreed on the lettered
Dalmatian Puppy `4B/204 EN 3` foil, corrected Elsa `39/204 EN 2` foil,
Merlin `57/204 EN 14` Rainbow Pillars foil, and the unmapped foil of
A Whole New World `10/C1 EN 1`. The public Hades review also exercised
the size choice, mapped foil, unpriced oversized printing, and ownership
relaunch. Scan tests start with supplied footer text on the simulator.

The result bundle and verified receipts are in
`CodexBuilds/LorcanaCatalogGoal-20261111/LorcanaLiveAcceptance-20261112`
on the external SSD.

## Replay and release check

The public inputs and checksums are retained on the external T7 at
`CodexBuilds/LorcanaCatalogGoal-20261111/SourceEvidence` and
`CodexBuilds/LorcanaCatalogGoal-20261111/ReviewedCatalog-20261112`. The final
audit CSV, generator decisions, and scoped price replay are in
`ReviewedCatalog-20261112/c1-verification`. The
retained October expansion candidate is the generation baseline. Replay with
a copy of the current UUID ledger so the producers reuse every allocated ID.

```sh
artifact="${ARTIFACTS_ROOT:?set ARTIFACTS_ROOT to the external SSD mount}/CodexBuilds/LorcanaCatalogGoal-20261111"
evidence="$artifact/SourceEvidence"
review="$artifact/ReviewedCatalog-20261112"
out=$(mktemp -d)
cp TradingCardScanner/LorcanaCatalogSeed/physical-id-assignments.json "$out/assignments.json"
python3 scripts/build_lorcana_discovery_catalog.py \
  --cards "$evidence/en-allCards.json" --groups "$evidence/groups.json" \
  --products "$evidence/products" --output "$out/discovery.json"
python3 scripts/build_lorcana_market_catalog.py \
  --discovery "$out/discovery.json" --sources "$review/market" \
  --baseline "$evidence/baseline/candidate.json" --assignments "$out/assignments.json" \
  --output "$out/market.json" --report "$out/report.json" \
  --reviewed-at 816177600 --review-later-expansions --review-disney100
python3 scripts/audit_catalog_coverage.py --output "$out/audit" \
  --lorcana-baseline-ref 7daef56 \
  --lorcana-publisher-gallery "$evidence/gallery.html" \
  --lorcana-market-capture "$review/market"
```

For the next catalog refresh, capture the English gallery, the LorcanaJSON
inventory, and the TCGCSV products and lanes together. Inspect gallery
differences, update the independent release inventory for new sets, then
replay and compare with the previous shipped catalog. Any new sibling or
changed finish declaration must be accounted for before a family can remain
complete. Check the Swift scan, Browse, and finish matrix before adopting the
generated bundle. The CI audit checks the release inventory, source-to-family
coverage, and existing printing identity against the pull request base.

The final dirty checkout based on `7daef56` passed 458 selected app tests in
Debug on the dedicated iOS 27 simulator using `TradingCardScanner-ProfileLocal`.
Three live opt-ins skipped. Retained-input tests checked all 1,677 added
printings and their finishes, all mapped quotes for those additions, and
ownership export and replay across the reviewed distribution groups.
The 46 offline catalog and audit tests passed. The result bundle is
`CodexBuilds/LorcanaCatalogGoal-20261111/LorcanaReleaseVerification-20261112.xcresult`
on the external SSD.
The broader scanner run had one One Piece recovery fixture failure and two
Keychain failures on the unsigned simulator.

See the [release inventory](../../scripts/lorcana_release_inventory.json),
[product evidence](../../scripts/lorcana_product_evidence.json) and
[October expansion review](../research/lorcana-expansion-candidate-review-2026-10-23.md).
Physical-camera acceptance and production distribution require their own
checks.
