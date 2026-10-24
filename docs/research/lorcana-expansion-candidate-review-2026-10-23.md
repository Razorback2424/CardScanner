# Lorcana expansion candidate review

**Date:** 2026-10-23. **Base:** `4cefbfa` plus the retained preparation-document
diff and this focused tooling/test change. **Status:** isolated candidate
validated; production keys, publication, activation and bundled catalog adoption
remain on owner-directed hold. Paid Apple membership is not needed for these
offline source and simulator checks. This is the evidence authority for the
builder's opt-in later-expansion policy, not a release approval.

## Local loader and Disney100 follow-up — 2026-10-23

**Current checkpoint:** the local packaging blocker is resolved in source and
Simulator acceptance. Keys, publication, remote activation and replacement of
the bundled production catalog remain on hold. The prior 1,440 candidate below
has been validated through the actual app resource-loader function; its bytes
and identities remain unchanged. The subsequent isolated candidate adds six
Disney100 cards, leaving **387** of the original discrepancy rows held.

### Bounded actual loader

`LorcanaCatalogRegistry.maximumManifestBytes` defines a shared **16 MiB** local
manifest budget for byte decoding and bundled market resources. The resource
loader reads at most budget + 1 before rejecting, instead of allocating an
arbitrarily large file before checking its size. Discovery and optional Browse
price resources retain their 8 MiB and 4 MiB bounds. The source SHA-256 binding,
schema/identity validation, record-count limits and transition rules remain
enforced.

`LorcanaDiscoveryCatalog.bundledMarket` calls `loadBundledMarket(from: .main)`.
Candidate acceptance builds an isolated resource bundle with the exact candidate
and matching discovery, then calls this **same loader**. It also exercises
`LorcanaCatalogRegistry(data:previous:)`. The earlier typed-manifest bypass and
expected oversize rejection were removed from the candidate tests.

The exact 11,364,404-byte, 1,440-addition candidate passed **five focused tests,
zero failures/skips**: actual bundle-resource loading/identity/ownership/CSV and
all 2,652 price mappings, plus input-boundary and source-binding tests. Boundary
coverage admits a valid manifest at the local limit and rejects one extra byte;
the resource tests reject oversize market/discovery inputs and mismatched hashes
before admission. `loader-1440.xcresult` retains this separate run.

Signed network delivery retains its existing **8 MiB payload / 12 MiB envelope**
budgets. No signing or remote transport policy was broadened. The local bundle
fix does not claim that this larger catalog is ready for a future signed remote
rollout. Device memory/startup timing, distribution archive and actual production
adoption remain separate acceptance work.

### Six held Disney100 cards resolved in isolation

