# Catalog completeness and pricing failure-mode inventory

Source inspection: 2026-11-15. This is a classification reference, **not** a
claim that every possible runtime error has occurred or that all five live
catalogs were enumerated. It distinguishes an observed retained-data finding,
a static publisher validation rule, a live/runtime condition, and an area that
the offline report cannot assess. Each label below has a distinct evidentiary
standard. Do not use a missing row as evidence that a live catalog is complete.

## Output contract

- `catalog-inventory.csv`: retained record/printing/finish observations;
  `source_scope` distinguishes `installed`, `candidate`, `historical`,
  `retained_raw`, `test_only`, `retained_physical`, `retained_discovery`,
  and `retained_seed`. Multiple product appearances can legitimately produce
  multiple rows for one physical printing.
- `catalog-exceptions.csv`: only inventory rows assessed `actionable`.
- `catalog-summary.csv`: counts each issue by game, source scope, product
  set, and issue code. Counts are **issues**, not unique physical cards.
- `catalog-census-findings.csv`: raw `audit_catalog_coverage.py`
  discrepancies, with original code, scope, disposition and detail. These can
  refer to a set, source or family, not necessarily a physical printing.
- `catalog-metadata.json`: reproducibility and source hashes.
  `catalog-run-failure.json` is retained on a known structural or feed
  validation failure; a failed run never emits a fabricated partial inventory.

A `verified` printing does not imply a price; a matching number or artwork
does not prove a printing; a complete provider response with a null price is
not a request failure. A source risk cohort is not proof of a defect.

## Shared price and catalog states

| Code or state | Where detected | Meaning; what evidence is required |
|---|---|---|
| `PRINTING_NEEDS_REVIEW` | offline inventory | Discovery/held physical identity has not been approved |
| `CANONICAL_CARD_MISSING` | One Piece observations | Discovery number has no canonical English card; not shown in current Browse |
| `SOURCE_OBSERVATION_INCOMPLETE` | One Piece observations | Source discovery lacks product membership or printed number |
| `FINISH_UNVERIFIED` / `EDITION_UNVERIFIED` | physical catalog | Finish / edition is genuinely missing; not an inference from a raw provider slot |
| `RAW_FINISH_COVERAGE_UNEVALUATED` | raw Pokémon checklist | Physical finish corrections were **not run**; non-actionable until verified |
| `PHYSICAL_FAMILY_INCOMPLETE` / `PRINTING_FAMILY_INCOMPLETE` | Lorcana / Yu-Gi-Oh | Family authority or membership is explicitly incomplete; do not call the recorded finish unverified |
| `CANONICAL_LINK_UNRESOLVED` | Yu-Gi-Oh seed | Explicit unresolved canonical linkage |
| `PRICE_MAPPING_MISSING` | supported printing + finish/edition | No currently usable exact pricing association retained |
| `PRICE_MAPPING_UNAPPROVED` / `PRICE_MAPPING_CONFLICT` | One Piece mappings | Candidate mappings exist but none approved, or more than one active exact lane exists |
| `MARKET_MAPPING_INCOMPLETE` | retained exact mapping | Missing/invalid group, product, number, name or lane; can be identified without network |
| `MARKET_MAPPING_MISMATCH` | captured complete product inventory | Stored product identity disagrees with a captured product or product was absent; **not** a null quote |
| `PRICE_NOT_CHECKED` | no matching trusted capture | No current determination; **not actionable** by itself |
| `NO_MARKET_QUOTE` | complete, validated captured feed | Exact product/lane exists but its market value is missing/null; not a request error |
| `PRICE_SNAPSHOT_STALE` | capture freshness policy | Provider **snapshot** is older than threshold; individual quote update time is not proven |
| `quoted` | captured product and lane | Provider observation has usable USD amount; not proof an unverified physical printing is collectible |

