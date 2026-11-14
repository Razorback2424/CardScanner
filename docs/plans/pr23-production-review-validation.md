# PR #23 — production review reconciliation and release verification

**Status:** implementation in a draft PR; device, provider, migration and full-suite results are **not yet certified**. This document is a validation plan, not evidence that the tests passed.

**Baseline:** production review of `main` at `4c4a2e6f` on November 13, 2026. Review findings and implementation are tracked in [PR #23](https://github.com/Razorback2424/CardScanner/pull/23).

## Reviewed findings

| Finding | Code disposition | Remaining evidence |
| --- | --- | --- |
| F1 — graded valuation offers a raw TCGplayer link | Graded Price Check, collection and movement destinations suppress underlying raw product links. Raw links are retained for raw cards. | Confirm each surface on an actual slab and raw counterpart. |
| F2 — unresolved printed finish looks like a provider outage | Graded resolver, scanner and Price Check use distinct physical-identity, incomplete-search and provider-failure outcomes. | Confirm copy, correction, offline and retry behavior on device. |
| F3 — graded binding waits for a long background refresh | Scanner-initiated binding and certified-rescan identity writes use the existing cancel-and-replay gate. `gradedPriceBindingCommit` signpost isolates the post-lookup interval. | Measure cancellation latency, refresh replay, vendor quota and durable price state with a slow refresh. |
| F4 — failed price snapshot read leaves stale UI silently | Three bounded read attempts, last-known snapshot preservation, published failure state and Collection retry affordance. | Run injected failure tests, inspect layout at accessibility text sizes and test foreground recovery. |
| F5 — collection fingerprint omits displayed finish provenance | Fingerprint includes `variantResolutionRaw`, with an isolated-provenance test. | Verify real collection finish overlay changes without unrelated edits. |
| F6 — transient Keychain access failure cached as missing key | Only confirmed missing-key status is cached as absent; transient failures remain retryable. | Simulate lock/unlock or Keychain access failure on a signed device. |
| F7 — no complete iOS application release gate | `.github/workflows/ios-release-gate.yml` builds the app in Release and runs the complete iOS test scheme, retaining result bundles. Existing catalog-specific CI remains. | Verify the workflow runs on the PR's exact head and passes; review any known research-only failures rather than masking them. |

Other graded-pricing fixes already in PR #23: unbound finish eligibility and manual retry; precise grader/grade/finish matching; stale vendor-data attribution; null, expired and never-priced quote handling; and historical graded value excluded from current totals.

## Required acceptance matrix

Run each test on a **physical supported iPhone**, using representative Pokémon and Magic cards where the game supports graded pricing. Preserve anonymized results, app build SHA and provider response timestamps.

- **Graded acquisition:** verified label, correct catalog printing, grade, qualifier, language, print run and finish; save once; observe pending state; resolve exact vendor listing; display source, timestamp and amount.
- **Identity blocked:** ambiguous finish, absent label evidence, mismatched set/number, unsupported grade or qualifier; no adjacent-grade/raw-price substitution; correct finish; manually retry and obtain an exact quote.
- **Coverage:** card not tracked, no graded listings, grade not tracked, bounded search incomplete, transport timeout, absent vendor credentials and temporary Keychain denial; each message names the actual limitation and offers only a useful action.
- **Quote lifecycle:** current price, vendor timestamp older than 24 hours, current null quote, expired sale, never priced and later new sale; no stale/last-known amount counted as current portfolio value.
- **Marketplace trust:** graded Price Check, collection and movement screens never imply the underlying ungraded TCGplayer listing verifies the slab quote; ordinary raw-card links still work.
- **Ownership and history:** certified duplicate scan is a no-op; certless copies, conversion, correction, undo, price-key migration and activity history preserve quantity, identity and historical quote lineage.
- **Interruption:** foreground/background during OCR, lookup and binding; navigation away while write completes; CloudKit merge during refresh; account/storage-generation switch; cancellation and replay do not duplicate writes or price observations.
- **Exceptional storage:** one failed price-snapshot read recovers without a new save; three failures preserve the last snapshot and show Retry; a successful retry clears the warning and updates the value.

The eight-second post-save slab-conversion offer should be observed in a continuous-scanning session before changing its duration or adding UI.

## Performance baseline and release targets

These are **targets**, not measurements or promises. Capture median and p95 for collections with approximately **100, 1,000 and 5,000** rows, including duplicates, graded holdings, Magic treatments and unpriced items.

| Interaction | Proposed target / observation |
| --- | --- |
| Return to scanner from another tab | Under 300 ms to responsiveness, excluding OS camera startup |
| Recognized card to visible saved acknowledgement | p95 under 1 second with a local catalog identity |
| Collection filter or sort | Visible update under 200 ms for ordinary collections |
| Warm Collection tab switch | No blank-state flash or unexpected loading screen |
| Collection scroll | Sustained 60 fps on a supported baseline device, no recurring frame stalls |
| Background refresh during scan | Scan, save and browse remain usable |
| Graded price | Distinguishable lookup, gate wait, durable bind and UI publication times; no unexplained post-lookup delay |

Use existing `PerformanceSignpost` intervals, including `gradedPriceBindingCommit`, and Instruments. Separate OCR, catalog resolution, provider request pacing, serialization, model-actor work and SwiftUI presentation. Measure cold/warm launch, camera activation, image cache hits/misses, collection fingerprinting, portfolio replay and background transitions. Record before/after distributions and quota/replay counts. Do **not** add incremental indexes, additional caches, new refresh machinery or a scanner concurrency rewrite without a demonstrated bottleneck.

## Merge gates and evidence record

1. **CI:** exact PR head SHA; Release app build passes; complete iOS scheme tests pass; existing catalog/publisher checks pass. Archive result bundles and note any environment-dependent test exclusions explicitly.
2. **Device:** signed build on a real iPhone; physical slab and raw-card comparisons; interrupted refresh; transient credential and snapshot failures; accessibility-size collection warning; camera background/foreground.
3. **Live provider:** exact graded market listings and current null/expired cases; verify credentials, quota and USD source timestamps; never treat an unverified listing as a cert-specific appraisal.
4. **Data integrity:** representative old local store migration, CloudKit sync, ownership ledger, price lineage, undo and portfolio exclusion of withdrawn prices.
5. **Release scope:** keep unfinished catalog/report features behind existing gates; do not merge until new changes have reviewed results. An unmeasured performance target is not a failed functional test, but it remains an explicitly open release-quality decision.

### Results to fill in before merge

| Evidence | Commit / device / run | Result |
| --- | --- | --- |
| Release build | Not yet recorded | Pending |
| Complete iOS test scheme | Not yet recorded | Pending |
| Existing catalog checks | Not yet recorded | Pending |
| Physical graded scan / pricing | Not yet recorded | Pending |
| Slow-refresh bind and replay | Not yet recorded | Pending |
| CloudKit and old-store migration | Not yet recorded | Pending |
| 100 / 1,000 / 5,000 row performance baseline | Not yet recorded | Pending |

The repository's CI can prove compilation and simulated behaviors; it cannot prove camera, live marketplace, signed Keychain, CloudKit or real-device frame pacing.
