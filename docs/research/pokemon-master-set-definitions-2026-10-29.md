# Pokémon Master and Grand Master criteria

**Status:** researched collector contract and local implementation — 2026-10-29.

## Collector convention and app scope

There is no official Pokémon definition of either term. The useful common
distinction is the source of the physical card, rather than the name of its foil:

| Goal | Includes | Excludes from this goal |
| --- | --- | --- |
| Master | Every numbered card, including secret rares, and every confirmed booster-pack parallel of those cards. | Promotional stamps, product-only finishes, and deck-only reprints. |
| Grand Master | Master plus cataloged promotional, stamped, product-exclusive, and documented printing variants associated with the checklist. | Uncataloged variants, other languages, and oversized cards. |

[Collector discussion](https://www.reddit.com/r/pkmntcgcollections/comments/1qae5y5/we_need_agreement_on_sets_definitions/)
supports this distinction while also documenting disagreement over errors,
jumbos, promo numbering, and the term “True Master.”
[MasterSet's collector guide](https://masterset.io/master-set) similarly includes
promotional and special product printings in Grand Master and treats combined
vintage print runs as another possible scope. These are conventions, not an
official universal checklist.

The app counts English cards within the displayed set and print run. Separately
numbered promo sets, Trainer/Galarian Gallery and Classic Collection subsets,
and separately cataloged Basic Energy remain separate checklists. Consequently,
the Grand Master percentage means **completion of the variants listed here**;
it does not certify every related promo ever released. In particular, SVP 051
Snorlax and its Pokémon Center version are not silently added to 151: their
association is documented on the
[official 151 Pokémon Center ETB page](https://www.pokemon.com/uk/pokemon-tcg/product-gallery/scarlet-violet-151-pokemon-center-elite-trainer-box),
but cross-set promo membership is not yet modeled. Additional promo membership,
all-print-run aggregation, and exhaustive error coverage remain catalog gaps.

## Corrections

- Display **Master** and **Grand Master** in both set detail and Settings.
  Preserve `standard` / `expanded` as stored values so saved choices survive.
- Include pack Poké Ball and Master Ball parallels in Master. The
  [official Prismatic Evolutions release](https://press.pokemon.com/en/MEDIA-ALERT-Pokemon-Trading-Card-Game-Scarlet-VioletPrismatic-Evolutio)
  confirms both patterns; the
  [Prismatic set guide](https://www.pokebeach.com/2025/01/prismatic-evolutions-set-guide-full-card-list-secret-rares-cut-cards-products-and-more)
  distinguishes their eligibility and product-only Eeveelution promos.
- Include reviewed Ascended Heroes Energy/ball/Team Rocket pack patterns.
  [TCGplayer's observed expansion guide](https://www.tcgplayer.com/content/article/The-10-Cards-Everybody-Wants-from-Ascended-Heroes/c53a68cf-d3da-4d21-b3b6-313c23ae3e37/)
  describes these booster variants. Unknown patterns do not automatically become
  pack requirements.
- Recognize EX-era Energy-pattern and set-logo reverses as pack cards. Collapse
  generic reverse aliases when the same card has its named reverse pattern.
  [PSA's Hidden Legends review](https://www.psacard.com/articles/articleview/10094/psa-set-registry-collecting-2004-poke-mon-ex-hidden-legends-overlooked)
  documents the Energy pattern;
  [the EX-series foil study](https://insights.collexy.com/database-insight-holofoil-overview-ex-series-era/)
  describes the changing reverse patterns and stamped reverse cards.
- Collapse duplicate gold/rainbow rarity descriptors into the numbered holo slot
  for the reviewed catalog sets. Preserve collection identities and recognize
  their existing finish aliases for ownership. Keep 151's UPC metal Mew separate.
- Remove phantom plain-holo duplicates of 151 Charmander/Charmeleon's Cosmos
  product printings. Keep Prismatic Lugia's non-holo product printing out of Master.
  Public TCGdex detailed records for `sv03.5-004`, `sv08.5-082`, `sv08.5-176`,
  and `sv03.5-205` were inspected on the review date; their source files are
  retained externally with the review artifacts. Bundled/signed fingerprints
  and stored holdings are not rewritten by the read-time projection.
- Hide the tier selector when both checklists contain the same slots, including
  the current 30th reviewed Holofoil fixture. Search/ownership filters cannot
  hide a meaningful tier choice.

## Representative offline expectations

These counts describe the app's current catalog scope, including secret rares.
Grand Master counts are deliberately labeled **cataloged**, not exhaustive.

| Set | Master | Cataloged Grand Master | Boundary checked |
| --- | ---: | ---: | --- |
| 151 | 360 | 378 | 207 numbered + 153 reverses; promos out of Master; metal Mew remains separate. |
| Prismatic Evolutions | 447 | 472 | All 100 Poké Ball and 67 Master Ball parallels included; no invented Trainer Master Balls; non-holo Lugia excluded from Master. |
| Celebrations | 25 | 25 | No invented reverses or duplicate tier choice. |
| Celebrations Classic Collection | 25 | 25 | Subset tracked independently, without promo requirements. |
| Destined Rivals | 415 | 436 | Pack cards/reverses included; promotional stamps excluded from Master. |
| Brilliant Stars | 310 | 315 | Numbered rainbow/gold rares counted once; Gallery tracked separately. |

The [official 151 checklist](https://assets.pokemon.com/assets/cms2/pdf/trading-card-game/checklist/mew_web_cardlist_en.pdf)
confirms the numbered run continues through 207, rather than stopping at 165.
The broader vintage corpus has not been certified against a complete independent
physical-printing census; the EX checks establish pattern classification and
alias handling, not exhaustive historical catalog accuracy.

## Verification

HIG source-review verdict: **PASS**. No outstanding design issues; the minimal
UI change is native picker labels, matching progress/VoiceOver titles, and
definition text. Top-level navigation is unchanged.

| Category | Result and rationale |
| --- | --- |
| Platform patterns | PASS — existing system pickers remain in place. |
| Clarity | PASS — pack parallels belong to Master and the cataloged Grand Master boundary is explicit. |
| Typography | PASS — semantic fonts and wrapping explanatory text remain; no fixed text heights are added. |
| Accessibility | PASS — progress labels follow the selected tier; existing focus order and controls remain. |
| Interaction cost | PASS — no new prompt or extra tap; redundant choices remain hidden. |
| App Review design | PASS — the copy avoids claiming exhaustive promo coverage. |

The final simulator selection passed **122 tests, zero failures, zero skips**:
84 checklist cases, 36 collection/ownership cases and two offline-upgrade cases.
This includes directory/detail parity across all 157 bundled sets, the six
representative counts above, both 30th builder fixtures, EX pattern boundaries,
saved preferences and preservation of existing finish ownership. Corrected
metadata is cached per entry revision; the measured cold directory pass was
0.59 seconds in this simulator run, with cached repeated projections in the
microsecond range. This is deterministic workload evidence, not device latency.
Documentation links and `git diff --check` pass. All build products,
host temporary files, package/compiler caches, logs, results, and research inputs
are external. Simulator evidence does not establish device or release readiness.
