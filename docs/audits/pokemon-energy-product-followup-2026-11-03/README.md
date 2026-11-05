# Energy product follow-up: coverage and exact binding limits

**Status:** existing MEE coverage verified; additional SVE bindings reviewed but
uninstalled — 2026-11-03. Checkout `a404f67470db20352b9b8f79925e2b96fe0597a9`
plus preserved earlier work. Authoring remains **75 descriptors / 99 protected
records**, SHA-256 `9f02256a44cd007c06601b9bfcc196aad8c840ef5faf921de7f5dfdfe6ba631d`.
This follows the [broader coverage ledger](../pokemon-broad-coverage-2026-11-02/README.md)
and its earlier 32-primary-identity / 128-object Energy checkpoint.

## Current provider and product comparison

Fresh reads cover all **24 SVE and eight MEE primary-provider identities** and
**128 detailed objects**. All **112 primary product requests succeeded**. The
32 ordinary, unstamped Normal objects have handles whose names and numbers
match. Across all detailed objects, 104 handles are populated: all 104 names
and 103 numbers match. The sole number mismatch remains the previously reviewed
SVE 002 Prize Pack Cosmos association with product 651037, which is printed 010.

The [provider receipts](provider-cards.json), [primary products](products.json)
and [complete findings/comparison](findings.json) preserve price-free metadata
and raw-response hashes. The 24 raw missing handles remain eight Professor
Program patterns, eight Tinsel patterns and eight bare Reverse objects. A
missing handle alone does not establish a missing physical printing or a wrong
displayed quote.

## MEE 009–016 are already covered by the app

TCGdex still lists only MEE 001–008; all eight expected `mee-009` through
`mee-016` endpoints return 404. However, the app already supplies these cards
under stable **`tcgplayer:` identities** through `PokemonReviewedEnergyCatalog`.
The bundled MEE checklist contains 16 distinct identities / 24 slots: the
original eight Normal/Reverse identities plus eight reviewed Holo cards.

| Printed number | Energy | Existing product / identity suffix |
| --- | --- | ---: |
| MEE 009 | Grass | 713248 |
| MEE 010 | Fire | 713249 |
| MEE 011 | Water | 713250 |
| MEE 012 | Lightning | 713251 |
| MEE 013 | Psychic | 713252 |
| MEE 014 | Fighting | 713253 |
| MEE 015 | Darkness | 713254 |
| MEE 016 | Metal | 713255 |

All eight fresh primary products agree with the existing app rows and the
independent [retailer's English/Holofoil listings](https://www.acecollectibles.com.au/collections/vendors?q=MEE%3A+Mega+Evolution+Energies).
[Eight public retailer identity reads](mee-retailer.json) also succeeded. All
eight product images were visually inspected for English MEE footers, exact
numbers and the anniversary mark; see [image observations and hashes](image-review.json).
These are product images, not physical-camera or reflective-foil tests.

[Existing app coverage](app-coverage.json) records exact rows, source hashes and
the fixture. Scanner lookup, Browse, refresh and checklist regeneration already
use the reviewed source. Do not mint fake `mee-009` provider records, duplicate
these memberships or infer a missing app card from the primary provider's 404.
The MEE provider's count of eight is not a printed `/8` denominator. This
closes a suspected gap; it does not claim a newly installed repair.

## Correct positive replacement for SVE 002 Prize Pack Cosmos

Primary product **622936** identifies Basic Fire Energy **002 (Cosmos Holo)**
in Prize Pack Series Cards. Its image shows English `SVE 002`, the Play! Pokémon
mark and Cosmos depiction. That agrees with the provider's physical-object
identity and distinguishes it from ordinary unmarked Cosmos product 517178 and
the incorrectly attached **010** product 651037.

The existing **authored** exclusion for 651037 is unchanged. The findings now
record the positive replacement candidate and the exact old handle; no signed
positive replacement has been installed. A future correction must retain the
wrong embedded quote isolation while preserving SVE 010 and the unmarked Cosmos
sibling. The current contract does not admit a positive stamped-pattern binding
with provider type Reverse; neither a plain Cosmos membership nor a broad Fire
Energy replacement would be equivalent.

## Professor Program 2024: eight exact identity matches, two review holds

Each raw SVE 009–016 Professor object lacks a handle. Fresh primary product
metadata and all eight images establish the exact SVE number and Professor mark.
Six have consistent Cosmos identity evidence. Two need further review before
binding or selecting a marketplace printing:

| Card | Exact identity product | Review status |
| --- | ---: | --- |
| Grass 009 | 604499 | Consistent Cosmos; signed support pending |
| Fire 010 | 604500 | Image has large geometric facets; verify the pattern rather than infer Cracked Ice or delete Cosmos from one image |
| Water 011 | 604496 | Consistent Cosmos; signed support pending |
| Lightning 012 | 604498 | Image depicts the Professor/Cosmos object, while primary marketplace metadata is Normal-only; review the exact marketplace printing |
| Psychic 013 | 604497 | Consistent Cosmos; signed support pending |
| Fighting 014 | 604501 | Consistent Cosmos; signed support pending |
| Darkness 015 | 604494 | Consistent Cosmos; signed support pending |
| Metal 016 | 604495 | Consistent Cosmos; signed support pending |

All eight are recorded as uninstalled. Identity agreement is separate from
physical-pattern and market-printing agreement. A Normal-only market label
does not make an otherwise matching product a wrong-number association; do not
exclude 604498 or request Holofoil blindly. The existing engine can accept a sole
listing on an exact object, but no paid quote acceptance is claimed here.

## Remaining eight Tinsel and eight bare-Reverse objects

SVE 017–024 Tinsel objects have same-number marketplace candidates already used
by their ordinary Normal siblings. Their product metadata allows multiple
printings. Product identity alone is insufficient to choose the Tinsel listing
or reuse a Normal quote; these remain candidates, not signed repairs. Likewise,
no product is assigned to the eight bare Reverse SVE 009–016 objects merely
because another same-number foil product exists.

These cases require exact physical-pattern and marketplace-printing scoping.
The current signed whitelist and consumer do not support those positive data
records. This report does not broaden the pending [stamped-support approval](../pokemon-pokeween-stamps-2026-11-03/README.md)
or change underlying logic. No new approval request is inferred from the MEE
provider gap, because the app already covers those cards.

## Verification milestone and source limits

**Four existing focused simulator tests passed, zero failed or skipped.** They
check MEE checklist regeneration, retained primary rows, reviewed finish data,
footer parsing/negative evidence and two representative cards (013/015) through
resolution, refresh and collection CSV export/import without identity changes.
All eight reviewed source/bundled identities were independently compared with
fresh primary metadata. Do not call this eight end-to-end runtime cases.
The [validation receipt](validation.json) records scope and the external-SSD
result bundle. There were zero build errors and 41 compiler warnings; a
warning-free build or release gate is not claimed. No new test code was written.

The [discovery index](discovery.json) returned only the latest eight SVE products,
omitting known older products, so it cannot certify marketplace completeness.
Two [public TCGCSV inventory reads](inventory-access.json) returned HTTP 401;
those are access failures, not empty inventories. No credentials, bypass or
retry was used. Source images and numeric prices are not added to this audit.

No app/Core or authoring bytes changed in this batch. Native publication
validation was not repeated for unchanged authoring; the prior 99-record
candidate retains its earlier scope. No signing, publication, paid-provider
request or physical-camera acceptance occurred. Exhaustive English coverage
remains open.
