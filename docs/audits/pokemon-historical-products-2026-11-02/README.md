# Southern Islands and early Trainer Kit membership

**2026-11-02 — production publisher input updated; unsigned and unpublished.**

Added five complete historical set memberships, **62 numbered card identities**,
to the existing [publisher input](../../../publisher/catalog-input.json):

| Set | Provider ID | Numbered cards |
| --- | --- | ---: |
| Southern Islands | si1 | 18 |
| EX Trainer Kit Latias | tk-ex-latia | 10 |
| EX Trainer Kit Latios | tk-ex-latio | 10 |
| EX Trainer Kit 2 Minun | tk-ex-m | 12 |
| EX Trainer Kit 2 Plusle | tk-ex-p | 12 |

All 54 preceding descriptor objects are preserved. The production input now has
59 descriptors: the original 33 plus 26 newly authored historical memberships.
No scanner, portfolio, catalog-consumer, finish policy, price binding or saved
holding logic changed. The numbered identity additions include six Basic Energy
records; this is not an assertion about special foil Energy coverage.

## Two-catalog corroboration

Every number/name pair was compared across TCGdex's English set inventory and
Serebii's complete printed-fraction tables. Both are specialist reference
catalogs, not two official manufacturer statements. Source URLs and hashes are
retained in the [independent tables](independent-checklists.json), with per-card
matches and detailed-card hashes in [evidence.json](evidence.json).
The candidate data is [membership-input.json](membership-input.json).

Serebii uses type-only labels such as Fire for Basic Energy; the factual table
expands these to Fire Energy to match the physical Energy title and provider
category. The published
[EX Latias Fire Energy image](https://www.serebii.net/card/extrainerkitlatias/10.jpg)
was visually inspected: its printed footer is **10/10**. This guards against
mistaking an Energy's deck/checklist position for an unprinted collector number.
No image is committed or claimed as private-device scanning evidence.

The existing [preparation utility](../../../scripts/prepare_pokemon_membership_batch.py)
now accepts an explicit provider set ID as well as its previous McDonald's
year input. This is an evidence-authoring utility; production app and publisher
logic remain unchanged. It requires complete number/name agreement before
emitting a candidate or complete native fixture.

## Wider Trainer Kit census

The [20-half-deck provider census](trainer-kit-provider-census.json) found 19
sets with contiguous local IDs matching their declared official count. The
Lycanroc half deck (`tk-sm-l`) contains only **18 of 30** local IDs. Missing
provider slots are **2, 3, 6–10, 17, 20, 24, 26 and 28**. This is a provider
coverage finding, not independent evidence identifying what each missing card
is. It was not admitted as a complete membership or patched with guessed cards.

At this batch's checkpoint, the other 15 complete Trainer Kit half decks were
pending independent per-card source review. The subsequent
[later Trainer Kit batch](../pokemon-later-trainer-kits-2026-11-02/README.md)
corroborated and admitted those 15 sets, and independently identified all 12
missing Lycanroc slots as Fighting Energy while retaining the provider-gap hold.
Provider-only contiguous numbering is not enough to authorize new
physical-printing data. Normal/Holo flags and product bindings are outside
the membership census and are not silently treated as verified finishes.

## Native validation and release boundary

Complete detailed records for the new 62 cards were combined with the prior
319 POP/McDonald's cards. The existing native publisher `validate` command
passed for **26 complete sets and 381 card records**. The
[union report](native-union-review.json) classifies this isolated candidate as
`newSet`; its revision 1 is fixture-local and is not the production revision.
All 381 added provider-card IDs are unique. The previous 54 descriptors are
unchanged, local report links resolve, and `git diff --check` passes.

The existing membership tests passed 9/9 at the preceding 319-card milestone.
They were not redundantly rerun for this data-only batch; current evidence is
the native publisher's complete 381-card validation. No new iOS build or device
scan was run. No existing test count is presented as end-to-end validation of
the new cards.

Membership descriptors use the already-supported `notScannable` form with
`scanEnabled: false` and explicit printed-fraction/title membership. This
avoids inventing a modern set code; the existing historical membership path
reads these descriptors separately. Same-number/name cards across the two
half decks keep distinct provider identities and existing printing-choice
safeguards. Physical finish and price handling require their own acceptance.

The normal [signing workflow](../../../.github/workflows/pokemon-catalog.yml)
must rebuild the full production candidate against the active release, then
use the protected new-set route described in the
[runbook](../../plans/pokemon_catalog_key_handling_runbook.md). Do not publish
the isolated validation fixture as the full catalog. No signing key was read;
no commit, push, workflow dispatch, signature, publication or deployment was
performed. Device routing, exact-price acceptance and complete English physical
printing coverage remain open.
