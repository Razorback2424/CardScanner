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

## Star Pack VRAINS duplicate Starfoil label (2026-11-21)

Konami describes 49 Common printings and 50 Starfoil printings over 50
collector numbers. Its card database calls the single foil lane
“Shatterfoil” in this set and shows one artwork entry per title. TCGplayer,
the English specimen gallery, PriceCharting and Cardmarket file the same
foil as Starfoil or Starfoil Rare. The collector guides keep the Common and
foil as separate choices. This decision applies to Star Pack VRAINS alone.
[Konami product description](https://www.yugioh-card.com/en/products/star_vrains/)
[Konami card database](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=1&pid=11117002&request_locale=en&rp=99999)
[TCGplayer](https://www.tcgplayer.com/categories/trading-and-collectible-card-games/yugioh/price-guides/star-pack-vrains)
[English specimen gallery](https://ftp.yugipedia.com/wiki/Set_Card_Galleries%3AStar_Pack_VRAINS_%28TCG-EN-1E%29)
[PriceCharting](https://www.pricecharting.com/console/yugioh-star-pack-vrains?sort=model-number&view=table)
[Cardmarket](https://www.cardmarket.com/en/YuGiOh/Products/Singles/Star-Pack-VRAINS)

The rule pins the set, 49 exact English codes, the marketplace product
file hash, and the reviewed Konami checklist hash. For each code, the
exact Common and Starfoil Rare products must already correspond to their
two YGOPRODeck rows and carry the sole 1st Edition lane. Only an additional
“Starfoil” source row for the same card and release is redundant.
Decode Talker (`SP18-EN031`) was already complete with its single foil.
The replay removed the three false ledger reasons for every affected code.
Both marketplace choices, including their artwork and prices, are preserved.
[Reviewed rule](../../../scripts/yugioh_correspondence_rules.json)
[Konami Dotscaper `SP18-EN011` printings](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=13193&ope=2&request_locale=en)
[TCGplayer Dotscaper foil product](https://www.tcgplayer.com/product/164000/yugioh-star-pack-vrains-dotscaper-starfoil)