`CatalogLookupError` (stale catalog, invalid adapter outcome/printing
choice, printing choice required, catalog incomplete), `CatalogFailure`
(not in catalog, transient, provider unavailable), `PriceQuoteError`
(identity mismatch, provider unavailable, mapping unavailable, pricing
unsupported), and the four user-facing `CatalogFailurePresentation`
messages (connectivity, catalog refresh, game unavailable, pricing access)
are **runtime-only** in this offline export. A retryable transport failure,
401/403 credentials failure, stale device catalog, rate limit, cancellation,
and pricing unsupported are not evidence that a marketplace quote is absent.
Sources:
`TradingCardScanner/Games/Core/GameCatalogAdapter.swift`,
`TradingCardScanner/Services/CardCatalog.swift`,
`TradingCardScanner/Services/PriceQuoteService.swift`,
`TradingCardScanner/Models/BrowseCatalogModels.swift`,
`TradingCardScanner/Services/TCGCSVProductPriceSource.swift`.

## Exact user-facing catalog and price messages

The phrases below are grounded in the present app, but a **message type is
not proof it occurred**. Only per-record notices that can be derived directly
from retained input are populated in `user_facing_notice`; live error banners
need runtime evidence.

| Actual UI text (counts vary) | Code / diagnostic meaning |
|---|---|
| `Printing needs review` | One Piece Browse discovery without a verified physical printing |
| `Browse only` | One Piece held physical printing |
| `Partial catalog` | One Piece product has unresolved discoveries/held printings/incomplete canonical coverage |
| `Price mappings pending for N cards` | Catalog price-sort slots with `mappingMissing`; not a failed provider request |
| `Couldn't price N cards` | Price-sort slots unresolved after requests; retryable; not proof of absent quotes |
| `No USD quote from checked sources for N cards` | Resolved source check with no accepted USD price |
| `This printing needs identity review (reason).` | Yu-Gi-Oh printing `identityReason` (`ir`) |
| `No supported edition is recorded for this product.` | Yu-Gi-Oh edition authority absent |
| `The available labels do not distinguish this printing.` | Yu-Gi-Oh choice evidence is insufficient; requires native candidate comparison |
| `Canonical card linkage is unresolved.` | Yu-Gi-Oh unresolved canonical relationship |
| `We couldn’t reach the catalog. Check your connection and try again.` | Generic connectivity, not catalog absence |
| `This listing needs updated catalog information. Refresh the catalog and try again.` | Generic catalog-resolution failure/stale generation |
| `This feature isn’t available for this game in the current catalog.` | Capability unsupported |
| `Pricing access is unavailable. Check your API key and account access in Settings.` | Pricing credentials/access unavailable |

Sources: `TradingCardScanner/Games/OnePiece/OnePieceBrowseAdapter.swift`,
`TradingCardScanner/Games/YuGiOh/YuGiOhBrowseAdapter.swift`,
`TradingCardScanner/Views/BrowseView.swift`,
`TradingCardScanner/Models/BrowseCatalogModels.swift`.
`user_facing_notice` is blank if the repository cannot determine an exact
per-card notice from offline inputs. Do not synthesize an error banner for a
network request that never ran.

## Pokémon

Retained audit findings in `catalog-census-findings.csv`:
`rawChecklistUsesOnlyNormalFinish`, `declaredSlotCountDifference`,
`displayCountDiffersFromStandardSlots`,
`seedDescriptorWithoutOfflineChecklist`,
`checklistOutsideModernSeedDescriptors`,
`seedPublisherDescriptorDifference`,
`reviewedParallelMissingFromRawSnapshot`.
Their original dispositions matter: an intentionally basic raw checklist
or historical seed mismatch is not automatically a missing physical card.

The retained raw checklist and its per-set slot counts are included, but the
read-time additional variants, corrected finish mappings, actual live
TCGdex inventory, and the complete Swift `PokemonTCGCSVMapping` projection
are not evaluated. Therefore absence of `PRICE_MAPPING_MISSING` or
`NO_MARKET_QUOTE` in Pokémon does **not** establish price completeness.

`PokemonTCGCSVError`: `unsupportedSet`, `invalidResponse`,
`identityMismatch`, `retryLater`. A single product's mismatched title,
number or group can reject the entire captured set, rather than proving all
its cards lack prices. `PokemonCatalogBuildError` covers invalid/missing
provider set/card fields, duplicate or drifted set codes, official-count
mismatch, missing details, membership mismatches, descriptor errors, and
fingerprints; `PokemonCatalogCandidateValidationError` also checks
snapshots, revision, reports and candidate classification.
Sources: `TradingCardScanner/Services/PokemonTCGCSVPriceService.swift`,
`PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogBuilder.swift`,
`PokemonCatalogCore/Sources/PokemonCatalogCore/CatalogCandidateValidator.swift`.

