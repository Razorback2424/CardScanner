# Collection Integrity Retention Contract

Version: `collection-integrity-retention-v1`<br>
Status: Frozen for Phase 0<br>
Effective date: 2026-09-13

## Hypothesis

> Serious collectors who establish a canonical collection and use Place →
> Verify → Reconcile will voluntarily return to CardScanner after their
> physical collection changes, making the integrity system a meaningful
> retention advantage.

The public 1.0 does not implement Place, Verify, or Reconcile. This contract
freezes the future behavioral experiment so the release does not optimize
against an unstable definition.

## Cohort

Recruit approximately 15 deliberately selected serious collectors. Include
people who own and actively change multiple physical storage locations, or a
collection large enough that location and identity drift is a real problem.
Exclude developer accounts, synthetic QA collections, scripted data, and
casual users who never attempt a real physical workflow from the primary
scorecard.

## Events

The event names and meanings are fixed:

- `meaningful_location_created`: a participant completes a placement that
  represents a real, useful physical location rather than a test or placeholder.
- `first_verify_started`: the participant begins the first verification of a
  meaningful location.
- `first_verify_completed`: that verification completes with an explicit
  outcome, including a clean result or a reviewed discrepancy.
- `genuine_discrepancy_found`: verification surfaces a real mismatch between
  the expected and observed physical state, not an instrumentation or test
  artifact.
- `genuine_discrepancy_reconciled`: the participant explicitly resolves that
  discrepancy through the approved reconciliation flow.
- `qualifying_collection_change`: after the first verification, the physical
  collection changes in a way that should make a later verification useful.
- `repeat_verify_after_change`: the participant completes a later verification
  after a qualifying collection change.

Only the completion event counts for completion rates. Starting a flow,
opening a screen, downloading the app, or expressing a compliment does not
count as validation.

## Window and directional thresholds

Observe each eligible participant for 42 days from the first meaningful
placement. The frozen directional thresholds are:

- at least 10 of 15 complete a meaningful first placement;
- at least 8 of 15 complete a first Verify;
- at least 5 of 15 find and reconcile a genuine discrepancy;
- at least 4 of 15 complete `repeat_verify_after_change` within the window.

These are directional thresholds, not statistical proof and not willingness-
to-pay criteria.

## Interpretation and falsifiers

- Import/catalog without meaningful placement means Place activation failed or
  the job is weak.
- Place plus one Verify without a repeat means one-time organization utility,
  not recurring retention.
- Repeated Verify with few discrepancies means frequency or targeting needs
  reassessment.
- Repeated Verify with speed complaints supports later page-level computer
  vision investment.
- Repeated Verify is evidence of retention value, not willingness to pay.

The experiment is falsified or requires redesign if the target behavior does
not occur in the frozen window, if participants cannot establish a meaningful
canonical collection, or if the observed activity is dominated by test data.

## Monetization boundary

No price is frozen here. Grade/Sell and economic workflows receive a separate,
future experiment after their own value and policy questions are defined. The
public 1.0 is free and contains no StoreKit product, subscription, paywall,
entitlement, purchase, or restore flow.

## Privacy rule

Validation must not upload raw inventories, card names, certificate numbers,
precise physical locations, images, or collector identity. The scorecard may
contain pseudonymous study IDs, booleans, dates, elapsed days, and coarse note
categories only.
