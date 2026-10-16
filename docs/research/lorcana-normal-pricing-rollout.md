# Lorcana normal-workflow pricing rollout

**Enchanted extension — 2026-10-15:** the
[four-game review](catalog-variant-coverage-2026-10-15/README.md) adds all 132
original Enchanted printings across sets 1–8 using exact footers, reviewed
Lava/VerticalWave foiling and exact Holofoil market joins. The original 1,617
physical records are preserved. Current totals are 1,749 physical records,
1,748 mapped printings and 3,364 finish mappings. Earlier ordinary-only totals
below are dated evidence. Later Enchanted, Epic/Iconic and special distributions
remain outside the adopted policy; discovery and ownership are separate.

**Status:** normal app registration, expanded ordinary mappings and bounded
live/simulator acceptance passed — 2026-10-13, `8613a1d` plus local changes on
`feat/lorcana-implementation`.

**Later production follow-up:** the [production checkpoint](../release/lorcana-production-acceptance.md)
records actual iOS archives and development export, focused storage/compatibility
checks and the corrected Pokémon fixture regression. It supersedes the open
archive and Pokémon-failure statements in this earlier pricing snapshot.
CloudKit is deferred for current on-device 1.0; distribution, hardware, app-page
publication and source/artwork acceptance remain open.

The owner requested expansion from public online sources and pricing in normal
app workflows, with production rollout as the priority. This supersedes the
earlier restriction to the isolated Hades pricing workspace for this reviewed
ordinary-card scope. It does not claim physical camera/device, production signed
hosting, commercial publication/asset rights or App Store release certification.

## Reviewed ordinary scope

The bundled [market catalog](../../TradingCardScanner/LorcanaCatalogSeed/market.json)
contains **1,616 mapped printings / 3,232 Normal and Cold Foil mappings** across
the first eight expansions, plus the retained unpriced oversized Hades record.
The [UUID ledger](../../TradingCardScanner/LorcanaCatalogSeed/physical-id-assignments.json)
allocates app-owned IDs independently of marketplace IDs. Existing Hades UUIDs
remain unchanged. The generator reuses allocations and refuses disappearance,
identity or artwork changes under prior IDs; those need explicit withdrawal or
supersession review.

| Expansion | Newly mapped ordinary printings |
| --- | ---: |
| The First Chapter | 202, plus retained mapped Hades |
| Rise of the Floodborn | 202 |
| Into the Inklands | 200 |
| Ursula's Return | 204 |
| Shimmering Skies | 204 |
| Azurite Sea | 204 |
| Archazia's Island | 203 |
| The Reign of Jafar | 196 |

The exact join requires an English ordinary expansion record, numeric collector
1–204 with denominator 204, a single source candidate for its footer, the
reviewed ordinary normal/silver-foil declaration, exact normalized title and
Number in the correct marketplace group, no qualified market sibling, and one
Normal/Cold Foil lane each. Amounts do not establish finishes. Null market values
are allowed observations and remain unavailable through the existing adapter.
Fuzzy name matches, product-name lookup fallback, language-specific SKU or
Near Mint prices are not introduced.

Fifteen additional rows remain held: five source physical-candidate collisions
and ten missing/ambiguous exact joins or qualified siblings. Dalmatians with
artwork suffixes, promos, Enchanted/premium cards, Quest records, later sets and
other oversized cards are outside this promotion. They stay visible in discovery
and cannot acquire ordinary-card prices or write authority. Oversized Hades
retains the earlier separately reviewed explicit size choice and unpriced lane.

## Public source policy and receipts

