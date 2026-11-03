# SVE Basic Energy signed recognition

**2026-11-02 — catalog-only authority fix prepared; unsigned and unpublished.**

The scanner already supports registered Energy prefixes through rules version 2,
but production input registered only MEE. Thus an SVE footer could not select
the existing Scarlet & Violet Energy catalog using the Energy route. Added one
descriptor to [normal publisher input](../../../publisher/catalog-input.json):
`sve`, kind `energy`, prefix **SVE**, three-digit numeric local IDs, rules 2,
scan enabled, no expansion denominator. No app scanner, portfolio or catalog
consumer logic changed. All previous 74 descriptor objects are preserved.

The existing SVE records and their variants are not rekeyed or rewritten. This
fix grants signed prefix recognition for **24 numbered identities**, which can
then use the existing catalog lookup and variant-choice paths. It does not
create new finishes or pricing bindings, nor assert that every holo pattern is
correctly represented or priced.

## Two-authority evidence

All 24 identities matched the TCGdex English SVE set against
[Bulbapedia's SVE Basic Energies table](https://bulbapedia.bulbagarden.net/wiki/SVE_Basic_Energies_%28TCG%29).
The [independent factual table](independent-checklist.json) and
[per-card comparison receipts](evidence.json) preserve numbers, names, source
URLs and hashes. Bulbapedia includes Basic in the printed name; TCGdex omits that
word. The comparison explicitly accounts for this naming difference.

| Number range | Eight types in order | Printing group identified by the independent source |
| --- | --- | --- |
| 001–008 | Grass, Fire, Water, Lightning, Psychic, Fighting, Darkness, Metal | Original Scarlet & Violet |
| 009–016 | Same sequence | Stellar Crown crystal designs |
| 017–024 | Same sequence | Black Bolt / White Flare designs |

The manufacturer's [SVE 001 artwork](https://www.pokemon.com/static-assets/content-assets/cms2/img/cards/web/SVE/SVE_EN_1.png)
was visually inspected and shows the SVE prefix and numeric 001 footer without
an expansion fraction. Manufacturer image reads succeeded for 001–008; reads
for 009–024 returned HTTP 403. Those access results are retained in the
[artwork receipt](official-artwork-check.json); they are not represented as
24 successful official-image inspections. All 24 numbered identities instead
have the TCGdex/Bulbapedia corroboration above. No downloaded image is committed.

The [authoring utility](../../../scripts/prepare_pokemon_sve_energy.py) verifies
all 24 set/local IDs and type names, fetches complete native provider details,
and emits the [existing-format descriptor](energy-input.json). It never signs,
publishes, or changes finishes. No `/24` fraction is fabricated from a set count.

## Meaningful milestone verification

- Native publisher validation passed for the new SVE descriptor and all 24
  provider card records. Combined validation passed for **42 new sets / 818
  numbered records**: the earlier 794 membership identities plus 24 SVE cards.
  The [union review](native-union-review.json) is an isolated fixture report,
  not a full production release or a proposed production revision number.
- The real public-key verifier and contract validator passed for the full
  **75-descriptor** union against hosted revision 19, preserving all active
  33 descriptors. The [signing report](native-signing-report.json) confirms
  protected `newSet` classification. Its 794 `newMemberships` count deliberately
  excludes SVE: SVE uses prefix authority, not a per-card membership list.
- Existing Energy and membership Core regressions: **10 passed, 0 failed**.
- Focused iOS Simulator XCTest run: **3 passed, 0 failed, 0 skipped**, including
  the new production-input-driven SVE test and two existing Energy regressions.
  The new test checks all 24 SVE footers, their lookup identity and saved scan
  snapshot round trip, split English observations, foreign-language/fraction
  rejection, and separation from MEE. The unchanged bundled seed continues to
  reject SVE until the registry update grants it authority.
- [Executed test identifiers](native-parser-results.json) were verified from
  the completed xcresult. The modern summary reader failed on a Library/Caches
  write; the legacy object reader succeeded and supplied both counts and named
  passing test records. The success claim is not inferred from selection flags.
- All 75 provider set IDs are unique, prior descriptors are preserved, source
  comparisons and local links pass, and `git diff --check` passes. Build data,
  compiler caches and xcresult were kept on the external SSD.

Only the new regression test, authoring/evidence utility and catalog data changed
for this fix. No physical camera/OCR, paid-provider, persisted collection or
portfolio acceptance was performed. Simulator parser tests do not prove those
gates or flawless pricing. Existing provider Cosmos, Cracked Ice, Poké Ball and
Tinsel metadata remains subject to independent physical/product review.

## Signing and remaining scope

This change uses existing schema/rules support and therefore fits the owner's
catalog-only restriction. The normal [production workflow](../../../.github/workflows/pokemon-catalog.yml)
must rebuild the full candidate against the then-active release, request the
protected new-set route, and sign it according to the
[runbook](../../plans/pokemon_catalog_key_handling_runbook.md). The isolated
42-set fixture must not replace the full 75-descriptor production catalog.
No signing key, commit, push, workflow dispatch, new signature or publication
was used here. Existing installed apps do not gain SVE from an unpublished input.

The separate request for minimal signed variant/product-override support remains
pending. SVE registration does not resolve the reported Eevee Cosmos or Charizard
**Jumbo** omissions, W-stamp pricing handles, missing Lycanroc Energy records,
or the full English-history objective.
