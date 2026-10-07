# OP16 / OP17 pricing gap investigation

**Date:** 2026-10-07. **Candidate:** `merge/one-piece-integration`, base
`1711b06` plus existing local changes. Read-only investigation; no application,
signed catalog, collection, or rollout changes.

## Finding

The owner catalog has verified physical cards without reviewed market mappings.
The base-market reviewer requires a normalized vendor title equal to the canonical
name. Vendor number suffixes such as `Shanks (020)` do not equal `Shanks`, so the
reviewer holds these otherwise matching listings as `nonunique-or-qualified-title`.
All 64 held rows below have one candidate whose title is the canonical name plus
the exact three-digit printed-number suffix, in the correct vendor group, with
the exact printed number. Alternate Art, Manga and other qualified products were
excluded from this diagnostic candidate match.

| Set | Verified cards | Existing mappings | Held mappings | Live candidate quotes in the catalog finish |
| --- | ---: | ---: | ---: | ---: |
| OP16 | 119 | 82 | 37 | 36 |
| OP17 | 119 | 92 | 27 | 27 |

OP17's 27 missing mappings match the owner's reported count. OP16's local catalog
has 37 missing mappings versus the owner's displayed 36. The exact installed
catalog generation, loaded rows and cache were not inspected; the one-card display
difference remains unconfirmed. The 36 quoted candidates must not be presented
as proof of the installed UI's counting behavior.

Public live product/price responses were read from TCGCSV for
[OP16 products](https://tcgcsv.com/tcgplayer/68/24664/products),
[OP16 prices](https://tcgcsv.com/tcgplayer/68/24664/prices),
[OP17 products](https://tcgcsv.com/tcgplayer/68/24736/products) and
[OP17 prices](https://tcgcsv.com/tcgplayer/68/24736/prices).
All 82 OP16 and 92 OP17 existing mappings still match live product identity and
have a USD quote in their expected finish. This is public TCGCSV verification;
no JustTCG key or request was involved.

Examples: OP17-020 Shanks has the base title `Shanks (020)`; OP16-052 Luffy has
`Monkey.D.Luffy (052)`. OP16-030 Trafalgar Law needs separate finish review:
the catalog permits Normal, but vendor product 696016 exposes only Foil. Borrowing
that Foil quote would violate the current exact-finish pricing contract.

## Why Retry does not resolve the mapping gap

`OnePiecePriceAdapter.refresh` returns `.unavailable(nil)` without a mapping.
`CatalogSortPriceResolution.exactLookup` classifies that as unresolved. Browse
then displays “Couldn't price … cards” with Retry. This therefore conflates a
catalog mapping gap with a retryable request failure. Retry cannot create a
reviewed mapping, and raw One Piece pricing intentionally forbids provider
fallback.

## Focused repair direction

Allow an optional trailing numeric suffix only when it exactly equals the
already-validated card-number suffix; retain strict group, product, uniqueness,
standard-art and finish checks. Add regressions for a matching number, wrong
number, duplicate candidates, Alternate Art and Manga. Regenerate and review the
affected market mappings through the existing signed owner-catalog publication
pipeline, preserving physical UUIDs and collection keys. Review OP16-030 finish
evidence separately. Present missing mappings as catalog coverage rather than a
network Retry state.

The diagnostic found 63 candidate quotes; none were installed or promoted to
pricing authority. No simulator, physical-device or CloudKit readiness is claimed.
Public response captures and the per-card diagnostic are retained externally under
`CodexBuilds/OnePiecePricingGaps-20261007/`.
