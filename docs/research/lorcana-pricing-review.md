# Lorcana public-reference pricing review

**Status:** historical bounded source review and live local acceptance passed —
2026-10-13. The [normal pricing rollout](lorcana-normal-pricing-rollout.md) now
supersedes this isolated-only scope for ordinary mappings across eight sets.
Existing Hades UUIDs and mapping evidence are retained; the dated replay below
describes the earlier local checkpoint for [Slice 5](../plans/lorcana_code_implementation.md).

## Public reference review 2026-10-13

The owner explicitly requested use of existing/public online evidence rather
than supplying physical packets. This checkpoint reviews that evidence for a
small local pricing slice. It does not declare the retained 12 physical specimen
packets approved, claim two human reviewers or establish card-in-hand dimensions,
foil observations, production publication rights or whole-catalog completeness.

The bounded seed is
[`pricing-review.json`](../../TradingCardScanner/LorcanaCatalogSeed/pricing-review.json).
Its new app-owned UUIDs are independent of provider IDs and the synthetic UI
fixture UUIDs. Only the explicit DebugRemoteLocal `LorcanaPricingReview` route
loads it. At this earlier checkpoint ordinary discovery pricing was unchanged;
normal app registration now loads the expanded market catalog instead.

| Evidence | Reviewed conclusion |
| --- | --- |
| [Publisher Hades image](https://api.lorcana.ravensburger.com/images/en/set1/5_eb74bbe5d3dfea633d596496243d7972e930b81a.jpg), visually inspected in the browser | Original Alex Accorsi artwork; `5/204 · EN · 1`, upright layout, no visible special stamp. |
| [Publisher gift-set description](https://www.disneylorcana.com/en-US/product) and [package image](https://ravensburger.cloud/cms/gallery/s1-giftset.png), visually inspected | Hades occurs as playable foil and oversized foil; both sizes must remain in the footer candidate universe. |
| [Disney's collector guide](https://disneyparksblog.com/products/getting-started-with-disney-lorcana-trading-card-game/) | The standard First Chapter cards have nonfoil and foil versions. This supplies finish evidence independently of market columns. |
| [TCGCSV product feed](https://tcgcsv.com/tcgplayer/71/22937/products), retrieved with HTTP 200 | Category 71 / group 22937: product **485364**, exact title **Hades - King of Olympus**, Number **5/204**. Product **516775** separately names Oversized, also Number 5/204. Its image visibly marks an oversized card. |
| [TCGCSV price feed](https://tcgcsv.com/tcgplayer/71/22937/prices), retrieved with HTTP 200 | Ordinary product 485364 has separate `Normal` and `Cold Foil` lanes. They never price product 516775 or another physical UUID. |

The reviewed local universe contains standard and oversized English Hades for
this footer, based on these publisher/product references. The Enchanted Hades
market record has a different collector number and is outside this seed.
The standard record represents the same published playable design rather than
inventing separate ownership identities for a visually identical gift-set foil
and booster foil. No undocumented manufacturing/reprint distinctions are claimed.
Further contradictory observations must hold or supersede the affected record,
not silently mutate its UUID. Physical specimen verification remains separate.

| App-owned physical UUID | Finish | Market mapping |
| --- | --- | --- |
| `5c35671f-b9d5-42c5-b30f-4eb61a24115c` (standard) | `normal` | 71 / 22937 / **485364** / **Normal**, US/USD aggregate |
| Same standard UUID | `foil` | 71 / 22937 / **485364** / **Cold Foil**, US/USD aggregate |
| `64cde47d-47b8-4d05-ac65-05975c59ead4` (oversized) | `foil` | Deliberately withheld in this first pricing slice. Its separate marketplace product exists; exclusion is a mapping-scope decision, not a missing-product claim. |

## Provider access and observation scope

[TCGCSV's FAQ](https://tcgcsv.com/faq) explicitly permits fetching its cached
JSON and asks for an identifiable User-Agent. The existing shared transport
supplies that header, bounded requests, pacing and a daily cache. Its
[documentation](https://tcgcsv.com/docs) describes the product + subtype join
and USD market values; the [home page](https://tcgcsv.com/) excludes
condition-specific SKU observations. The local acceptance therefore uses USD
aggregate market prices, with no Near Mint, language-SKU, listing or sales-history
claim. Feed receipt time remains distinct from source update time.

This records permission for the requested public-feed acceptance, not a broader
redistribution/asset license or production provider contract. No credentials,
provider account or paid service were used. Artwork is referenced by public URL;
no source artwork binary is committed.

Capture receipts are external at `CodexBuilds/LorcanaLivePricing-20261013/`:

- Products: SHA-256 `02078dafdcb20eabff4488d66a9562ef576f1674a657b206278fea986824a211`;
  349,666 bytes, HTTP 200, received 2026-10-13 15:22:53 UTC.
- Prices: SHA-256 `21c40d21f9f616e08781a1d6144e201b66b496c195a05d1ed7b2e62e91061a59`;
  66,385 bytes, HTTP 200, same receipt time. These are source observations, not
  app-workflow acceptance by themselves.

## Acceptance replay

Use `TradingCardScanner-DebugRemoteLocal`, with launch arguments:

```text
-ui_debug_route LorcanaPricingReview -ui_debug_state size
```

The camera stays off; the known footer enters the existing scanner callback.
Printing/finish selection, Price Check, post-save pricing, Browse and Collection
refresh use the ordinary shared workflow. Storage/recovery/catalog cache are
isolated under `Application Support/LorcanaPricingReview/`, separate from the
synthetic review store and ordinary collection. The banner identifies public
reference review. `unknown` exercises incomplete recovery; `withdrawn` loads the
same physical identities without market mappings so persisted managed quotes
are withdrawn before publication. Relaunch with `size` restores the mappings.

`LorcanaPricingTests.testLivePublicReviewPricingWorkflow` is opt-in. A local
Documents file named `lorcana-live-pricing-acceptance.json` must contain an
`expiresAt` Unix timestamp within the next two hours and `catalogSHA256` matching
the bundled seed. Without it the test skips, so routine/offline tests cannot
contact the provider. Use an isolated simulator, install the built test host,
write the short-lived opt-in, and select that test with `xcodebuild`. Keep the
report/feed/store artifacts external and remove the opt-in after the run.

The live replay exercises exact Normal/Cold Foil retrieval, unmapped oversized,
Price Check without ownership writes, scanner save, Browse detail, collection
refresh, disk-backed relaunch/cache receipt reuse and mapping withdrawal without
ownership loss. Deterministic tests retain in-flight withdrawal and manual-value
preservation coverage.

## Verified live results — 2026-10-13

At base `8613a1d` on `feat/lorcana-implementation` plus local changes,
DebugRemoteLocal build-for-testing passes. Final `live-final.xcresult`, verified
with `xcresulttool`, has **86 tests, 86 passed, zero failures/skips**.
The selection covers pricing (including the live
test), ownership, physical registry and activation. The live test uses a fresh
transport/cache with real URLSession HTTP requests; its Normal and Cold Foil
quotes identify `tcgplayer:485364:Normal` and `tcgplayer:485364:Cold Foil`, share
the original feed receipt time, and carry the reviewed mapping fingerprint.
Observed amounts were **$0.19 Normal / $0.35 Cold Foil**. Amounts are observations,
not test constants or a freshness guarantee. Two internal QoS priority-inversion
warnings are recorded; this is not a full-suite or performance certification.

The separate `offline-opt-in-gate.xcresult` has one intentional skip, zero
failures and no warnings after removing the opt-in. No provider request is made
by that skipped path. Both final build/test receipt artifacts and the raw public
feed snapshots remain on the external SSD; no collection/store/log binary is
committed.

Rendered iPhone 17 Pro/iOS 26.5 acceptance confirms Price Check Normal shows
$0.19 with provider and retrieved time without creating a Normal ownership row;
scanner Foil save returns
$0.35, Collection and Browse show the live aggregate price with provenance,
withdrawal removes the quote while retaining the owned Foil copy, and restoring
the mappings plus the ordinary Collection refresh recovers the mapped price.
Oversized saves as its separate UUID and remains unpriced beside the mapped
ordinary card; both copies survive relaunch. The final collection total includes
only the mapped copy and explicitly excludes the unpriced copy. An iPad M4/iOS
26.5 pricing-choice capture was inspected, but its automation taps did not
advance the screen; no new tablet pricing-interaction pass is claimed. The
earlier synthetic phone/tablet UI acceptance retains its separate scope.

Evidence: `iphone/final-choice/`, `iphone/browse-live-prices.jpg`,
`iphone/price-check-provenance-final.jpg`,
`iphone/collection-withdrawn.jpg`, `iphone/collection-restored-final.jpg`,
`iphone/collection-after-price-check-final.jpg`, `ipad/choice/`,
`lorcana-live-pricing-final-results.json`, `final-seed-sha256.txt` and result
bundles under `CodexBuilds/LorcanaLivePricing-20261013/`. Expired receipt frames
are diagnostics; persistent Collection/Browse captures and semantic snapshots
establish the corresponding results.

The public-source local pricing gate is complete for these two ordinary lanes.
Broader mapping coverage, the retained physical specimen corpus, production
provider/publication rights, keys/activation, physical camera/device and spoken
VoiceOver, CloudKit/mixed-client and release gates remain open. No commit or
push was made.
