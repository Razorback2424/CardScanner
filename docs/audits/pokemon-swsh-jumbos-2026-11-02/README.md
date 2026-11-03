# Sword & Shield promo Jumbo batch

**Status: 54 additions prepared in signed authoring input; full native live validation passed; unsigned and unpublished.**
Reviewed 2026-11-02, checkout `9413e906cab65c1d8c61882d8eb6f137bf44617e`
plus preserved local changes. No app, scanner, portfolio or publisher algorithm
changed in this batch. Uses the approved Jumbo supplement format.

## Complete family census and independent review

The English TCGdex `swshp` inventory returned 307 member cards. All 307 detailed
identity requests succeeded without retries. The census found 73 Jumbo objects
on 73 canonical cards; 67 supplied marketplace handles. All 67 independent
TCGplayer product-metadata requests succeeded. A copied provider handle alone
was not accepted as second-source evidence.

[Provider receipts](provider-cards.json) retain each request URL, response hash,
identity and Jumbo-only physical details; standard rows retain identity and hashes
without copied rules or quotes. [Marketplace receipts](products.json) retain
primary product names, numbers, category and finish flags, with no numeric prices.
The [per-card ledger](review.json) records every admission or hold.

The 54 admitted records agree on Pokémon card identity, collector number, Jumbo
marketplace category and Holo treatment, except for the separately resolved
Infernape number-attribute typo below. Exact stamps are required on five records.
All other descriptor fields and all earlier supplements are preserved.

| Provider card | Name | Exact TCGplayer product | Required provider stamp |
| --- | --- | ---: | --- |
| `swshp-SWSH005` | Meowth VMAX | 205467 | none |
| `swshp-SWSH014` | Rillaboom V | 220754 | none |
| `swshp-SWSH015` | Cinderace V | 220755 | none |
| `swshp-SWSH016` | Inteleon V | 220753 | none |
| `swshp-SWSH017` | Toxtricity V | 206426 | none |
| `swshp-SWSH021` | Polteageist V | 214236 | none |
| `swshp-SWSH030` | Copperajah V | 214229 | none |
| `swshp-SWSH043` | Galarian Sirfetch'd V | 220274 | none |
| `swshp-SWSH045` | Eternatus VMAX | 220282 | none |
| `swshp-SWSH049` | Dubwool V | 223753 | none |
| `swshp-SWSH055` | Hatterene V | 223756 | none |
| `swshp-SWSH057` | Grimmsnarl V | 229436 | none |
| `swshp-SWSH061` | Pikachu V | 232443 | none |
| `swshp-SWSH078` | Orbeetle V | 227026 | none |
| `swshp-SWSH083` | Alakazam V | 228981 | none |
| `swshp-SWSH085` | Boltund V | 243659 | none |
| `swshp-SWSH086` | Cramorant V | 251622 | none |
| `swshp-SWSH097` | Dragapult VMAX | 232609 | none |
| `swshp-SWSH099` | Crobat VMAX | 232614 | none |
| `swshp-SWSH102` | Venusaur VMAX | 234375 | none |
| `swshp-SWSH103` | Blastoise VMAX | 234376 | none |
| `swshp-SWSH106` | Single Strike Urshifu V | 234377 | none |
| `swshp-SWSH107` | Rapid Strike Urshifu V | 234378 | none |
| `swshp-SWSH111` | Galarian Rapidash V | 236055 | none |
| `swshp-SWSH130` | Ice Rider Calyrex V | 245870 | none |
| `swshp-SWSH131` | Shadow Rider Calyrex V | 245869 | none |
| `swshp-SWSH132` | Dragapult | 252817 | 25th-celebration |
| `swshp-SWSH133` | Lance's Charizard V | 251104 | 25th-celebration |
| `swshp-SWSH134` | Dark Sylveon V | 251105 | 25th-celebration |
| `swshp-SWSH136` | Mimikyu | 260878 | 25th-celebration |
| `swshp-SWSH154` | Dragonite V | 253421 | none |
| `swshp-SWSH176` | Hoopa V | 253420 | none |
| `swshp-SWSH180` | Flareon VMAX | 257709 | none |
| `swshp-SWSH182` | Vaporeon VMAX | 257708 | none |
| `swshp-SWSH184` | Jolteon VMAX | 257710 | none |
| `swshp-SWSH195` | Leafeon VSTAR | 263260 | none |
| `swshp-SWSH197` | Glaceon VSTAR | 263261 | none |
| `swshp-SWSH198` | Pikachu V | 260712 | none |
| `swshp-SWSH214` | Lucario VSTAR | 268305 | none |
| `swshp-SWSH219` | Boltund V | 276051 | none |
| `swshp-SWSH225` | Alolan Exeggutor V | 279028 | set-logo |
| `swshp-SWSH249` | Kleavor VSTAR | 276050 | none |
| `swshp-SWSH252` | Infernape V | 284499 | none |
| `swshp-SWSH254` | Origin Forme Palkia VSTAR | 449514 | none |
| `swshp-SWSH256` | Origin Forme Dialga VSTAR | 449513 | none |
| `swshp-SWSH265` | Zeraora VSTAR | 449524 | none |
| `swshp-SWSH268` | Deoxys VSTAR | 449525 | none |
| `swshp-SWSH280` | Regieleki V | 479879 | none |
| `swshp-SWSH281` | Regidrago V | 479880 | none |
| `swshp-SWSH286` | Pikachu VMAX | 478425 | none |
| `swshp-SWSH294` | Hisuian Electrode V | 451116 | none |
| `swshp-SWSH295` | Virizion V | 449517 | none |
| `swshp-SWSH298` | Hisuian Zoroark VSTAR | 449528 | none |
| `swshp-SWSH301` | Lugia V | 506006 | none |

