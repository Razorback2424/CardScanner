# Pokémon finish coverage: collector conventions

**Status:** current. Decided 2026-11-18 for the batch finish certifier
(`scripts/certify_pokemon_finish_coverage.py report-all` / `certify-all`).
The machine-readable rules are in
[`publisher/pokemon-finish-conventions.json`](../../../publisher/pokemon-finish-conventions.json)
and [`publisher/pokemon-finish-coverage-groups.json`](../../../publisher/pokemon-finish-coverage-groups.json).

## Principle

The owner's rule: follow what collectors expect when they look up the card.
Where references genuinely disagree, give the user more choice. Never present
a guess as certified fact, never show a wrong price, and never slow the app.

In the app this works as follows:
- A **certified** card lists exactly the printings the evidence proves.
- A card that is not certified keeps its projected finishes as selectable
  choices and shows "Finishes not yet confirmed" in card details.

Leaving a card uncertified is therefore the flexible option. It is never a
silent claim.

Every convention below only builds a cited resolution. `certify()` re-checks
that resolution with its unchanged gates. Each certificate records how it
differs from the bundled checklist slots (`slotChanges`).
`testCertifiedFinishCoverageIsCompleteAndConsistent` then checks each
difference against the set's evidence report. That check replaces the earlier
"certificate equals slots" test with a stricter one: nothing differs without
evidence.

## Decisions

### Q1 Finishes beyond the bundled slots (`checklistMissingFinish`)

