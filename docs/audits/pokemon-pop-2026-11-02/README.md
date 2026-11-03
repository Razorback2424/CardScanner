# POP Series signed membership batch

**2026-11-02 — production input updated; unsigned and unpublished.**

Added POP Series 1–9 to [publisher input](../../../publisher/catalog-input.json)
using its existing membership-recognition schema: nine sets, 153 numbered card
identities. All 33 previous descriptors are preserved as equal JSON objects.
No scanner, portfolio, catalog consumer, finish policy, collection key or
pricing logic changed. No price bindings or finish memberships changed.

## Two-source evidence

Every number/name pair was compared across TCGdex's English set inventory and
Serebii's independent card-number tables. These are specialist card catalogs,
not two official manufacturer statements. The per-card comparison, source URLs
and source-byte SHA-256 receipts are in
[pop-membership-evidence.json](pop-membership-evidence.json).
All nine sets have exactly 17 matched members and printed denominator 17.
Delta Species qualifiers are preserved in membership names. Symbol-only Gold
Star marks are not separately encoded as finishes by this change.

The [preparation utility](../../../scripts/prepare_pokemon_pop_membership.py)
fails the batch on any missing/duplicate independent number or normalized-name
mismatch. Its output is retained separately as
[pop-membership-input.json](pop-membership-input.json). It does not publish.

## Why the existing format applies

The descriptor kind is `notScannable`, with `scanEnabled: false`, because no
modern printed expansion code or promo prefix is being invented. The current
runtime separately reads every descriptor with `membershipRecognition` in its
historical fraction/title resolver, including descriptors of this kind. The
existing 30th Classic Collection uses the same format. This is signed membership
data, not a claim that a POP card has a modern scan code. Ambiguity resolution
and printing-choice safeguards remain the existing implementation.

All nine sets are absent from the currently served revision 19 and from the
bundled checklist. The broader [scope census](../pokemon-signed-scope-2026-11-02.json),
captured before this input change, observed 220 English provider-directory
entries: 15 Pocket-only and 205 physical sets. It found 59 physical sets without
a bundled checklist. Absence of a signed descriptor alone is not a scanner
failure: many historical sets are already handled through the historical path.
The census did not independently verify the served envelope's signature.

## Validation and signing

- Fetched all 153 detailed provider cards and all nine set records into a
  temporary fixture. The native publisher's normal `validate` command passed
  against the complete batch. The isolated [native report](native-review.json)
  classifies it as `newSet`. Its revision 1 is a fixture-local validation value,
  not a proposed production revision or a replacement for revision 19.
- The first native validation caught two authoring normalization errors
  (diacritics and Delta Species); both were corrected in the preparation utility
  and data. Final validation passed with all 153 identities.
- Existing `ProductionMembershipBoundaryTests`: **2 passed, 0 failed** after the
  production input update. Those tests protect the production authority boundary;
  they are not a 153-card device-scanning or pricing acceptance test.
- Existing input rows are unchanged, all 153 memberships are unique, local
  links resolve, and `git diff --check` passes.

Publication must use the ordinary [Pokémon signing workflow](../../../.github/workflows/pokemon-catalog.yml)
and [runbook](../../plans/pokemon_catalog_key_handling_runbook.md). The workflow
fetches the full production candidate, including these explicit historical
inputs, and classifies it against the actually active release. New-set authority
requires the protected production route; do not publish this isolated nine-set
fixture as the full catalog. No signing secret was accessed. No commit, push,
workflow dispatch, signing or deployment was performed.

## Open acceptance gates

The installed app must still be checked with the resulting signed candidate for
POP fraction/title routing, ambiguous cross-set names, saved identity, exact
finish choices and prices. The provider's complete physical-finish coverage is
not established by its numbered-card checklist. No physical-device evidence,
full English-history coverage or flawless pricing is claimed.

Eevee Cosmos and the Charizard **Jumbo** variant remain separate open repairs;
their required variant-override transport cannot be added under the current
no-consumer-logic-change constraint. The next useful data batch is the remaining
historical fraction-based promotional sets, subject to complete two-source
identity evidence and the same native publisher gates.