## Conflicts retained as holds

Nineteen provider Jumbo objects were not admitted:

| Reason | Provider cards |
| --- | --- |
| No exact marketplace product | `swshp-SWSH226`, `swshp-SWSH227`, `swshp-SWSH228`, `swshp-SWSH230`, `swshp-SWSH292`, `swshp-SWSH293` |
| V-UNION composite identity | `swshp-SWSH139`, `swshp-SWSH155`, `swshp-SWSH159`, `swshp-SWSH163`, `swshp-SWSH215`, `swshp-SWSH287` |
| Provider Holo conflicts with marketplace Normal-only | `swshp-SWSH001`, `swshp-SWSH002`, `swshp-SWSH003`, `swshp-SWSH084`, `swshp-SWSH137`, `swshp-SWSH138`, `swshp-SWSH299` |

A combined V-UNION Jumbo is not automatically the same printing as a numbered
quarter of its four-card assembly. The existing one-card supplement must not
silently acquire a composite or alias its price. Six missing product handles
also remain unpriced review leads. The seven Normal-only conflicts require
independent finish review; neither source was silently declared correct.

## Image review and Infernape exception

Inspected 11 primary marketplace images: the three First Partner starters,
Dragapult, Lance's Charizard V, Dark Sylveon V, Mimikyu, Light Toxtricity,
Hydreigon C, Alolan Exeggutor V and Infernape V. The inspected stamp images
agree with provider `25th-celebration` or `set-logo` as applicable. Image
observations do not resolve the seven conflicting finish flags by themselves.

Product 284499 names Infernape V **SWSH252**, but its number attribute says
`SWS252`. Its inspected card footer reads SWSH252, agreeing with the provider
and product name. The signed entry keeps canonical SWSH252 and exact product
284499; no invented SWS252 identity or broad spelling alias was introduced.
[Image receipts](image-receipts.json) record URLs and hashes. Images are not
committed; the marketplace image is evidence from that same source, not a third
independent authority. No physical-camera or paid-quote test is claimed.

## Separate 30th product promo gap

An adjacent check found HTTP 404 for MEP 094–101. The
[Bulbapedia promo table](https://bulbapedia.bulbagarden.net/wiki/MEP_Black_Star_Promos_(TCG))
lists these product identities, and the
[official product showcase](https://www.pokemon.com/uk/news/pokemon-tcg-30th-celebration-product-showcase)
describes the associated product cards. The
[provider-gap receipt](mep-provider-gap.json) retains all eight endpoint failures.

These are provider-gap review leads, not added card/finish data. The current
signed supplement needs an existing provider identity; it cannot manufacture
a missing base card. No unsupported payload fields, duplicate main-set aliases
or guessed provider records were installed. Broader 30th products and MEP
finish/size/product corroboration still need systematic review.

## Validation and publication boundary

The production baseline was freshly fetched and is still signed revision 19
with envelope SHA-256 `ba47f27434d48983218374538f84550101d70ab0f15e123ab691ae9708087333`.
The first normal full native run stopped on unrelated `sv08.5-117` HTTP 502
before producing artifacts. A direct recheck returned HTTP 200; the normal full
retry exited zero. Its unsigned revision-20 candidate contains **75 sets, 6,675
numbered cards and 74 supplements: 73 Jumbos and Eevee Cosmos**. All 33 existing
provider fingerprints remain unchanged. Protected authority changes include
`swshp`, alongside the earlier `30th`, `sv03` and `svp` repairs. The overall
classification remains protected `newSet` because of the earlier set additions.

All 54 admitted Jumbo product handles are distinct from the corresponding
standard-size provider handles, and each has a standard-size comparison handle;
see [product isolation](product-isolation.json). This verifies identifier
separation, not actual paid quotes. Every new supplement survives the normal
candidate build unchanged. The [final receipt](receipt.json) binds input,
payload, snapshot and review hashes to this run and preserves the earlier failure.
Ambiguous secondary artwork matches and one secondary HTTP 500 were warnings;
they were not silently reported as fully healthy artwork-provider evidence.
Generated candidates remain on the external SSD.

No production signature, signing secret, workflow dispatch, commit, push or
deployment was used. Existing app/Core test milestones were not repeated for
this data-only change. Global English-printing completeness, paid pricing,
physical-camera acceptance, PAF 054 alternate-face routing and the recorded
historical/provider holds remain open.

Reproduce the public, price-free census:

```sh
python3 scripts/audit_pokemon_jumbo_family.py --fetch --set-id swshp --output /tmp/swsh-jumbo-family.json
python3 scripts/audit_pokemon_jumbo_family.py --fetch --set-id swshp --retry-errors --output /tmp/swsh-jumbo-family.json
```
