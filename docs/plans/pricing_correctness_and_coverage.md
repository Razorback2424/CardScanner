# Pricing correctness before coverage expansion

**Date:** 2026-10-18. **Candidate:** `56d981f` plus local changes.
**Scope:** Priority 1 correctness only. Final signed simulator verification passed:
522 passed, four intentional opt-in skips, zero failures across 526 cases.

This is the current execution order for the pricing investigation. Existing
catalog coverage authorities remain responsible for individual printing joins.
The committed Lorcana Browse scaffolding is retained; this follow-up adds no
mapping data, physical UUIDs, provider credentials, or ownership migrations.

## Priority 1 contract

| Condition | Required behavior |
| --- | --- |
| Valid exact USD quote | Display and value only that printing/finish; retain its actual source and dates. |
| Historical EUR observation | Preserve durable evidence; exclude it from current USD display and portfolio valuation. |
| Invalid/foreign refresh response | Reject it before reference-cache replacement; preserve a prior valid quote. |
| Missing approved product/finish mapping | Report mapping pending across Browse, details, Price Check and collection diagnostics. Do not count a provider failure or invent a provider observation/check. |
| Provider confirms no market quote | Report an absent USD quote separately from missing mappings and transport errors; retain a prior valid quote. |
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