## Magic

Retained census codes: `runtimeAuditSourceDifference`,
`declaredAuditTotalDifference`, `runtimeTreatmentOutsideRetainedAudit`,
`runtimeTreatmentIdentityDiffersFromAudit`,
`seedCompiledVocabularyDifference`, `treatmentOutsideVocabulary`,
`declaredAuditCountDifference`.
The full Magic card catalog is retrieved through Scryfall; the
`MagicTreatmentSnapshot` is test-only and is *not* a complete current
printing inventory. The exporter correctly marks those rows
`coverage_not_evaluated` rather than inventing missing prices.

Build/publisher failures include duplicate codes/UUIDs, UUID-to-code
changes, printed-size drift, routing-authority drift, unauthorized removal,
candidate report/revision mismatch and publication change-class mismatch.
Historical lookup can also be `catalogIncomplete` or
`invalidPrintingChoice`; Scryfall can return unsupported printing,
identity mismatch, not-found, rate-limit or transient unavailable.
Those are not observed by the offline test-only snapshot.
Sources: `MagicCatalogCore/Sources/MagicCatalogCore/CatalogBuilder.swift`,
`MagicCatalogCore/Sources/MagicCatalogCore/CatalogCandidateValidator.swift`,
`TradingCardScanner/Games/Magic/MagicCatalogAdapter.swift`.

## One Piece

The installed Browse adapter displays a **single discovery row per product
and printed number**; individual artwork observations are joined evidence,
not additional rows. The offline report follows that grouping and preserves
the source IDs. The registry can project one verified printing into more
than one product via `appearances`, so product set and printed set marker
must be separate. Retained revision-4 candidate observations (including
OP18) are not described as installed. Historical unmatched TCGplayer
products are separate discovery *leads*, not missing verified printings.

Retained census codes: `reviewedPrintingAbsentFromOwnerSeed`,
`noVerifiedPrinting`. Current publisher validation has 53 distinct
fail codes, grouped here by cause (these are **possible validation errors**,
not observed incidents in a valid installed seed):

- Release/contract: `unsupportedContract`, `invalidRevision`,
  `invalidTimestamp`, `nonMonotonicRevision`, `invalidCandidateIndexes`,
  `incompleteSourceInventory`.
- Evidence and canonical: `missingReview`, `missingDistinctionEvidence`,
  `invalidEvidenceReference`, `invalidCanonicalIdentity`,
  `unreviewedCompleteness`, `invalidArtworkEvidence`, `invalidImageHash`,
  `invalidPerceptualHash`, `invalidImageURL`,
  `missingCanonicalReference`, `missingArtworkReference`,
  `printingLanguageMismatch`, `missingReleaseReference`,
  `invalidPrintingVariants`, `contradictoryReviewedEvidence`,
  `missingFinishEvidence`.
- Observation/alias: `invalidObservation`, `invalidBrowseDiscovery`,
  `invalidAlias`, `invalidBrowseDiscoveryAlias`, `duplicateSourceAlias`,
  `missingAliasObservation`, `unregisteredCanonicalObservation`,
  `unreconciledCanonicalObservation`.
- Marketplace: `invalidMarketMapping`, `conflictingMarketMapping`,
  `unverifiedExactMarketPrinting`, `marketIdentityMismatch`,
  `missingMarketFinishQualifier`.
- History/supersession: `orphanSupersededPrinting`,
  `invalidSupersession`, `unreviewedSupersession`,
  `supersessionCycle`, `invalidCorrection`, `invalidSplit`,
  `invalidMerge`, `correctionGraphMismatch`,
  `removedPermanentPrinting`, `mutatedPermanentIdentity`,
  `unreviewedAliasChange`, `removedCorrectionHistory`.
- Distribution/inventory: `invalidVariant`, `invalidProduct`,
  `invalidProductAppearance`, `missingProductAppearanceEvidence`,
  `invalidInventory`, `missingObservationInventory`.

