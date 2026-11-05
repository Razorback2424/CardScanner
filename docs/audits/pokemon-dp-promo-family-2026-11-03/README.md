# Diamond & Pearl promo coverage and exact product bindings

**Status:** 22 corroborated product bindings authored and native-validated;
unsigned and unpublished — 2026-11-03. Checkout
`a404f67470db20352b9b8f79925e2b96fe0597a9` plus preserved local changes.
No app/Core source changed. This extends the [comprehensive ledger](../pokemon-broad-coverage-2026-11-02/README.md)
into DP ordinary products, sizes, stamped distributions and language boundaries.

## Full current census

All [56 provider cards](provider-cards.json) were read successfully, with **87
detailed objects**: 64 Holo, 23 Normal, including seven Jumbo objects. This
differs from BW's generated-Normal-only evidence; do not infer another blanket
missing-Holo family. The [directory receipt](provider-set.json) preserves the
provider list and hash. It is not proof of 56 physical English releases.

The discovered marketplace group contains **76 product IDs**. [Primary reads](products.json)
succeeded for 66; ten returned HTTP 400 and were retained without retries.
Their discovery labels refer to Japanese movie cards, but a bad request itself
does not prove language or physical absence. Among successful reads, 57 products
cover 54 distinct DP numbers; nine are ordinary-expansion prerelease/staff
products, not additional DP Black Star identities. The [comparison](comparison.json)
keeps every number, product, failure and non-DP item separate.

All 87 provider objects lack a direct TCGplayer handle. A second batched
[price-identity inspection](price-identities.json) retains only product IDs and
presence flags: none has a detailed pricing product; only Magmortar DP20 has a
flat Holofoil product identity, 87057. No numeric quotes are retained and no paid
provider was queried. Flat identity presence is not a claim that an exact
detailed quote is usable. Existing provider Holo membership and missing exact
price identity are separate findings.

## Nineteen existing LV.X Holo bindings

| Printed number and identity | Exact ordinary product |
| --- | ---: |
| DP09 Torterra LV.X | 89990 |
| DP10 Infernape LV.X | 86282 |
| DP11 Empoleon LV.X | 85207 |
| DP12 Lucario LV.X | 86890 |
| DP17 Dialga LV.X | 84813 |
| DP18 Palkia LV.X | 87920 |
| DP19 Darkrai LV.X | 84712 |
| DP28 Mewtwo LV.X | 87434 |
| DP29 Rhyperior LV.X | 88750 |
| DP30 Regigigas LV.X | 88670 |
| DP31 Heatran LV.X | 86055 |
| DP37 Dialga LV.X | 84814 |
| DP38 Giratina LV.X | 85743 |
| DP39 Shaymin LV.X | 89116 |
| DP45 Charizard G LV.X | 84202 |
| DP46 Garchomp C LV.X | 85630 |
| DP47 Rayquaza C LV.X | 88641 |
| DP53 Arceus LV.X | 83605 |
| DP56 Arceus LV.X | 83606 |