[Disney's collector guide](https://disneyparksblog.com/products/getting-started-with-disney-lorcana-trading-card-game/)
describes ordinary 204-card expansions and foil/nonfoil versions before Fabled.
The source-discovery snapshot retains publisher artwork URLs and printed
English footers from [LorcanaJSON](https://lorcanajson.org/), with its original
source hashes/counts/completeness receipts. The mapping review cross-checks
those records against [TCGCSV product/price data](https://tcgcsv.com/docs) in
category 71, within each exact expansion group. Its
[public access policy](https://tcgcsv.com/faq) permits JSON requests; USD values
remain aggregate product/finish observations. This is source-policy review,
not a card-in-hand measurement or a claim that every image received manual
visual inspection. The retained physical specimen packets remain unapproved.

Fresh product/price snapshots for groups 23303, 23367, 23474, 23536, 23746, 24011
and 24258 were retrieved with an identifiable User-Agent and pacing. Today's
22937 snapshots were reused. Source bodies, receipt hashes and the complete
mapped/held decision report remain external at
`CodexBuilds/LorcanaNormalRollout-20261013/`. No source artwork binaries,
credentials, personal collection exports or private logs are committed.

## Normal app integration

`appDefaults()` now registers `LorcanaDiscoveryCatalog.bundledMarket`, with
pricing, raw collection writes and import authority from the existing
`LorcanaPriceAdapter`, `LorcanaCatalogAdapter`, `LorcanaVariantPolicy` and
`LorcanaImportAdapter`. Discovery and the 177 sealed-product inventory remain
available. Browse substitutes exact reviewed UUIDs for their source rows while
retaining held rows in the existing sets; it adds no parallel Lorcana UI.

Scanner/footer resolution, printing/finish choices, Price Check, Browse add,
post-save quotes, import validation and collection refresh use the same bound
registry and normal container authority. Source IDs cannot become ownership
keys. Price authority fingerprints withdraw changed/removed managed quotes
before publication and preserve manual values. Discovery/presentation changes
also change the composite generation, so cursors and in-flight choices cannot
survive an incompatible catalog or upcoming-release transition.

This is a bundled app release catalog. Remote signed delivery is not configured
by this change; existing signature/transition machinery remains available for
that separate rollout step. No credentials or production signing key are
invented, and no CloudKit schema changes are needed for these existing models.
Mixed-version/device sync acceptance still needs its release evidence.

## Verification

Twelve Python builder/discovery tests pass, including exact joins, independent
finish policy, stable UUID allocation, held collisions/qualified siblings,
wrong group/number rejection and explicit prior-identity protection. Resource
validation confirms the discovery SHA binding, unique physical/ledger UUIDs and
all 3,232 lanes. DebugRemoteLocal build-for-testing and the generic simulator
**ReleaseLocal build pass**; the latter excludes debug review routes. After the
shared refresh notification fix, Debug was rebuilt and ReleaseLocal was rebuilt
for arm64 successfully (`release-refresh-arm64-build.log`).

Finalized `xcresulttool` summaries confirm these overlapping scoped runs on
iPhone 17 Pro / iOS 26.5:

| Result bundle | Passed | Failed / skipped | Scope |
| --- | ---: | --- | --- |
| `normal-live-regression.xcresult` | 260 | 0 / 0 | Lorcana pricing/discovery/ownership/physical/activation, shared pricing and One Piece integration |
| `held-final-tests.xcresult` | 100 | 0 / 0 | Lorcana pricing/discovery and Browse, including the per-printing held detail flag |
| `unmapped-ui-final-tests.xcresult` | 66 | 0 / 0 | Browse replay after the rendered unavailable-pricing fix |
| `refresh-final-tests.xcresult` | 239 | 0 / 2 | Post-refresh-fix Browse/Lorcana/One Piece/shared pricing and 15 refresh lifecycle cases; live opt-in removed |

The post-refresh-fix bundle is finalized and verified: **239 passed, zero failed,
two expected live-opt-in skips** across 241 selected cases, with one internal QoS
warning. The live replay had already passed before its opt-in was removed; this
is not counted as a new live-provider run. Xcode finalized the bundle about ten
minutes after all selected cases finished.

The first two bundles report three internal QoS warnings each; the final Browse
bundle has none. The earlier Pokémon supplemental-pricing `unknownSet` failure
remains unresolved; these scoped green runs are not a full-app release baseline.

The expiring market-hash-bound live test used `appDefaults().bound(to:)`, the real
shared TCGCSV source and common collection refresh worker. It obtained Normal
and Cold Foil quotes for one ordinary printing in **each of eight sets**, saved
eight foil rows and persisted eight effective price records. Sixteen observations
with exact source lanes, UUIDs, generation and original feed receipts are retained
in `normal-live-results.json`. The opt-in was removed after acceptance. Prices
are observations, not bundled constants. Deterministic normal-runtime scanner
acceptance separately proves footer → exact UUID → finish choice → collection save
without requiring networking in routine tests.

The normal iPhone Browse navigation route uses the ordinary app container, with
no synthetic catalog or pricing-review storage/banner. Inspected rendering shows
Ariel — On Human Legs, First Chapter `1/204 EN 1`, **$0.13 Normal / $0.75 Foil**,
explicit finish selection, one saved foil copy in the ordinary Collection and
the matching **$0.75** price. Refresh reports prices already current; relaunch
retains the owned count. Unsupported Fru Fru has no request/retry panel, displays
“Pricing unavailable for this printing” and the review reason, and disables Add.
The first rendered pass found and corrected the misleading retry panel and
game-level Add capability leaking into held details. No unrelated UI was added.

Relaunch on iPad exposed a shared refresh presentation defect: an empty automatic
queue could leave “Updating prices…” on screen after the controller was idle.
Queue ownership was unobserved and its idle-to-idle completion emitted no status
change. `activeRefresh` now publishes its lifecycle to the existing small observers.
A regression checks the terminal notification for an empty automatic pass with
unchanged idle status. Final phone/tablet rendering preserves their chosen finish,
quantity and quote and clears the startup indicator; explicit tablet refresh
returns “Prices already current.” This changes state notification, not provider
selection, freshness policy or queue behavior.

The iPad normal split-view pricing/add pass also completed. XcodeBuildMCP semantic
taps initially failed to advance its game row; native Device Hub controls resolved
that automation issue. Search opens the same Ariel UUID, displays both live lanes,
and the existing finish popover saves one **Normal** copy. Collection immediately
shows **$0.13**, one owned copy and the matching detail price, while the right pane
retains separate Normal/Foil observations. Relaunch preserves the normal copy,
its quote and the directory's one-owned count. Earlier synthetic phone/tablet rendering
evidence remains separate. No physical-device camera, spoken VoiceOver,
mixed-version CloudKit or App Store/archive acceptance is claimed.

Inspected screenshots are retained externally as `iphone/normal-mapped-price.jpg`,
`iphone/normal-collection.jpg`, `iphone/held-printing-final.jpg`,
`iphone/relaunch-final/ui-latest.png`, `ipad/normal-registration.jpg`,
`ipad/normal-mapped-price.jpg` and `ipad/normal-save-collection.jpg` under the
rollout artifact directory. `ipad/refresh-fixed-relaunch.jpg` retains the inspected
final idle indicator; final phone relaunch is under `iphone/refresh-fixed-final/`.
Public card artwork remains remote; no screenshots
or user collections are committed. There was no commit, push, archive or release.

A redundant iPad relaunch invocation omitted the prebuilt path and started the
script's default Debug build in `/tmp`; it exited 75 with an internal Xcode IDE
failure before installation. The corrected invocation reused the already tested
SSD binary. This incidental failed build is not included in the successful Debug
and ReleaseLocal verification above.

## Fastest remaining release path

### All-mapping acceptance continuation — 2026-10-14

The [production checkpoint](../release/lorcana-production-acceptance.md) records
fresh-feed acceptance for **all 3,232 enabled lanes / 1,616 printings**, with zero
unavailable quotes or identity mismatches. `LorcanaPricingTests` passes all 19
cases with live opt-in, including the existing normal eight-set and isolated
Hades workflows. Catalog/UUID replay is byte-identical, with 15 decisions still
held. This extends the earlier bounded live samples without expanding coverage.

`testLiveAllMappedPrintingPrices` reuses the existing runtime, bound quote service
and TCGCSV adapter with an ephemeral session and new cache directory. It checks
each exact product/finish, source, USD currency, mapping fingerprint, finite
nonnegative amount and current retrieval time. A valid null quote is counted as
unavailable, rather than failing identity or borrowing another finish. Feed data
can itself be approximately 24 hours old; retrieval time is not source market time.

To repeat live acceptance, use the existing dedicated-simulator opt-in procedure
in [the pricing review](lorcana-pricing-review.md): set `expiresAt` within two hours,
`marketCatalogSHA256` to the bundled `market.json` hash, and `catalogSHA256` to
the `pricing-review.json` hash for the Hades case. Run `LorcanaPricingTests`, retain
`lorcana-all-mapped-live-results.json`, `lorcana-normal-live-results.json` and
`lorcana-live-pricing-results.json`, plus the new `LorcanaAllMappedLive-*` feed directory outside version control,
then remove `lorcana-live-pricing-acceptance.json`. Resolve the current app data
container after the run; Xcode reinstallation may migrate its directory.
Without opt-in, 16 deterministic cases pass and all three live cases skip.

New evidence is in `CodexBuilds/LorcanaRolloutCloseout-20261014/` on the reconnected
SSD. Local App Store export confirms a missing distribution provisioning profile;
no signing assets were created and nothing was uploaded. Privacy/support pages
and URL configuration remain owner-deferred. Physical checks and source/artwork
authorization remain separate from the successful pricing matrix.

### Remaining candidate boundaries

Use this bundled catalog for the candidate; production signing/hosting for remote
catalog updates is a separate optional delivery project. Follow the later
production checkpoint for hardware camera/performance, publication/asset-rights,
live app-page and distribution/TestFlight acceptance. Development archive/export
now pass and the known Pokémon fixture regression is corrected. Mixed-client
CloudKit applies before enabling sync, which is unavailable in current 1.0. Keep the
unsupported printing classes held. Expand them through the same offline review
and UUID ledger when their identity/finish evidence is sufficient.
