# Comprehensive Pokémon coverage: ordinary finishes, Energy and remaining axes

**2026-11-02 — ordinary-finish and Energy corrections implemented locally;
unsigned and unpublished.**
Checkout `9413e906cab65c1d8c61882d8eb6f137bf44617e` plus preserved local changes.
The owner approved minimal signed-catalog correction support for the concrete
seven-card / one-product proposal. Its [implementation receipt](implementation.json)
retains that 82-record milestone's hashes and tests. The subsequent
[2017 Mythical Collections batch](../pokemon-mythical-collections-2017-2026-11-02/README.md)
adds 13 independently corroborated ordinary Holo minimums through the approved
mechanism. Current input has **75 descriptors and 95 protected records**:
94 memberships (73 Jumbo, Eevee Cosmos, 20 ordinary Holo) and one exact product
exclusion. The follow-up owns the current input hash and live validation.
The owner explicitly requested comprehensive coverage beyond Jumbo cards.

## Coverage dimensions

The [coverage matrix](coverage-matrix.json) retains the research checkpoint and
tracks each dimension separately. The table below describes that checkpoint;
the implementation section records subsequent local application and tests.
It is not a certificate or a percentage of every physical English printing.

| Dimension | Measured state and next work |
| --- | --- |
| Releases and base identities | Fresh directory: 220 entries, including 15 Pocket entries; 205 non-Pocket entries are not necessarily distinct physical releases. Current bundle has 146 sets, authoring input 75 descriptors, served revision 19 has 33 descriptors. Eight directory groups remain outside both bundle and authoring input. |
| Ordinary Normal/Holo/Reverse | Existing bounded minimum table covers 457 identities in eight sets. New complete XY census has 216 cards; 155 exact ordinary product matches signal missing Holo evidence. Seven now have independent official foil confirmation. |
| Special Energy | Complete current SVE/MEE cohort: 32 base identities, 128 detailed provider rows, 95 distinct marketplace products. Includes Cosmos, Poké Ball, Cracked Ice, Tinsel, Prize Pack and Professor rows. One cross-number product conflict confirmed; 24 rows lack a TCGplayer handle. |
| Stamps and promotional distributions | Compiled Trick or Trade entries cover 2022–2024, 30 per year. Later years need reconciliation with generic provider rows and independent release inventories. W, Staff, Prize Pack, Professor, Pokémon Center and retailer families remain separate work. |
| Editions and print runs | Existing First Edition/Unlimited/Shadowless representations do not establish exhaustive physical-printing or price coverage. Vintage family review remains open. |
| Subsets, alternate arts and special numbering | SV/TG/GG/RC and reviewed Classic memberships exist. Bare-number, numberless, alternate-letter and composite identities need separate route/evidence review. |
| Oversized cards | Existing 73-Jumbo authoring cohort retained. Unfinished XY/SM Jumbo work is recorded below and is not the sole workstream. |
| Exact pricing and holdings | Product identifiers are checked separately from paid quotes. Wrong-number bindings must be blocked without modifying holdings; unknown replacements remain unresolved. |
| Signing and device acceptance | Latest full native candidate passed before this research batch. No production signature/publication or physical-camera/paid-quote acceptance is claimed. |

The [scope receipt](scope.json) records the fresh directory/Pocket/production
hashes and the exact per-set inventory. This Python census does not verify the
envelope itself; its envelope hash matches the revision-19 bytes already
verified by the preceding normal native publisher run. The eight residual
groups are `miscp`, `basep`, `wp`, `jumbo`, `sp`, `np`, `rc`, `tk-sm-l`.
Earlier reports explain why these include aliases, empty aggregations and
numbering/provider holds, rather than eight simple missing releases.

## Ordinary promo finish cohort

All 216 current XY provider records were read successfully. All have no plain
Holo evidence in their flags/detailed rows. This does not prove every XY promo
should be Holo. The independent product-ID discovery directory supplied 271
IDs; 269 primary TCGplayer metadata reads succeeded, while 237531 and 250035
returned HTTP 400. Explicit bad-request receipts were retained, not retried as
transient failures. The discovery directory is not treated as physical proof.

Exact ordinary name/number matching yields 165 candidate rows. Of these, 155
have primary marketplace Holo-only metadata while the provider lacks Holo.
These are review leads, not permission for a blanket set-wide correction.
[Provider receipts](xy-provider.json), [primary products](xy-products.json) and
[all ordinary finish signals](xy-finish-review.json) preserve those boundaries.

Seven Mythical Collection cards have both exact TCGplayer Holo-only products
and independent official Pokémon product pages identifying foil promos:

| Provider card | Name | Exact product |
| --- | --- | ---: |
| `xyp-XY111` | Celebi | 114526 |
| `xyp-XY112` | Jirachi | 117266 |
| `xyp-XY114` | Darkrai | 121946 |
| `xyp-XY116` | Arceus | 121364 |
| `xyp-XY118` | Keldeo | 126034 |
| `xyp-XY119` | Genesect | 125322 |
| `xyp-XY120` | Meloetta | 125898 |

The [concrete corrections](reviewed-corrections.json) link each official page
and primary product receipt. Official observations came from indexed official
page bodies; no unobserved raw-body hash is claimed. The proposed change is
additive Holo membership and exact product binding. Retained Normal evidence
needs physical/product review; no deletion or automatic holding rekey is
proposed. At this checkpoint the other 148 primary-only missing-Holo signals
remained unadmitted. The later 2017 product-family review corroborates 13 of
those signals; 135 original primary-only signals remain review leads.