[The manufacturer's announcement](https://www.disneylorcana.com/en-US/news/s2-announcement)
identifies six exclusive alternate-art cards with satin holographic foil and
printed copies of animator signatures. Retained publisher images and source
metadata match the exact titles/footers below; Mickey and Genie reference images
were independently inspected for the frame, printed signature and footer. These
are printed signature designs, not hand-signed autograph identities.

| Source ID suffix | Card | Printed footer | Exact product |
| --- | --- | --- | ---: |
| 676 | Mickey Mouse — Friendly Face | 18/P1 EN 2 | 516448 |
| 677 | Elsa — Gloves Off | 19/P1 EN 2 | 516452 |
| 678 | Genie — Powers Unleashed | 20/P1 EN 1 | 516454 |
| 679 | Stitch — Abomination | 21/P1 EN 1 | 516456 |
| 680 | Maleficent — Uninvited | 22/P1 EN 1 | 516459 |
| 681 | Maui — Demigod | 23/P1 EN 1 | 516460 |

The additional `--review-disney100` option is separate from the ordinary command
and later-set review option. It requires these six source IDs, exact titles,
printed markers/number/denominator, declared collector distribution, standard
layout, publisher image namespace and single Satin pattern. Group **23305**,
Promo rarity, exact product ID, Alternate Art title and Holofoil lane must agree.
Other promos, extra siblings, different patterns, non-foil lanes and wrong
market groups stay held. The stamp identity explicitly says **Disney100 printed
animator signature**; each artwork/printing gets its own durable UUID.

All 3,189 objects in the preceding candidate remain byte-equivalent as decoded
objects. The new isolated candidate contains **3,195 physical objects / 6,022
mappings**, adding 1,446 records / 2,658 mappings over the unchanged active
baseline. Size: **11,383,097 bytes**. SHA-256:
`c3c9f2f66c09e33696c231b07c52e1378f87abe7cbefe813ea41fdaaa9cf8579`.
Rebuilding with its retained UUID ledger reproduces identical output.

### Final verification and remaining work

- **Native:** 141 selected cases, **138 passed, zero failed, three skipped**;
  `xcodebuild` exit 0. The three existing live-opt-in tests skip deliberately;
  all three prepared-candidate tests and both loader tests execute and pass.
  Every new mapping replays through the real price adapter with seven retained
  product/price feeds. Foil-only records also reject Normal acquisition. The
  six Lorcana suites are the same focused selection as the prior checkpoint.
- **Python:** 23 passed, including Disney100 opt-in, identity/printed-signature
  preservation, deterministic UUID allocation, wrong distribution/source/product/
  rarity, unexpected siblings/lanes and wrong group rejection.
- SDK-format, Simulator/network and IOSurface diagnostics remain in the logs;
  no physical-device, warning-free or full-app certification is claimed.
- Active catalog, discovery and permanent UUID resources remain unchanged.
  No production key, hosting, rollout setting, publication, enrollment or upload
  was performed.

The complete original-row ledger now accounts for **1,446 validated isolated
candidate rows + 387 held = 1,833**. Held categories are 16 multiple-foil
distributions, ten oversized identities, 29 earlier artwork/special distributions,
15 market-only evidence cases, **213** promo/event identities, 103 numbered Quest
scenario records and one unnumbered Quest identity. The six resolved rows were
previously in the promo/event category. The twenty later-set holds are unchanged.

The 16 multi-pattern rows still require distinct booster/starter distribution
evidence and acquisition identities, rather than choosing an arbitrary generic
foil. The Discovery adapter's one-source-to-one-physical mapping also needs to
be reconciled before representing multiple physical distributions of one source
row (source inspection; no physical multi-treatment acceptance is claimed).
The unnumbered/size/stamp and incomplete inventory evidence requirements
from the earlier ledger remain open. Catalog discovery counts still do not prove
an exhaustive physical denominator.

New artifacts are under the existing external review root's
`LoaderAndDisney100/`: candidate/UUID ledger/acceptance receipt, source captures,
reference images, all-row/remaining-held ledgers, `review-summary.json`,
`final-regression.xcresult`, build/test logs and reproduction scripts. The parent
retains the original 1,440 candidate and `loader-1440.xcresult`.

## Earlier 1,440-candidate checkpoint — superseded where noted above

The first 970 additions pass native catalog transition/validation, exact footer
recognition, automatic acquisition validation, every supported finish/CSV key,
and representative collection add/Undo, disk reopen and repeated CSV import.
All 1,749 existing physical objects remain unchanged. No actual physical-card
camera accuracy, optical foil detection or exhaustive physical census is claimed.

The subsequent review adds 470 more physical records to the isolated candidate:

| Category | Added records | Evidence and constraint |
| --- | ---: | --- |
| Original prepared ordinary additions | 970 | Exact source/printed set and number, official publisher image reference, one source footer, explicit Normal/Silver declaration, exact unique market join and finish lanes. |
| Attack of the Vine! ordinary run | 207 | Set 13 only, printed denominator 207, numbers 1–207. Does not broaden another set's denominator. |
| Separate Normal/Foil marketplace products | 19 | Four Winterspell and fifteen Wilds Unknown rows, each explicitly paired by reviewed product IDs. The six equivalent set-13 pairs are included in its 207 ordinary records. |
| Original later Epic/Enchanted/Iconic runs | 228 | Each of six sets has 18 Epic, 18 Enchanted and two Iconic matches with separate physical numbers/artwork and one declared foil pattern. |
| Single-pattern Whisper ordinary rows | 15 | Set 10 only, exactly None/FreeForm1; exact Holofoil lane for foil. Additional RainbowPillars patterns stay held. |
| Bruno Madrigal — Undetected Uncle | 1 | Set 9 only, physically printed 0/204, independently inspected in the official publisher image. No global zero-number policy. |
| Total additions | 1,440 | 2,652 new exact price mappings; all original 970 identities and mapping identities preserved. |

The complete isolated candidate has **3,189 physical objects and 6,016 price
mappings**, including existing unpriced objects. Its bytes/hash are:

- 11,364,404 bytes.
- SHA-256 `25e95e2a5d1a3bccfade2714a693516e679343715c02affc8b47abd8c510ff6d`.
- Existing bundled baseline hash remains
  `d456110e5202a309bd1ce86c8dc0ceeae41bd4368c005c7515c3df8e1a9019ac`.

| Set | Added isolated candidate records | Remaining discrepancy rows |
| --- | ---: | ---: |
| 9 — Fabled | 239 | 4 |
| 10 — Whispers in the Well | 238 | 4 |
| 11 — Winterspell | 242 | 1 |
| 12 — Wilds Unknown | 238 | 5 |
| 13 — Attack of the Vine! | 245 | 2 |
| 14 — Hyperia City | 238 | 4 |
| Earlier/special/Quest scopes | 0 | 373 |
| Total | 1,440 | 393 |

The counts disposition the retained 1,833 discovery-only rows, rather than
certifying that discovery contains every physical printing.

## Evidence and policy decisions

[Ravensburger's rarity announcement](https://www.disneylorcana.com/en-US/news/2025/08/2025-8-stunning-new-rarities)
describes distinct Epic artwork/foil treatment and Iconic artwork/foil/stamping.
These become separate numbered physical records, each with its own artwork UUID;
an ordinary card does not gain an invented Epic/Iconic finish. The manufacturer's
[Hyperia creative review](https://www.disneylorcana.com/en-US/news/2026/09/creative-spotlight-hyperia-city)
also distinguishes ordinary and Enchanted artwork.

For each later-set row, retained LorcanaJSON footer/image/foil declarations are
joined against the exact market set, title, Number and, for special rarities,
Rarity. The 12 retained product/price feeds bind groups 24348, 24414, 24500,
24617, 24666 and 24740. The review flag enforces these source group IDs.
The manufacturer [set-13 card gallery entry](https://cards.disneylorcana.com/en-US/?cardId=3173)
identifies a printed 207 denominator. The retained source/market observations
agree across that run. The official Bruno image visibly reads `0/204 • EN • 9`;
its reference/hash is retained externally. These are online source observations,
not photographs of independently owned specimens.

The [builder](../../scripts/build_lorcana_market_catalog.py) requires explicit
`--review-later-expansions`; normal commands and the bundled catalog remain
unchanged. It admits only set-specific numbered ranges and declared single
foil patterns. Fifteen set-10 None/FreeForm1 rows map Normal and Holofoil; the
source physical-finish declaration precedes market validation. Ordinary Silver
maps Cold Foil. Exact lane comparison rejects missing, duplicate and unexpected
lanes, including any extra product sibling outside the 25 reviewed split pairs.
Price amounts are never evidence of a finish or physical identity.

The 25 Normal/Foil product pairs keep one physical UUID and map each finish to
its explicit product ID. Foil product numbers/titles and independent source
Normal/foil declarations agree; arbitrary `(Foil)` siblings are not generally
accepted. Tests preserve rejection of third alternate-art siblings and duplicate
lanes. New physical evidence references name this review; the original active
physical records, artwork and UUID ledger remain untouched.

The October 16 LorcanaJSON source drift is still separate. Hydra's changed text
and image URLs were not applied to an existing physical record. This review uses
the bundled discovery snapshot so its physical/source binding stays stable.

## Every remaining held row has an evidence requirement

Fresh product metadata was retained for the other 15 market groups, giving 21
groups in total. All 1,833 original rows were reconciled into a complete review
CSV. No row was silently dropped. Of the 393 held rows, 304 have a declared
market product present in those captures; that association alone grants no
ownership authority.

| Held category | Rows | Required next evidence |
| --- | ---: | --- |
| Multiple foil distributions | 16 | Separate booster/starter distributions and their foil identities. Preserve the declared Silver/FreeForm1 plus RainbowPillars distinction. |
| Oversized physical identity | 10 | Verify size, artwork and distribution against ordinary-size siblings. Four are also unnumbered oversized Quest objects. |
| Earlier artwork/special distributions | 29 | Review exact artwork suffixes, qualified products, distribution and existing family membership. |
| Market-only physical evidence | 15 | Verify footer, size, stamp/artwork/distribution and finish independently of a listing. |
| Promo/event physical distribution | 219 | Identify exact stamp/event/year, marketed finish, artwork, size and released distribution. |
| Numbered Quest/scenario identities | 103 | Verify component role, actual physical size, release inventory and Normal-only distribution. |
| Unnumbered Quest identity | 1 | Vine Tendril has no printed number. The physical catalog currently requires a numbered footer; do not invent one. |
| Total | 393 | Explicitly held; complete-coverage gate remains open. |

The 20 later-set holds are 16 multi-pattern cards and four extra marketplace
records outside the reviewed main-set special runs: Sven 243 (set 11),
Mr. Incredible 243 (set 12), Christopher Robin 246 and Violet Parr 247 (set 13).
Those need distinct physical/distribution evidence. Counts or rarity labels
cannot extend a reviewed number range automatically.

## Verification and delivery boundary

The original 970 selection passed two native tests, zero failures/skips. The
expanded 1,440 selection independently passed the same two tests, zero failures/
skips. They are overlapping selections, not an accumulated test total.

The final focused selection also exercises all new price mappings through the
real Lorcana/TCGCSV adapter using the retained feeds and an isolated cache. It
checks exact USD amounts, product/finish identity and valid null-price absence;
this is captured-feed replay, not another fresh live provider census.
**Final native result:** 139 selected cases: **136 passed, zero failed, three
skipped**, `xcodebuild` exit 0. The three existing live-network cases skip
without their time-limited opt-ins. All three prepared-candidate tests actually
execute and pass. The selection includes Lorcana activation, discovery,
integration, ownership, physical catalog and pricing. Build and Simulator logs
retain SDK-format, QoS/network and IOSurface diagnostics; this is not a
warning-free or full-application certification.
Twenty Python builder/discovery tests pass, including review opt-in, denominator
scope, source group/marker/image/distribution, pattern multiplicity, special
rarity identity, split products, extra siblings and duplicate lanes. The default
generator still replays the existing bundled catalog byte-identically with an
unchanged active UUID ledger.

**Historical packaging blocker, resolved by the local-loader follow-up above:**
the first 970 candidate is 9,626,925 bytes and the expanded
candidate is 11,364,404 bytes, both above the current 8 MiB registry/bundled
market input bounds. Native acceptance decodes the isolated manifest and then
uses the real typed catalog/discovery/ownership contracts. It explicitly verifies
that the current byte-oriented registry loader rejects the oversize candidate.
That is not a packaged-app load pass. Bound/resource/performance work remains
necessary before adoption; no bound was relaxed during the production hold.

External evidence root: `CardScannerBuilds/ThreeGatePreparation-20261023/ExpansionReview/`
on the external SSD. It retains `candidate.json`, `uuid-ledger.json`,
`acceptance.json`, `join-report.json`, `all-discrepancy-dispositions.csv`,
`remaining-held-review.csv`, `held-review-summary.json`, the extra market captures,
native result bundles and logs. The parent retains the original 970 candidate,
its native result, the twelve later-set feeds and source drift report.

The three prepared-candidate native tests use an explicit hash-bound simulator
Documents workspace and skip when absent. All other tests remain independent of
those external inputs; no live network opt-in is introduced. No production key,
publication, bundle replacement, remote activation, Apple account enrollment,
submission or physical-camera/accessibility acceptance occurred.

For reproduction, set `REVIEW` to the external `ExpansionReview` directory,
`CAPTURE` to its parent's `later-set-market-sources`, and `SEED` to the repository's
`TradingCardScanner/LorcanaCatalogSeed` directory. Retain the review UUID ledger:

```sh
python3 scripts/build_lorcana_market_catalog.py \
  --discovery "$SEED/discovery.json" --sources "$CAPTURE" \
  --baseline "$SEED/market.json" --assignments "$REVIEW/uuid-ledger.json" \
  --output "$REVIEW/candidate.json" --report "$REVIEW/join-report.json" \
  --review-later-expansions
python3 -B -m unittest discover -s scripts/tests -p 'test_lorcana*.py' -v
```

The native fixture consists of the exact candidate, original baseline,
hash/count-bound `acceptance.json` and twelve retained `feeds/` files inside
the isolated Simulator app's `Documents/lorcana-expansion-acceptance/`. Build
for testing and select `LorcanaPricingTests/testPreparedExpansion…` or the six
Lorcana suites named above. Stage only in a disposable test collection; do not
replace the app's bundled resources to run these checks.