This is the complete LV.X cohort in the current DP-numbered product review.
Each exact provider identity has `LEVEL-UP` stage, Holo true, Normal false and
one unmarked standard broad-Holo object. Primary marketplace metadata agrees on
name, number, ordinary promo group and Holo-only listing. The independent
[release inventory](https://bulbapedia.bulbagarden.net/wiki/DP_Black_Star_Promos_(TCG))
corroborates all 19 numbered LV.X identities and their tin families. The provider
omits the LV.X text from its name field but preserves the stage; names are not
rewritten or matched across numbers. [The per-record review](review.json)
retains all three evidence hosts and exact signed authoring records.

These records bind products to existing broad Holo objects. They do not assert
a second physical Holo printing, add Normal, or certify exhaustive named foil
coverage. In particular, the earlier [DP merchandise history](https://bulbapedia.bulbagarden.net/wiki/2008_Fall_Collector%27s_Tins)
identifies Cosmos tin treatments; precise named-pattern choices remain a separate
review. The plain Holo binding does not price any player-signature object.

The existing supplement consumer treats ordinary records as finish minimums,
even when the Holo object already exists. Consequently these records can require
explicit finish confirmation instead of automatic single-Holo resolution. This
is the existing conservative behavior, not a new scanner algorithm or proof of
complete physical coverage. The tradeoff is exact product routing with a review
step; no special price-only positive-record semantics were invented here.

## Three unambiguous Jumbo objects

| Existing provider object | Exact Jumbo product | Ordinary product kept separate |
| --- | ---: | --- |
| Darkrai DP24, one Holo Jumbo object | 211427 | The ordinary DP24 listing |
| Regigigas DP40, one Holo Jumbo object | 211505 | The ordinary DP40 listing |
| Arceus DP50, one Holo Jumbo object | 211415 | The ordinary DP50 listing |

[Fresh Jumbo products](jumbo-products.json), provider objects and the independent
[Jumbo release inventory](https://bulbapedia.bulbagarden.net/wiki/Giant_cards)
corroborate the size distinction. All three primary product images were inspected:
English text, matching footer, and marketplace oversize label. Their hashes are
in the review receipt; no physical dimensions were inferred from image pixels.
Independent indexed retailer entries also identify English DP24 Jumbo and DP50
Jumbo Holo; direct opens returned cache misses, so no raw-page hash is claimed.
The [DP40 release history](https://bulbapedia.bulbagarden.net/wiki/Regigigas_(DP_Promo_40))
separately corroborates ordinary and Jumbo Colossal Box cards.

Dialga DP26 and Palkia DP27 each have **two** Jumbo provider objects, Mirror and
Cracked Ice. Their marketplace group supplies only one undifferentiated product
per number. Neither binding is admitted and the existing one-object guard is
unchanged. Standard Cosmos and legitimate DVD Normal objects remain separate;
the three admitted records do not assign Jumbo prices to them.

## Language and stamped review holds

DP54 Beginning Door and DP55 Ultimate Zone appear in the English provider list
but are absent from the successful numbered marketplace inventory. Absence alone
is not proof. The current independent release list explicitly identifies both
as French-only; a [contemporary report](https://www.pokebeach.com/2010/03/missing-dp54-and-dp55-promos-found-en-francais)
documents their French discovery while English release remained unresolved.
They are recorded as language-exclusion findings, with no row or holding deleted.
The separately proposed exact-card exclusion support would be needed to deliver
that distinction through protected signing; no new support was added here.

Six reviewed Tropical Wind base/staff products map to the existing DP05/25/48
Worlds 2007/2008/2009 objects, all Normal-only. These are prepared in the review,
not installed through an unstamped binding. Six products in this group do not
account for all 21 published Worlds objects, ranked cards or number-error
editions. Positive stamped support remains separately pending. Player-signature
and countdown-calendar objects also retain separate review status; no stamped
Holo object borrows a plain Holo product in this batch.

## Delta and verification

Exactly **22 records** were added only to `dpp.additionalVariants`; all prior
116 records and other parsed input values remain unchanged. Input now has
**75 descriptors / 138 protected records**: 76 Jumbo authorizations, Eevee Cosmos,
41 earlier ordinary Holo minimums, 19 existing-Holo product bindings and one
price-only exclusion. These are authoring records, not 138 new physical printings.
The original XY signal queue is unchanged at 121 remaining pairs.

Normal native live validation **passed** against signature-verified production
revision 20. The unsigned revision-21 candidate has **75 descriptors, 6,675
numbered summaries and all 138 records**. All 95 active corrections and all 75
provider fingerprints remain exact. [Validation hashes](validation.json) and
the [native report](native-review.json) retain artifact identity.

[Artwork continuity passes for this candidate](artwork-continuity.json): all
238 active mappings remain exact, none missing or changed, with 28 added for a
total of 266. This clears the preceding candidates' continuity holds only for
these exact bytes. It does not prove URL health, every recovered image's identity
or future provider stability. No candidate payload was hand-edited.

No app/Core build/test rerun was needed for this data-only batch. Earlier 88
shared passes/one optional skip and 80 iOS passes retain their mechanism scope;
all 19 live runtime pricing paths and physical camera scans were not newly tested.
No signing key, signature generation, deployment, commit/push or paid-quote
acceptance occurred. Comprehensive English coverage remains open.
