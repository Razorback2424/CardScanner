# Pricing correctness before coverage expansion

## First-edition finish and stale detail follow-up — 2026-11-02

**Validation base:** `main@9413e906cab65c1d8c61882d8eb6f137bf44617e`,
plus the local source patch recorded below. Both remaining medium findings were
confirmed and repaired:

- After a successful TCGCSV snapshot fetch, a cached detail quote takes
  precedence only while both its detail receipt and market-data evidence are
  fresh. Repeated sort loads now select the fresh snapshot over a stale detail
  quote; genuinely fresh detail pricing retains its existing preference.
- First-edition catalog detail preserves the physical Holo/Normal finish and
  carries print run separately. When catalog finish metadata is absent, an
  owned raw finish can supply the row. A generic edition-only quote remains
  context when no physical finish is known and cannot price a known Holo slot.
  Display and reconciliation use the same finish selection.

Three new native regressions failed before these fixes and pass afterward.
The final affected selection executed **298 tests: 297 passed, one expected
skip, zero failures**, across `PricingTests`, `BrowseFeatureTests`,
`QuoteCacheTests`, `PokemonTCGCSVPriceTests`, `CollectionStoreDigestTests`,
`RefreshStructuralWriteTests` and `JustTCGV2GradedSurfaceTests`. The centering
corpus was excluded by this selection, as requested. This is an affected-suite
result; the historical full-suite failures below remain recorded.

External SSD evidence uses stem
`owned-price-followup-final-9413e90-20261102`: `.xcresult`, `.summary.json`,
`.source.patch` and `.manifest.json`. The manifest records the base SHA, all
source-file hashes, the source patch captured before `xcodebuild` and verified
unchanged afterward, the exact command, and the built app/test binary hashes.
Source-patch SHA-256:
`ecff788ebabf054588030118ef27d760e07a5ded084432f37500d0518c9d68f7`.
The native summary confirms the counts independently of stdout. Initial
`xcresulttool` cache creation failed; reading with a temporary tool cache
recovered the summary without repeating the successful tests.

Using that same tested app binary, four inspected simulator captures confirm
first-edition Holo's saved **$713.30** on the production set grid, catalog detail
and Collection detail, and **$816.38** on catalog detail after newer evidence.
The catalog row remains Holo, with the correct saved/new source attribution.
Captures and their hashes are retained with the external evidence; no source
or layout changes followed the native run.

Set-grid refresh still updates catalog ordering hints, not owned valuations.
Owned reconciliation remains on detail opening and Collection refresh. These
repairs do not explain or certify the physical Mega Gengar case, provider
coverage or any device/release gate.

## One owned price and honest sort dates — 2026-11-02

**Historical implementation checkpoint:** started at `51b97bc`, with focused
native and simulator evidence. Seven unrelated baseline test failures remain,
as below. The supplied plan's seven findings were confirmed before repair: the set
grid, catalog detail and Collection read independent prices; alias promotion can
bypass the selected record's guards; owned values wait on catalog quotes;
variant-only state can conflate local entries; Pokémon detail drops cache bypass;
sort producers discard their evidence dates; the unpriced export omits valued
cards needed for this investigation. Collection refresh's `priceTarget` had the
same alias-promotion defect. A new native regression failed before the fix:
an older catalog quote replaced the selected $713 legacy value with $0.42 under
the previously absent primary key.

The validated implementation contract is:

- The ownership projection carries the exact key and `PriceDisplay` selected
  by Collection, including legacy aliases and physical-review exclusions.
  Browse overlays owned values on catalog ordering hints for tile prices,
  accessibility, sorting and the priced count. An unpriced owned entry remains
  unpriced. Graded, stamped and sealed entries do not supply a raw-slot value.
- A pure reducer preserves each local entry. The newest valued entry supplies
  a slot's single amount; differing entries remain individually attributed in
  the Owned section. Collection identity and selected key govern reconciliation,
  rather than finish alone. Matcher-only finish aliases are display-only.
