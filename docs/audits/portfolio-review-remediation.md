# Portfolio review remediation

**Date:** 2026-10-09. **Status:** implemented locally; focused simulator tests pass.

The supplied review was checked against the current source. All ten numbered
findings describe present integration or presentation problems. Arithmetic,
close revision policy, quantity repair revalidation, and the chart's market-only
meaning are unchanged.
The existing choice to hide the best-cards rail for a non-authoritative summary
also remains; publishing pre-epoch holdings does not override that policy.

| Finding | Implementation |
| --- | --- |
| 1: ownership edits deferred during refresh | Monitor ownership requests bypass the price gate without awaiting completion; ordinary checkpoints stay gated and the controller retains its terminal replay. Explicit quantity repair also bypasses the gate. |
| 2: range changes clear history | History caches its last value inputs and calculates the newly selected range synchronously; failed or missing inputs clear the cache. |
| 3: cold start uses failure copy | A neutral value placeholder displays while loading. Read failures still show “Value unavailable”; loading accessibility copy describes calculation. |
| 4: excluded copies undisclosed | The hero and Pricing & Data disclose unpriced copies and copies priced in another currency separately. |
| 5: deltas produce false history residuals | History consumes a replay-consistent summary. Scrubbing Today uses the latest live headline value, including for VoiceOver. |
| 6: unbounded home diagnostics | The home warning shows a count and at most three plain-language issues, with quantity issues named where holdings resolve. Full diagnostics are available in Pricing & Data, including cold-start read failures. |
| 7: details freeze on navigation | Pricing & Data observes portfolio and history publications. An explicitly opened movement breakdown retains its selected-period snapshot. |
| 8: no-op deltas republish holdings | Map into a local array and publish only when a holding changed. |
| 9: no epoch suppresses holdings | Holdings, contributions and factors publish before the epoch guard. Foreground day checks also allow a deferred epoch retry. |
| 10: instrument count says copies | Carried-forward coverage copy refers to prices. |

The retry button now says “Retry reconciliation”, matching its existing ordinary
recompute behavior. Removed the unused coverage view and safe-array subscript;
signed money presentation shares the existing zero-aware formatter. The toolbar
attention predicate now includes cancellation, matching the details screen.

The performance-factor pipeline and its tested contracts are retained. Its lack
of a displayed return metric alone does not establish that removing replay
outputs is a worthwhile part of this focused fix. Other helpers used by tests
are retained. No scrub rendering, close retention, or refresh-duration
optimization is claimed without measurement.

## Verification boundary

New deterministic regressions cover live scrub values/accessibility, synchronous
range selection, history accounting during deltas, cache clearing, pre-epoch
holdings, no-op publications, gate bypass, and a monitor ownership edit during a
paused provider pass. The monitor test counts ownership and terminal replays.
At `3c28b30` plus local changes, Xcode 26.6 / iOS 26.5 iPhone 17 Pro completed
147 selected tests with one opt-in performance baseline skipped and zero failures
(146 passed). Targets: PortfolioHistoryEngineTests, PortfolioReconciliationTests,
PortfolioTrustPassTests, StoreRevisionMonitorTests and PriceRefreshLifecycleTests.
The first attempt failed during simulator runner bootstrap before assertions.
The next run exposed two incomplete new fixtures, corrected before the final
passing run: activity/ledger consistency and refresh staleness eligibility.

Build products and xcresults are on the external drive under
`CodexBuilds/PortfolioReview/`. The successful result is
`Test-TradingCardScanner-2026.10.09_14-15-44--0600.xcresult`.
Normal PortfolioToday and PortfolioHistory captures were inspected on an
isolated simulator using the tested binary and synthetic fixture. Headline,
chart, period chips, toolbar and tab bar display correctly without new clipping
or overlap. Captures and the checklist are in `/tmp/portfolio-review-ui-today/`,
`/tmp/portfolio-review-ui-history/` and `/tmp/portfolio-review-ui-checklist.md`.
Loading, excluded-copy and large-warning visual states were checked in source,
not separately captured. No screenshot is committed.
Real-device frame timing, 500/1,500/3,000-card refresh duration, provider behavior,
CloudKit initial sync, archives and release readiness remain unverified.

## HIG design gate

**Verdict: PASS for the scoped design review.** No new design issues identified;
no further minimal fixes required by this gate.

| Category | Status | Rationale / minimal fix |
| --- | --- | --- |
| Platform patterns | PASS | Existing navigation, system buttons and details list are retained; no fix needed. |
| Clarity | PASS | Loading and failure copy differ, excluded copies are disclosed, and home diagnostics are bounded; no fix needed. |
| Typography | PASS | Added explanations use secondary Dynamic Type caption/footnote styles; no fix needed. |
| Accessibility | PASS | Live scrub values match VoiceOver and idle loading announces calculation; no fix needed. |
| Interaction cost | PASS | No new prompt is introduced, and full diagnostics are one action away; no fix needed. |
| Design consistency | PASS | Retry copy describes its actual behavior and standard controls are preserved; no fix needed. |

Existing hero typography is unchanged; a complete Dynamic Type audit is outside
this evidence. This is a scoped design assessment, not App Store certification.

## Plan reconciliation

The older [October plan §H](../plans/october-refinement-implementation-plan.md)
said an active price pass owned the trailing replay. That remains true for price
checkpoints. Ownership edits now additionally request immediate coalesced work
because withholding them makes Collection and Portfolio disagree. This is a
deliberate cost tradeoff: an ownership edit may buy an extra replay during a pass,
while the terminal replay still reconciles all pricing evidence.
