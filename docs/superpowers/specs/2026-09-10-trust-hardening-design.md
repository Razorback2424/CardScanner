# Trust Hardening Design

**Date:** 2026-09-10  
**Status:** Approved for implementation by the user

## Goal

Make the app's trust claim mechanically defensible: delayed price evidence must
not be discarded, only USD values may enter portfolio totals, exact graded
identity must survive lookup and persistence, and the app must show enough
variant provenance for a person to notice uncertainty before relying on the
record.

The implementation deliberately excludes binder-page multi-detection and
physical-location mapping. Those capabilities depend on the identity pipeline
being trustworthy first.

## Architecture

### Price evidence and valuation

`PriceObservationLog.isOutOfOrder` will only order observations. When both sides
carry a provider source clock, strictly newer source timestamps are accepted,
strictly older timestamps are rejected, and equal timestamps are accepted so
`PriceObservationRules.decide` can apply its existing unchanged/append policy.
If either side is unstamped, the existing conservative local-receipt rule
remains in force; explicit invalidation remains exempt.

A pure `eligibleUnitPrice(amount:currencyCode:) -> Money?` rule will become the
single USD valuation gate. `PortfolioEngine.applyPriceDeltas` and
`InventoryLedger.resolveValuation` will both call it, while the latter keeps its
observation precedence and invalidation semantics. Ineligible transitions
produce `nil` unit and holding values and subtract the old holding value from
the live total.

### Exact graded identity

The existing `GradedCardIdentity` remains the canonical identity. Its
`groupingKey` will account for every stored property that can distinguish a
vendor request, including `pokemonPrintRun`. Its matching projection will
always require canonical set compatibility and will compare the complete
collector-number evidence when both sides publish a number; one-sided number
absence is ambiguous and is rejected for a numbered request. Graded lookup
results will be validated before a vendor handle or price is bound to a
collection row.

No language or finish/treatment fields will be added to this type in this
slice. The current JustTCG graded payload exposes card name/set/number and
grading data, not those axes; Pokémon locale is already part of the vendor game
projection and Magic treatment is already a separate collection/price key.
The type should gain another field only if the vendor's graded identity contract
proves that field is a pricing discriminator.

The picker-to-confirmation-to-`CollectionStore.addGraded` path will carry
`pokemonPrintRun` without a default being applied accidentally. Tests will pin
the round trip and the distinct lookup groups.

### Provenance presentation

`VariantResolution.isAutomatic` keeps its existing meaning: whether a future
rule change may revisit the resolution. A new certainty/presentation property
will model a different concern and will not reuse `isAutomatic`. Card detail
will always render finish plus provenance, including the explicit catalog-silent
case. Scan receipts will render an attention treatment for catalog-silent,
user-confirmed, imported, or otherwise unresolved outcomes; routine catalog-
unique and deterministic-set-rule outcomes remain visually quiet while staying
available to accessibility text where appropriate.

The receipt model will carry the resolution rather than reconstructing it from
the finish label, so the displayed provenance remains the same fact that was
persisted.

## Verification design

Tests will assert behavior-level invariants:

1. live delta valuation equals authoritative replay across replacements,
   invalidation, and USD/EUR transitions;
2. Collection and Portfolio use the same eligible valuation;
3. graded identity and print run survive picker/persistence/refetch;
4. distinct identities do not share intermediate lookup keys;
5. external products are rejected before authoritative binding;
6. uncertain resolution cannot become definite through a projection; and
7. shuffled arrivals with identical source chronology converge to one final
   state.

Targeted tests will cover delayed newer source stamps, genuinely older stamps,
equal-stamp delegation, invalidation, same-number/different-set rejection, and
print-run lookup order independence. UI verification will use deterministic
routes/screenshots for catalog-silent, finish-lock, user-confirmed, and routine
unique-in-catalog states.

The competitor benchmark is manual by design. The repository will contain a
recording template and protocol with the six requested outcomes, but it will
not invent competitor results or claim a run that has not happened.
