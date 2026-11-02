# Pricing correctness before coverage expansion

## Reconciled PR #14 — 2026-11-02

Starting head `ce17ea0acb8999bbdfb754a1c7b4f1145edf96ba` matched the review.
The local observation-kind column now represents passive expiry and physical
review without a SwiftData schema change. Ordinary provider observations still
use local receipt time; provider `effectiveAt` never moves a prior close.
For a previously learned future deadline, the local expiry event's `receivedAt`
is that deadline and `effectiveAt` records when its evidence was learned. An
already-expired response or an inherited record without local history starts
at local knowledge time. Explicit provider withdrawals retain their intervals.

The shared writer materializes an elapsed deadline before replacing either the
positive observation or lifecycle metadata. Fresh checkpoints repeat the whole
quote decision against intervening evidence. Manual graded adds, duplicates and
additional copies use that writer; lifecycle-free re-adds cannot erase a known
deadline. Retained handles reestablish the trusted set-directory ID, with exact
product routes unchanged and unresolved directories failing closed.

Physical review is appended when learned, for canonical and imported lookup
keys, without changing quantity, physical identity or source amounts. Historical
valuation uses those events rather than applying today's rule retroactively.
Expiry sorts before equal-time recovery; explicit withdrawal and physical review
dominate equal-time quotes. Log reads, refresh indexes, replay, chart ordering,
valuation and alias selection share this precedence. Reconciliation is
idempotent; a stored historical amount is not recovery evidence. Unknown stored
kinds withdraw value and block authoritative recomputation. Downgrading to a
binary that lacks these semantics is not validated by schema compatibility.

Withdrawals enter pricing adjustment, never market loss. Failed reconciliation
rolls back and marks computation non-authoritative; unexplained current/replay
differences cannot publish closes. Integrated disk-store tests exercise expiry,
inactive recovery/reopen, real Bidoof reverse and Charmander Cosmos legacy IDs,
imported aliases, repeated reconciliation, equal timestamps, already-expired
receipt, stale queued recovery, save/checkpoint failure and unknown kinds.

Intermediate Xcode 27.1 / iOS 27 simulator selection: 617 executed, 616 passed,
one existing skip, zero failures. Final ordering/unknown-kind checks and CI
results are recorded in the handoff. Earlier fixture/compiler/space failures
remain recorded in `progress.md`; no device, live-provider or release claim.

**Date:** 2026-10-18. **Candidate:** `56d981f` plus local changes.
**Scope:** Priority 1 correctness only. Final signed simulator verification passed:
522 passed, four intentional opt-in skips, zero failures across 526 cases.

This is the current execution order for the pricing investigation. Existing
catalog coverage authorities remain responsible for individual printing joins.
The committed Lorcana Browse scaffolding is retained; this follow-up adds no
mapping data, physical UUIDs, provider credentials, or ownership migrations.

## 2026-11-01 — stale collection quotes after manual refresh

The supplied Misty screenshot retained a $6.85 TCGCSV quote received October 28
after a November 1 check. The current checkout additionally had an empty
`TCGCSV_PRICE_BASE_URL`; both trusted hosts returned HTTP 404 for the feed.
Daily ingestion was succeeding while publication was disabled. The November 1
candidate contains the exact reviewed Misty Holofoil product `716159` at $6.03,
source build `2026-10-31T20:05:59+0000`.

Collection refresh now forwards manual intent to the shared set-price source,
coalesces one request per set across the whole pass, and cannot inherit a saved
fallback from an overlapping automatic request. A failed explicit source check
preserves the quote and records failure separately. Unchanged build checks
cannot extend the original server capture's 24-hour freshness, including caches
written by earlier app versions. Stale catalog amounts remain eligible for
fallback on a manual check; eligible metered work bypasses the weekly local
cooldown and requests full responses while retaining vendor budget limits.

The focused iPhone 17 Pro / iOS 27 simulator selection passes **169 tests, zero
failures** across Pokémon TCGCSV, pricing, refresh lifecycle and structural writes.
The nine feed publisher tests and hosting configuration check pass. Artifacts
are retained outside the repository on external storage.
The opt-in `testLivePublishedMistyRefresh` requires a short-lived sandbox receipt
and verifies the built app's endpoint, real feed, preserved capture date and
replacement of a stale saved amount in an isolated collection.

