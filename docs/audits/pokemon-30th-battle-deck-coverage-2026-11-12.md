# Pokémon 30th Celebration Battle Deck catalog coverage

**Open.** Checked November 12, 2026 against signed production revision 23
and the working tree based on `7daef56`. Recheck weekly during Pokémon
catalog review until the verified deck finishes are selectable in Scan and
Browse.

Pokémon released the English Espeon ex and Umbreon ex Battle Decks on
October 30, 2026. Each contains 60 foil cards. The box backs and decklists give
24 distinct entries per deck and 38 across both, with 10 shared. Each deck
contains four stamped Lillie's Determination `MEG 119/132` and two stamped
Pokégear 3.0 `BLK 084/086`. The owner's photos show the Pikachu 30 stamp and
the original footers on both. [Pokémon product page](https://www.pokemon.com/us/pokemon-tcg/product-gallery/30th-celebration-battle-deck-espeon-ex-and-30th-celebration-battle-deck-umbreon-ex),
[Espeon box back](https://pisces.bbystatic.com/image2/BestBuy_US/images/products/770c5a27-794c-4c6d-95ee-3f5f38adc851.png),
[Umbreon box back](https://pisces.bbystatic.com/image2/BestBuy_US/images/products/3a4dc988-8eca-4887-9d0d-cc953c769791.png),
[Espeon decklist](https://bulbapedia.bulbagarden.net/wiki/Espeon_ex_30th_Celebration_Battle_Deck_%28TCG%29#Deck_list),
[Umbreon decklist](https://bulbapedia.bulbagarden.net/wiki/Umbreon_ex_30th_Celebration_Battle_Deck_%28TCG%29#Deck_list).

## Catalog and provider results

- **Scan and Browse.** The signed snapshot has all 38 underlying card
  identities, and the bundled checklist has 27. The catalog lacks 34
  deck-specific finish entries. Scan resolves the photographed cards to
  `me01-119` and `sv10.5b-084` by the footer. Their existing finishes include
  ordinary Reverse. Pokégear also has a separate Poké Ball parallel. The
  Pikachu stamp sits in the artwork and the footer supplies the same card
  identity for every one of those copies. An ordinary finish selection can
  therefore record the stamped copy under the wrong finish. [Signed snapshot](https://catalog.scan-stash.com/v1/releases/23/pokemon-catalog-snapshot.json),
  [Scan lookup](../../TradingCardScanner/Games/Pokemon/PokemonCatalogAdapter.swift),
  [finish resolver](../../TradingCardScanner/Models/TCGdexCard.swift).
- **TCGdex.** All 38 English card endpoints returned the underlying
  identities. The 23 numbered older-set cards and four `MEE` cards omit the
  30th-stamped deck variant. The seven `30C` reprints have the set-wide 30th
  stamp on their base records and omit the deck Reverse. The two photographed
  variants are also absent in TCGdex source at
  `5fbf524a3650cbf33926382388133c5a14965840`. [Lillie API record](https://api.tcgdex.net/v2/en/cards/me01-119?source=catalog-audit),
  [Pokégear API record](https://api.tcgdex.net/v2/en/cards/sv10.5b-084?source=catalog-audit),
  [Lillie provider source](https://github.com/tcgdex/cards-database/blob/5fbf524a3650cbf33926382388133c5a14965840/data/Mega%20Evolution/Mega%20Evolution/119.ts),
  [Pokégear provider source](https://github.com/tcgdex/cards-database/blob/5fbf524a3650cbf33926382388133c5a14965840/data/Scarlet%20%26%20Violet/Black%20Bolt/084.ts).
- **TCGplayer and TCGCSV.** The November 11 `20:05:27 UTC` feed and direct
  TCGplayer product details agree on 38 exact products and English SKU lanes.
  Group `1840` contains all 30 deck Reverse Holofoil products, including
  Lillie `729924` and Pokégear `729923`. Group `24461` contains four separate
  stamped Energy products `729815`–`729818` in its Holofoil lane. Specimen
  images confirm their original `MEE` numbers and the 30th stamp. Physical
  foil terminology for the Energy cards still needs a side-by-side specimen
  check. The two `MEP` promos have their own Holofoil identities and exact
  product handles in TCGdex. The two leads have their ordinary `30C`
  Holofoil handles in TCGdex and the market. Any distinct deck finish for
  either lead remains unverified. [Deck Exclusives products](https://tcgcsv.com/tcgplayer/3/1840/products),
  [Deck Exclusives price lanes](https://tcgcsv.com/tcgplayer/3/1840/prices),
  [Lillie SKU](https://mp-search-api.tcgplayer.com/v2/product/729924/details),
  [Pokégear SKU](https://mp-search-api.tcgplayer.com/v2/product/729923/details),
  [MEE products](https://tcgcsv.com/tcgplayer/3/24461/products),
  [stamped Energy specimen](https://www.radamspokestop.co.uk/shop-all/p/psychic-energy-battle-deck-exclusive-energy-mee-005-30th-celebrations-presented-by-pokmon-tcg).
- **Hosted prices.** The app's scoped index omits groups `1840` and `24451`.
  Its checksummed `24461` files omit all four deck Energy IDs and include the
  separate anniversary Energy run numbered `009`–`016`. The hosted `24722`
  files contain both lead products. JustTCG exact-product coverage remains
  unverified. [Hosted price index](https://catalog.scan-stash.com/market-prices/v1/index.json).

## English deck inventory

The 30 rows in Deck Exclusives group `1840` use the Reverse Holofoil lane.
The four `MEE` rows use group `24461`, the two `MEP` rows use `24451`,
and the two lead ex cards use `24722`. Those eight rows use the Holofoil
market lane. The quantities sum to 60 in each deck.

| Printed footer | Card | Espeon ex | Umbreon ex | TCGplayer product |
| --- | --- | ---: | ---: | ---: |
| 30C 057/128 | Zeraora | 0 | 2 | `729907` |
| 30C 070/128 | Espeon ex | 2 | 0 | `696834` |
| 30C 092/128 | Umbreon ex | 0 | 2 | `696835` |
| 30C 114/128 | Kangaskhan | 1 | 0 | `729920` |
| 30C 117/128 | Eevee | 3 | 0 | `729916` |
| 30C 118/128 | Eevee | 0 | 3 | `729819` |
| 30C 126/128 | Poké Pad | 4 | 4 | `729919` |
| 30C 127/128 | Switch | 2 | 2 | `729918` |
| 30C 128/128 | Ultra Ball | 3 | 4 | `729917` |
| ASC 183/217 | Boss's Orders (Corbeau) | 3 | 3 | `729934` |
| ASC 184/217 | Buddy-Buddy Poffin | 2 | 2 | `729931` |
| ASC 196/217 | Night Stretcher | 2 | 2 | `729932` |
| BLK 079/086 | Air Balloon | 2 | 2 | `729927` |
| BLK 084/086 | Pokégear 3.0 | 2 | 2 | `729923` |
| CRI 011/086 | Fennekin | 3 | 0 | `729911` |
| CRI 012/086 | Braixen | 2 | 0 | `729912` |
| CRI 013/086 | Delphox | 2 | 0 | `729910` |
| CRI 030/086 | Emolga | 0 | 1 | `729908` |
| JTG 146/159 | Brock's Scouting | 0 | 1 | `729906` |
| JTG 149/159 | Iris's Fighting Spirit | 2 | 2 | `729922` |
| MEE 002 | Basic Fire Energy | 8 | 0 | `729817` |
| MEE 004 | Basic Lightning Energy | 0 | 3 | `729816` |
| MEE 005 | Basic Psychic Energy | 4 | 0 | `729818` |
| MEE 007 | Basic Darkness Energy | 0 | 8 | `729815` |
| MEG 088/132 | Yveltal | 0 | 1 | `729909` |
| MEG 119/132 | Lillie's Determination | 4 | 4 | `729924` |
| MEG 125/132 | Rare Candy | 2 | 0 | `729926` |
| MEP 102 | Victini | 1 | 0 | `713286` |
| MEP 103 | Zeraora | 0 | 1 | `713285` |
| PBL 059/084 | Chi-Yu | 0 | 2 | `729903` |
| PBL 084/084 | Voltaic Lightning Energy | 0 | 2 | `729904` |
| PFL 014/094 | Moltres | 1 | 0 | `729915` |
| PFL 045/094 | Zacian | 1 | 0 | `729914` |
| PFL 067/094 | Toxel | 0 | 3 | `729902` |
| PFL 068/094 | Toxtricity | 0 | 2 | `731781` |
| PFL 087/094 | Dawn | 2 | 0 | `729913` |
| POR 084/088 | Rosa's Encouragement | 2 | 0 | `729928` |
| WHT 084/086 | Hilda | 0 | 2 | `729905` |

## Recheck and catalog admission

1. Join the printed set, number, and name to each live English TCGdex card.
   Recheck `variants_detailed` for the expected stamp and finish, and match
   the exact product against the TCGCSV group and English TCGplayer SKUs. A
   `30C` anniversary stamp by itself also appears on the base printing.
   Keep the two lead ex cards on watch for a corroborated deck distinction.
2. The marketplace evidence already supports a reviewed addition while TCGdex
   coverage catches up. Reuse the existing stamp-aware finish keys and original
   card identities. Add distinct Grand Master choices for the confirmed deck
   printings. The signed additional-variant validator currently accepts
   ordinary unstamped, Cosmos and jumbo membership. It needs explicit support
   for stamped membership. The `30C` Holo projection also needs to retain
   the confirmed deck Reverse. [Stamp keys](../../TradingCardScanner/Models/CardVariant.swift),
   [signed validator](../../PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogContract.swift),
   [Holo projection](../../TradingCardScanner/Models/TCGdexCard.swift).
3. Add only the matched group, product and finish to the scoped price feed.
   The existing Pokémon scope generator assumes Holofoil, so the 30
   `1840` entries need explicit Reverse Holofoil lanes. Verify both
   photographed cards in offline Browse and Scan. Use ordinary Reverse,
   Black Bolt Poké Ball, a `30C` pack card and unstamped `MEE` as controls.
   Confirm that saves use distinct finish keys and price requests use the
   corresponding exact SKU. [Price feed generator](../../scripts/market_price_feeds.py).
