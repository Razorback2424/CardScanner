# Collection Integrity v1 Privacy-Safe Scorecard

Version: `collection-integrity-retention-v1`<br>
Status: Frozen schema for Phase 0<br>
Effective date: 2026-09-13

| Study ID | Cohort eligible | First meaningful placement date | Meaningful location | First Verify complete | Genuine discrepancy found | Genuine discrepancy reconciled | Qualifying later change | Repeat Verify after change | Days placement→repeat | Evidence source | Notes category |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- |

The table may contain pseudonymous IDs, booleans, dates, elapsed days, an
evidence-source label, and coarse note categories. It must not contain
collector names, emails, card names, container names, precise locations,
certificate IDs, monetary values, images, or full exported inventories.

## Aggregation formulas

```text
meaningful_location_rate = meaningful_location_count / eligible_cohort_count
first_verify_rate = first_verify_complete_count / eligible_cohort_count
reconciled_discrepancy_rate = reconciled_discrepancy_count / eligible_cohort_count
repeat_after_change_rate = repeat_verify_after_change_count / eligible_cohort_count
```

All denominators are the eligible cohort count unless a later study revision
explicitly freezes a different denominator before observation begins. Missing
events are recorded as false/unknown according to the study protocol; they are
not silently excluded.

## Interpretation

Use the interpretation and falsification rules in the companion
[`collection-integrity-v1-retention-contract.md`](collection-integrity-v1-retention-contract.md).
Do not infer willingness to pay, subscription demand, or product-market fit
from this scorecard.