**Operational status:** the prepared candidate's 1,335 file hashes validate with
no missing products. [Publication run 41315945682](https://github.com/Razorback2424/CardScanner/actions/runs/41315945682)
was cancelled before deployment by GitHub's macOS 14 runner brownout. The
one-line publisher runner update to `macos-latest` is included in this requested
commit/push. Publication, daily activation, app endpoint configuration and live
native acceptance remain pending. The
[runner retirement notice](https://github.com/actions/runner-images/issues/13518)
confirms retirement on November 2. This source/simulator evidence does not
establish physical-device installation, CloudKit or release acceptance.

## 2026-11-01 — exact Cosmos and graded regression cases

The [case matrix](../audits/catalog-pricing-cases-2026-11-01.md) owns this
candidate's results and live/device limits. It covers reviewed Cosmos choices,
exact product proof through graded binding, saved/offline checklist lifecycle,
premium labels and PSA qualifiers, finish-preserving slab imports, Japanese
language, retained-ID refresh, and explicit graded quote expiry. Two reviewed
Ditto/Cosmos collisions retain distinct physical dimensions and hold ambiguous
legacy identities for review without migration. Daily aggregate quote coverage
is counted separately from membership/product presence. The inactive feed,
unavailable app-specific API key, unverified Spinarak replay, physical reviews
and Tinsel coverage remain gates; no completeness or release claim is made.

## Priority 1 contract

| Condition | Required behavior |
| --- | --- |
| Valid exact USD quote | Display and value only that printing/finish; retain its actual source and dates. |
| Historical EUR observation | Preserve durable evidence; exclude it from current USD display and portfolio valuation. |
| Invalid/foreign refresh response | Reject it before reference-cache replacement; preserve a prior valid quote. |
| Missing approved product/finish mapping | Report mapping pending across Browse, details, Price Check and collection diagnostics. Do not count a provider failure or invent a provider observation/check. |
| Provider confirms no market quote | Report an absent USD quote separately from missing mappings and transport errors; retain a prior valid quote. |
| Provider explicitly expires an exact graded quote | Withdraw current value, retain lifecycle/history evidence, and keep transport failure distinct. Never substitute `last_price` or another slab. |
| Provider failure | Preserve the prior quote and its retrieval timestamp; expose the unsuccessful refresh separately. |
| Stale quote | Preserve the amount and age; never renew its market timestamp merely because a check ran. |
| New exact handle after a failed name search | Permit a keyed lookup despite the old search miss. After a successful keyed response, respect the normal cooldown even if that lookup also missed. |
| Revised matcher/new exact adapter | Revisit obsolete negative/capability results without discarding resolved vendor handles or requiring paid fallback for an exact free adapter. |

Missing mappings are distinct from an operational error in the shared quote
service. Browse keeps their IDs separate from confirmed no-quote and request
failure IDs. An unqualified printing with one missing finish and another priced
finish still receives its highest available exact USD quote. Browse/detail
mapping-only gaps do not advertise a network Retry action. Collection refresh summaries report
pending mappings, and a pass with no due work no longer claims all prices are
current. Price Check refuses a foreign response rather than caching it and
remaining indefinitely in a checking state.

No SwiftData model/schema or ownership mutation is introduced by this follow-up.
The mapping diagnostic uses the existing price-record diagnostic field. No
ordinary-finish substitution, currency conversion, or low/mid listing-price
substitution is added.

## Verification

The first unsigned selection exposed the per-finish aggregation and withdrawn
mapping expectation changes, plus simulator Keychain entitlement failures.
The aggregation and tests were corrected; signing the simulator host resolved
the Keychain failures without changing production credential storage.

Intermediate signed selections passed 342 and then 483 cases, with four opt-in
skips in each. These selections overlap and are not additive. The final signed
iPhone 17 / iOS 27 selection completed with `TEST SUCCEEDED`, exit zero:
522 passed, four intentional opt-in skips, zero failures across 526 cases.
It includes Collection refresh presentation and legacy capability-cache recovery.
Evidence is retained outside the repository under
`/Volumes/Keller Family Photos/CardScannerBuild/PricingCorrectness-20261018-Verified.xcresult`.

Assertions cover USD currency eligibility, retained foreign evidence, rejection
of foreign cache updates, old quote preservation, exact finish isolation,
negative-cache recovery and pacing, mapped-game routing, source-null versus
missing mapping, and unchanged ownership/portfolio evidence. The suite is a
deterministic simulator regression, not fresh live-provider, physical-device,
CloudKit, archive, or release acceptance.

HIG source review: **PASS** for the bounded wording/status change. Existing system
labels, semantic fonts and informational symbols are retained; mapping gaps do
not add a blocking prompt or a misleading retry. Platform patterns, clarity,
typography, accessibility structure, interaction cost and design risk pass by
source inspection. No new rendered-device or
spoken VoiceOver acceptance is claimed.

## Deferred sequence

1. **Reviewed coverage batches:** start with Q3's available market quotes,
   Hyperia ordinary cards and existing exact Pokémon product IDs. Reproduce
   row-level availability first. Keep One Piece special-printing joins reviewed.
2. **One pricing decision pipeline:** align provider order and cache policy across
   Browse, Price Check and Collection. This follow-up aligns currency/status
   correctness; it does not establish identical provider retrieval on every screen.
3. **Coverage census:** count the entire installed Pokémon and Magic catalogs;
   classify all 1,833 Lorcana discovery-only records and 123 verified unmapped
   One Piece printings separately from upstream price availability.

Each census row needs game/set, verified printing count, exact pricing-lane
count, mapped lanes, valued lanes, upstream-null lanes, unresolved identities,
operational failures, source observation date and evidence reference. Printing,
product, finish-lane and artwork counts must not be treated as interchangeable.

The earlier Lorcana arithmetic reconciles as 1,218 records in the five named
later sets, 242 in Hyperia, 38 in Q3 and 335 in other distributions: 1,833 total.
The earlier Q3 live diagnostic found 13 market quotes and 25 nulls; low/mid
listing prices do not establish market-price availability. Those are dated
investigation results, not new live verification by this correctness slice.

Before any coverage rollout, independently verify Hyperia's prerelease/general
release dates and price labeling, and reconcile serialized Illustrious designs
as distinct objects. For Magic's 461/462 discrepancy, compare actual printing
IDs and extra-card inclusion rules. Do not alter counts to match one checklist.

See the [coverage audit](../audits/card-coverage-gaps-and-research.md),
[four-game review](../research/catalog-variant-coverage-2026-10-15/README.md),
[Pokémon pricing plan](browse_pricing_coverage_plan.md), and
[One Piece mapping investigation](../audits/one-piece-op16-op17-pricing-gaps.md).