- Catalog detail reconciles exact finish/treatment matches through the serialized
  writer. The complete selected-record decision is also replayed in Collection
  refresh's fresh checkpoint. An older source quote or a quote missing source
  dates cannot bypass a newer saved alias through an empty primary key.
  Catalog adds, their deferred fallback quotes and stored-row scan price staging
  use the same guard, so adding a copy cannot bypass the detail reconciliation.
- **Review correction (High):** alias promotion must also preserve invalidation
  and receipt-order guards. A pre-invalidation quote cannot create a primary
  value when the selected alias is invalidated. A delayed response cannot
  bypass a later receipt. New evidence after the correction can recover normally.
- **Review correction (Medium):** distinguish proven older source data from
  missing source-date evidence. The latter's age is unknown; the caption must
  never substitute the fetch time and claim it is older market data.
- Saved prices remain visible during loading, failure and unavailable results.
  Attribution and stale state use `PriceDisplay`; history names JustTCG and is
  identified as history separately from the saved Collection valuation.
- Stale owned values force a detail fetch. Forcing callers wait out ordinary
  tasks, then start or join a cache-bypassing task; ordinary callers may share
  a forcing task. Apply this to both detail tasks and shared Pokémon payloads.
- Every positive sort producer carries its original evidence receipt date.
  Persist per-slot `SortPriceHint(price, checkedAt)` under `sortprices-v2|`.
  Old positive quotes remain retryable hints, including after failed refresh,
  narrow write-back and reopening. Saving an envelope does not renew its slots.
- The all-card price-evidence export includes valued and stale-valued entries,
  the selected key, retained source/receipt dates and latest attempt evidence.

**Freshness scope:** set-grid fetching updates catalog ordering hints. It does
not refresh owned valuations. Owned prices change on catalog-detail reconciliation
or Collection refresh, so a successful set fetch may coexist with a stale or
unpriced owned slot. The grid shows the selected amount; detailed provenance is
on the detail surfaces. Set loading/pending-state redesign and unowned Price
Check unification remain deferred. No schema migration or new persisted quote
fields are needed.

Verification covers alias retention/promotion, invalidation during a queued
write, delayed receipts, distinct date captions, projection agreement, owned
grid inputs, stale detail/bulk/TCGCSV producers, forced-task sharing and the
valued-card export. That checkpoint's focused run passed **294 tests with one expected
skip and zero failures** (295 executed), including the removed-owner checkpoint
regressions and catalog-add alias retention. At the owner's request, subsequent broad runs
exclude `CardCenteringGroundTruthTests`, `CardCenteringInvariantTests` and
`CenteringProfileDumpTests`; the superseded unrestricted run was stopped during
the corpus diagnostics.

The broad run executed 3,016 methods, with 19 skips and ten failed methods
(32 XCTest failure reports). It exposed two removed-owner refresh regressions,
now fixed and covered by all five passing `RefreshStructuralWriteTests`, plus
a stale grading-key expectation corrected to include the existing finish field.
The seven remaining methods reproduce unchanged on `51b97bc`: three unsigned
Keychain tests (`-34018`), three scanner-state tests and a SwiftData notification
key-shape assertion. The isolated baseline control reproduced all seven with
28 failure reports. No production grading behavior was changed to satisfy a
test. This is focused feature verification, not a green full-suite claim.

The production set grid, catalog detail and Collection detail were captured for
native and legacy-alias records with both older and newer incoming evidence.
All twelve captures agree: $713.30 is retained for older evidence; $816.38 is
selected for newer evidence. Catalog attribution and expanded Collection Price
details agree on the source date. Failed, unavailable and undated checks retain
the saved amount, with distinct captions and no price spinner. Captures remain
outside the repository under `/private/tmp/pricing-ui/`; no personal collection
was seeded or exported. The largest accessibility text size exposed caption
truncation; the final captures confirm full wrapped captions and history heading
at Accessibility XXXL. Retry retains the saved-price explanation after another
check. The detailed visual loop is recorded in `progress.md`.

The 295-case run preceded the final caption/history wrapping edits; that older
bundle did not validate the final UI source tree. The source-bound 298-case
follow-up above includes those edits and the two subsequent repairs.

No phone, live-provider, CloudKit or release gate is inferred. The ASC 284 phone
case still requires an installed build and the new evidence export.

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
