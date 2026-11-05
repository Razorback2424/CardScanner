# Wizards-era promos, W stamps and English-only coverage

**Status:** complete current provider/product comparison and exact English-only
exclusion proposal; no new catalog or app/Core changes — 2026-11-04.
Public source receipts were gathered on 2026-11-03 and reviewed after resuming
on 2026-11-04. Checkout `a404f67470db20352b9b8f79925e2b96fe0597a9` plus preserved
local changes. The [comprehensive ledger](../pokemon-broad-coverage-2026-11-02/README.md)
remains the overall authority. This is evidence of specific gaps, not exhaustive
English coverage or paid-price acceptance.

## Batched scope

The [fresh directories](provider-sets.json) return all 53 Wizards Black Star
promos, while standalone `wp` still declares seven cards and returns none.
All 53 Wizards cards and eight adjacent original expansion cards were read:
**61 identities / 104 detailed objects**. Wizards contributes 74 objects
(63 Normal, eight Holo, three Reverse). Receipts are split into
[Wizards 1–18](provider-wizards-1-18.json),
[19–36](provider-wizards-19-36.json), [37–53](provider-wizards-37-53.json)
and [eight adjacent originals](provider-adjacent.json).

All **86 populated detailed product handles** were checked; 18 objects lack a
handle. Across linked products and the two discovery inventories, **102 distinct
primary identity requests returned HTTP 200**. [Initial products](products.json),
[World Collection follow-up](world-followup.json) and
[Base Pikachu products](base-pikachu-products.json) retain public metadata and
response hashes without numeric prices. The WoTC discovery group has 71
products, including one sealed product. The World group has 19 cards and two
sealed products. Discovery labels are not physical identity authority.

[The object comparison](object-comparison.json) keeps every row and distinguishes
numeric metadata checks from physical printed numbers. Eighty-four populated
handles agree with provider-key numerators; the remaining two are the unnumbered
English Grey Star print and Spanish SNAP product 161753, whose primary number
field says 4 while its inspected image visibly prints 26. The latter is a wrong
marketplace field on the correctly pictured Spanish product, not permission to
reassign it to English Pikachu 4.

Sixteen primary product images were inspected. [Image receipts](image-receipts.json)
retain URLs and hashes, not files. JR Eevee product 618732's image returned
terminal HTTP 404; no image inspection or successful retry is claimed.

## Seven non-English objects in the English feed

