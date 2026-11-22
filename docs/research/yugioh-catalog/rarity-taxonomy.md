# Yu-Gi-Oh! rarity taxonomy rules

**Decision (2026-11-20):** Two rarity-naming conventions are recorded as reviewed data in `scripts/yugioh_correspondence_rules.json`. They decide only whether a TCGplayer product and a YGOPRODeck `card_sets` row describe the same printing. Displayed rarity, editions, artwork and prices are unchanged.

## Prismatic Collector's and Ultimate Rares (RA01–RA05)

TCGplayer calls these "Prismatic Collector's Rare" and "Prismatic Ultimate Rare". YGOPRODeck calls them "Collector's Rare" and "Ultimate Rare". Konami's product pages describe them as "Prismatic"-style Collector's and Ultimate Rares: [RA01](https://www.yugioh-card.com/en/products/ra01/), [RA02](https://www.yugioh-card.com/en/products/ra02/), [Quarter Century Bonanza](https://www.yugioh-card.com/en/products/qcb/) and [RA05](https://www.yugioh-card.com/en/products/ra05/). [Quarter Century Stampede](https://www.yugioh-card.com/en/products/qcs/) describes itself as the direct successor to Bonanza, with the same set and pack configuration.

- The rules `ra01-`, `ra03-`, `ra04-` and `ra05-prismatic-taxonomy-v1` copy the reviewed `ra02-prismatic-taxonomy-v1`.
- Each rule is pinned to its group's `expectedProductsSHA256`. If TCGplayer changes the group's products, the rule stops applying and the group is reported under `taxonomyScopeDriftGroups`.
- The rules cleared 313 of the 331 open codes in those groups. The remaining 18 have no YGOPRODeck row, or a source row that disagrees, and stay open.

## Short Print and Super Short Print

YGOPRODeck labels some Commons by pack ratio ("Short Print", "Super Short Print"). Konami set lists and TCGplayer both treat these cards as Commons, because the card is physically a Common. The `short-print-is-common-v1` entry under `sourceRarityAliases` reads these labels as Common:
- in the exact-correspondence check;
- in the rarity-count check (`rarityShortfall`).

A Short Print row can therefore match only a product sold as Common.

Corroboration: Konami's reviewed Pharaoh's Servant checklist (`yugioh_printing_inventories.json`) lists the 12 PSV Short Prints as Common. With the label reconciled, those 12 codes pass every automatic-selection gate. `autoEligibleCodes` grew from 262 to 274.

## Hidden Arsenal: Chapter 1 Duel Terminal parallels

**Decision (2026-11-20):** TCGplayer's "Duel Terminal Technology Common" and "Duel Terminal Technology Ultra Rare" name the same physical finish as YGOPRODeck's "Duel Terminal Normal Parallel Rare" and "Duel Terminal Ultra Parallel Rare". The `hac1-duel-terminal-technology-v1` rule maps between the two naming conventions.

**Evidence:**
1. The HAC1 blister pack's product description on TCGplayer (TCGCSV group 2941, sealed product) reads: *"3 Duel Terminal Technology Ultra Rares, 1 Duel Terminal Technology Common, 14 standard Commons"*. The pack's contents description uses "Duel Terminal Technology" for the parallel-finish pulls in this set.
2. TCGplayer product names for these cards carry a "(Duel Terminal)" suffix (e.g. "Brionac, Dragon of the Ice Barrier (Duel Terminal)"), distinguishing them from the regular printings in the same group.
3. YGOPRODeck lists the same HAC1-EN codes with "Duel Terminal Normal Parallel Rare" (DNPR) and "Duel Terminal Ultra Parallel Rare" (DUPR) rarity labels.
4. Both sources list exactly two tiers of DT parallel (Common-level and Ultra-level) alongside standard Common and Secret Rare printings.
5. Konami's [HAC1 product page](https://www.yugioh-card.com/en/products/hac1/) describes "6 Ultra Rares (2 standard Ultra Rares, 4 colorful Ultra Rares)" and "30 Commons" per box — the DT Technology variants are a subset of these. Yugipedia (403 for automated fetches) and Cardmarket (403) could not be checked programmatically.

The rule is pinned to `expectedProductsSHA256` for group 2941. If TCGplayer changes the group's products, the rule stops applying.

## Publisher-confirmed rarity for source placeholders

**Decision (2026-11-21).** Where YGOPRODeck puts `New`, `New artwork`, or a deck quantity such as `2` or `3` in its rarity field, the English Konami card-detail record can supply the physical rarity for an exact reviewed code. For example, `MZTM-EN007` Defense of the Temple is Rare, and `L5DD-ENA01` Lonefire Blossom is Common. The latter shows the quantity 3 in a separate checklist column. [Konami card detail for Defense of the Temple](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=21041&ope=2&request_locale=en) · [Legendary 5D's Decks English checklist](https://ftp.yugipedia.com/wiki/Set_Card_Lists%3ALegendary_5D%27s_Decks_%28TCG-EN%29)

`scripts/yugioh_official_rarity_placeholders.json` pins the eight group names and product response hashes, the raw source labels, and the exact English card title, code, canonical source ID, and TCGplayer product ID. Each record names a captured English publisher release and pins the card-detail page hash. The builder requires an exact singleton in both the source and marketplace. It refuses competing products, changed titles or raw rows, and other languages. The resulting correspondence does not confer automatic scan selection.

For `BLMM-EN012`, the English checklist places “New” under notes and Ultra Rare under rarity. TCGplayer, Cardmarket and PriceCharting corroborate the Monster Mayhem printing. PSA’s same-set records also distinguish Starlight Rare by finish, though the reviewed card-detail page is the source of the rarity for each code. [English Monster Mayhem checklist](https://ftp.yugipedia.com/wiki/Set_Card_Lists%3ABattles_of_Legend%3A_Monster_Mayhem_%28TCG-EN%29) · [TCGplayer product](https://www.tcgplayer.com/product/635896) · [Cardmarket](https://www.cardmarket.com/en/YuGiOh/Products/Singles/Battles-of-Legend-Monster-Mayhem/The-Fabled-Behilmoth) · [PriceCharting](https://www.pricecharting.com/game/yugioh-battles-of-legend-monster-mayhem/the-fabled-behilmoth-blmm-en012) · [PSA same-set record](https://www.psacard.com/cert/152452989)

The reviewed codes closed both `rarityShortfall` and `unreviewedCorrespondence` in two offline captures. Counts by prefix were `L5DD` 27, `BLMM` 22, `MZTM` 21, `L26D` 20, `LAVD` 19, `BLGG` 12, `KC01` 4, and `JUSH` 1. Monster Mayhem cleared its final 22 correspondence gaps. Deck bonus variants, misprint listings, and unmatched canonical titles still require their own evidence.
