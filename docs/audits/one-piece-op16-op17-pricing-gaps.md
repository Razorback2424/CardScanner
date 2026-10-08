# OP16 / OP17 pricing gap investigation

**Systematic repair — 2026-10-07:** the shared reviewer now supports exact short
number suffixes, full-number suffixes and hyphenated full identifiers (including
unpadded numeric digits). It validates the suffix against the independent Number
field and retains category, release group, unique base title and exact finish
checks. Alternate Art, Manga, Parallel, Winner, duplicate candidates and wrong
identifiers remain rejected. The review report now groups coverage and held
reasons by release rather than leaving a flat queue for manual fixes.

The complete 2,373 eligible ordinary base-card decisions across 48 sets were
replayed from retained, hash-checked captures. **406 new mappings across 39 sets**
raise exact coverage from 1,961 to **2,367**. OP17 gains all 27 missing mappings;
OP16 gains 36 and retains OP16-030's finish disagreement. OP14's separate
`Monkey.D.Luffy - OP14-34` formatting issue is also handled by the common rule.

Fresh, paced public TCGCSV captures independently validate all 2,367 mapped
product identities, expected finish lanes and USD quotes with zero failures.
The other six held decisions are finish disagreements: EB03-001, OP16-030,
ST22-001, ST21-001, ST21-003 and ST21-008. Their reviewed physical finish differs
from the base vendor lane. This repair does not reinterpret owned finishes or
borrow a parallel/foil quote to hide those conflicts.

The updated registry, market observations/inventories and coverage report are
retained in the review corpus. Mapping-only signed owner revision **2** is bundled
with a new ephemeral review key's public pin alongside the retained old pin.
Publication validates the previous signed baseline, unchanged identities/finishes
and existing mappings, and independently verifies the signature and manifest.
Production rollout and write permissions remain unchanged. The shared reviewer,
regressions and [update preparer](../../scripts/prepare_one_piece_owner_update.py)
make the repair reproducible. Artifacts are external under
`CodexBuilds/OnePieceMappingRepair-20261007/`.

Verification: all 81 Python tests, 46 core tests and 88 One Piece simulator app
tests pass. The app tests include cross-family bundled mappings, trusted review
key rotation, blocked/unmatched finishes, exact pricing and collection safeguards.
The first core run failed only its old 1,961-mapping corpus expectation; it was
updated to 2,367 before the clean full recheck. The signed manifests agree and
classify exactly 406 mapping invalidations, with no physical identity changes.
The built simulator app contains revision 2 and its matching pin. The checkout
advanced through owner commits during this work; the final implementation is
verified against `0641b3a` plus local changes. The final Debug simulator build,
271 local documentation links and `git diff --check` pass. No device install, CloudKit or
production readiness is claimed.

The original investigation below is historical evidence preceding this repair.

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
