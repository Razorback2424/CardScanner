# Jumbo cohort and Eevee exact product review

**Status: implemented in local authoring input; full live candidate validated;
unsigned and unpublished.** Reviewed 2026-11-02, checkout
`9413e906cab65c1d8c61882d8eb6f137bf44617e` plus preserved local changes.
This follows the owner's explicit minimal signed variant/product-support
authorization and the [initial repair](../pokemon-retail-repairs-2026-11-02.md).

## Scope and independent sources

All 20 Jumbo candidates from the earlier census were checked against TCGplayer's
own public product metadata, separately from TCGdex's English card records.
The [provider receipts](provider-cards.json) contain all 21 requested card
identities (the Jumbo cohort plus Eevee). The [marketplace receipts](products.json)
contain 22 successful products plus the explicit HTTP 400 response for 791832.
Only identity fields are retained, with URL/status/body hash; no market prices
or copied card rules are installed. Numeric product IDs are not numeric prices.

TCGdex initially returned 503 for all 21 requests. A failure-only retry recovered
all 21; the invalid product response was not retried. [Receipt metadata](receipt.json)
retains the recovery count, image hashes, inspection notes, input hash and source
census hash. Both publications are independent catalog sources; TCGplayer's
CDN images are additional evidence from the same marketplace, not a third
independent authority.

| Provider card | Reviewed Jumbo product | Additional review |
| --- | ---: | --- |
| `sv03-125` Charizard ex | 581987 | OBF 125/197, distinct from SVP 196 |
| `svp-004` Mimikyu ex | 487439 | Matching name, number and Jumbo group |
| `svp-018` Cyclizar ex | 497721 | Matching name, number and Jumbo group |
| `svp-049` Zapdos ex | 520722 | Matching name, number and Jumbo group |
| `svp-067` Roaring Moon ex | 529857 | Matching name, number and Jumbo group |
| `svp-068` Iron Valiant ex | 531864 | Matching name, number and Jumbo group |
| `svp-072` Great Tusk ex | 666593 | Paldean Fates stamp confirmed in name and image |
| `svp-078` Meowscarada ex | 537979 | Matching name, number and Jumbo group |
| `svp-081` Skeledirge ex | 537976 | Distinct TCGplayer product; shared provider Cardmarket handle is not promoted |
| `svp-084` Quaquaval ex | 537977 | Matching name, number and Jumbo group |
| `svp-086` Mabosstiff ex | 543638 | Matching name, number and Jumbo group |
| `svp-100` Grafaiai ex | 548540 | Matching name, number and Jumbo group |
| `svp-126` Palafin ex | 560085 | Matching name, number and Jumbo group |
| `svp-162` Houndstone ex | 596423 | Replaces only provider handle 791832; image confirms SVP 162 |
| `svp-177` Bloodmoon Ursaluna ex | 595474 | Product name and inspected image confirm SVP 177 despite copied number attribute 141/167 |
| `svp-193` Hop's Zacian ex | 625633 | Marketplace number SVP193 matches provider identity |
| `svp-196` Charizard ex | 641615 | Previously reviewed Jumbo; label remains **Jumbo** |
| `svp-205` Team Rocket's Mewtwo ex | 639951 | Matching name, number and Jumbo group |
| `svp-208` Victini | 646170 | Matching name, number and Jumbo group |

The 19 objects include 18 additions to the first repair. Great Tusk's signed
`providerStamps: ["set-logo"]` must match exactly. Houndstone's signed
`replacesProviderProductIDs: [791832]` permits only that reviewed bad handle to
resolve to 596423. A quote attached to 791832 is discarded, even though a direct
lookup of 596423 is allowed. Unknown conflicts still block pricing.

Terapagos & Friends (provider `svp-500`, marketplace 595035) is an independently
corroborated oversized Horizons object, but its inspected image has no printed
collector number. Do not introduce an invented SVP 500 footer or enable its
Jumbo supplement through the numbered promo route. It stays on the review hold.

## Eevee Cosmos product

The readable primary metadata endpoint for
[717879](https://mp-search-api.tcgplayer.com/v1/product/717879/details) explicitly
identifies Eevee 116/128, 30th Celebration, Cosmos Holo in Blister Exclusives.
[714357](https://mp-search-api.tcgplayer.com/v1/product/714357/details) identifies
the ordinary expansion Holo. The two retailer finish receipts from the earlier
review remain independent corroboration of the physical Cosmos printing.

The signed entry now binds Cosmos to 717879. The approved supplement consumer
uses this exact product for fallback lookup and links; it does not reuse the
ordinary Holo quote. A provider Cosmos quote is accepted only with consistent
physical and product evidence. Tests reject both the ordinary Holo handle and
an unknown conflicting handle on a Cosmos object. No live paid quote is claimed.

## Publisher and test evidence

The normal native publisher validated the final input against a freshly fetched
and signature-verified production revision 19. The unsigned revision-20 candidate
contains **75 sets, 6,675 numbered card records and 20 reviewed supplements**
(19 Jumbo plus Eevee Cosmos). See [live validation](live-validation.json) and
the [native review report](live-candidate-review.json). Candidate artifacts are
on the external SSD; hashes bind this receipt to the exact input and payload.

Classification is protected `newSet`, including the earlier 42 set additions;
`30th`, `sv03`, and `svp` also have protected authority changes. Source-level
signing tests retain the metadata through fingerprinting and signed round trips.
No signing secret, production signature, commit, push or deployment was used.

Full shared suite: **86 passed, one opt-in live CDN test skipped, zero failures**.
Focused iOS milestone: **70 passed, zero skipped/failures** (eight retail cases,
40 resolver cases, 18 marketplace-link cases, four adjacent pricing cases).
The retail matrix checks all 19 reviewed Jumbo products, Houndstone quote
suppression, stamp mismatch, distinct keys/products, Cosmos price isolation,
withdrawal and explicit hold of the numberless object. Values in quote tests
are synthetic fixture data. Tests and native build artifacts stay on T7.

## Remaining publication and completeness work

**Artwork correction:** the five content flags in this recorded run are artwork
metadata changes, not provider fingerprint changes. Comparing signed descriptors
confirms unchanged provider fingerprints in all five sets and all 33 existing
sets. The [summary comparison](content-delta.json) retains the earlier candidate
identity and now records this correction. No numbered cards were added/deleted;
only 40 MEP summary image URLs changed. The
[artwork follow-up](../pokemon-artwork-delta-2026-11-02/README.md) records three
existing-field URL pins and a later successful native run that retained all
97 existing card-art mappings. The hashes above remain evidence for the earlier
candidate, not the later input. Asset availability and broader physical/pricing
coverage still require their own review.

The PAF 054 alternate face still needs canonical cross-printing alias support.
Physical-camera acceptance, live paid-pricing acceptance, the numberless object,
the remaining historical/provider gaps and the global completeness goal remain
open. This bounded cohort and successful publisher validation do not certify
every English Pokémon printing or every marketplace quote.

Reproduce public receipts (network required, price-free):

```sh
python3 scripts/audit_pokemon_jumbo_products.py --fetch --output /tmp/jumbo-products.json
python3 scripts/audit_pokemon_jumbo_products.py --fetch --retry-errors --output /tmp/jumbo-products.json
```