These IDs are outside the pre-existing overrides and eight-set minimum table.
Before authorization, `additionalVariants` enabled only Jumbo and Holo Cosmos.
Its approved extension now carries ordinary Normal/Holo/Reverse minimums and
`normalNeedsReview` on reviewed Holo additions. The seven signed records retain
their exact independent products. Raw provider fingerprints and bundled
resources remain unchanged; the normal publisher carries the corrections.

## Special Energy and stamped pricing

Every card read and all 95 primary product metadata requests succeeded.
[Provider physical records](energy-provider.json), [marketplace products](energy-products.json)
and [per-axis findings](energy-findings.json) retain price-free data and hashes.
The 128 rows are provider objects, not 128 independently reconciled worldwide
physical printings. Twenty-four missing handles are review leads, not proof
that a displayed quote is absent or wrong on a device.

For `sve-002`, the `reverse` / `cosmos` / `player-rewards-program` record uses
TCGplayer 651037. The marketplace identifies that product as **Basic Fire
Energy 010**, and the provider also assigns it to `sve-010`. This is an exact
collector-number conflict. The implemented correction blocks 651037 and any quote
attached to it for that one SVE 002 object; it neither guesses a replacement
product nor deletes the physical variant. Its two independent source URLs are
in [the correction proposal](reviewed-corrections.json).

Do not infer a pricing bug merely from a provider pattern being typed Reverse
while the marketplace calls it Holofoil. Existing per-object pricing already
accepts a sole priced listing on the exact detailed object. That is separate
from the confirmed wrong-number product binding and is not changed here.

## Retained Jumbo checkpoint and count correction

The earlier XY/SM Jumbo pass fetched all 464 base records and 90 primary Jumbo
products. Neither provider family exposes Jumbo detail rows. The preliminary
87 count was an inventory/marketplace candidate count, **not** a finished
installable finish cohort. The attempted proposal generator stopped on its
extra base-Holo assertion: many base flags are Normal. Nothing from that
failed generation was installed. Broader ordinary finish verification now
takes priority; no XY/SM Jumbo admission count is asserted here.

## Approved signed support and verification

The owner explicitly approved extending protected signed support for this
ordinary-finish and product-exclusion batch. The implementation:

1. Carry ordinary finish minimums with the existing physical-review semantics.
2. Carry exact physical-object product exclusions and discard excluded quotes.
3. Preserve signed authority classification, verification, withdrawal/cache
   behavior and holding identities; do not change recognition algorithms or
   portfolio calculations.

Optional `excludedTCGplayerProductIDs` and `providerFoil` fields identify the
exact standard-size, type, pattern and canonical stamp target. Exclusions
cannot assert membership, attach a replacement product, or weaken the existing
Jumbo provider-object requirement. Their complete metadata shares the existing
protected array and its signature, activation/cache and withdrawal comparisons.

Live/cache reads apply the verified registry. Ordinary Holo joins standard
checklist slots; exclusions add no slot. Existing incomplete-evidence resolution
asks for a finish choice. Signed Normal review blocks Normal quotes and automatic
finish correction. The Energy exclusion blocks embedded quotes, direct product
fallback and identified-card marketplace links without affecting SVE 010 or
unstamped Cosmos. Saved-only marketplace links still use stored metadata;
reconciling those with current signed corrections remains an acceptance check.

Shared suite: **88 passed, one optional live test skipped, zero failures**.
Final iOS milestone: **80/80 passed**, comprising 13 retail cases, 40 resolver
cases, 18 link cases and nine existing finish-evidence cases. New coverage checks
all seven ordinary records, conflicting products, Energy sibling isolation,
cache/withdrawal and persisted Normal holdings after refresh/reopen. The first
iOS test build failed on immutable fixture assignments; corrected final tests
passed. Quote values are synthetic fixtures, not live paid quotes.

The rebuilt normal publisher passed full live validation against verified
production revision 19: **75 sets, 6,675 numbered cards and 82 protected records**.
All 74 earlier records survive unchanged, as do all 33 prior provider
fingerprints. The [native report](native-review.json) classifies the overall
candidate as protected `newSet`. Secondary artwork was unavailable, omitting
97 existing card-art mappings as in the earlier documented outage. This is
data-validation evidence, not an artifact ready for publication without
artwork continuity review. Build/results remain on the external SSD.

No private signing key, production signature, commit, push or deployment was
used. Physical-camera, paid-quote, historical/provider gaps and exhaustive
English-printing coverage remain open. The [proposal](reviewed-corrections.json)
retains its pre-implementation snapshot; the implementation receipt owns the
current application and verification status.

## Subsequent ordinary product-family batch

The [2017 Volcanion/Magearna review](../pokemon-mythical-collections-2017-2026-11-02/README.md)
checks both boxes' complete 13-card ordinary promo contents against contemporary
primary reporting, fresh TCGplayer foil-only metadata and TCGdex identities.
It adds only 13 `xyp` Holo/product minimums with Normal review; all prior records
and other authoring fields are unchanged. No app/Core code changed in that batch.

Its full normal native live run passes at 75 descriptors, 6,675 numbered cards
and 95 protected records. All 33 previous provider fingerprints remain equal.
The secondary artwork source recovered: all 97 prior card-art mappings are
retained exactly, resolving the omission for this particular candidate. The
earlier unavailable-source candidate above remains historical evidence; neither
run proves global URL health or physical-camera/paid-price acceptance. The new
candidate remains unsigned and unpublished, and comprehensive coverage is open.
