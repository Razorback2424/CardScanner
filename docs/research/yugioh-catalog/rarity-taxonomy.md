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

### Common and Short Print rows for the same code (2026-11-21)

YGOPRODeck sometimes lists both **Common** and **Short Print** for the same
English card, release and code. The physical rarity comparison already
recognized both labels as Common, but the raw row count still expected two
printings. Konami lists one Common finish and one artwork entry for each
reviewed card, and TCGplayer lists one Common product with exact edition lanes.
Yugipedia describes Short Print as a distribution distinction for cards with
the Common finish. Its English Cybernetic Revolution galleries show that
finish on 1st Edition and Unlimited copies of Dragon's Mirror.
[Short Print](https://ftp.yugipedia.com/wiki/Short_print)
[1st Edition gallery](https://ftp.yugipedia.com/wiki/Set_Card_Galleries%3ACybernetic_Revolution_%28TCG-EN-1E%29)
[Unlimited gallery](https://ftp.yugipedia.com/wiki/Set_Card_Galleries%3ACybernetic_Revolution_%28TCG-EN-UE%29)

Cardmarket files Dragon's Mirror once under Cybernetic Revolution. PriceCharting
separates Jar Turtle by edition, and its PSA/CGC population view indexes
Dragon's Mirror by edition with no population figures for the sampled entries.
PSA's registry confirms the Cybernetic Revolution 1st Edition set scope.
Individual PSA registry rows could not be retrieved, so the grading references
serve as cross-checks of catalog organization.
[Cardmarket](https://www.cardmarket.com/en/YuGiOh/Products/Singles/Cybernetic-Revolution)
[PriceCharting checklist](https://www.pricecharting.com/console/yugioh-extreme-victory?sort=model-number&view=table)
[PSA/CGC population view](https://www.pricecharting.com/pop/set/yugioh-cybernetic-revolution)
[PSA registry index](https://www.psacard.com/psasetregistry/tcg/yu-gi-oh-sets/371)

The `common-short-print-distribution-pair-v1` rule pins the exact group,
code, TCGplayer product ID and title, YGOPRODeck card ID and title, and supported
edition lanes. It counts the two labels as one finish only when both exact
source rows match the sole marketplace product. Additional source rows,
marketplace printings, art labels, or lane conflicts retain the shortfall.
The exact spelling pair for `SOD-EN059` is **Cemetery Bomb** in TCGplayer
and **Cemetary Bomb** in Konami and YGOPRODeck. Gatling Dragon in OTS
Tournament Pack 7 uses the single reviewed Unlimited lane.
[Reviewed rule and capture hashes](../../../scripts/yugioh_correspondence_rules.json)
[Konami's Cemetary Bomb printing history](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=6148&ope=2&request_locale=en)
[Konami's Gatling Dragon printing history](https://www.db.yugioh-card.com/yugiohdb/card_search.action?cid=6264&ope=2&request_locale=en)

These were the last correspondence exceptions for eight set prefixes in the
retained capture. The bundle keeps the existing edition choices. All 720
automatic scan codes remain identical.

| English release | Closed collector numbers (after `-EN`) | Evidence |
| --- | --- | --- |
| Cybernetic Revolution (`CRV`) | 040, 042, 044, 060 | [Konami](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=1&pid=11104004&rp=99999&request_locale=en) · [TCGplayer via TCGCSV](https://tcgcsv.com/tcgplayer/2/160/products) |
| Extreme Victory (`EXVC`) | 035, 036, 062, 079 | [Konami](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=1&pid=11110003&rp=99999&request_locale=en) · [TCGplayer via TCGCSV](https://tcgcsv.com/tcgplayer/2/203/products) |
| Maximum Crisis (`MACR`) | 035 | [Konami](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=1&pid=11116003&rp=99999&request_locale=en) · [TCGplayer via TCGCSV](https://tcgcsv.com/tcgplayer/2/1922/products) |
| OTS Tournament Pack 7 (`OP07`) | 026 | [Konami](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=1&pid=1121217001&rp=99999&request_locale=en) · [TCGplayer via TCGCSV](https://tcgcsv.com/tcgplayer/2/2228/products) |
| Rise of Destiny (`RDS`) | 043, 044, 047, 051, 053, 054, 055 | [Konami](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=1&pid=11103005&rp=99999&request_locale=en) · [TCGplayer via TCGCSV](https://tcgcsv.com/tcgplayer/2/274/products) |
| Raging Battle (`RGBT`) | 080 | [Konami](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=1&pid=11108001&rp=99999&request_locale=en) · [TCGplayer via TCGCSV](https://tcgcsv.com/tcgplayer/2/270/products) |
| Soul of the Duelist (`SOD`) | 039, 040, 044, 045, 048, 049, 050, 052, 054, 056, 058, 059 | [Konami](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=1&pid=11103003&rp=99999&request_locale=en) · [TCGplayer via TCGCSV](https://tcgcsv.com/tcgplayer/2/285/products) |
| Storm of Ragnarok (`STOR`) | 036, 037, 062, 077 | [Konami](https://www.db.yugioh-card.com/yugiohdb/card_search.action?ope=1&pid=11110000&rp=99999&request_locale=en) · [TCGplayer via TCGCSV](https://tcgcsv.com/tcgplayer/2/302/products) |

## Hidden Arsenal: Chapter 1 Duel Terminal parallels

**Decision (2026-11-20):** TCGplayer's "Duel Terminal Technology Common" and "Duel Terminal Technology Ultra Rare" name the same physical finish as YGOPRODeck's "Duel Terminal Normal Parallel Rare" and "Duel Terminal Ultra Parallel Rare". The `hac1-duel-terminal-technology-v1` rule maps between the two naming conventions.

**Evidence:**
1. The HAC1 blister pack's product description on TCGplayer (TCGCSV group 2941, sealed product) reads: *"3 Duel Terminal Technology Ultra Rares, 1 Duel Terminal Technology Common, 14 standard Commons"*. The pack's contents description uses "Duel Terminal Technology" for the parallel-finish pulls in this set.
2. TCGplayer product names for these cards carry a "(Duel Terminal)" suffix (e.g. "Brionac, Dragon of the Ice Barrier (Duel Terminal)"), distinguishing them from the regular printings in the same group.
3. YGOPRODeck lists the same HAC1-EN codes with "Duel Terminal Normal Parallel Rare" (DNPR) and "Duel Terminal Ultra Parallel Rare" (DUPR) rarity labels.
4. Both sources list exactly two tiers of DT parallel (Common-level and Ultra-level) alongside standard Common and Secret Rare printings.
5. Konami's [HAC1 product page](https://www.yugioh-card.com/en/products/hac1/) describes "6 Ultra Rares (2 standard Ultra Rares, 4 colorful Ultra Rares)" and "30 Commons" per box — the DT Technology variants are a subset of these. Yugipedia (403 for automated fetches) and Cardmarket (403) could not be checked programmatically.

The rule is pinned to `expectedProductsSHA256` for group 2941. If TCGplayer changes the group's products, the rule stops applying.