The export does not execute the Swift validator or prove that a
`candidate` was signed/activated. For full pre-publication validity, run
the publisher's `CatalogCandidateValidator` and report its coded issues
separately from already-installed catalog exceptions.
Sources: `OnePieceCatalogCore/Sources/OnePieceCatalogCore/CatalogCandidateValidator.swift`,
`TradingCardScanner/Games/OnePiece/OnePieceBrowseAdapter.swift`,
`TradingCardScanner/Games/OnePiece/OnePiecePriceAdapter.swift`.

## Lorcana

Retained census code: `discoveryOnly`. Physical printings can be verified
individually while their **footer/family universe** remains incomplete.
This must be `PHYSICAL_FAMILY_INCOMPLETE`, not an unsupported finish.
Missing or not-yet-reviewed finishes remain separate. Source discovery may
coexist with verified physical records without implying duplicate identities.

Physical and registry validators distinguish `invalidManifest`,
`invalidCanonical`, `invalidPrinting`, `duplicateIdentity`,
`invalidUniverse`, `invalidCorrection`, `invalidTransition`,
`unsupportedSchema`, `invalidFamily`, `duplicateFooter`,
`duplicateSourceAlias`, `oversizedManifest`, and `invalidFooter`.
These validation failures must not be inferred from unverified discovery.
The offline capture supports known mapped product lanes but cannot verify
live price behavior without a matched dated feed.
Sources: `TradingCardScanner/Games/Lorcana/LorcanaPhysicalCatalog.swift`,
`TradingCardScanner/Games/Lorcana/LorcanaCatalogRegistry.swift`,
`TradingCardScanner/Games/Lorcana/LorcanaPriceAdapter.swift`.

## Yu-Gi-Oh

Retained census codes: `discoveryOnlyPrinting`,
`codeMultipleCanonicalCards`. Printing identity reasons (`ir`),
`incompleteCodes`, edition evidence (`e` and `ec`) and
`canonicalLink == "unresolved"` are independent restrictions.
The report uses distinct codes for missing edition, incomplete code family,
and unresolved canonical relationship. Product-level mapping `p` is enough
to permit a **current** edition quote, even if historical membership `m`
does not exist. Consequently absence of `m` is not
`PRICE_MAPPING_MISSING` by itself.

The `YuGiOhCatalog.LoadError` family is `missingResource`,
`invalidSchema` and `invalidRow(reason)` (e.g. duplicate group/card,
market binding, unpriced reference printing, printing family authority and
automatic eligibility). Separate review/selection restrictions can make
a physical printing non-acquirable even when its product has a quote.
The optional GitHub capture currently targets One Piece and Lorcana, **not**
Yu-Gi-Oh, so this report cannot establish its present-day quote coverage.
Sources: `TradingCardScanner/Games/YuGiOh/YuGiOhCatalog.swift`,
`TradingCardScanner/Games/YuGiOh/YuGiOhCatalogAdapter.swift`,
`TradingCardScanner/Games/YuGiOh/YuGiOhPriceAdapter.swift`.

## What is still needed for a truly complete five-game diagnosis

1. A native read-only catalog projection on iOS/Mac that enumerates exactly
   what Browse and the pricing adapters can resolve **after** their runtime
   corrections (especially Pokémon and live Magic), with release generation.
2. A dated cross-game market check covering all supported exact product
   lanes, including Pokémon and Yu-Gi-Oh. Record product identity mismatch,
   zero/null quotes, request failures, rate limits, permission failures and
   source freshness **without** collapsing them into `unpriced`.
3. Capture complete current provider discovery inventories to establish
   expected scope. Retained historic leads are not authoritative denominators.
4. Record candidate validation and activation/signing failures as their own
   publication report, not as supposed installed card defects.
5. Cross-check every exported installed Browse ID against the actual adapter
   inventory; compare counts per product, number and verified printing.
6. CI tests that ensure each new runtime diagnostic, validation issue and
   report disposition is assigned either a supported export path or an explicit
   `not_evaluated` boundary.

**No offline-only export can truthfully claim that all live request failures
have been enumerated.** The immediate deliverable is faithful retained-data
exceptions plus explicit gaps in what could not be evaluated.
