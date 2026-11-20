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
1. Konami's official HAC1 blister pack description (embedded in TCGplayer product data via TCGCSV group 2941) reads: *"3 Duel Terminal Technology Ultra Rares, 1 Duel Terminal Technology Common, 14 standard Commons"* — confirming the "Duel Terminal Technology" label is Konami's name for the parallel finish in this set.
2. TCGplayer product names for these cards carry a "(Duel Terminal)" suffix (e.g. "Brionac, Dragon of the Ice Barrier (Duel Terminal)"), distinguishing them from the regular printings in the same group.
3. YGOPRODeck lists the same HAC1-EN codes with "Duel Terminal Normal Parallel Rare" (DNPR) and "Duel Terminal Ultra Parallel Rare" (DUPR) rarity labels.
4. Both sources list exactly two tiers of DT parallel (Common-level and Ultra-level) alongside standard Common and Secret Rare printings.
5. Konami's [HAC1 product page](https://www.yugioh-card.com/en/products/hac1/) describes "6 Ultra Rares (2 standard Ultra Rares, 4 colorful Ultra Rares)" and "30 Commons" per box — the DT Technology variants are a subset of these. Yugipedia (403 for automated fetches) and Cardmarket (403) could not be checked programmatically.

The rule is pinned to `expectedProductsSHA256` for group 2941. If TCGplayer changes the group's products, the rule stops applying.
