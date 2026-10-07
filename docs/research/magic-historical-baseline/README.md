# Historical Magic baseline

**Recorded:** 2026-10-06 at `412a09d` plus local changes.
**Scope:** A's initial set inventory and B1's inert app-local classification.
Historical acquisition remains disabled. A's exit gate is not complete.

The subsequent [index pilot](../magic-historical-pilot/README.md) records new
AllPrintings/EXO/Scryfall captures and the initial C implementation. This baseline
continues to describe the earlier set-only input, without adopting its counts as
a physical denominator or completeness claim.

The [manifest](2026-10-06/manifest.json) hashes the existing schema-1 bundled
seed and the complete [set inventory](2026-10-06/set-review-inventory.csv).
It retains 910 set descriptors: 262 Phase-1 review leads, 40 pre-Exodus leads,
248 special/child sets and 360 outside the historical interval. These counts
are set dispositions, not physical printings or optical coverage. Digital sets
already omitted from the seed cannot be inventoried from this input. Paper,
language, physical number presence, layouts and printing exceptions remain
unverified. No provider download, MTGJSON crosswalk or live context is implied.
PLG20 is retained in the inventory and Browse, outside the historical interval;
its provider code is not evidence of a printed footer.

Reproduce from the repository root:

```sh
python3 scripts/inventory_magic_historical_scope.py \
  --input TradingCardScanner/MagicCatalogSeed/catalog.json \
  --output /tmp/magic-historical-inventory \
  --reviewed-on 2026-10-06
```

Exodus's June 15, 1998 release boundary was checked against the
[official product page](https://mtg-jp.com/products/0000112/). Dates classify a
set default; they do not establish visible collector numbers for its printings.
The local profile snapshot has version 1, exact printing-ID overrides with review
references, and a deterministic generation covering descriptors, catalog revision,
overrides and an optional future index generation. Historical activation is
unconditionally off. The compare-and-publish store invalidates captured generations
without changing modern adapter generations. No historical request or choice is
registered yet; the future index pin does not validate an artifact or renew freshness.
The signed contract, modern vocabulary, publication keys and rollout mode stay unchanged.

## Evidence policy frozen for the pilot

- Title/name matching and an English-filtered provider response only identify
  candidates; neither establishes card language.
- Encounter language must be represented as unknown, independently corroborated
  English, explicit user-confirmed English, or conflicting/non-English, with
  source and encounter identity. Title OCR must be stored separately. Unknown may
  retrieve candidates but requires an explicit confirmation before saving;
  conflicting/non-English cannot acquire through Phase 1.
- Confirmation belongs to one card encounter and its retries. Removal, cancellation
  or a new encounter resets it. A default selection never constitutes confirmation.
- The initial historical layout allowlist is `normal` only. Unknown, split,
  transform and special layouts stay manual pending physical/geometry review.
- Missing visible-number evidence, unresolved identity/physical distinctions,
  incomplete or expired candidate coverage, or stale generations prevent automatic
  resolution, including immediately before save.

## Pending A/C/D inputs

No labeled historical Magic physical-front corpus was found in the checked-in
test fixtures. Existing modern parser fixtures establish regression behavior only.
Before a pilot can activate, retain provenance-backed physical samples across the
frame transitions, promos and adversarial numerals; reconcile exact MTGJSON and
Scryfall identities, faces and cross-era collisions; define source refresh/expiry
rules; and validate the namespace-aware adapter, encounter language gates, exact
hydration, printing/finish choice and save-time freshness. See the
[implementation plan](../../plans/magic_historical_recognition_plan.md) for all gates.

## Verification

The pre-change simulator baseline passed 130 tests covering `ScanParserTests`,
`MagicContentKindTests`, `MagicCatalogBootstrapTests`, `MagicCatalogActivationTests`,
`MagicPhysicalObjectTests` and `CollectionKeyTests`. Build artifacts and result
bundles reside on the external volume under `CodexBuilds/MagicHistorical`.
This is deterministic simulator evidence, not camera/device/provider acceptance.
