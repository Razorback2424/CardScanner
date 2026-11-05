# HGSS promo family and adjacent 2010 tin reprints

**Status:** bounded provider/product census completed; five correction findings
prepared, **not installed** — 2026-11-03.
Checkout `a404f67470db20352b9b8f79925e2b96fe0597a9` plus preserved earlier work.
The [comprehensive ledger](../pokemon-broad-coverage-2026-11-02/README.md) remains
the overall authority. Authoring is unchanged at 75 descriptors / 99 protected
records, SHA-256 `9f02256a44cd007c06601b9bfcc196aad8c840ef5faf921de7f5dfdfe6ba631d`.

## Complete current family comparison

All **25 HGSS numbered provider cards** were read successfully. Their **33
detailed objects** were compared with all **38 primary marketplace products**
discovered in the HGSS group; all 38 metadata reads succeeded. Thirty-three
marketplace entries have HGSS numbers. Five others are prerelease Blastoise,
Leafeon and Electivire printings of ordinary set cards; they are not five extra
HGSS Black Star identities. The directory supplies discovery leads, not physical
admission proof.

All **32 populated provider product handles** match the primary product's name
and exact HGSS number. There is one missing handle, and one Normal-typed object
whose own correct product is foil-only. The [findings and full comparison](findings.json),
[provider receipts](provider-cards.json) and [primary products](products.json)
retain identity metadata and raw-response hashes, without numeric prices.

The shiny Raikou HGSS19 / Entei HGSS20 / Suicune HGSS21 trio is already present
as Holo, with distinct products 88535 / 85273 / 89605. The contemporary
[release report](https://www.pokebeach.com/2010/05/shiny-entei-suicune-and-raikou-promos-in-fall-2010-tins)
corroborates the shiny tin family. No duplicate membership or new “Shiny” finish
is added for their alternate-color artwork.

## Two World Championships findings

| Existing object | Finding | Exact product / next correction |
| --- | --- | --- |
| HGSS18 Finalist, `normal`, `finalist` + `worlds-2010` | Provider has no TCGplayer handle | 97704, whose primary metadata identifies the same numbered Finalist and is Normal-only |
| HGSS18 Participation, `normal`, `worlds-2010` | Finish label contradicts its correct foil-only product | Keep 90052 and correct this object's finish to Holo; review the exact legacy Normal identity |

The [Tropical Tidal Wave release history](https://bulbapedia.bulbagarden.net/wiki/Tropical_Tidal_Wave_(HGSS_Promo_18))
identifies the Worlds 2010 HGSS18 commemorative and English ranked/staff prints.
An independent [retailer listing](https://pokenola.com/products/tropical-tidal-wave-hgss18-worlds-10-participation-holofoil-hgss-promos-promo)
explicitly identifies Participation Holofoil. That retailer observation comes
from indexed text; its direct open returned cache miss, so no raw-page hash is
claimed. The five non-HGSS prerelease products are excluded from these findings.

**Do not exclude product 90052.** Its number and distribution are correct.
Existing pricing can accept a sole listing on an exact object even when the
provider's type is inaccurate. A Normal/Holo type difference alone does not
prove a wrong product or wrong quote. The other six ranking/staff products are
Normal-only; a blanket HGSS18 Holo correction would damage those identities.

The proposed positive bindings and exact legacy review target are recorded in
the findings. Current signed support cannot admit ordinary stamped memberships
or express that review hold; the [pending stamped-support proposal](../pokemon-pokeween-stamps-2026-11-03/README.md)
describes that mechanism. These HGSS findings are not installed or represented
as a new approval. Saved holdings must retain keys, quantities and provenance.

## Three adjacent Cracked Ice price-identity gaps

The 2010 tins also contained Secret Wonders reprints. Each already has Holo,
Reverse and Cracked Ice provider objects and bundled checklist slots. Its
Cracked Ice object has neither a direct TCGplayer handle nor an embedded
TCGplayer pricing object. Flat pricing identifies the ordinary product instead.

| Card | Existing variant | Exact Cracked Ice product | Ordinary product to keep separate | Independent release evidence |
| --- | --- | ---: | ---: | --- |
| Entei 4/132 | `cracked-ice` | 153236 | 85272 | [Release history](https://bulbapedia.bulbagarden.net/wiki/Entei_(Secret_Wonders_4)) |
| Raikou 16/132 | `cracked-ice` | 153238 | 88534 | [Release history](https://bulbapedia.bulbagarden.net/wiki/Raikou_(Secret_Wonders_16)) |
| Suicune 19/132 | `cracked-ice` | 153235 | 89604 | [Release history](https://bulbapedia.bulbagarden.net/wiki/Suicune_(Secret_Wonders_19)) |

All six [primary product reads](adjacent-products.json) succeeded, verifying
distinct ordinary and explicitly named Cracked Ice products. Each independent
release history associates that exact numbered card's Cracked Ice printing with
the Fall 2010 tins. Leading-zero marketplace numbers were normalized only for
comparison; no printed identity is rewritten.

[Provider identities](adjacent-provider.json), [additional price-product
observations](adjacent-price-identities.json) and [bundled slots](adjacent-bundled-rows.json)
separate existing physical membership from missing product binding. The
[discovery receipt](adjacent-product-discovery.json) is not counted as independent
physical proof. There were three additional pricing-identity reads of the same
cards, with only product IDs and presence flags retained, not quote values.

These are product-identity corrections for existing variants, not three new
physical memberships. The current signed whitelist accepts Cosmos but does not
accept Cracked Ice positive bindings. Delivery also needs an accurately reviewed
`dp3` descriptor; it is not currently in the 75-descriptor authoring input.
Do not invent a scan abbreviation or disable existing historical recognition
merely to attach these bindings. No unsupported field or false Cosmos record
is inserted into the production input.

## Further review and verification boundary

Latias HGSS10 and Latios HGSS11 already have correct, distinct Cosmos and Cracked
Ice products. Their broad Holo flags coexist with those two named objects.
Current `catalogVariants` source can expose a generic Holo choice alongside the
patterns. That is a semantic review lead; this census does not prove a third
physical printing or authorize deleting an unknown holder's generic choice.
The [Latias](https://bulbapedia.bulbagarden.net/wiki/Latias_(HGSS_Promo_10)) and
[Latios](https://bulbapedia.bulbagarden.net/wiki/Latios_(HGSS_Promo_11)) release
histories corroborate the named reprints. No runtime UI inspection is claimed.

HGSS has no local bundled numbered checklist, as in the earlier scope census;
it already has an authoring and served revision-19 descriptor. This is not a
new missing set. The adjacent `dp3` Cracked Ice slots are bundled.

This batch changes evidence and documentation only. No app/Core code, catalog
authoring, build/test, native candidate, signature or deployment changed. The
prior 99-record native validation and mechanism test counts retain their earlier
scope. JSON, source/delta assertions, relative links and whitespace are checked.
No paid-provider request, physical-camera acceptance or exhaustive English
printing coverage is claimed. The next work is exact stamped/named-pattern
support and scoped application, followed by one meaningful verification milestone.
