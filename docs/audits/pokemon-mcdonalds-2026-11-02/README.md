# English McDonald's membership batch

**2026-11-02 — production publisher input updated; unsigned and unpublished.**

Added 12 English collections to the existing signed membership authoring input:
2011, 2012, 2014–2019 and 2021–2024. The batch contains **166 numbered identities**.
The previous 33 production descriptors and nine POP descriptors are preserved
as equal JSON objects. Current input contains 54 descriptors. No scanner,
portfolio, catalog-consumer, finish, pricing or saved-collection logic changed.

## Corroboration and scope

Every added number/name pair was matched across the TCGdex English set inventory
and Bulbapedia's numbered set table. These are specialist reference catalogs,
not two official manufacturer statements. The [independent factual tables](independent-checklists.json)
were extracted through the web tool, then compared mechanically against the
provider by the [preparation utility](../../../scripts/prepare_pokemon_membership_batch.py).
The [receipts](evidence.json) retain per-card comparisons, source URLs, a hash
of the independent input and hashes of the fetched provider records. No USD
price or product mapping was installed from these sources.

| Provider sets | Numbered cards | Printed denominator |
| --- | ---: | ---: |
| 2011bw, 2012bw, 2014xy, 2015xy, 2016xy, 2017sm, 2018sm, 2019sm | 96 | 12 |
| 2021swsh | 25 | 25 |
| 2022swsh, 2023sv, 2024sv | 45 | 15 |

Bulbapedia's 2011 page also contains Japanese collection sheets; only the
English 12-card table was retained. Its 2018 and 2019 pages contain distinct
40-card French collections; only the English 12-card tables were retained.
The provider's 2024 label is retained even though the English promotion began
in 2025 in some countries. These identities are not newly invented 2025 IDs.

This batch establishes numbered membership only. It does not establish every
physical finish. The 2021 page explicitly distinguishes Non Holofoil and
Confetti Holofoil, but no new finish override is authored through membership.

## Existing signing and runtime boundary

The [production input](../../../publisher/catalog-input.json) uses the existing
`notScannable` / `scanEnabled: false` descriptor form with explicit membership
recognition. This avoids inventing modern printed codes for historical cards.
The existing historical resolver separately reads membership descriptors and
matches printed fraction/title evidence. This is the same supported data path
used by the [POP batch](../pokemon-pop-2026-11-02/README.md); no parser or resolver
was changed. Existing printing-choice safeguards remain in place when several
collections share a fraction and name.

Normal publication must rebuild the **full** production candidate against the
then-current active release and use the protected new-set signing route in the
[workflow](../../../.github/workflows/pokemon-catalog.yml) and
[runbook](../../plans/pokemon_catalog_key_handling_runbook.md). Do not publish the
isolated validation fixture as a replacement for production. No commit, push,
workflow dispatch, key access, signature or deployment occurred in this turn.

## Milestone validation

- Complete provider details were fetched for all 166 cards. The new batch was
  combined with all 153 prior POP cards for native publisher validation:
  **21 sets, 319 cards, passed**. The [union report](native-union-review.json)
  classifies the isolated batch as `newSet`. Its fixture-local revision 1 is
  not a production revision or signed release.
- Existing native membership regressions: **9 passed, 0 failed**, including
  complete-checklist requirements, unique physical identities, provider-ID
  binding and production authority-boundary checks.
- Verified all original production and POP descriptor objects were unchanged,
  all 319 new provider card IDs are unique, local document links resolve and
  `git diff --check` passes.
- No iOS build, simulator scan, physical-device scan, live fallback-price
  request or persisted-collection mutation was performed. Native publisher
  validation does not prove those acceptance gates.

## Pricing and finish follow-up

The downloaded data has detailed TCGplayer product handles for all 166 identities,
but only the 96 cards in 2011–2019 carry any USD quote in the inspected provider
payloads. The 70 cards in 2021–2024 have no USD quote there. This observation is
not a paid-provider or fallback-pricing test, and it does not authorize using
another printing's price.

The provider's detailed-type inventory is 96 Holo rows across the eight early
collections; 25 Normal plus 25 Holo for 2021; 15 Holo for 2022; nine Normal plus
six Holo for 2023; and eight Normal plus seven Holo for 2024. The all-Holo 2022
inventory needs independent physical-finish review before treating it as
complete/correct. No provider finish flag was changed in this batch.

Remaining work includes independent finish/product corroboration, ambiguity
checks across annual sets, signed-candidate installation, exact-price handling
and device scanning. Global English historical completeness remains unproven.