All 104 objects omit an explicit `languages` array. The `/en` endpoint and English
names therefore fail to prove the language of the represented physical card.
The full 2000 Pikachu World family is corroborated independently by the
[PSA numbered registry](https://www.psacard.com/psasetregistry/tcg/famous-figures/pokemon-pikachu-master-set/composition/21958)
and [release inventory](https://bulbapedia.bulbagarden.net/wiki/Pikachu_World_Collection_2000).
Primary product images were also inspected for every row below.

| Physical World 2000 printing | Language | Current original-card object | Exact product |
| --- | --- | --- | ---: |
| Ivy Pikachu 1 | Portuguese | `basep-1`, Normal + tail stamp | 161750 |
| Movie Pikachu 4 | Dutch | `basep-4`, Normal + tail stamp | 161752 |
| Flying Pikachu 25 | German | `basep-25`, Normal + tail stamp | 161749 |
| SNAP Pikachu 26 | Spanish | `basep-26`, Normal + tail stamp | 161753 |
| Baby Pikachu 27 | Italian | `basep-27`, Normal + tail stamp | 161747 |
| Surfing Pikachu 28 | French | `basep-28`, Normal + tail stamp | 161754 |
| Jungle Pikachu 60/64 | Chinese | `base2-60`, Normal + tail stamp, no handle | 161751 |
| Base Pikachu 58/102 | Korean | No tail object in reviewed `base1-58` | 161748 |
| Birthday Pikachu 24 | **English** | `basep-24`, tail stamp, raw Holo label | 159115 |

There are **eight non-English physical printings**, but only **seven corresponding
objects in the reviewed provider records**. Do not create a Korean object merely
to exclude it, remove the ordinary English cards or apply a blanket tail-stamp
filter: Birthday Pikachu is English. Its physical Non-Holo finish versus the raw
Holo label is a separate correction requirement. Exact language evidence does
not justify deleting saved holdings.

The [reviewable exclusion proposal](english-exclusion-proposal.json) contains
the seven full object selectors and the separately corroborated French-only
DP54/55 base identities. It proposes protected `excludedVariants` plus the
previously discussed `excludedCards`, with two authoritative sources per entry,
source/name validation, cached/live lookup and acquisition coverage, and retained
holding keys/quantities/provenance. No unsupported field has been added to input
or app code. Existing exact **price** exclusions cannot remove non-English
physical choices; using them alone would leave the owner's requirement unmet.
This extension needs an explicit exception to the owner's no-logic-change
restriction. It does not authorize unrelated pending support proposals.

## English cards distributed in Japan stay in scope

Grey Star Pikachu 696103 has English text on its inspected image; the
[release history](https://bulbapedia.bulbagarden.net/wiki/Pikachu_(CoroCoro_promo))
and [exact CardTrader entry](https://www.cardtrader.com/en/cards/363327-pikachu-corocoro-1999-glossy-n-025-gray-star-promo-corocoro-promo)
identify the English glossy print distributed in Japan. Its missing printed
promo number must not be replaced with a fabricated `/53` identity.

JR East Rally Eevee 618732 is also English and Non-Holo. Its
[exact Pokumon history](https://pokumon.com/card/eevee-jr-pokemon-stamp-rally-2000-2000-unnumbered/)
and [independent release history](https://bulbapedia.bulbagarden.net/wiki/Eevee_(Wizards_Promo_11))
explicitly establish the English print distributed in Japan. The provider's
`jr-stamp-rally` tag is not proof of a visible physical stamp or printed number.
Distribution country and card language are separate facts.

The adjacent 2010 marketplace inventory has ten card products: nine language
subjects and an additional green Japanese design. Product 215153 is labeled
English. Its `PW 1` marketplace number is not proof of a physically printed code;
front/back distinctions and a stable catalog identity remain to be reviewed.
No 2010 foreign-language entries or synthetic provider IDs are admitted.

## Seven W-stamp product bindings prepared

[The exact W-family review](w-stamp-bindings-review.json) matches the seven
original expansion objects to primary named W-stamped listings and the
[independent release history](https://bulbapedia.bulbagarden.net/wiki/W_Promotional_cards).
The correct products are Pikachu 126209, Kabuto 123631, Wartortle 127206,
Dark Arbok 126208, Dark Charmeleon 180834, Misty's Psyduck 166296 and
Brock's Vulpix 123632. Both Gym W-stamp product images were inspected. The first
five current W objects lack a handle; the two Gym objects incorrectly reuse
ordinary 87539 and 83986, including embedded ordinary edition quotes.

These seven bindings are **not installed**. Positive stamped authorizations are
unsupported. For the two Gym price exclusions, their sets also lack signed
descriptors. Adding a `notScannable` descriptor would make
[`isScanDisabled`](../../../TradingCardScanner/Services/PokemonCatalogRegistry.swift)
true, removing their existing live historical fraction route. Do not use that
workaround, fabricate modern expansion codes or declare the original W cards
missing because the standalone `wp` directory is empty. A safe correction
carrier must preserve historical recognition.

## Finish findings and remaining admission work

Primary finish flags yield five review signals, with different dispositions:

| Card | Reviewed evidence | Disposition |
| --- | --- | --- |
| Venusaur 13 / 90311 | Raw Normal, Holo-only primary metadata, visibly Holo English image | Prepare Holo minimum and Normal review; retain the correct product. |
| Cool Porygon 15 / 84422 | Raw Normal, Holo-only primary metadata, visibly Holo English image and independent English release history | Prepare Holo minimum; precise named-pattern representation remains separate. |
| Team Rocket's Meowth 18 / 89851 | Raw Holo and visibly Holo image, conflicting primary Normal-only flag | Keep the correct product. Do not create a Non-Holo printing from the flag. |
| English World Birthday Pikachu / 159115 | Raw Holo tail object; independently Non-Holo English physical printing | Correct the finish while retaining English membership; no blanket tail removal. |
| Scizor 33 / 88960 | Raw Reverse, primary Normal-only, exact English Non-Holo Pokumon entry | Prepare finish correction; retain the correct product identity. |

[The review receipt](review.json) retains these findings. Scizor's
[per-card history](https://pokumon.com/card/scizor-33-wizards-black-star-english-promo/)
explicitly identifies English Non-Holo. Other named finishes, glossy coatings,
missing HP/error objects, inverted movie stamps and JR-family distinctions
remain open; this census is not exhaustive physical-printing certification.

Base Wizards admission also remains open. The 53-card set total is not a printed
denominator. Current membership records require a positive denominator, so bare
numbers must not be fabricated as `/53`. Admitting the whole raw variant family
before excluding its known foreign objects would violate English-only scope.
No set descriptor or unsafe scan-route substitute was authored.

## Verification boundary

Input SHA remains
`4ba743210bc5c32fd3083b2ade3cb6b51615cfa6ea27e2139d81e3cbee4cc55c`:
75 descriptors / 140 protected records. No new native candidate, app/Core build,
mechanism tests, signature, deployment, commit or push was needed for this
evidence-only batch. The preceding POP candidate's ten-missing artwork hold
remains current; this research does not clear it.

The owner's separate existing changes to BrowseView, SealedBrowseViews and
BrowseFeatureTests were observed and preserved. No physical-camera or paid-quote
acceptance is claimed. Comprehensive English coverage remains unproven.