- **What collectors expect.** Every card except Ultra Rares, Secret Rares and
  full arts has a Reverse Holofoil counterpart. This has held since Legendary
  Collection
  ([Bulbapedia: Holofoil](https://bulbapedia.bulbagarden.net/wiki/Holofoil)).
  Price guides list "Hitmontop [Reverse Holo] Lost Thunder 113" as its own
  printing
  ([PackMagik](https://www.packmagik.com/cards/1742367065209x369973251910796350-reverse-holo)).
  TCGplayer sells it as a Reverse Holofoil lane on the same product
  ([product 178926](https://www.tcgplayer.com/product/178926)).
- **Source data.** The bundled slots come from TCGdex. TCGdex still lists
  Hitmontop SM8 113 as normal only
  ([API](https://api.tcgdex.net/v2/en/cards/sm8-113)), so refreshing from
  TCGdex would not fix the slots.
- **Decision.** A certificate may add a finish the slots omit when either of
  these supports it:
  - market agreement with the retained audited evidence
    (`legacy-finish-evidence.json` or `finish-minimums.json`); or
  - the reviewed `reverse-holo-lane` convention: a Reverse Holofoil lane with
    a positive market price on the card's own set-group product.

  Every addition is recorded in `slotChanges.added`, and the app test checks
  it against the report's market lanes or cited resolution.
- **Excluded sets.** The reverse-lane convention skips sets where a Reverse
  lane does not name a single printing:
  - Expedition, whose holo and non-holo rares share reverses;
  - EX Hidden Legends and FireRed & LeafGreen (energy-pattern reverses);
  - EX Team Rocket Returns through Power Keepers (stamped; see Q3);
  - Ascended Heroes, Black Bolt, White Flare and SV Energy (patterned).

### Q2 Gold and Rainbow secret rares (`rainbow`/`gold` + `holo`)

- **What collectors expect.** One printing. TCGdex itself lists a single
  variant for Kyurem VMAX 197 (type holo, foil rainbow, TCGplayer product
  284152) ([API](https://api.tcgdex.net/v2/en/cards/swsh11-197)). PriceCharting
  has one page for the card
  ([PriceCharting](https://www.pricecharting.com/game/pokemon-SWSH-Lost-Origin/Kyurem-VMAX-197)).
  Retailers name the rarity, not a second finish
  ([CoolStuffInc](https://www.coolstuffinc.com/p/Pokemon/Kyurem+VMAX+%28Rainbow+Rare%29+-+197%2F196)).
- **Decision.** The certificate keeps the priced holo printing and records the
  `gold`/`rainbow` slot in `slotChanges.removed`. This matches the app's
  existing `rarityFinishAliasesHolo`. The set list mirrors
  `PokemonMasterSetDefinition.rarityFinishAliasSetIDs`, and
  `testTreatmentAliasConventionMatchesTheAppAliasSets` keeps them equal.
- **Exception.** 151 Mew 205 stays separate, because its gold slot also names
  the UPC metal card.

### Q3 Stamped parallels

Stamped printings are separate collectibles. TCGplayer and TCGdex list them
as their own products and variants. Three cases are decided:

- **EX-era set-logo reverses** (`ex-set-logo-reverse`). From EX Team Rocket
  Returns through EX Power Keepers, every reverse holo carries the expansion
  logo
  ([Bulbapedia](https://bulbapedia.bulbagarden.net/wiki/EX_Team_Rocket_Returns_(TCG))).
  TCGplayer sells it as the Reverse Holofoil lane
  ([Kingdra 86445](https://www.tcgplayer.com/product/86445)), and retailers
  title it "(Stamped)"
  ([example](https://tcgosaurus.tcgsync.com/products/kingdra-12-109-stamped-ex-team-rocket-returns)).
  That lane is evidence for the card's set-logo stamp finish, not for a second
  plain reverse. This matches the app's `isPackReversePattern`.
- **Modern set-name stamps** (`set-name-stamp`). TCGplayer titles them
  "<card> - <number> (<Set Name> Stamp)" or "(<Set Name> Stamped)" in
  Miscellaneous Cards & Products or the era's promo group
  ([Corviknight 274102](https://www.tcgplayer.com/product/274102),
  [Tyranitar Paldea Evolved Stamp](https://cardlist.io/cards/pokemon/pk-mcap/pk-mcap-tyranitar-paldea-evolved-stamp-135)).
  The stamp must name the card's own set.
- **Not yet decided.** The rest stay open as `parallelFinishNotListed`:
  - Player Rewards, League, Snowflake (holiday calendar), GameStop/EB Games,
    regional championships and Pokémon Day;
  - World Championship deck player stamps.

  For these, TCGplayer's naming varies by product or event, and there is no
  single verifiable title rule. The app keeps these finishes selectable and
  shows them as not yet confirmed.

### Q4 Prize Pack Cosmos

- **What collectors expect.** Every Prize Pack card carries the Play! Pokémon
  stamp. Later series print their foils as Cosmos Holofoil
  ([Series One](https://bulbapedia.bulbagarden.net/wiki/Play!_Pok%C3%A9mon_Prize_Pack_Series_1_(TCG)),
  [Series Seven](https://bulbapedia.bulbagarden.net/wiki/Play!_Pok%C3%A9mon_Prize_Pack_Series_Seven_(TCG))).
  Sellers grade and list them as stamped promos.
- **Decision.** A Prize Pack Cosmos is a separate stamped printing, not
  evidence of plain Cosmos. The `cosmos-holo-exclusives` convention excludes
  Prize Pack, League and Trick or Trade groups. It accepts TCGplayer's three
  spellings ("Cosmos Holo", "Cosmos Holofoil", "Cosmos Foil") in Deck
  Exclusives, Blister Exclusives and Miscellaneous.

### Q5 Sets without a market group

- **Linked.** `bog`: TCGplayer's "Best of Promos" holds the nine 2002 Best of
  Game promos, numbered N/009. Its Winner-stamped copies are separate
  printings and stay open.
- **Left open, with reasons in the links file:**
  - `exu`: the Unown Collection sits inside the EX Unseen Forces group, shared
    with ex10. Its products are titled "Unown (A)" and numbered A/28.
  - `fut2020`: the five Futsal promos sit inside Miscellaneous Cards &
    Products.
  - `xya`: the Yellow A alternates are split across Alternate Art Promos and
    their own set groups.

  Linking any of these needs a group-subset capture format, which the
  single-set certifier does not have yet.

### Historical Normal placeholder (largest remaining reason after Q1)

- **The problem.** `legacy-finish-evidence.json` marks every card in 30 BW, XY
  and SM sets with a Normal placeholder for review. TCGdex lists Ultra Rares
  such as Venusaur & Snivy GX as normal only
  ([API](https://api.tcgdex.net/v2/en/cards/sm12-1)).
- **What collectors expect.** A holo rare is not also sold non-holo.
- **Decision** (`historical-normal-placeholder`). When all three hold, the
  certificate records a Normal review decision of `exclude`:
  - no audited minimum asserts Normal;
  - the card's own TCGplayer products sell no Normal lane;
  - the rest agrees.

  The app already withholds this placeholder
  (`PokemonFinishMinimumCatalog.projectingLegacy`). Cards whose audited minimum
  lists Normal stay open for a person.

### Reviewed unnumbered Energy (`reviewedUnnumberedEnergy`)

- **The problem.** Sets such as Sword & Shield (`swsh1`), Sun & Moon (`sm1`)
  and Team Up (`sm9`) include basic Energy that has no collector number.
  Those cards already live in `reviewed-unnumbered-energy.json` as their own
  printings, keyed by TCGplayer product. Their presence blocked the whole
  set's numbered certificate.
- **What collectors expect.** Basic Energy is a separate, unnumbered product
  line, filed by TCGplayer as its own product per type and finish. It is not
  part of the set's numbered checklist.
- **Decision.** The numbered certificate covers only the checklist cards.
  Reviewed unnumbered Energy keeps its reviewed finishes and still shows
  "Finishes not yet confirmed". It no longer blocks the set.
  `certify()` refuses a certificate that would include a reviewed Energy card.
- **Result.** `swsh1` was certified (216 cards). `sm1` and `sm9` remain open
  for card-level reasons.

### EX Energy-pattern reverse holo (`ex-energy-reverse`)

- **The problem.** For EX Hidden Legends (`ex5`) and EX FireRed & LeafGreen
  (`ex6`), the checklist lists both a plain reverse and an Energy-pattern
  reverse. TCGplayer sells one Reverse Holofoil lane per card.
- **What collectors expect.** One reverse holo per card, and it carries the
  energy-symbol pattern. Sources: Bulbapedia's
  [Holofoil](https://m.bulbapedia.bulbagarden.net/wiki/Holofoil) page, and
  retailers listing one "Reverse Holo" per card (for example
  [ex6-90](https://facetofacegames.com/products/energy-switch-90112-uncommon-ex6-90-reverse-holo)).
- **Decision.** The Reverse Holofoil lane is evidence for the Energy pattern,
  and the plain reverse slot is the same printing. This matches the app's
  `isPackReversePattern`.
- **Result.** About 70 items closed. Neither set is certified yet: both still
  have World Championship deck stamps, Cracked Ice and extra Normal lanes.

## 8. Celebrations Classic Collection number remap (`celebrations-classic-collection`)

- **Convention ID.** `celebrations-classic-collection` in `numberRemaps`.
- **Observation.** The checklist uses CC numbers (CC001-CC025) while TCGplayer
  group 2931 lists each Classic Collection card under its original expansion
  number (for example Blastoise as 2/102, Charizard as 4/102). All 25 products
  have exactly one Holofoil lane, matching the checklist's holo requirement.
- **Sources.** [TCGCSV group 2931 products](https://tcgcsv.com/tcgplayer/3/2931/products),
  [TCGCSV group 2931 prices](https://tcgcsv.com/tcgplayer/3/2931/prices),
  [Bulbapedia Celebrations](https://bulbapedia.bulbagarden.net/wiki/Celebrations_(TCG)#Classic_Collection).
- **Decision.** A reviewed mapping from each CC number to the original number
  and TCGplayer product ID resolves the mismatch. The mapping is verified
  against the TCGCSV product data: each product ID exists at the stated number
  with a single Holofoil lane. Market product rows from the same group are
  excluded because the remap accounts for them.
- **Result.** 47 items closed (25 CC cards + 22 market products), cel25cc
  certified.

## Sources not reachable

Bulbapedia returns HTTP 403 to automated fetches. Its statements above come
from search-index excerpts of the cited pages, not from a direct page read.
PSA and CGC population pages and Cardmarket were searched. They gave no
statement more specific than the sources above, so they are not cited.
