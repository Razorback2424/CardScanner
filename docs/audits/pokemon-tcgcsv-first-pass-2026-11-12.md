# First Pokémon TCGCSV comparison

November 12, 2026. The audit captured TCGCSV build `20:06:19 UTC` across
all 221 Pokémon groups. It retained 33,100 products and 45,773 price rows.
Three group exports were empty without a declared item count. The comparison
uses signed catalog revision 24 with the `03fcf38` checkout and its pending
M26 app changes.

The ProfileLocal audit test activated the signed release in an isolated
simulator catalog. It exported the 216 installed Browse set pages, checked
Scan with explicit printed codes where available, and recorded exact product
bindings and detail links. Legacy footers without verified scan inputs are
marked untested. Name and number matches suggest a base identity for review.
Exact printing and live provider coverage require separate evidence.

## Confirmed gaps and controls

| Family | Evidence |
| --- | --- |
| Delta Reign deck cards | `DLR 021/103` Magmortar and `DLR 075/103` Kommo-o resolve in Scan and Browse with Holo and Reverse choices. Both also have an English Normal deck printing. [Magmortar 732417](https://www.tcgplayer.com/product/732417), [Kommo-o 732418](https://www.tcgplayer.com/product/732418), [prerelease deck specimens](https://www.pokejoelcollectables.com/product-page/all-2-non-holo-rare-from-delta-reign-prerelease-decks-delta-reign-non-holos). |
| Delta Reign Black Star Promos | `MEP 111–117` are absent from the installed checklist. The TCGdex English fallback returned 404 for each number and returned the adjacent `MEP 110` control. TCGCSV lists 11 products across the seven numbers, including three Staff products and the Pokémon Center Kyogre. The stamped Kyogre has an exact English Holofoil SKU and lacked a market quote in this capture. [Mega Evolution promo products](https://tcgcsv.com/tcgplayer/3/24451/products), [Pokémon's product showcase](https://www.pokemon.com/us/news/pokemon-tcg-mega-evolution-delta-reign-product-showcase), [stamped Kyogre 732872](https://www.tcgplayer.com/product/732872). |
| Prize Packs | Scan and Browse show the underlying Zeraora `078/182` and Bug Catching Set `143/167` with their expansion finishes. The Cosmos and left-stamp choices are absent from those installed card records. TCGplayer confirms separate English Holofoil and Normal SKUs respectively. [Zeraora 704473](https://www.tcgplayer.com/product/704473), [Bug Catching Set 709703](https://www.tcgplayer.com/product/709703). |
| Wizards and Nintendo promos | The installed Browse catalog lacks the `basep` and `np` set pages. A prior retained TCGdex audit recorded 53 Wizards and 40 Nintendo cards. The two market groups also contain reprints and other products. [Prior historical promo audit](pokemon-residual-promos-2026-11-02/README.md#all-eight-residual-groups). |
| M26 and the 30th Battle Decks | All 15 M26 and all 34 reviewed Battle Deck products matched the installed Scan and Browse finishes and exact card-detail links. The Battle Decks had 34 hosted quotes. All 15 M26 quotes existed upstream. Both public hosts returned 404 for the M26 product and price files even after the hosted feed refreshed to the November 12 source build. [Upstream M26 quotes](https://tcgcsv.com/tcgplayer/3/24938/prices), [hosted feed index](https://catalog.scan-stash.com/market-prices/v1/index.json). |

## Retained evidence

The first pass and repeat are under `.codex_build_pokemon_tcgcsv/runs/`. Follow
`latest-run.txt` to the current `summary.json`, `review-queue.csv`, and
`comparison.json`. The repeat found zero coverage changes and checked the
newer hosted price build without downloading the same TCGCSV build again.
The 4,126 review rows include unresolved product bindings, finish leads, and
pricing gaps. Only the examples checked above are confirmed here. Direct
spot-check receipts are in `.codex_build_pokemon_tcgcsv/first-pass/spot-checks`.

The exported app inventory used an iOS 27.0 simulator and the ProfileLocal
DebugRemoteLocal app. The audit XCTest was recompiled and linked into the
already-built app's test bundle on T7 because the machine's SwiftPM cache
symlinks pointed to an unavailable drive. The first complete runner result is
`inventory.xcresult` under the `20261112T211721Z-tp367123` run directory.
The [publisher runbook](../../publisher/README.md#daily-tcgcsv-coverage-audit)
describes the daily command and the evidence boundaries.
