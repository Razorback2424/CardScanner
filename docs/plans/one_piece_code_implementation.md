# One Piece implementation and verification ledger

**Status:** implementation in progress; no One Piece production support enabled.
**Started:** 2026-10-03, worktree `one-piece-integration`, base `69c714f`.
**Scope:** the owner's full code-level plan, corrected by the source review.

**Systematic mapping repair — 2026-10-07:** shared exact-identifier title rules
repair 406 mappings across 39 sets, including 27 OP17 and 36 OP16 cards. All
2,367 resulting mappings pass fresh public vendor identity/finish/quote checks.
Six genuine finish disagreements stay held; physical IDs, finishes and previous
mappings are unchanged. Signed owner revision 2 and its new public review pin are
bundled; the old pin remains trusted for the baseline. See the updated
[audit](../audits/one-piece-op16-op17-pricing-gaps.md) and reusable publisher
preparation script. Production rollout, collection gates and storage are unchanged.

**OP16/OP17 pricing investigation — 2026-10-07:** the
[read-only audit](../audits/one-piece-op16-op17-pricing-gaps.md) identifies
37/27 held owner-catalog market mappings caused by vendor printed-number title
suffixes. Live public TCGCSV data has exact-finish candidate quotes for 36/27;
OP16-030 has a separate Normal/Foil disagreement. Existing mapped rows still
validate. OP16's reported display count of 36 versus 37 local missing mappings
requires installed-generation/cache evidence. No mapping or runtime changes
were made; Retry cannot repair these missing catalog joins.

**Sealed browse repair — 2026-10-07, base `1711b06` plus local changes:**
enabled One Piece runtimes, including the owner runtime, now expose `.sealed`.
Disabled and validation-only configurations remain disabled. JustTCG requests
use the documented `one-piece-card-game` mapping and existing English vendor
directories, pagination, caches, artwork and quotas. Unsupported requests are
rejected before cache/request access. Exact vendor product/variant identities
remain separate from physical raw-card identities; batch sealed repricing uses
the injected capabilities. Raw-card pricing and its fallback restrictions remain
covered by the focused regression suite.

Add/Undo follows the injected collection-write capability and the existing
CollectionStore/CloudKit gates; blocked writes show “Saving unavailable”. Typed
feedback distinguishes connectivity (Retry), catalog (Refresh Catalog), feature
availability and credential access. Failed directory retries preserve cached
content and omit empty vendor sections. No production write permission or signed
catalog rollout setting changed, and no persistence migration was introduced.

The 405-test focused suite and final 95-test targeted suite passed with zero
failures; these overlap. The final Debug simulator build passed. Recorded-provider
iPad UI evidence covers directory → pagination → detail → Add/Undo; live JustTCG
verification remains pending because the existing key is unavailable in the
simulator and host keychain. Exact sealed repricing is deterministic test evidence,
not a live-provider observation. Physical-device, CloudKit and release gates stay
open. Artifacts are external under `CodexBuilds/BrowseReliability-20261007*`.

**Camera acceptance preparation — 2026-10-06, clean `3fe972a`:** ordinary signed
Debug device build, signature/identity/seed checks and in-place installation
pass on iPhone 15 Pro Max / iOS 26.6.1. Launch is denied because the phone is
locked. The [device record](one_piece_device_review.md) retains the five build
warnings, external evidence location and pending observations. No application
code change, test rerun, physical scan or collection verification occurred.
The [bounded camera plan](one_piece_camera_acceptance_slice.md) remains the next
acceptance work after unlock and presentation of an exactly matched owner card.

**Existing-save reliability — 2026-10-06, `230a55f` plus local changes on
`merge/one-piece-integration`:** the owner prioritized existing saves and
explicitly deferred speculative supersession under KISS/YAGNI. The retained
registry has zero correction records and zero superseding printings. Migration
remains unimplemented; revisit it when a reviewed correction affects owned copies.

Five new disk-backed tests pass in `Focused-r3.xcresult`. They exercise the real
scanner writer's failed insert and increment, same-session/relaunch recovery,
an unrelated successful save, all three finish-correction entry points with
new/existing destinations (six combinations), and signed catalog withdrawal
failure through both streamed and requested activation. Retry conserves ownership
and acquisition lineage; manual/imported prices survive; failed withdrawal
publishes no new authority. Source artwork deliberately remains available for
undo. Debug-only instance hooks inject faults immediately before the final save;
normal persistence still calls `ModelContext.save()`. No production save defect
was reproduced and no production behavior fix was needed.

The affected twelve-class Debug simulator regression passes 380/380 cases with
no skips or failures, including all 80 One Piece and 96 scanner cases.
`Regression.xcresult` retains that separate run; its selection includes the
five new tests, so the two runs are not 385 distinct cases.
Debug builds through the passing test run. The generic `ReleaseLocal` simulator
build passes for arm64 and x86_64 in `ReleaseLocal.xcresult`; the arm64 executable
has no `beforeSaveForTesting`/`setBeforeSaveForTesting` symbols. All 149 checked
local links and `git diff --check` pass. No screenshots were needed.

The initial compile attempt referenced a private test-fixture property; the next
run had recovery-store initialization and artwork-retention expectation errors.
Those fixtures were corrected before the clean five-test run. Build products,
caches, logs, results and synthetic fixture directories are retained on the
external drive under `CodexBuilds/OnePieceSaveReliability-20261006/`. The tests
accept `ONE_PIECE_SAVE_FAILURE_ROOT` for externally hosted synthetic stores and
retain them until the runner exits instead of unlinking open SQLite files.

These injected pre-save failures do not establish crash recovery halfway through
a save across the production collection/local SQLite configurations. Full
storage/account, physical-device, provider, CloudKit and release gates remain
open. The next recommended acceptance slice is representative One Piece
physical-camera scan → printing/finish choice → save → relaunch, using the
existing local owner catalog and ordinary app identity.

**Variants/catalog edge-case pass — 2026-10-05, `f40e704` plus local changes:**
the [audit and evidence](../audits/one-piece-variants-catalog-edge-cases.md)
record fixes for external-SKU qualifier/numeric alias collisions, duplicate
market mappings, unanchored product membership, invalid product/finish metadata,
missing CSV finish, foreign-language price authority, lost primary-release order,
older multi-printing recovery choices and case-sensitive finish-lock identity.
All 44 core and 49 offline Python tests pass; the five affected app regressions
and broader 389-case app/corpus selection pass. After the final finish-lock
adjustment, all 204 affected cases pass (74 One Piece, 96 scanner, 34 variant).
These are separate passing selections. Permanent UUIDs, payload/key formats and the retained catalog's
eligibility statuses are unchanged. Held/special-printing review and operational
gates remain open. At that checkpoint supersession and failed-save evidence were
next; the 2026-10-06 reliability checkpoint above supersedes that priority.

**Integrated local acceptance slice — 2026-10-05, `f40e704` plus local changes:**
the new `OnePieceAcceptance` developer route exercises the verified full catalog
through the actual scanner, printing/finish controls and collection writer. It
waits for the initial collection projection, uses separate persistent test and
recovery storage, and never starts the camera. Ordinary owner launches retain
their existing storage and identity. The
[release checklist](one_piece_release_acceptance.md#reproducible-simulator-acceptance-route)
documents launch/sample commands and the
[rendered checklist](../../references/one_piece_acceptance_success_checklist.md).

New integrated regressions cover ST11-003's original and later printing with the
same normal finish, permanent UUID/key separation, on-device disk-store reopening,
exact overdue-price refresh, offline Browse/details/add and full CSV import. The
mapped printing can quote; the later unmapped printing remains unpriced. Printing
skip/reload/retry is exercised against the retained full corpus.

Rendered relaunch exposed early recovery saves racing the initial backlog load.
Shared scanner recovery now serializes reloads, defers saves until the latest
merge completes and retains removals during loading. A gated regression injects
a new encounter during disk loading; another dismisses a row during reload.
Earlier records must survive and dismissed records must stay dismissed. Genuine
read/write failures remain visible and preserve existing bytes.

The nine-class simulator regression executed 316 cases: 315 passed and one
StoreRevisionMonitor fixture failed because it enabled monitoring before starting
Portfolio. The corrected fixture starts Portfolio and verifies its settled
baseline; all five monitor cases then passed in `Monitor-Final.xcresult`.
All 70 One Piece and 96 scanner cases passed in the broader run. This is a
selected regression plus an affected recheck, not a single clean 316-case run.
The final Debug simulator build and screenshot-helper syntax check passed.
The final acceptance-sample recheck passed after replacing the unsupported
OP99 series with uncataloged OP01-999; every route sample must enter the actual
full-catalog recognizer before lookup. `Acceptance-Samples.xcresult` records it.
Results remain on the external SSD under
`CardScannerBuild/OnePieceAcceptance-2026-10-05/FinalRegression.xcresult`.
Final rendered captures show the distinct ST11/ST16 choices, Karoo Normal and
Shanks Foil receipts without extra choice stages, OP01-999 recovery, and all four
owned rows after process relaunch. ST16 remains unpriced. Displayed app quotes
are not fresh-provider sampling evidence. Details/skip/retry controls and the
separate persistent test collection are recorded in the rendered checklist.
Hardware/provider/CloudKit/release gates stay open.

**Scanner product correction — 2026-10-05:** the owner requires the same choice
rule as Pokémon/Magic: one available verified printing resolves immediately;
multiple verified printings require a picker. The shared finish resolver still
asks only when multiple supported finishes remain. This supersedes the earlier
requirement for English confirmation and complete candidate-universe coverage
before resolving a sole verified printing. Provisional/conflicted rows remain
unavailable, and unknown numbers remain retryable. The tradeoff is that resolution
uses the available English catalog, without claiming complete worldwide printing
coverage or independently detected card language. The printing picker now uses
a headline, a full-width set subtitle, compact rounded buttons, and two columns
from three choices onward; Details retains artwork/footer evidence.

Verification at `534127f` plus local changes: the 97-case One Piece/variant run
and 56-case final recovery/scanner run both passed, covering 118 distinct cases.
Shiki OP17-047 from the bundled verified catalog saves without either picker;
one printing with multiple finishes still asks. Persisted sole-option choices
revalidate against the current exact printing and reject tampered evidence.
The [visual checklist](one_piece_printing_choice_visual_checklist.md) records
settled phone captures for long set names, accessibility3, 61 choices and
unavailable artwork, plus Details, skip and final-candidate interaction checks.

**Ordinary Xcode installation — 2026-10-05:** the owner rebuilt before the
custom-configured app's first launch, exposing the saved-preference dependency.
The normal project now copies the existing signed corpus and public pin into
the app. Local Debug registration prefers those verified bundled resources,
without custom Info.plist settings or a Documents copy. The ordinary device
build, in-place install and argument-free launch passed. App name, identity and
normal collection storage remain unchanged.

**Owner app correction — 2026-10-05:** restored the original app name and normal
collection paths after the owner rejected isolated review storage. One Piece
uses a verified owner-local signed catalog with collection writes enabled in
the existing app. Only a successfully verified public pin is retained for later
ordinary local builds. Device build and in-place installation passed; 32 focused
owner-catalog/storage tests executed with zero failures and one expected simulator
skip. See the [installed app record](one_piece_device_review.md). No collection
export or uninstall was performed; collection contents await phone confirmation.

**Release preparation — 2026-10-05, based on `534127f`:** the owner approved
English/verified/text-only/exact-price v1, the TCGCSV/TCGplayer and official-site
source roles, and confirmed there are no other users with older builds. The
[release acceptance checklist](one_piece_release_acceptance.md) records the
controlled-distribution policy and remaining rights/device/sync/signing gates.
Seed preparation now runs off the main actor. Recovery updates offer explicit
reload after scanning rather than resetting screens automatically; no-change
retries retain existing bindings. Production collection writes have an explicit
default-off flag, honored only in remote-authority builds. One Piece hosting
cache rules, signed immutable restoration and reproducible review sampling are
prepared. No production keys, seed, publication or device acceptance is claimed.

**Preparation verification:** app build passed; all 59 One Piece integration
tests passed. The subsequent final recovery/scanner/forward-compatibility/storage
selection executed 159 tests with zero failures and one expected simulator
data-protection skip. The core suite passed 40; the enhanced hosted-release CLI
test then passed with matching revision, wrong revision, wrong key and corrupt
envelope cases. Seven focused Python tests passed (restoration, sampling, pins),
six hosting cache rules validated, and relative documentation links/diff checks
passed. Final regression results are on the external SSD under
`CardScannerBuild/OnePieceReleasePrep-2026-10-05/ReleasePreparationRegression.xcresult`.
An intervening MCP export failed for internal disk space; only this task's two
generated bundles were moved to the SSD, and the final run used SSD results
directly. These are selected simulator/local checks, not full-suite/release gates.
Rendered `CatalogUnavailable` inspection confirmed the banner and all tabs;
Retry kept the Collection tab selected, was disabled while Scan was active, and
became available after returning to Collection. The simulator has no rear camera;
this verifies control state/navigation, not OCR or physical-camera behavior.
**Latest plan audit:** 2026-10-05, main checkout on
`merge/one-piece-integration`, initially based on `55dc1e4`, verified equal to
freshly fetched `origin/main` before edits. The integration, eleven finding fixes,
and subsequent remaining-audit cleanup are committed; earlier isolated-worktree/
uncommitted descriptions below are dated history. The cleanup removed the
accidentally committed `undefined/` source copies, corrected model spacing,
accepted CSV display names, moved withdrawal reads off the main thread,
separated requests across withdrawals, and added visible optional-catalog
recovery without relaunch. The release-preparation follow-up requires an explicit
reload so remote arrival cannot interrupt navigation or a scan.
See the [current review handoff](../audits/one-piece-integration-review-handoff.md).

**Remaining-audit verification:** initial focused iPhone 17 Pro / iOS 26.5 run
passed 94 tests; the final pricing/cache, runtime, scanner/recovery, activity
and CSV selection passed 257, zero failures/skips, with `TEST SUCCEEDED`.
Derived data and the final result/logs are under the external drive's
`CardScannerBuild/OnePieceAudit-2026-10-05/` directory (`FinalRegression.xcresult`).
A subsequent layout-only correction passed its final Xcode build and inspected
`CatalogUnavailable` captures, including Retry and Collection navigation.
The warning has its own layout space, preserving screen headers and all tabs.
This is simulator/source evidence; production, device/provider and sync gates
remain open. The same 37 legacy branches still fail the architecture gate.

The [catalog integration design](one_piece_catalog_integration_plan.md) remains
the authority for source roles, rights, physical distinctions, and production
acceptance. This ledger records code slices and evidence, not replacement
completeness or licensing claims. The baseline differs from the reviewed
`031e5fb` only by seven scanner tracing lines.

## Current source snapshot and immediate priority — 2026-10-05

This section, the current execution plan and delivery-status matrix supersede
older checkpoint wording about missing components. Historical test counts are
retained against their original runs; this source review does not rerun them.

| Area | Current position |
| --- | --- |
| Ordinary corpus | The checked-in registry has 2,692 canonical cards, 2,745 artwork/printing records, 2,490 verified, 224 provisional and 31 conflicted printings. The reviewed product manifest covers 58 groups; 60 product records are retained in the registry and recorded Browse evidence exposes 52 verified-target groups. All 2,692 canonical physical-coverage flags remain false. |
| Retained review | Combined observation files contain 10,198 records, including 1,961 base-market observations; 257 discrepancies remain retained. The ordinary capture/reconciliation pipeline and full ordinary adoption are implemented. Remaining work is physical special/reprint/revision evidence and scope/rights gaps, not rebuilding ordinary discovery. |
| Exact base pricing | 1,961 reviewed TCGCSV aggregate USD product/finish mappings and 412 held market decisions. Scanner save, Price Check, Browse detail/add and stored-printing collection refresh use exact UUID/finish joins with no borrowed-printing fallback. Unmapped physical records remain unpriced. |
| Activation and corrections | `CollectionAuthorizedActivationSource` and `CardGameRuntimeContainer.bound(to:isCurrent:)` install collection authority and save managed-price withdrawal before exposing a generation. Exact finish correction, rejection, rebinding and retired-session guards have focused evidence. The 2026-10-06 checkpoint adds failed-save/retry evidence. Supersession is owner-deferred until a real correction requires it; full storage/device acceptance stays open. |
| Catalog adapters | Pokémon modern/promo/offline/cache/historical behavior and Magic Scryfall/child routing now live in game-owned catalog modules; central `CardCatalog` prepares/coalesces/validates generic outcomes and never caches a user's printing answer. Legacy Browse/import extraction, signed legacy runtime activation and temporary correction allowances remain open. |
| Shared signed mechanics | All three games use `SignedCatalogReleaseStore`; One Piece uses `SignedCatalogUpdateClient`. Pokémon/Magic transport and domain wire/trust contracts remain separate. A shared store does not imply completed signed runtime activation for legacy games. |
| Local kit and rollout | The recorded full ordinary/base-pricing debug kit contains all 2,745 records with an independent ephemeral review key. Its local bootstrap enables scan/Browse/write/pricing in isolated persistent storage; production configuration remains disabled with no endpoint/key pins or bundled production seed. |
| Latest recorded app checkpoint | Variants/catalog audit above: 389/389 selected app cases, followed by 204/204 affected cases after the final finish-lock fix (74 One Piece, 96 scanner, 34 variant). The retained eligible corpus passes scan/Browse/CSV consistency. All 44 core and 49 offline Python tests pass. Persistent ownership, exact pricing and recovery are covered by selected simulator evidence. Earlier acceptance and 192-case checkpoints remain historical. |

**Current priority — reconciled 2026-10-06:** Package 1's focused failed-save and
retry evidence is implemented in the checkpoint above. Explicit supersession
migration is deferred until reviewed data supplies a concrete owned correction.
The next recommended acceptance slice is physical-camera scan/save/relaunch for
the existing One Piece flow. Preserve permanent UUIDs, claims, history and manual
prices when authority is denied or withdrawn. Broader special-printing review,
Browse/import migration and production delivery remain full-plan work.

The read-only boundary script rerun for this documentation audit fails on eight
Pokémon/Magic labels, all in `BrowseCatalog.swift`. Its pattern checks selected
case labels, not every explicit game dependency or Lorcana case; do not weaken
the gate or claim complete architecture from its count. The
[Lorcana plan](lorcana_code_implementation.md) uses these shared seams under its
own data, identity and rollout gates. Production rights, physical-device/camera,
mixed-client CloudKit, keys/hosting and archive/release acceptance remain open.

## Latest full ordinary batch — 2026-10-04

Adopted 58 reviewed product groups/2,731 selected ordinary release/artwork rows:
2,692 canonical cards and 2,745 permanent printing records (2,490 verified,
224 provisional, 31 conflicted). All 817 earlier printing/artwork records,
794 canonical records and 19 product records remain unchanged. Combined source
observations: 8,237; retained capture metadata: 2,940; open discrepancies: 257.
Physical-universe completeness, app artwork rights and production sync remain
unapproved. Original-base market joins were subsequently reviewed below. Parallel/premium/event/promo reconciliation
is still full-plan work, including the retained PRB reprint artwork scope.

The complete batch is in `ReviewCorpus/english-stress`. Source review binds
exceptional retailer titles to exact path/number/manufacturer/title tuples;
changed/missing tuples fail replay. Labelled special treatments and the PRB01
row with no finish metadata are explicitly excluded from base finish evidence.
ST13's retained manufacturer statement supports foil only for its selected deck
rows. Missing retailer evidence remains held; no finish is inferred from rarity.

Allocation-free replay matches all five generated artifacts. Unsigned revision
13 validates against revision 12 as `protectedReview`; retained candidate SHA-256
is `2d1bb42d19d14fa61c1cb6f0391487aa6932346fde39df0d8d47f47c55cee8b0`.
All 42 selected Python tests pass. The first core run reports 39 passes and one
new test assertion failure: EB04-061's base release is OP15–EB04, while OP17
contains a later artwork occurrence. Corrected that assertion; the affected test
now passes. No full-suite repeat was needed. The representative app run covered
43 integration tests: 41 passed initially; two updated assertions incorrectly
assumed all 60 products were visible in Browse. Browse correctly exposes 52
groups with verified printing targets; entirely held ST30/ST31 products remain
unowned. Corrected those assertions and both affected tests passed. The expanded
scan/choice/finish/save matrix covers ST13, OP17, EB03/EB04 and PRB01/PRB02.
Result bundles are `test_sim_2026-10-05T05-07-05-006Z_pid96208_d4b73a8c.xcresult`
and affected recheck `test_sim_2026-10-05T05-13-33-976Z_pid96208_1aeee76a.xcresult`
under the existing XcodeBuildMCP workspace result-bundle directory.

One signed local kit now exposes the full 2,745-record corpus, retained privately
on the SSD at `OnePieceSourceReview/2026-10-04/full-ordinary-local-review-kit`.
Its independent debug bootstrap uses revision 1 and an ephemeral key; this is
separate from the protected unsigned publisher successor at revision 13.
Verified signed envelope: 16,119,026 bytes, below the transport's 50,331,648-byte
bound; unsigned local payload: 12,089,158 bytes. Raw envelope SHA-256:
`963368df7315c3271d959b86f11b7f9a9a356232339a1d680bffec930f8a4424`.
No production key, publication, app artwork rights or shared-sync gate changed.
Rendered/device launch and cold activation/memory profiling remain open.

## Binding implementation decisions

### Base-case pricing priority — 2026-10-04

The owner requested testable base cases with pricing. TCGCSV is now the first
implemented One Piece product-level USD source; Scrydex is not a prerequisite
for this milestone. TCGCSV does not expose condition SKUs. The mapping condition
is `aggregate`, with exact product/group/title/printed-number and Normal/Foil
lane qualifiers. A reviewed market mapping changes pricing, never ownership.

- `Games/OnePiece/OnePiecePriceAdapter.swift`: validate the selected verified
  physical UUID, language, release, printed number and supported finish; consult
  only one exact USD mapping. No mapping returns `.unavailable(nil)`. Duplicate
  mappings/lanes and changed product metadata fail. Disable provider fallback.
  Coordinator-backed adapters read the current registry and recheck the mapping
  after HTTP; a withdrawn mapping cannot publish its in-flight response.
- The TCGCSV source coalesces group requests, spaces requests by 100 ms, caches
  successful product/price feeds for 24 hours on disk and backs off failures for
  15 minutes. Quotes preserve product/lane provenance and receipt time; no
  condition-specific amount or provider timestamp is invented.
- `OnePieceGameRuntime.swift` and `OnePieceCatalogBootstrap.swift`: enable pricing
  for the explicit local review launch and authoritative runtime. Validation-only
  registration retains no capabilities; normal production registration remains
  disabled by configuration and collection writes remain separately gated.
- `GamePriceAdapter.swift`, `PriceQuoteService.swift`, `PriceCheckCoordinator.swift`:
  retain existing Pokémon/Magic behavior, supply exact stored-printing refresh
  and prevent One Piece fallback to a name/number-based JustTCG search.
- `CardGameRuntime.swift`, `PriceRefreshController.swift`: install runtime pricing
  with collection authority and route supported raw UUID targets directly to the
  adapter before the existing legacy provider pass. Keep quote storage keys as
  game + permanent printing UUID + finish.
- `CatalogCardDetailView.swift`: display mapped prices in the existing finish
  rows, independently of offline detail loading; adding a card queues an exact
  mapped refresh without requiring JustTCG credentials.
- `ScannerViewModel.swift`: use the same exact adapter in the existing
  post-commit quote queue, retain storage-generation guards and update interested
  scan-session entries; paid-provider credentials are not required.
- `scripts/review_one_piece_base_market_mappings.py`: replay retained captures;
  select only original OP/ST/EB standard-art releases with unqualified unique
  titles, one supported finish and its exact observed price lane. Preserve all
  existing UUIDs; require explicit correction for changed mappings. Premium,
  stamp, promo, reprint, title disagreements and missing lanes stay unmapped.

Reviewed batch: 1,961 exact mappings, 412 held decisions, 48 retained price-group
responses. `base-market-observations.json`, `base-market-inventories.json`,
`base-market-review.json` and `base-market-captures.json` retain the crosswalk and
provenance. Combined observations are now 10,198; physical counts stay unchanged.
All 2,745 records build and independently verify in the fresh SSD review kit
`OnePieceSourceReview/2026-10-04/base-pricing-local-review-kit`.
Signed local envelope: 20,873,783 bytes, within the existing 48 MiB transport cap.
Unsigned publisher revision 14 validates against revision 13 as `protectedReview`;
SHA-256 `fd0b8ab39cc2dff136638287c569d1d81b7b21d8b245ce032bce3424c7a96cbf`.
The kit remains a separate ephemeral-key revision-one debug bootstrap.

Evidence: four market-review Python tests pass and two affected retained-corpus
core tests pass. The 59-test app checkpoint initially passed 56; three new pricing
fixtures wrongly combined complete discovery authority with an incomplete market
inventory. Corrected the fixture's completeness claim; those three plus the
affected Browse registration test pass in the four-test recheck. No full suite
was repeated. Result bundles: `test_sim_2026-10-05T05-38-19-674Z_pid96208_62f3f0ee.xcresult`
and `test_sim_2026-10-05T05-41-30-024Z_pid96208_184c6bdc.xcresult`.
The final scanner-save quote-queue test also passes, using no paid credentials:
`test_sim_2026-10-05T05-48-56-721Z_pid96208_5fef46aa.xcresult`.
Total selected app coverage is 61 distinct passing tests across that checkpoint
and affected rechecks; no camera image/device or complete regression claim.
Live simulator smoke: full kit launched, 52 One Piece Browse groups visible,
Shanks OP01-120 Romance Dawn Foil showed $8.16 from TCGCSV, Add Raw Copy produced
one owned copy and the collection total/row displayed $8.16. Existing unmapped
FILM RED Nami stayed unpriced. This is one provider/UI base case, not camera,
physical-device, all-mapping or release certification.

Base acceptance sequence: use that kit's `launch-arguments.json` in Debug or
DebugRemoteLocal; browse/search Shanks OP01-120, choose Romance Dawn Standard
artwork, confirm Foil, check the exact quote, add it and refresh collection prices.
Repeat with an unmapped promo/parallel: it must remain unavailable and retain its
own UUID. Camera/language evidence, loaded artwork, device performance and production/provider acceptance
remain open. Do not expand physical edge-case reconciliation before this
representative base-case check.

Cached-price withdrawal implementation — 2026-10-05: exact quotes now retain a
hash of the reviewed market mapping in `NormalizedPrice`, `PriceRecord` and
`ReferenceQuote`. `CollectionAuthorizedActivationSource.swift` saves withdrawals
of managed-provider quotes before publishing a new catalog snapshot or installing
collection correction authority. Manual/imported values are preserved. Invalidated
reference quotes and owned prices reject older receipts. `CardGameRuntime.bound`
loads the current coordinator snapshot before constructing consumers; the app
creates those consumers per authoritative storage container. Scanner, Browse,
normalization and pricing share that boundary. Older/conflicting revisions are
rejected, identical installed revisions permit a fresh subscription, and old
storage sessions cannot publish into the replacement session.

Feed caches are bound to the catalog generation. A changed generation or an older
unbound cache obtains a fresh product/price receipt once per requested group;
unchanged generations keep the 24-hour cache. Never rewrite a cached feed's
receipt timestamp merely to restore a displayed price. The consolidated simulator checkpoint
passed all 103 `OnePieceIntegrationTests` and `PricingTests` cases; no full app
regression was repeated. Result: `test_sim_2026-10-05T06-05-38-225Z_pid96208_8c4f62aa.xcresult`.
The 18-case same-container rebinding/quote-cache follow-up also passed:
`test_sim_2026-10-05T06-10-45-782Z_pid96208_e45a7ff4.xcresult`.
Relaunch exposed the older feed-cache receipt blocking an invalidated quote;
the generation-bound cache fix initially failed its new test because the protocol's
default async method bypassed the actor's synchronous implementation. Making the
actor method explicitly async fixed dispatch; the single affected recheck passed:
`test_sim_2026-10-05T06-20-09-576Z_pid96208_ad6e60c2.xcresult`.
The earlier three-case follow-up passed collection refresh and withdrawal; a retry
also hit internal-disk exhaustion while packaging test products. Two generated
bundles were retained on the SSD, freeing space; no source or user data was deleted.
Final full-kit simulator relaunch plus Refresh Prices restored the existing Shanks
copy to $8.16 and displayed that portfolio value. Full storage-transition/device
acceptance remains open.

**Immediate handoff:** test the existing full debug kit's representative starter
and booster flow before expanding reconciliation or architecture work. Verify
scan → explicit printing choice → finish → save → exact price; also Browse/add,
relaunch and CSV round-trip. An unmapped printing must save independently without
borrowing a quote. Keep all ordinary sets in this one kit and fix observed base
defects as a batch. Production enablement and the remaining physical edge cases
follow that acceptance; they are not prerequisites for this local test milestone.

- A canonical number is evidence within the supported English catalog. Per the
  2026-10-05 owner correction above, a sole verified printing resolves without
  language confirmation or complete candidate-universe coverage. Multiple
  verified printings still require a choice; held rows remain unavailable.
- Recognizers distinguish hard ambiguity from soft rejection. Ambiguity blocks
  other identities and fallback; Magic spatial rejection blocks historical
  fallback but does not override an independently valid primary identity.
- Scan requests pin immutable catalog semantics. Vocabulary and semantic
  generations are separate. Catalog lookups, candidate choices, and caches
  cannot mix generations; publication and stale-result policies are explicit.
- Resolved cards carry game-neutral physical identity, display metadata,
  variant evidence, provenance, retrieval time, and persistence eligibility.
  Existing Pokémon/Magic keys and semantics remain stable.
- One Piece Browse ownership requires exact printing IDs or reviewed aliases.
  Canonical-card completion and physical-printing completion are separate units.
- Camera suppression, physical encounters, recovery rows, and ownership keys
  are separate identities. Resolving one encounter cannot clear another copy.
- Collection keys do not depend on mutable variant counts. Unknown game IDs,
  finish IDs, namespaces, and snapshot versions are preserved without invoking
  another game's adapters. Blank/malformed input receives an explicit result.
- A minimum supported build is not a CloudKit enforcement mechanism. Until an
  enforceable mixed-client policy is verified, One Piece and unsupported-game
  creation must not enter the shared synced model through scanning, Browse,
  CSV, manual entry, or recovery. Existing unknown synced rows remain readable.
- Pricing capability applies to every quote, refresh, fallback, Browse,
  correction, background, and graded path. Missing capability means no provider
  requests and no fabricated provider observations. One Piece exact base pricing
  is implemented for the explicit local review; unmapped printings remain
  unavailable and production provider/access/rights acceptance remains open.
- Product appearances are a separate many-to-many relation. Permanent UUIDs,
  retained aliases, reviewed merges/splits, historical references, and mapping
  corrections have explicit validation and quote invalidation behavior.
- Shared release transport/storage preserves both existing wire contracts,
  signing bytes, paths, trust/schema policies, recovery, monotonicity, and event
  semantics. Rotation is verified with failure injection and concurrent updates.
- Optical comparison initially ranks choices only. DON!! remains a separately
  gated visual-recognition project, with no synthetic printed identifiers.

## Current execution plan — reconciled 2026-10-05

This section supersedes earlier execution priorities and dated “next” statements.
The full A–N/design acceptance scope remains intact. Code completion, reviewed
catalog coverage and production release approval are separate outcomes; none
substitutes for the others. This audit changed documentation only and reran no
builds or tests.

### Verified position

The source counts are recorded in the current snapshot above. Ordinary review
covers 2,731 selected rows across 58 OP/ST/EB/PRB groups, including combined
releases and selected product-scoped reprints. The earlier ordinary-only total
was 8,237 observations; the base-market review brings the combined total to
10,198 without changing physical UUIDs or statuses. Unsigned publisher revision
14 validates against revision 13 as protected review; the signed local debug kit
is a separate revision-one bootstrap, not the production baseline.

Recorded pipeline verification includes 42 selected Python passes, 39 initial
core passes plus the corrected affected test, and ordinary app coverage of 41
initial passes plus two corrected affected tests. Later pricing/publication and
catalog-extraction work culminated in the 192-test selected checkpoint above.
Do not sum overlapping selections or relabel these results as a new complete
suite. They establish scoped catalog/app behavior, not physical-camera, rights,
CloudKit or release readiness.

The small real-corpus milestone is implemented: local recognition injection,
explicit printing choice, finish, ownership, Browse and recovery/export have
evidence. Rendered Browse addition/relaunch has earlier evidence. Rendered real
scanner choice and physical-camera/device acceptance still need direct evidence.
Do not rebuild a small demo or repeat existing foundation work as the next slice.

### Why execution needs to change

- Product-by-product captures, hard-coded tuples, manual large JSON patches,
  per-batch signing and repeated app checkpoints have made coverage expansion
  expensive. The broad retained TCGCSV inventory already exists; reuse it for
  inventory and review triage, without promoting marketplace rows to owned IDs.
- Standard numbered rows are only part of physical coverage. More ordinary
  products alone cannot close parallels, stamps, original/revision distinctions
  or the named stress fixtures. Track these as explicit work, rather than
  interpreting growing verified counts as full-plan completion.
- Chronological notes still described a canonical-only corpus or an unbuilt
  compact picker. They are historical; current source and the status matrix win.
- Actual release dependencies remain unresolved: artwork/data rights, independent
  keys/seed/hosting, mixed-client sync policy and device evidence. Prepare concrete
  decisions alongside implementation instead of discovering them at the end.

### Ordered work packages and exit evidence

The bulk discovery/draft notes immediately below are historical implementation
checkpoints. Their temporary PRB-01 gap, deferred tests and no-successor wording
were superseded by the full ordinary adoption and base-pricing checkpoints at
the top of this ledger. The batching contract still applies to future coverage;
do not repeat the completed ordinary pass or regenerate its UUIDs.

**Bulk discovery implementation — 2026-10-04:**
`scripts/discover_one_piece_products.py` now retains all observed index pages and
ordinary series through the existing capture transport. The private
`bulk-product-discovery-v3.json` covers 18 official index pages, 58 series,
3,881 numbered artwork rows and 52 linked product pages. These counts include
reprints/parallel discovery and do not change the reviewed physical corpus or
prove complete deck contents. PRB-01's product page was not linked in the observed
index; its series and market-group evidence remain retained with that gap.
Combined OP14/OP15–EB04 releases and shared starter product pages must retain
their actual release grouping in reconciliation. New authored discovery tests
are registered in CI but deferred locally to the end-of-batch checkpoint.

**Whole-batch draft/capture — 2026-10-04:** discovery now accepts
`--draft-products` and writes an explicitly unadopted manifest plus an adjacent
`.scope.json` ledger. Private `bulk-product-discovery-v4.json` and
`bulk-draft-products-v2.json` retain 57 products/2,730 selected rows and preserve
all 17 existing product specifications. PRB-01 lacks an unambiguous retained
manufacturer release-date/page join and remains in the deferred-series ledger;
do not drop it from the final coverage requirement. Foreign unsuffixed numbered
rows in combined boosters remain release-specific selections; ambiguous parallel
aliases remain explicit held artwork review. Single product-scoped starter
reprint aliases are selected for evidence review, with no inferred finish.
The draft's retailer routes are constructed from retained category/group data:
captured response evidence must confirm them before corpus adoption.
`capture_one_piece_products.py --keep-going` collects HTTP availability/empty
retailer source gaps across the full batch. Integrity/origin/schema failures
remain fatal. Its `failedProducts` ledger and `batchCaptureComplete` flag must be
reviewed before reconciliation. Reuse capture IDs even when the retained series
HTML filename differs from the conventional `bandai-<prefix>.html` name.
The 57-product capture completed with no HTTP/empty-page gaps and 2,935 retained
source records. No revised corpus or successor candidate is claimed yet.
Authored draft/metadata fixtures remain deferred to the final check.
`reconcile_one_piece_launch_products.py --audit-only` now shares retained-source
validation with reconciliation, reports the entire batch without UUID allocation,
and writes only `product-source-audit.json` under a new `--output-dir`. A nonzero
exit means source review remains required, not a catalog candidate was activated.
The initial full audit found 22 source-ready products out of 57: remaining issues
include exact printed-number annotations in titles, separately named special
treatments, and genuinely missing standard-card finish evidence. Matching now
removes only a final annotation containing the exact expected printed number;
it retains SP/Manga/Pirate Foil/Reprint and other physical labels. Review those
listing paths and missing-evidence scopes together before allocation; do not
broaden title normalization to silently merge treatments. Record explicit
manufacturer finish statements only for their exact product/card scope.

**Owner-directed batching change — 2026-10-04:** implement all remaining ordinary
OP/ST/EB/PRB products as one coverage deliverable, then perform one consolidated
verification checkpoint. Do not stop after each small group of sets to run core/
app suites, prepare a signed kit or create another publisher revision. Network
captures may use bounded resumable chunks; these are internal progress, not
separate implementation milestones. Inline byte/hash/schema checks remain active.

For the next declared coverage batch, retain this execution contract; the
ordinary-product pass and revision-13/14 local-kit milestones are already done:

1. Run `scripts/discover_one_piece_products.py` with the private capture root,
   existing reviewed `products.json`, retained TCGCSV `68-groups.json`, initial
   `captures.json`, an output path and `--as-of 2026-10-04`. This retains every
   observed official index page and ordinary series list, joins product-page
   evidence and market-group discovery, and preserves combined release prefixes
   and reprint aliases without allocating physical identities. Discovery output
   is private review input, not a reviewed product manifest. Enumerate the entire
   remaining product inventory from this retained broad
   discovery and official English product/card-list evidence. Extend the reviewed
   `products.json` once across that inventory; record unavailable/presale groups
   and unsupported source structures explicitly instead of silently omitting them.
2. Capture all selected lists, product evidence, retailer pages and required
   artwork fingerprints through `capture_one_piece_products.py`. Reuse existing
   bytes. Resume bounded requests as needed; no app builds or per-set test runs.
3. Reconcile into one staged registry and discrepancy ledger. Retain every old
   UUID/alias. Records lacking exact finish/release/revision evidence remain held.
   Collect source discrepancies across products for review together; do not let
   the easiest subset redefine the batch's declared inventory. Retain discovery
   of parallels/premiums/events even where physical reconciliation remains open.
4. At the end of the ordinary-product implementation, run Python/core suites,
   allocation-free replay, whole-batch retention validation against the latest
   independently verified predecessor candidate (currently revision 14),
   and one representative app regression selection. Fix demonstrated failures
   and rerun only affected checks. Build one successor candidate and prepare one
   local review kit after this consolidated checkpoint.
5. Reconcile the remaining parallel/premium/event/promo and named stress
   distinctions in a second bulk pass, using the same consolidated verification
   rule. Full-plan acceptance, activation routing and production gates remain
   required; this changes batch size and checkpoint frequency, not scope.

| Priority | Existing work package | Remaining concrete exit evidence |
| --- | --- | --- |
| Complete locally | Package 4: integrated local base-case acceptance | Reproducible real-catalog scanner route and integrated durability/pricing/Browse/CSV/recovery tests are verified at the checkpoint above and rendered checklist. Physical-camera/device/provider acceptance remains open. |
| Focused evidence complete | Package 1: existing-save reliability | Failed insert/increment/correction/withdrawal and successful retry have disk-backed evidence in the 2026-10-06 checkpoint. Supersession remains deferred until a real reviewed correction affects owned copies. Review direct saves when affected ownership paths change; preserve UUIDs, claims, history and manual prices. Full storage/account/device acceptance stays separate. |
| 3 | Package 2: remaining physical coverage | Reuse the implemented manifest, capture/reconciliation/discrepancy pipeline and adopted ordinary corpus. Review held original/revision records, parallels/premiums/events/promos and named stress distinctions in declared batches. Fresh discovery may add ordinary releases; none may silently redefine the coverage denominator. |
| 4 | Package 3: remaining legacy adapter routing | Catalog extraction is implemented. Move Pokémon/Magic Browse and import/normalization behavior, complete signed legacy runtime snapshots and remove temporary bindings/correction allowances only after validated replacements exist. Preserve keys/caches/behavior; eight audited labels remain in Browse. Inspect dependencies beyond the regex. |
| 5 | Packages 4–5: measured delivery and release acceptance | Measure full-kit cold/warm activation, memory and candidate-list costs; provision the reviewed production seed/keys and rehearse all-game hosting/rollback. Record rights, device/accuracy/accessibility and enforceable mixed-client policy. Keep shared production writes disabled; map each full requirement to direct evidence and run warranted regression/archive checks on the stable candidate. |

Owner-controlled rights/key/hosting/sync decisions should be prepared during
packages 1–2; source reconciliation can continue while those decisions are pending.
No publication or credential provisioning is implied by this plan-only audit.
An isolated local review remains useful evidence but is not a substitute for the
specified production persistence and delivery requirements.

### Code/file-level implementation handoff

Follow the priority table above. The original file tables below specify package
contracts and include completed work; **new** in those dated tables does not
mean the named file is still missing. Read each later checkpoint before editing.
Preserve current public
callers while moving implementation, then remove obsolete bridges after the
affected regression checkpoint. Do not change persisted game/collection keys,
game-specific SwiftData columns, existing signed wire formats or Pokémon print-run keys.

Read the checkpoint before each package's file table: those tables describe the
intended final change, including work already implemented. Do not recreate the
Package 1 correction API, container-bound activation, Package 2 manifest/capture
pipeline, runtime registry, picker or recovery model. These are implemented;
the next deliverable is integrated local base-case acceptance with the existing
full kit. Remaining acceptance gaps are listed in the current priority/status
tables, not inferred from an older instruction to add a file.

#### Package 1: accurate evidence and exact collection correction

| File | Required change |
| --- | --- |
| `scripts/reconcile_one_piece_launch_products.py` | In `reconcile`, make language/release review descriptions conditional on whether `entries` contains retailer rows. For the two ST-10 OP-01 reprints, describe the official English deck list and explicitly note the missing retailer card listing. Retain the manufacturer all-holographic finish observation. |
| `OnePieceCatalogCore/ReviewCorpus/english-stress/registry.json` | Patch the two existing ST-10 OP01-016/OP01-025 review descriptions as an explicit reviewed data correction, then replay the corrected script without allocation. Keep all UUIDs, artwork fingerprints, aliases, statuses and supported finishes unchanged. Stage output externally, compare semantic JSON and validate the next candidate against revision 11. The regenerated `starter-booster-review.json` has decisions/captures, not these prose fields; do not invent new fields there. |
| `TradingCardScanner/Games/Core/GameCatalogAdapter.swift` | Add synchronous `validateVariantCorrection(printingID: String, variantID: String?) throws`. Its default implementation throws `CatalogLookupError.invalidPrintingChoice`; new modules must explicitly supply authority before accepting corrections. This method performs local validation only. |
| `TradingCardScanner/Games/OnePiece/OnePieceCatalogAdapter.swift` | Implement the method using `resolution(forPrintingID:)`: require a canonical lowercase UUID, an English verified printing and a non-nil variant ID present in that exact resolved card's `variantEvidence.catalogVariants`. Reject missing/withdrawn/provisional/conflicted printings and unsupported/cleared finishes. Do not infer a replacement printing or finish. |
| `TradingCardScanner/Services/CollectionStore.swift` | Extend the existing locked, weak-container `CollectionStoreSessionRegistry.Entry` with the installed `GameCatalogAdapterRegistry`, per-game activation revision and legacy-game allowance. Add `CollectionStore.configureCatalogAdapters(_:legacyCorrectionGames:for:)`, `installCatalogAdapter(_:revision:for:)` and a synchronous `requireSupportedVariantCorrection` helper. Run validation against the freshly fetched source row in each of the three mutation implementations; the collection-key overload continues delegating. Reject missing authority for non-legacy games before any ledger, row, activity or price mutation. |
| `TradingCardScanner/Games/Core/CardGameRuntime.swift`, `TradingCardScanner/Views/ContentView.swift`, `TradingCardScanner/App/TradingCardScannerApp.swift` | Configure authority for the actual runtime-backed app container. Derive temporary Pokémon/Magic compatibility from registered runtimes' existing legacy bindings. Keep a root activation listener while scanner UI is closed, install revisions monotonically, and verify that scanner/Browse consumers cannot act on a newer generation before collection authority accepts it. |
| `TradingCardScannerTests/OnePieceIntegrationTests.swift` | Keep the focused evidence and collection-correction cases in the existing test file. Cover exact supported finish, unsupported/nil finish, malformed UUID, provisional printing, missing adapter, activation with scanner UI closed, single/multi-claim rejection and existing Pokémon/Magic behavior. Snapshot quantity, keys, claims, ledger operations, activities and price lineage before rejection and prove they remain unchanged. |

#### Package 1 implementation checkpoint (2026-10-04)

The ST-10 registry rows and reconciler now describe the official English
manufacturer list without claiming absent retailer card listings. The treatment
description also stops attributing parallel exclusion to a retailer when no
card-level listing exists. The manufacturer all-holographic finish observation,
both permanent UUIDs, artwork fingerprints, source aliases, statuses and finish
assertions are unchanged. Replaying all 533 standard identities against the
retained 571-capture source set produced exactly matching decoded JSON values
for the registry, observations, inventories and review manifest after the two
registry descriptions were corrected.

The correction API, exact One Piece validation and per-container adapter/revision
store are implemented. All three correction mutation paths validate the fetched
row synchronously before ledger or row mutation. The root runtime configures this
authority and keeps an activation listener while scanner UI is closed. A focused
test covers evidence roles, missing adapter and single/multi-claim rejection
with unchanged rows, activities, inventory events and price keys. The 42-test
One Piece selection compiled and reported 41 passes plus one failure caused by
a test UUID that contained no letters to uppercase; after correcting that input
and adding the missing-adapter assertion, the affected test passed in isolation.
That initial run was not a clean combined 42-test result; later checkpoints,
including the full One Piece integration selection within the 192-test run,
supersede its regression gap without rewriting its original outcome.

At that 2026-10-04 checkpoint, activation ordering and withdrawal fixtures were
still open. The 2026-10-05 container-bound publication checkpoint supersedes that
status: a signed revision quarantines the existing printing while scanner UI is
absent, persists quote withdrawal before publication, hides that printing from
Browse, and rejects actual single-claim and multi-claim collection corrections.
The rejection snapshot compares row identity/quantity/finish, acquisition claims,
ledger operation IDs, inventory events, price identities and observation IDs;
none change after either attempted correction. Same-container rebinding accepts
the identical generation. A separate fixture rejects a conflicting identity at
the same revision, retains N+1 on stale N, retires the original container and
installs N+1 only into its replacement.

All three selected correction/publication tests passed in one focused checkpoint:
`test_sim_2026-10-05T12-24-13-145Z_pid18958_115e2d5a.xcresult`.
This adds direct mutation and storage-retirement evidence to the prior 103-case
One Piece/pricing checkpoint; it is not a full-suite or device/account-switch
claim. Explicit supersession migration and failed-save injection remain separate
acceptance cases; quarantining a printing does not migrate owned copies.
The audit at that checkpoint reported 13 legacy case labels; subsequent catalog
extraction reduced the current count to eight, all in Browse, under Package 3.

The one-time `rg` audit found CSV writes guarded by game and import
adapters, normalizer writes guarded by `permitsSyncedMetadataWrite` and
`validatePendingGameWrites`, detail edits guarded before direct saves, and
quantity/removal delegated to `CollectionStore`; treat this as source inspection,
not runtime proof for every caller. The corrected candidate has not been signed
or validated as a successor to protected publisher revision 11; this checkpoint
records source replay only.

Collection validation and mutation must stay on the owning `ModelContext` executor
without an intervening suspension. A provider fetch or an asynchronously prepared
approval is not sufficient authority at commit time. The locked session registry
returns immutable adapter snapshots; do not hold its lock during validation or
SwiftData work. The container's installed generation defines application
activation; do not treat a queued coordinator event as already installed.
The following publication contract is now implemented at the runtime source
boundary in
`Games/Core/CollectionAuthorizedActivationSource.swift`, a container-bound wrapper
of `GameCatalogActivationSource`. Both `currentSnapshot()` and streamed snapshots
must install collection authority before returning/yielding that snapshot. Use
the same wrapped sources for scanner, Browse, normalization and root observation;
do not rely on scheduling order among independent listeners. Retain raw sources
only for refresh delegation. Install on the container's owning executor and
validate matching game plus nonnegative revision before publication. Track the
accepted revision: ignore older updates, allow an already-installed identical
revision to reach a newly subscribing consumer, and reject a conflicting identity
at the same revision. Do not treat `installCatalogAdapter` returning false as
proof that a snapshot is safe; it currently also returns false for stale input.

Bind these wrappers after `CollectionStorageBootstrap` supplies the authoritative
session, before enabling writable scanner/Browse controls. Update runtime factory
callers in `TradingCardScannerApp.swift`/`ContentView.swift` accordingly; preserve
unbound constructors for read-only previews and existing tests. Rebind and cancel
old observers when the storage container changes. In `OnePieceIntegrationTests`,
activate revision N+1 with scanner hidden, withdraw the exact printing, assert
correction rejects without mutation, then open scanner/Browse and verify N+1.
Also deliver N and duplicate N+1, and test a consumer subscribing during activation.
No old container may acquire authority for the replacement session.
After package 3 registers Pokémon/Magic adapters, implement their correction
method with the existing legacy behavior and remove the temporary allowance.

The one-time source audit covered `CollectionStore.swift`, `CollectionCSV.swift`,
`CollectionCatalogNormalizer.swift`, `CollectionActivity.swift`, `CollectionView.swift`
and `CollectionCardDetailView.swift`, including direct context writes, quantity/
variant assignments and correction calls. Repeat it only when one of these
ownership paths changes. Keep local artwork and read-only display/export behavior
outside synced-ownership gates.

#### Package 2: one reproducible product/corpus pipeline

The manifest migration, capture driver, discrepancy ledger and full ordinary
adoption are implemented. The table and migration requirements below retain the
original contract; the dated 13-product/547-record checkpoints are historical.
Continue with remaining physical distinctions after local base acceptance.
Source-only batches require no iOS build unless app semantics change. The manifest
configures ingestion; it does
not replace the core release schema or become another app catalog.

| File | Required change |
| --- | --- |
| **new** `OnePieceCatalogCore/ReviewCorpus/english-stress/products.json` | Replace the script's `PRODUCTS`/`STANDARD_REPRINT_ALIASES` tables with a versioned reviewed manifest. Each product records stable `productID`, label/date, manufacturer series/list/product URLs, retailer group ID, expected printed-number inventory, selected standard artwork aliases, included reprints, excluded parallel aliases and optional explicit manufacturer finish specification. Seed existing entries without changing identities. |
| **new** `scripts/capture_one_piece_products.py` | Port the temporary product capture procedure into a bounded stdlib CLI: `--products`, `--capture-root`, `--offline`. Preserve the current capture record fields (`rawFile`, `sourceURL`, `payloadSHA256`, `byteCount`, `observedAt`, optional `id`). Follow observed retailer pagination until exhausted; retain every page and reject cycles/foreign origins. Use at most four image workers, global 150 ms request spacing, 40-second request timeout and 5 MiB response limit. Only permitted Bandai/CoreTCG HTTPS origins are accepted. |
| `scripts/reconcile_one_piece_launch_products.py` | Add required `--products`; read the manifest instead of fixed tuples. Preserve observation IDs for existing records; new reprints use product-qualified IDs. Match reviewed manufacturer artwork aliases to exact number/name/release and explicit finish observations. Keep duplicate finish assertions; normal/foil disagreement remains conflicted. Existing record changes require explicit review, not overwrite. `--allocate-new-printings` remains the only allocation path. |
| `scripts/build_one_piece_catalog.py`, `scripts/one_piece_tcgcsv_capture.py`, `scripts/reconcile_one_piece_tcgcsv_sources.py` | Reuse the existing dated category-68 snapshot and offline replay as the broad discovery inventory. Join it to review queues by normalized printed number, product and source alias; retain market observations separately. Do not copy product IDs into ownership, turn price lanes into quotes or claim source language/finish qualifiers absent from the export. |
| `OnePieceCatalogCore/ReviewCorpus/english-stress/registry.json`, observation/inventory JSON and **new** `discrepancies.json` | Store approved permanent identities plus all held distinctions. A discrepancy records source aliases, printed number/product, reason code, evidence references, status and required evidence to resolve it. Use reason codes `missing-finish`, `revision-unresolved`, `release-unresolved`, `artwork-unresolved`, `source-conflict`, `inventory-gap`, `rights-unresolved`. Preserve source artifacts privately; normalized app data contains no unauthorized image/rules-text copy. |
| **new** `scripts/tests/test_one_piece_product_pipeline.py`, existing normalizer/TCGCSV tests, `OnePieceCatalogCoreTests.swift`, `.github/workflows/one-piece-catalog.yml` | Add retained-byte fixtures for multi-page capture, offline replay, duplicate finishes, standard/reprint selection, explicit manufacturer finish, changed bytes and permanent UUID retention. Extend workflow path filters and validation to the new driver, manifest, reconciliation script and tests; the current workflow omits the launch-product reconciler. |

Capture reuse verifies both hash and byte count; a mismatch stops the batch.
Offline mode never fetches missing bytes. Write a newly completed capture and
its manifest through separate atomic renames, capture first. Two files cannot
share one atomic rename: interruption between them leaves an orphan that must
stop with an explicit repair result, never be silently adopted or overwritten.
Reusing a recorded capture preserves its source time. Name reprint captures by their
reviewed artwork alias, not printed number alone. Retain every explicit pagination
gap; scoped completeness is not provider-wide completeness.

Use `products.json` with `schemaVersion: 1` and `products: []`. Each product has
`productID`, `label`, `releaseDate`, `prefix`, `manufacturerCaptureID`,
`manufacturerListURL`, optional `manufacturerProductURL`, `retailerGroupID`,
`retailerStartURL`, `retailerCaptureFiles` and `cards`. Each card has
`printedNumber`, `artworkAlias`, `isReprint` and optional `excludedArtworkAliases`.
Use explicit inventories: ST-10 includes both OP-01 reprints as well as its own
17 numbered cards. Optional `manufacturerFinish` has `captureFile`, `sourceURL`,
`exactText`, `variantID` and `appliesToPrintedNumbers`. Seed ST-10's retained
statement and foil evidence; URLs/group IDs come from captures, never guesses.

Pass the parsed products into `reconcile` explicitly. Reject unknown schema
versions, duplicate product IDs/numbers within a product, absent selected aliases,
missing capture references and unknown finish IDs before generating outputs.
Preserve current observation IDs/order and the OP02-095 reviewed name exception;
new appearances of existing numbers require product-qualified observation IDs.
Keep current registry-change rejection and explicit allocation semantics.
Derive scope from the manifest. Correct the review output's inaccurate limitation
that all finish evidence is retailer metadata: explicit manufacturer evidence
also exists. Initial migration must reproduce registry, observations and
inventories as equal decoded JSON; allow only that declared review-description
change. A second allocation-free run must reproduce all four outputs exactly.

The capture driver uses a versioned User-Agent and exact permitted origins from
retained Bandai/CoreTCG URLs. Check pagination and redirects as well as initial
URLs. Reject absolute/traversal paths and symlink escapes in capture and replay.
Use one rate limiter across workers; HTTP failure or missing offline bytes stops
without marking a product complete. Tests mock transport; no live requests.

`discrepancies.json` has `schemaVersion: 1` and `discrepancies: []`; each entry
has stable `id`, `productID`, optional `printedNumber`, `sourceAliases`,
`reasonCode`, `evidenceReferences`, `status` (`open` or `resolved`) and
`requiredEvidence`. Resolved entries retain resolution references. Exhausted
pagination is scoped inventory evidence, not physical-universe completeness.

**Manifest migration checkpoint — 2026-10-04:** `products.json` now supplies all
13 current product specifications and 533 reviewed standard identities. The
reconciler requires `--products`, validates explicit inventory/artwork selections,
and retains existing observation keys plus permanent UUIDs. Existing keys are
stored as each card's `observationKey`; new cards default to a product-qualified
key. Manufacturer finish specs additionally retain `evidenceDetail` so migration
does not rewrite established evidence prose. The retained-source replay preserved
all 547 printing records and reproduced registry/observation/inventory JSON.
Review metadata changed only to a manifest-derived scope and an accurate finish
limitation. A second allocation-free run reproduced all four outputs exactly.
All 24 selected Python tests passed, including seven product-pipeline cases.
The workflow now includes the launch reconciler and its tests. No iOS/core build
was run because no Swift/schema behavior changed. Capture automation, discrepancy
ledger, wider coverage and the Package 1 activation checks remain open.

**Capture/discrepancy checkpoint — 2026-10-04:** the bounded stdlib capture driver
is implemented. It validates origins, paths, redirects, retained hashes/counts,
explicit retailer page/group progression and nonempty product-page structure.
Four image workers share a 150 ms network-request limiter; responses are limited
to 5 MiB with 40-second timeouts. Recorded responses are replayed without fetching,
and orphan/interrupted writes stop for explicit repair. CLI execution locks the
capture directory. Successful runs emit `captured-products.json` (the reconciler
input including observed pages) and `product-capture-review.json`; pagination
exhaustion never changes physical completeness. Replay of the retained 13-product,
533-artwork corpus used no network and left its source manifest unchanged.

The durable discrepancy ledger contains 103 open items: 92 revision distinctions,
eight source conflicts, one missing finish and the corpus-wide inventory/rights
gaps. Reconciliation appends new held-record items, preserves reviewed entries and
resolution references, and refuses a resolved item whose printing is still held.
It never resolves an item just because the record disappears from a new batch.
All five reconciler artifacts, including this ledger, matched retained replay.
All 32 selected Python tests passed. No iOS/core build or live-provider expansion
was performed. Next: expand the remaining ordinary OP/ST/EB/PRB batches with this
pipeline; close Package 1 activation ordering/withdrawal alongside the next app
checkpoint. Full physical coverage and production gates remain open.

**Ordinary-product expansion checkpoint — 2026-10-04:** added all 270 selected
standard identities for OP-04/OP-05/ST-11/ST-12. OP-04 has 119 verified records;
OP-05 has 118 verified plus provisional OP05-032 revision evidence. ST-11 has
five verified new-numbered cards and ten OP-02 reprints held for missing finish.
ST-12 has four verified and thirteen held for missing finish. Missing finishes
are provisional with no supported variants, rather than falsely classified as
source disagreement. The discrepancy ledger now retains 127 open entries.

The product manifest's optional `retailerEvidenceMissing` records exact reviewed
number gaps; newly appearing retailer evidence requires another review, not silent
promotion. Optional `excludedRetailerListingPaths` records exact product-group
paths for nonstandard treatments. OP-05's PSA Magazine Luffy and SP Enel rows
are excluded from base-art finish evidence; their source bytes remain retained.
Known played-condition lanes can supply explicitly listed normal/foil evidence,
with `sourceCondition` retained on those observations. They supply no market quote
or condition-independent pricing authority. Other unknown treatment/finish lanes
still stop reconciliation for review.

The unsigned revision-12 candidate validated against revision 11; all 547 earlier
printing records are unchanged. All five allocation-free replay artifacts match
the adopted corpus. All 40 core and 35 Python tests pass. One Piece integration
tests now exercise OP04-083, OP05-119, ST11-001 and ST12-003 through choice/finish/
collection and assert that held ST-11/ST-12 records cannot become Browse ownership
targets. All 43 One Piece integration tests passed, with no skips or failures,
using `TradingCardScanner`/`Debug` on iPhone 17 Pro Simulator. The result bundle is
`~/Library/Developer/XcodeBuildMCP/workspaces/TradingCardScannerMVP_fixed_v4-c63baff95376/result-bundles/test_sim_2026-10-05T02-02-30-807Z_pid84710_45412889.xcresult`.
The durable unsigned candidate is
`<external-ssd>/CodexBuilds/OnePieceSourceReview/2026-10-04/starter-booster-review/review-candidate-revision-12.json`.
No new signed local kit or rendered/device
acceptance is claimed. Next coverage remains later OP/ST/EB/PRB ordinary products,
then the remaining physical stress distinctions and delivery/activation gates.

Expand in two passes: remaining ordinary OP/ST/EB/PRB release groups first, then
their parallel/premium/event/promo distinctions and every named stress case in
the integration design. Generate proposed product inventories from retained
sources, review the manifest, then reconcile the whole batch. Dates, aliases,
excluded rows and known reprints are approved input, not developer guesses.
Unknown treatment names and new prefixes enter discovery/review; the activated
registry continues supplying OCR vocabulary without app-side set tables.

For each complete coverage pass: stage new outputs externally; allocate only approved new UUIDs;
compare old printing/artwork/alias identities; run core validation and exact
replay; build one candidate against the previous accepted candidate; inspect the
diff and discrepancy counts. Update the durable registry only after review.
Prepare a signed local kit once after the complete pass, not per product or
small group of products. The owner-directed batching rule above supersedes the
earlier four-product checkpoint cadence.
Keep `printingCoverageComplete` false until that canonical card's complete
physical universe has documented evidence; held records cannot create uniqueness.

#### Package 3: move existing behavior behind existing adapters

**Base-case handoff priority — 2026-10-05:** catalog extraction verification is
complete in the recorded 192-test selected checkpoint, and the
existing full ordinary/pricing kit is installed for local acceptance. Do not
start Browse/import extraction or another
physical-coverage batch before the owner tests representative scan, printing
choice, finish, save, relaunch and exact-price cases. Those packages remain part
of the full plan; they are not prerequisites for this local milestone.

**Pokémon catalog extraction — 2026-10-05:**
`Games/Pokemon/PokemonCatalogAdapter.swift` owns modern/promo lookup, signed
artwork enrichment and the captured-definition completion rule. Modern/promo
requests retain their captured definition through activation; historical requests
reject changed membership before and after lookup. Generation includes revision
and descriptor content. `PokemonCatalogSupport.swift` retains the offline factory,
checklist lookup, provider injection and resolved disk cache with unchanged keys.
`PokemonHistoricalCatalog.swift` retains historical provider request behavior.
`Games/Core/BoundedCache.swift` and `TCGdexCircuitBreaker.swift` retain shared
mechanics. Runtime registration supplies the adapter; each catalog consumer gets
its own mutable Pokémon lookup engine while retaining the existing source/cache
dependencies. `CardCatalog.swift` now owns generic preparation, coalescing and
outcome validation, plus typed compatibility forwards for the legacy print-run
flow. It has no game-specific lookup switch. Signed legacy activation and
Browse/import extraction remain open. The strict audit reports eight matching
labels, all in Browse; that count does not certify the full architecture boundary.
The consolidated checkpoint passed all 192 selected tests: full One Piece
integration, pricing and quote-cache suites; forward compatibility; Pokémon
activation/historical behavior; Magic routing; and eleven offline/fallback/cache/
artwork regressions. Result bundle:
`test_sim_2026-10-05T13-01-49-160Z_pid18958_cc372487.xcresult`.
No full-suite, camera/device or production claim. The new simulator build is
installed and launched with the unchanged full ordinary/base-pricing kit.
The relaunch displays the saved Shanks copy and portfolio at $8.16. This is
startup/cache display continuity; no new live quote or camera acceptance is
claimed. The owner can now run the base acceptance sequence above.

**Magic catalog extraction checkpoint — 2026-10-05:**
`Games/Magic/MagicCatalogAdapter.swift` owns the existing regular Scryfall lookup,
signed/live token and art-card child routing, validation-only parity reporting,
and returned child-set/layout checks. Its injected `ScryfallService` and optional
coordinator never call back into `CardCatalog`. `MagicGameRuntime` registers it;
the module-owned default factory preserves older `CardCatalog` initializers.
The central service no longer owns a Scryfall instance or switches on a Magic
lookup case. Pokémon helpers were still pending at this Magic-only checkpoint;
the subsequent Pokémon extraction above closes that catalog-routing work.

`GameCatalogAdapter.prepareLookupIdentifier` is implemented with a strict default.
Magic validates its legacy payload and pins an absent generation without changing
printed fields, display identity or suppression identity. One Piece/future games
still reject missing/stale generations. `CardCatalog` now coalesces adapter lookup
tasks under prepared identifiers and keeps a bounded 256-entry outcome cache.
It caches canonical candidate lookup, never a selected physical printing; incomplete
outcomes and failures remain retryable. Installation clears cached outcomes and
in-flight completion still rejects a changed generation. Cache hits retain the
original quote retrieval timestamp.

The Magic adapter currently retains the legacy provider-generation/coordinator
behavior (`magic-provider-v1`); it does **not** claim signed revision activation
has been migrated. Complete Magic activation snapshots with the remaining legacy
runtime extraction, and remove the temporary collection-correction allowance only
after its adapter supplies validated authority. Pokémon identifier preparation
and provider/cache extraction are now implemented; Browse and import modules
remain open.

All 55 selected tests passed in one checkpoint: Magic content-kind/routing,
forward compatibility, historical Pokémon request bounds, One Piece stale lookup
and independent printing choices. New mocked HTTP tests prove signed token/art
routing does not fetch `/sets`, ordinary cards keep their parent code, concurrent
requests share one fetch/receipt, wrong layouts reject without fallback, and retry
fetches again after failure. Result:
`test_sim_2026-10-05T12-37-17-792Z_pid18958_d68ce592.xcresult`.
The strict boundary audit remains red with 11 matching labels, down from 13;
regex counts are not proof that all legacy dependencies have been removed.
No full suite, provider/device or production gate is claimed.
The updated app was installed and relaunched with the unchanged full local kit;
the existing Shanks quote/portfolio remained $8.16 without another price request.
This confirms startup/cache display continuity, not camera or all-game acceptance.

| Current implementation | Destination and boundary |
| --- | --- |
| Catalog extraction — implemented | `Games/Pokemon/PokemonCatalogAdapter.swift`, `PokemonCatalogSupport.swift`, `PokemonHistoricalCatalog.swift` and `Games/Magic/MagicCatalogAdapter.swift` own provider/cache/offline/historical and child routing. `CardCatalog` retains generic preparation, bounded outcome caching/coalescing, validation and typed legacy forwards. Preserve this behavior; do not recreate the removed central lookup branch. |
| `BrowseCatalog.swift`: game branches in `loadSetDirectory`, `cards`, `search`, `details`; Pokémon checklist/secondary/artwork/bulk-price projection and Magic live/signed set/card handling | **new** `Games/Pokemon/PokemonBrowseAdapter.swift` and **new** `Games/Magic/MagicBrowseAdapter.swift`. Move provider-specific state/helpers into game-owned actors. Keep `CatalogCacheStore` and on-disk keys compatible. `BrowseCatalog` keeps game-neutral history, coalescing, cache coordination and activation rejection. Preserve signed/offline authority before live fallback and existing price freshness behavior. |
| `CollectionCatalogNormalizer.swift`: `ImportedCatalogResolver.resolvePokemon`, `resolveMagic`, Pokémon missing-artwork enrichment | **new** `Games/Pokemon/PokemonImportAdapter.swift` and **new** `Games/Magic/MagicImportAdapter.swift`. Move identity normalization and enrichment into `metadata(for:)`; keep request/result `identityKey` unchanged. Register adapters and remove the parallel legacy raw-card tasks. Unknown games return no enrichment. Preserve generation revalidation before writing patches. |
| `CollectionCatalogNormalizer.swift`: `resolveSealed`/JustTCG game mappings | Move this existing provider implementation to **new** `Games/Core/LegacySealedImportResolver.swift`. It retains only verified Pokémon/Magic provider mappings and metered-request sequencing. The normalizer invokes that resolver before raw-card adapter tasks; new numbered games do not gain sealed support implicitly. |
| `PokemonGameRuntime.swift`, `MagicGameRuntime.swift`, `Games/Core/CardGameRuntime.swift` | Register catalog/Browse/import adapters and activation snapshots in each runtime. Feed coordinator registries to those modules, not new central switch cases. Remove `legacyCatalogBindings` only after all current consumers have been replaced. Preserve existing default initializers with module-backed defaults so legacy tests exercise the same behavior. |

Migration order is catalog, Browse, then import/normalization. Move behavior
before simplifying it. Preserve captured modern definitions, historical membership
withdrawal, promo keys, Magic language/content-kind/layout checks, cooldowns,
price provenance and cancellation tokens. Do not route adapters back through
the same public service they are replacing; that would recurse or retain the
central game dependency. Keep `PendingPrintRunChoice`/`PokemonPrintRun` keys and
UI semantics intact. Remove obsolete game-specific central helper methods after
their callers use module-owned operations.

The implemented catalog extraction handles legacy nil-generation identifiers
with module-owned `prepareLookupIdentifier(_:)` on `GameCatalogAdapter`:
the default requires matching game/generation; Pokémon/Magic implementations
validate their existing legacy payloads and pin a nil-generation request to the
captured adapter generation without replacing its captured set definition.
`CardCatalog` prepares once at dispatch and uses that identity for coalescing,
cache keys and outcome validation. One Piece/future games retain strict rejection
of nil/stale generations; recovery rebases only through `identifierForRetry`.
Preserve the existing Pokémon rule that already-dispatched modern/promo requests
retain their captured definitions, while historical membership withdrawal still
invalidates lookup. Encode this completion policy in the Pokémon module rather
than a central game branch, and cover it with the existing historical/request
regressions before removing the legacy path.

Exit: `scripts/audit_game_boundaries.sh` passes, and a source review finds no new
game cases required in scanner/catalog/Browse/CSV/normalization/recovery/pricing
or collection identity when registering another numbered-game runtime. Inspect
explicit `if game ==` dispatch as well as the script's case-label matches.

#### Packages 4–5: product acceptance and signed production delivery

| File/artifact | Required change or recorded evidence |
| --- | --- |
| `Views/ScanSessionOverlays.swift`, `ScannerViewModel.swift`, `UnresolvedScanDetailView.swift`, `OnePieceIntegrationTests.swift`, `docs/plans/one_piece_printing_choice_visual_checklist.md` | Use the current compact picker with reviewed standard/reprint, award and held-record cases. Verify two copies of one number choose different UUIDs; skip persists an encounter; relaunch/retry asks again; details do not select; missing artwork/indistinguishable choices stay unavailable. Record rendered phone/tablet/large-text evidence and physical-device OCR separately. Change UI only for a demonstrated failure. |
| `Services/OnePieceCatalogBootstrap.swift`, `OnePieceCatalogCoordinator.swift`, `OnePieceCatalogRegistry.swift`, `OnePieceCatalogReleaseStore.swift` | Measure production-sized decode/signature/index construction and cold/offline activation. Remove duplicate seed verification only if profiling identifies it as material; reuse a verified immutable release rather than weaken checks. Retain dictionary number lookup, atomic two-slot recovery, monotonic activation and stale-generation rejection. |
| **new** `TradingCardScanner/OnePieceCatalogSeed/one-piece-catalog-release.json`, `TradingCardScanner.xcodeproj/project.pbxproj`, `Config/OnePieceCatalogProduction.xcconfig`, **new** `Config/OnePieceCatalogTrustedKeys.json` | Bundle a reviewed signed envelope under the exact filename requested by `bundledRuntime`. Add it to the app Resources phase so `Bundle.main.url(forResource:)` resolves it. Public keys in xcconfig/JSON must agree and differ from Pokémon/Magic keys. Private keys remain protected secrets. Debug ephemeral keys and revision 11 review candidates are not production releases; the first production baseline is explicitly signed at revision 1 with the same durable physical IDs. |
| `.github/workflows/one-piece-catalog.yml`, `scripts/restore_catalog_hosting_site.sh`, `.github/workflows/pokemon-catalog.yml`, `.github/workflows/magic-catalog.yml` | Preserve all three namespaces before any shared-site deploy. Retain existing positional restore arguments; append optional One Piece pointer/package/public-key-file arguments and teach that branch to use its publisher `verify` command. Each deployment fetches and verifies the other current pointers; only a confirmed HTTP 404 permits an absent initial namespace. Non-404 failure/tampering aborts. Use the existing `scanstash-catalog-production-hosting` concurrency group with `cancel-in-progress: false`. |
| `publisher/site/one-piece/v1/` (generated deployment artifact) | Immutable `releases/<revision>/release-envelope.json`, `manifest.json` and reviewed canonical candidate; `current.json` is the verified envelope itself, as expected by `OnePieceCatalogUpdateClient`, not a manifest or URL indirection. Restore/sign/verify each retained revision and compare bytes before changing the pointer. Rehearse on a staging tree; redeploying Pokémon or Magic must preserve these bytes. Restore last-known-good content through a newer monotonic revision, never lower the accepted revision or regenerate owned IDs. |
| **new** `docs/plans/one_piece_release_acceptance.md`, `CollectionStorageBootstrap.swift`, `ContentView.swift`, `CardGameRuntime.swift` | Record candidate hashes/revisions, source-use rights, rendered/device results, startup/memory/payload measurements, delivery rehearsal and every creation path. Keep `.collectionWrite` out of the shared production runtime until an enforceable mixed-client policy is approved and tested. Current unknown-game preservation on the minimum client does not prove older installed clients cannot receive new rows. |

Release inputs requiring owner/external evidence are explicit: permitted data,
image/display/recognition-artifact use; independent signing/public-key provisioning;
hosting approval; supported-client/sync enforcement; physical-device observations.
Record each as approved, blocked or unverified in the acceptance artifact with its
evidence. Developers must not choose a provider/license, invent a minimum-build
enforcement mechanism or enable shared writes to close the checklist. Finish
authorized code/staging work while those inputs are pending. Exact base pricing
already works in the isolated local kit; expanded mappings and production
provider/access/rights approval remain independent gates.

For One Piece restore verification, pass publisher `verify --input` the envelope,
`--trusted-keys` the dedicated JSON key map and `--reviewed-payload-sha256` the
manifest's payload hash. Revision 1 uses `--bootstrap-registry yes`; each later
revision uses `--previous` with the independently verified preceding envelope.
Check expected revision, envelope hash and candidate payload bytes as well as the
signature. Do not invoke the Pokémon/Magic `verify-release` CLI for One Piece.
Add a retained local hosting-tree test that restores each namespace in turn and
asserts the other two namespaces' pointer and immutable-release bytes are identical.

#### Concrete verification handoff

Run commands from this worktree. Set `task_build_root` to the available external
SSD build directory; use internal temporary storage only when none is available.

```sh
python3 -m unittest discover -s scripts/tests -p 'test_*one_piece*.py'
swift test --package-path OnePieceCatalogCore \
  --scratch-path "$task_build_root/OnePieceCatalogCore"
bash scripts/audit_game_boundaries.sh
git diff --check
```

For the collection/shared-code checkpoint, use `xcodebuild test` with project
`TradingCardScanner.xcodeproj`, scheme `TradingCardScanner`,
configuration `Debug`, an available iOS Simulator destination and
`-derivedDataPath "$task_build_root/OnePieceIntegration"`. Select
`OnePieceIntegrationTests`,
`CollectionActivityHistoryTests` and `CardGameForwardCompatibilityTests` for
package 1. After package 3, also select `ScanParserTests`,
`ScanSubjectSuppressionTests`, `UnresolvedScanStoreTests`, `BrowseFeatureTests`,
`CatalogNormalizationTests`, `CSVImportResumeTests`, `PokemonCatalogTests`,
`HistoricalCatalogRequestTests` and `SignedCatalogReleaseStoreTests`.
Use the existing XcodeBuildMCP test workflow where available; these are its exact
project/scheme/configuration and test-selection inputs, not a second mandatory run.

Data batches require publisher `build --previous` plus exact offline replay and
UUID/alias retention; signing uses existing `prepare_one_piece_local_review.py`
only at a milestone. Register any new test source in the test target according
to the project's existing file inclusion mechanism. Record commands, actual
results and artifact paths once in the ledger; never sum overlapping test counts.
Before final completion, map every original numbered requirement and named
fixture to source/artifact/behavior evidence in `one_piece_release_acceptance.md`.
Mark missing evidence open; provider/device/sync gates cannot be closed by a unit
test or this handoff document.

### Catalog batching rules

Keep canonical identity, artwork, physical printing, finish and market mapping
separate. Reuse app-owned UUIDs; never assign ownership from a vendor ID, rarity,
first search result or image similarity. Capture required artwork fingerprints
in bounded batches with caching; existing verification evidence remains required.
Do not repeatedly fetch unchanged sources or download images for optional ranking.
Review generated output as one batch instead of hand-assembling each product's
data patches; preserve the repository editing rules and inspect the actual diff.

Missing finish/release evidence and conflicting records stay retained and
unavailable for acquisition. A blanket Errata notice is a review queue, not proof
that every original is a new printing or permission to discard a distinction.
Reconcile actual physical text/artwork before promotion. Product appearances and
identical-art reprints need explicit review; an unsuffixed number or `_pN` alone
does not establish the physical release. Add representative reprint/stress tests
when semantics change; do not duplicate one test for every ordinary card.

Maintain separate dated measures for discovered inventory, reviewed physical
coverage, held records and exact market joins. The 7,408 marketplace discovery rows
are not a physical-printing denominator and cannot support a completion percentage.
The named stress cases and fresh OP/EB/PRB/ST/P discovery remain full-plan work.
Small review batches are acceptable for difficult distinctions; full coverage
must not be redefined around the easiest currently verified rows.

### Verification budget and scope control

For the next bulk coverage pass, the end-of-pass checkpoint above governs:
no Python/core/app suite runs or candidate revisions for individual sets or
small product groups. Continue collecting and reconciling the full inventory
before the consolidated check; byte/hash/origin/bounds checks still execute
inline because they define valid captured input.

- Documentation changes: links and `git diff --check`; no builds.
- Source/data-only changes: changed normalizer tests, core validation, exact
  replay, UUID/alias retention and previous-release classification. Reuse the
  publisher executable unless its code changed. Do not rebuild the iOS app for
  each ordinary product or prepare a new signed kit for every minor data edit.
- Run an app checkpoint when catalog semantics/UI/shared code change, at a
  substantial coverage milestone, or after a real failure. Include representative
  supported finishes, reprints and held records. Expand to affected Pokémon/Magic
  suites for shared routing changes, not for unrelated source additions.
- Render/device/performance checks occur at integrated milestones and after
  relevant changes; prior simulator results cannot close device or rights gates.

Keep the implemented shared game identity/runtime, recognition aggregation,
printing choice, versioned recovery and signed storage needed for Lorcana.
Lorcana expansion remains separately scoped while One Piece is the priority.
Preserve the implemented exact base-pricing flow and unavailable behavior for
unmapped printings; expanded/provider production activation still requires rights
and reviewed exact mappings. Optical ranking and DON!! retain
separate decisions and gates. Record deferred/conditional work explicitly; do
not mark it implemented or silently delete it from the full audit.

## Historical execution priorities after the KISS/YAGNI review

The notes below record earlier decisions and checkpoints. Their next-step wording
is superseded by the current execution plan above.

2026-10-03 owner clarification: Lorcana is a planned subsequent integration.
It is not part of the current One Piece implementation scope. Shared game
identity, recognizer aggregation, exact-printing outcomes, printing-choice UI,
versioned recovery and capability-based pricing therefore serve a concrete
second integration. Retain these boundaries and existing verified foundations.
The owner subsequently requested the first Lorcana slice on 2026-10-04; its
[recalibrated scope and 44-test checkpoint](lorcana_code_implementation.md) now
exist in this worktree. That separately scoped slice does not replace the current
full One Piece objective; the owner explicitly returned work to One Piece.

The architecture is on track: canonical number, physical printing and finish
are separate, and One Piece now exercises the shared runtime through local
catalog, Browse, import and recovery fixtures. The next milestone is **a usable
local slice backed by a small real, reviewed English stress corpus**. The current
synthetic physical records do not establish the physical candidate universe or prove that
a collector can distinguish its entries. The signed store, picker/recovery
contracts and configured bootstrap already exist; recreating those foundations
is not the next task.

Real discovery input is now retained for those three numbers: six dated Bandai/
Limitless captures normalize into 30 observations. The initial canonical-only
registry has since gained the first award identities described below. See the
[stress-source review inputs](../../OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).
This begins the corpus milestone; it does not complete physical reconciliation.

The supplied English catalog kit has now been adapted and run against retained
TCGCSV category-68 responses: 7,408 review rows in 87 groups, with one empty
presale inventory explicitly incomplete. Raw responses and CSV/JSON outputs are
external review artifacts; hashes, 31 scoped market observations and candidate
crosswalks are retained in the stress corpus. Seven privately inspected thumbnail
pairs establish illustration correspondence only; the eighth (Nami) is a placeholder.
No source product ID was promoted to physical ownership. Remaining release/footer,
finish, exact UUID allocation and coverage reconciliation remain the next work.
The source layer has nine passing Python checks and 32 core/publisher tests;
full offline replay is byte-identical. No app build was repeated for this source work.

A subsequent package-only checkpoint passes 34 core/publisher tests. Unverified
review printings can now retain an unresolved finish as an empty variant list;
verified printings still require a registered finish. Regeneration retains the
same UUIDs, unresolved candidates prevent automatic uniqueness, and verification
promotion remains protected review. This closes a schema pressure to invent
finishes, not the missing physical evidence or reviewed corpus gate.

The first real award reconciliation is now retained: the official 2022 Super
Pre-Release prize specification and independent grading-company physical photo
support one verified English P-001 winner UUID with a manufacturer-supported foil
finish. A separate participation UUID remains provisional with unresolved finish.
Five hashed captures provide six additional observations; no market mappings,
original-footer claims or app image URLs were added. Canonical coverage remains
incomplete, so explicit printing choice is still required. Publisher revisions
2/3 preserve the same UUIDs and evidence against the prior canonical-only baseline,
with zero automatic candidates. Two affected corpus tests and three selected app
cases pass after targeted corrections. This advances the real local slice without
completing stress-corpus, rights, device or sync acceptance.

Finish verification is now enforced rather than implied by a printing review.
Rules version 2 requires evidence for each verified supported variant, bound to
the canonical number, language and release; market/image-only evidence cannot
authorize it. The real winner review explicitly references the official silver
foil specification. All 38 core/publisher tests pass. Unsigned revisions 4/5
migrate the review contract and preserve both UUIDs; earlier candidates remain
historical inputs. Production remains disabled and the app checkpoint is recorded
as 43 passing selected cases (35 One Piece integration and eight signed-store
cases), with a successful terminal xcodebuild result. This is not a full app suite,
physical-device or production-release certification.

Use permitted source captures for OP01-120, ST01-007 and P-001 first, retaining
dated observations, permanent UUIDs, discrepancies and collector-readable
distinctions. Mark coverage incomplete where review cannot establish completeness.
Exercise actual printing choice, finish, two different copies of the same number,
offline Browse and relaunch recovery against that corpus. Acquisition may be
demonstrated in an explicitly isolated, non-synced development store; production
collection creation remains gated. Expand to the other stress cases only after
this flow is reviewable. Real source access/asset rights are required for the
corresponding use; test fixtures are not an entitlement.

Close the correctness and picker gaps below alongside this slice. Retain the
implemented generic identities, adapters, versioned recovery and signed storage
needed for Lorcana. Defer optional coordinator/crypto extraction, additional
provider abstractions and optical work. Finish necessary legacy routing before
claiming the full architecture criterion, but do not make every bridge migration
a prerequisite for the first usable One Piece demonstration.

This changes execution order, not the recorded full-plan completion criteria.
The checklist below remains open where incomplete. Work postponed past the
vertical milestone is not counted as completed or silently removed from scope.

## Current status by delivery slice

This is the 2026-10-05 source audit at `6b64abe`, not a new build or release
certification. Full checkboxes remain open where acceptance is incomplete.

| Slice | Present in the worktree | Remaining completion evidence/work |
| --- | --- | --- |
| A | Open string-backed game identity, single-string Codable, explicit CSV game preservation; live container policy, scoped history/backfill and inventory guards | Audit remaining direct saves; verify mixed-client policy |
| B | App-scoped runtime, registries, capability enumeration, container-bound activation and Pokémon/Magic catalog extraction | Legacy Browse/import routing, signed legacy runtime activation and temporary bindings/allowances remain; expanded lexical audit reports 37 existing branches across Browse and collection normalization |
| C | Generic identifiers, generation pinning, recognizer aggregation and suppression; selected cross-game/catalog regressions recorded | Real-card geometry/language and full warranted shared regression acceptance |
| D | Generic resolved card, compact Pokémon/Magic-style buttons, bounded grid, Details sheet; phone/tablet/large-text, footer, skip, missing-artwork and final-choice fixture evidence | Owner review, loaded artwork/real-corpus distinguishability and device/accessibility acceptance remain open |
| E | Versioned/opaque recovery, legacy decoding, persisted choices and current-catalog retry after relaunch | Real-corpus/device recovery and remaining encounter/physical-choice acceptance |
| F | Shared verified two-slot storage used by Pokémon/Magic/One Piece; bounded conditional transport used by One Piece | Pokémon/Magic transport remains separate; full contract parity, failure/recovery and concurrent-update acceptance remain required |
| G | Core/builder/validator/publisher; 58 ordinary groups, 2,745 permanent printings (2,490 verified), 10,198 combined observations and 1,961 exact base market mappings | 224 provisional/31 conflicted records, expanded parallel/premium/event/promo physical distinctions, rights and full stress-case acceptance |
| H | Signed store/coordinator/runtime, disabled configuration, bootstrap and optional signing workflow | Actual bundled seed/resource, dedicated provisioned keys, protected hosting delivery and operational rehearsal |
| I | Registry-derived English numbered parsing, ambiguity, local lookup, consistent payload validation and retryable incomplete-catalog recovery | Real-card geometry/language and real-corpus/device recovery evidence |
| J | Exact UUID/finish keys, local fixture/real-corpus collection flow, exact correction, container-bound withdrawal/revision/session guards and focused disk-backed failed-save/retry evidence | Supersession migration deferred until concrete reviewed corrections; full storage/device evidence, production creation policy and mixed-client CloudKit compatibility |
| K | Local Browse/search/details, product memberships, exact ownership/completion, raw UUID import and game-scoped activation refresh | Manual/alias import policy and real-corpus rendered UI/export acceptance |
| L | Exact TCGCSV base pricing, 1,961 reviewed mappings, Price Check/scanner-save/Browse/collection refresh, mapping fingerprints, persisted managed-quote withdrawal and generation-bound feed caches | Integrated mapped/unmapped base-case acceptance, expanded physical mappings, provider/device and production acceptance |
| M / N | Scope and gates documented | Optical ranking needs a measured benefit; DON!! is a separate visual project, not a numbered-launch prerequisite |

<a id="audit-findings-and-required-follow-up--2026-10-04"></a>

## Audit findings and required follow-up — reconciled 2026-10-05

1. **High — real physical corpus remains incomplete.**
   [`OnePieceProviderNormalizer`](../../OnePieceCatalogCore/Sources/OnePieceCatalogCore/ProviderModels.swift)
   normalizes supplied captures; it is not a complete Bandai/Limitless/Scrydex
   ingestion pipeline. Passing synthetic stress fixtures proves mechanics, not
   actual Shanks/Nami/Luffy releases, source pagination, completeness or rights.
   The award, retail and ordinary corpus now has dated capture/replay evidence;
   named premium/event/stamp/revision distinctions and complete physical universes
   remain incompletely reconciled. Counts in the current source snapshot supersede
   earlier canonical-only or two-UUID descriptions.
   Complete the remaining reviewed registry and discrepancy records before marking
   G or the corpus gate complete. Base-case exact TCGCSV pricing is now required
   by the owner's latest request; expanded physical mappings remain a later pass.

   A bounded [retained-HTML normalizer](../../scripts/normalize_one_piece_sources.py)
   now processes the initial Bandai/Limitless review captures. It preserves
   separate reprint appearances and source aliases without assigning printing IDs
   or finishes. The real discovery manifest, normalized observations and incomplete
   inventories were initially retained beside a canonical-only registry. The
   subsequent award, retail and ordinary reviews add durable physical UUIDs;
   base pricing adds 1,961 reviewed market joins. Physical completeness remains
   false for every canonical card. Scrydex
   ingestion/access and broader physical reconciliation remain open.

2. **Printing-choice mechanics corrected; real-corpus UX acceptance remains open.**
   Compact replacement is implemented in the current source; verification
   is recorded in the visual checklist. The original rejected presentation described here is retained
   as the reason for the change, not a claim that the new default still dumps metadata.
   [`PrintingChoiceBar`](../../TradingCardScanner/Views/ScanSessionOverlays.swift)
   uses compact short-label buttons, a bounded grid/large-text column, a 44-point
   dismiss target and shared live/recovery presentation. Both the unbounded grid
   and verbose metadata-list findings are superseded. The owner rejected the
   former concatenated release/treatment/distribution/footer/date presentation on
   2026-10-04; the full evidence now belongs in Details.
   The
   [`One Piece projection`](../../TradingCardScanner/Games/OnePiece/OnePieceCatalogAdapter.swift)
   now carries optional artwork identity and region/footer detail, preserving old
   saved-choice JSON. Keep this evidence in the model; it need not all appear in
   every row. Image-only collisions require a loaded distinct artwork, while
   indistinguishable entries remain unavailable. This is presentation protection,
   not proof that catalog labels establish a complete physical candidate universe.

   **Required compact design — owner clarification:** follow the existing
   Pokémon/Magic `VariantChoiceBar` format in the same source file: compact glass
   panel, card name/number in the header, relevant set/release at the trailing
   side, short option buttons, one horizontal row for up to three choices and a
   two-column grid beyond three. Use the existing option-button styling and
   ordinary 50-point button baseline; allow growth for large text. Bound scrolling
   for long printing histories rather than restoring an unbounded grid. Do not
   introduce a thumbnail-led metadata list as the default. Use a short
   collector-facing release/artwork/stamp label containing the essential
   distinction for that choice (for example Winner stamp or a distinguishing footer).
   Avoid repeating English, shared product text, region, copyright or dates when
   they do not separate choices. Put full provenance/footer/date in an explicit
   details affordance, with its own accessible control; opening details must not
   select a printing. Do not truncate away the only distinguishing evidence.
   Dynamic Type may wrap essential labels rather than shrink them. Keep all
   candidates reachable, retain skip/recovery and 44-point targets, and do not
   replace missing evidence with a guessed choice or global number default.
   Apply the same concise labels to recovery. The actual finish step already
   uses the shared `VariantChoiceBar`; retain that common format. Keep printing
   and finish resolution separate; artwork/stamp identities are still physical
   printings. Reuse the existing presentation patterns without adding a new
   picker framework or changing legacy Pokémon/Magic identities.

   First review compact two-choice, identical-art/footer and long-history states
   with realistic labels. Then verify phone/tablet, large text, image failure,
   details-versus-selection, final-candidate reachability and recovery. The
   [visual checklist](one_piece_printing_choice_visual_checklist.md) is explicitly
   unaccepted; prior fixture rendering and passing unit tests do not approve UX.

   The compact replacement has final phone/tablet/large-text fixture captures and
   native skip/details/final-candidate checks. Buttons use the shortest published
   distinction that separates candidates, falling back to full distinction text
   when shortening would collide. Long histories use a bounded two-column grid;
   accessibility sizes stack header metadata and use one scrollable column.
   Details retains artwork and full evidence, with an explicit selection action.
   Artwork-only choices remain disabled in the compact panel and require the
   distinct image to load in Details. Local dark material maintains camera-label
   contrast in light app appearance. No legacy finish picker or identity changed.

3. **Unsupported-row protection strengthened; direct-save audit remains open.**
   [`CollectionStore.validatePendingGameWrites`](../../TradingCardScanner/Services/CollectionStore.swift)
   now checks CollectedCard, blank-game legacy CollectionActivity and inventory-only
   changes at guarded commits. History resolves its live ownership row or preserves
   the game in raw/graded/sealed namespaced keys. Existing stores consult the current
   configured container policy, so an earlier writable fixture registry does not
   survive policy withdrawal. This is not a global ModelContext save hook or an
   atomic policy-change/save transaction.
   [`CollectionCatalogNormalizer`](../../TradingCardScanner/Services/CollectionCatalogNormalizer.swift)
   also consults that live policy during request discovery, legacy sealed-artwork
   repair and metadata application after provider suspension. Its two save paths
   validate pending game writes; sealed rekeying uses the same configured store.
   A captured writable normalizer registry cannot override a restricted container.
   [`CollectionCardDetailView`](../../TradingCardScanner/Views/CollectionCardDetailView.swift)
   artwork save/remove permits local overrides while preserving unsupported synced
   `userArtworkFilename`. A local empty override suppresses legacy fallback on
   removal and survives relaunch. Supported migration and metadata saves use the
   pending-write validator; unsupported artwork migration is skipped.

   Backfill resolves blank-game history against ownership, excludes unsupported
   cards/history from repair and uses a completed-watermark fast path scoped to
   writable cards. Targeted coverage includes repeated backfill, policy withdrawal,
   inventory-only denial and local artwork relaunch. Inventory all remaining
   direct saves and staged paths before claiming universal read-only behavior;
   mixed-client/CloudKit enforcement remains unverified. In particular, a caller
   saving ModelContext directly can still bypass this application-level guard.

   Verification — 2026-10-04: the initial simulator checkpoint executed 60 cases
   with one retained-object rollback assertion failure. A fresh-context assertion
   confirms persisted state was unchanged. Four affected One Piece integration
   cases exposed one fixture that passed a writable importer registry into an
   explicitly restricted container; the fixture now configures its isolated store.
   Targeted follow-ups pass both corrected cases, the other three integration
   cases and two artwork correction cases: 66 distinct passing cases across these
   runs, not a single combined green run or full-suite/device certification.

   Normalizer follow-up — 2026-10-04: a suspended exact One Piece metadata lookup
   resumes after container policy withdrawal without changing the owned row,
   metadata-check watermark, artwork, history or price observations. The isolated
   enrichment fixture now explicitly enables its container, rather than attempting
   to override container policy with an initializer. The batched simulator selection
   passes 84 cases: 36 One Piece integration, 18 normalization and 30 forward
   compatibility cases. This does not close the wider direct-save or CloudKit audit.

4. **Recovery/identifier gaps — deterministic follow-up implemented 2026-10-04.**
   [`ScannerViewModel.resolveUnresolved`](../../TradingCardScanner/Views/ScannerViewModel.swift)
   now routes retry-save without a memory-only commit through the same
   current-catalog evidence revalidation as retry-lookup. It does not carry a
   stored physical-printing hint into a new selection, and dismissed/read-only
   rows cannot be re-enqueued after revalidation. One Piece lookup, selection and
   retry use one payload validator, including language confirmation, unknown
   fields and agreement between printed number and suppression identity.
   Incomplete local lookup uses the existing retryable `noCatalogEntry` reason,
   with copy about missing confirmed printings, instead of OCR uncertainty.
   Focused simulator evidence below covers relaunch with a changed generation
   and a later verified release supplying a missing number. Real-corpus and
   physical-device recovery acceptance remain open.

5. **Browse activation metadata and live search corrected — 2026-10-04.**
   [`BrowseCatalog.installBrowseSnapshot`](../../TradingCardScanner/Services/BrowseCatalog.swift)
   now emits the activated game and its actual revision. Pokémon/Magic legacy
   publications also name their own game; raw provider-directory changes use a
   nil revision rather than borrowing another game's catalog revision. Global
   updates from older providers/test doubles remain supported.

   BrowseViewModel refreshes only affected game directories and invalidates active
   search rows/cursors through the existing debounce. Open-set events check both
   game and provider-set identity. Deliberate reset loads fetch the current set
   descriptor before paging, while old descriptors/cursors still fail when used
   directly against a changed generation. A withdrawn set clears old selectable
   rows. Cache/detail generation checks and exact product memberships remain.

   The batched Browse checkpoint passes 104 selected cases; four focused follow-ups
   pass after adding set-descriptor rebasing. They cover unchanged One Piece search
   refresh, correct revision metadata, same-ID cross-game isolation, scoped fetches,
   legacy global events and stale set/detail rejection. The final withdrawal guard
   has a successful simulator build-only check. Rendered
   open-set activation/withdrawal and physical-device acceptance remain open; these
   source and model checks do not certify every visible navigation state.

6. **Release blocker — preparation is not production delivery.**
   The [One Piece workflow](../../.github/workflows/one-piece-catalog.yml) builds,
   optionally signs/verifies and retains artifacts; it does not deploy a catalog.
   The [seed directory](../../TradingCardScanner/OnePieceCatalogSeed/README.md)
   contains no production JSON; configuration has no enabled endpoint/key pins.
   Before production activation, provision/review dedicated keys and a bundled
   signed seed,
   wire the actual resource, verify protected publication and bind publication
   to the verified live baseline with stale/concurrent-update refusal.

   The existing [shared hosting restore](../../scripts/restore_catalog_hosting_site.sh)
   and [Pokémon](../../.github/workflows/pokemon-catalog.yml)/
   [Magic](../../.github/workflows/magic-catalog.yml) deployment workflows restore
   only their two namespaces before deploying the shared site. Publishing One
   Piece there without updating **every** site deployment risks removing its
   namespace on a subsequent legacy-game deployment. Rehearse publication in each
   order and prove all immutable releases/current pointers survive. Uploaded
   workflow artifacts and declared environment names do not prove protection,
   live baseline freshness or deploy readiness.

7. **Performance gate — enabled startup work is synchronous and unmeasured.**
   [`OnePieceCatalogBootstrap`](../../TradingCardScanner/Services/OnePieceCatalogBootstrap.swift)
   decodes/verifies the seed during app runtime construction; release-store
   fallback construction verifies it again and registry/runtime projections are
   built before first UI. Measure cold launch and peak memory with the intended
   real signed release, not just the small fixtures; remove duplicated/blocking
   work only if the measurements justify it. Keep dictionary canonical-number
   lookup and measure candidate/choice costs separately from OCR.

8. **Full architecture acceptance remains open.**
   The read-only boundary audit now fails on eight legacy case labels, all in
   BrowseCatalog. Pokémon/Magic catalog extraction is implemented. Its regex
   checks selected switch
   labels, not all explicit game dispatch. CollectionCatalogNormalizer still
   launches legacy Pokémon/Magic resolvers, and legacy provider/coordinator
   bindings remain. Passing the script alone cannot establish “next game requires
   no central edits.” Before closing B, review catalog, CSV, normalization,
   recovery and scanner control flow against the actual adapter contracts and
   finish the required legacy routing. Avoid cosmetic regex workarounds.

9. **Exact collection finish correction implemented; remaining acceptance is explicit.**
   The existing collection-row overloads of
   [`CollectionStore.recordVariantCorrection`](../../TradingCardScanner/Services/CollectionStore.swift)
   consult the installed exact-printing adapter before any row/ledger mutation.
   One Piece rejects unsupported/nil finish, malformed UUID and
   withdrawn/provisional/conflicted printings. Recorded tests attempt actual
   single/multi-claim corrections after signed quarantine and preserve ownership,
   claims, inventory and price lineage. Container-bound activation orders that
   authority before consumers receive the new generation. Do not reimplement
   this fix; explicit supersession migration and failed-save injection remain
   acceptance work, as do physical-device/storage transitions and production sync.
   Pokémon/Magic retain their temporary legacy correction allowance until their
   runtime/authority migration is complete.

## Historical sequence and verification checkpoints

The current execution plan above governs remaining work. These dated checkpoints
are preserved as evidence, not as competing task lists.

2026-10-04 next starter/booster batch: added all 202 standard numbered rows from
OP-02 and ST-05–ST-09, including the fifteen-card scopes of ST-08 and ST-09.
Two OP-02 revision records remain provisional; 200 new printings are verified.
The corpus now retains 394 canonical cards, 405 printing records (306 verified,
91 provisional, eight conflicted) and 1,284 observations. All earlier 203 printing
records are unchanged. Offline replay is exact, protected publisher revision 10
validates against revision 9, and the expanded signed local review kit is prepared.
The validator now accepts fractional-second ISO-8601 source timestamps while
continuing to reject invalid timestamps. All 40 core and 40 One Piece integration
tests pass; injected-recognition base cases choose/save one card per new product
with exact printing UUIDs and supported finishes, without price observations.
Later starters/boosters and held revision distinctions remain unfinished. This
checkpoint establishes no new physical-camera, production, rights or sync readiness.

Historical checkpoint:

2026-10-04 remaining launch starters: added all seventeen standard numbered rows
from each of ST-02, ST-03 and ST-04, with 24 additional verified printing UUIDs.
The corpus now retains 192 canonical cards, 203 printing records (106 verified,
89 provisional, eight conflicted) and 678 observations. The new decks contribute
nine, eight and seven verified cards respectively. Twenty additional records
remain provisional for revision review; seven have incompatible retailer finish
listings, all retained rather than overwritten or promoted to dual-finish identity.
All 39 core tests pass, offline replay preserves the final artifacts, and protected
publisher revision 9 retains revision 8's identities. The signed local kit expands
to all four launch starters without production publication or asset/market joins.
All 40 One Piece integration cases pass. The standard base case now also chooses
and saves foil ST02-001, normal ST03-008 and normal ST04-005 with exact UUIDs and
no price observations. Next coverage targets are OP-02 and the later starter
products; held original/revision distinctions remain an explicit reconciliation
task. No new rendered/device, production or sync acceptance is claimed.

2026-10-04 starter/booster expansion: retained the complete standard-art numbered
scope of ST-01 (17) and OP-01 (121). Manufacturer product/card-list evidence and
exact English retailer finish listings enable 69 additional printing UUIDs:
ten starter cards and 59 booster cards. The corpus now contains 141 canonical
cards, 152 retained printing records (82 verified, 69 provisional, one conflicted)
and 518 observations. Source metadata and 138 render fingerprints are retained
privately; no app artwork URLs, market joins or prices were introduced. Errata
notices keep 68 standard records provisional pending original/revision physical
artwork/text review. Both conflicting finish listings for ST01-001 remain visible
to the publisher and excluded from acquisition. Starter Nami's non-foil finish
has retailer evidence, but its original/revision printing is still unresolved.
All 39 catalog-core tests pass. The offline reconciliation replay retains all
UUIDs, publisher revision 8 validates against revision 7, and an expanded signed
local kit is prepared. All 40 selected One Piece integration cases also pass,
including standard Karoo, starter Luffy and booster Shanks recognition, explicit
printing choice, expected finish and exact collection identity. The earlier
premium/winner recovery/export cases remain green. No physical-camera or new
rendered UI acceptance is claimed. Next: reconcile the held original/revision records and
extend the same evidence-backed coverage to the remaining starter/booster products.

2026-10-04 rendered base-flow review: the expanded signed local kit was launched
in the simulator. Browse search selected the FILM RED Nami, raw addition resolved
the manufacturer's sole foil finish, and an actual stop/relaunch retained the
release, finish and quantity one. The collection showed price not checked. The
review exposed internal product IDs in Browse and unsupported-pricing retrieval
and history claims on details; the adapter now projects readable product labels
and number prefixes, and details use a concise unavailable state for games without
pricing capability. Camera OCR and rendered scanner printing choice remain open.
The combined One Piece/Browse checkpoint passes all 102 selected tests with no
failures or skips. Reinstalling the built app preserved the review collection;
the refreshed launch shows Nami owned quantity one and the detail accessibility
tree exposes only “Pricing unavailable”, without retrieval/history claims.

2026-10-04 retail base expansion: reviewed all twelve manufacturer-listed FILM
RED retail printings from the official product/card list and explicit silver/texture
foil specification. The [review corpus](../../OnePieceCatalogCore/ReviewCorpus/english-stress/README.md)
now contains 14 canonical cards, 14 retained printing UUIDs (13 verified, one
provisional) and 103 observations. Coverage remains incomplete, requiring explicit
printing choice. The Nami retail scan/choice/foil/collection case passes; the
winner disk-reopen/CSV/Browse base case remains green. All 38 core tests and 39
selected app integration tests pass. Protected publisher revision 6 and unchanged
revision 7 replay retain UUIDs; an expanded signed local kit is prepared externally.
No production asset URLs, exact market joins or sync enablement were added.
Original starter Nami finish is still missing evidence; ordinary starter/booster
coverage and rendered scanner base-flow acceptance remain the next priorities.

2026-10-04 owner steering: prioritize the working base flow, then return to edge
cases and guards. The opt-in debug/local-only
[review launch](../../TradingCardScanner/OnePieceCatalogSeed/LOCAL_REVIEW.md) now
loads a signed real review catalog, enables isolated collection writes and keeps
its databases/recovery separate from the ordinary collection. It has no remote
catalog update or pricing adapter; release/entitled builds do not expose it.
The real P-001 winner base test recognizes the number, requires explicit choice,
resolves its sole foil finish, saves through the scanner and reopens the disk
stores with the same UUID/quantity. CSV export and offline Browse agree.
The batched checkpoint executes 68 cases: 67 passed, one storage case skipped,
zero failures. The new review-kit preparation tool completed candidate validation
and ephemeral-key signing on the external SSD. That earlier checkpoint did not
complete a rendered launch after the test runner shut down the simulator. The
later rendered review above closes Browse addition/process relaunch; the scanner
test still injects recognized text rather than proving physical-camera recognition.
This advances the local base milestone without closing wider corpus, production
delivery, exact correction, architecture or sync requirements. Next: exercise
the rendered scanner base flow and expand real ordinary-printing coverage before optional
foundation work or additional defensive edge cases.

The earlier five-step sequence is superseded by the current ordered work packages.
Prior checkpoint counts overlap and must not be summed into a whole-tree pass.
The current audit reran no builds/tests and establishes no new rendered, device,
provider, CloudKit or release evidence.

## Full delivery checklist

The unchecked A–N items represent full delivery/acceptance, not an assertion that
each component is absent. The current status matrix identifies implemented work.

**Historical presentation checkpoint — 2026-10-04:** source included optional printing
artwork/footer metadata, bounded live/recovery presentation and collision safety.
The existing `/private/tmp/one-piece-printing-presentation-followup.log` records
52 passing selected cases: 33 One Piece integration, three scanner printing-choice
cases and 16 unresolved-store cases. An earlier build failed in new test cleanup;
the corrected follow-up passed. This audit read the existing log; it did not run
builds/tests or create new rendered evidence. These tests establish old-choice
compatibility, footer projection and deterministic fixture behavior, not accepted
picker design. The owner's subsequent direction supersedes the verbose list:
match Pokémon/Magic's compact option-button format, which is now implemented with
recorded fixture rendering. D remains open for real-corpus/owner/device acceptance.

- [ ] A: open CardGame, registry descriptors/capabilities, unknown-game safety,
  lossless CSV/collection/activity/price identity and creation gates.
- [ ] B: runtime/adapter dependency injection for existing games; bootstrap,
  service lifecycle, capability-specific enumeration, and architecture audit.
- [ ] C: generic scan identity, stable normalized fields, generation binding,
  primary/secondary recognition aggregation, confirmation and latch regressions.
- [ ] D: game-neutral resolved card and physical-printing candidates/selection;
  preserve historical Pokémon and legacy print-run keys.
- [ ] E: generic versioned recovery snapshots, opaque future-version retention,
  encounter-scoped merging/clearing and restart-safe candidate choices.
- [ ] F: shared signed-release mechanics with historical fixtures, two-slot
  failure/recovery, concurrent activation and conditional-fetch verification.
- [ ] G: OnePieceCatalogCore, durable printing/artwork/alias registry, separate
  source observations/product memberships/market mappings, builder, validator,
  change classification, publisher and stress fixtures.
- [ ] H: independent One Piece signed seed, coordinator, runtime, keys, rollout
  config and protected publication workflow; production publication stays gated.
- [ ] I: registry-derived numbered OCR, geometry and language evidence, hard
  ambiguity, local canonical lookup and incomplete-catalog recovery.
- [ ] J: exact physical selection, finish resolution, stable collection keys,
  provenance and enforcement of the sync/creation boundary.
- [ ] K: local Browse/search/details, exact ownership and defined completion,
  import/export/normalization, manual correction and recovery.
- [ ] L: exact pricing integration seam, absence/capability behavior and mapping
  invalidation; provider activation only after the design's rights/access gate.
- [ ] M: measured optical candidate ranking behind its separate acceptance gate.
- [ ] N: separately scoped DON!! visual catalog/recognition project and fixtures.
- [ ] Acceptance: focused then warranted broader regression, package tests,
  rendered phone/tablet accessibility, cold/warm/offline performance, payload
  size/memory, device evidence, mixed-client CloudKit and release rehearsals.

## Evidence

Worktree creation verified at `69c714f`, initially clean. The following entries
are chronological checkpoint evidence, not current TODOs: later entries and the
status matrix above supersede their earlier descriptions of missing components.
Full delivery/acceptance checkboxes remain open.

2026-10-03 foundation evidence: CardGame now keeps the existing single-string
wire representation while retaining unknown identities. Descriptor capability
enumeration replaces closed enumeration; collection/activity/price copies no
longer substitute Pokémon. CSV previews retain explicit unknown games, distinguish
absent and blank game columns, and namespace non-Pokémon keys. Unsupported CSV
rows are refused before ownership ledger writes. JustTCG mappings refuse unknown
games before provider requests. These are transitional seams pending runtime
adapter extraction and complete creation/mutation gating.

Eight isolated Swift identity/capability checks passed. The generic identifier
foundation now compiles: normalized unique field keys, presentation-independent
equality, separate suppression identity, and immutable existing-game context
through a transitional typed projection. New unresolved records write versioned
snapshots. Legacy records still rehydrate; unsupported games and future snapshot
versions remain visible read-only. Original read-only JSON retains unknown fields,
and undecodable neighboring records are isolated and retained during saves.

Focused simulator evidence on the external artifact drive: 120 unique cases
passed across the final per-suite runs (CSV resume 5, game compatibility 9,
Pokémon catalog slice C 10, parser 76, suppression 4, unresolved store 16).
The initial run had one incorrect new blank-game test expectation; the importer
correctly rejected the row with `noCards`. After correcting the expectation,
the 25 game/recovery cases reran with zero failures. The app build passed.

The typed projection remains a migration bridge; full runtime-adapter extraction,
secondary-recognition routing, encounter-scoped recovery,
generic physical candidates and complete unsupported-game mutation/provider
guards are unfinished. This evidence does not complete A, C, or E.

2026-10-03 recognition evidence: primary recognition now dispatches through
registered game adapters under `Games/`. The registry rejects duplicate
registration, combines vocabulary deterministically, evaluates all recognizers,
and distinguishes hard ambiguity from soft fallback-blocking rejection. Pokémon
and Magic both retain internal multi-identity ambiguity instead of presenting it
as a miss. Magic spatial behavior lives behind its adapter; a valid independent
primary identity still wins over that soft rejection. Existing profile context
for historical Pokémon remains a migration bridge to the runtime layer.

Generic identifiers/snapshots now carry an optional semantic catalog generation.
Confirmation cannot merge generations, while the suppression key remains stable
across activation. The module must supply the generation; One Piece does not yet
have an activated registry or runtime. Focused simulator runs passed 99 recognition,
suppression and historical-capture cases, then 107 parser/game/recovery cases
after generation binding. No production feature was enabled.

2026-10-03 runtime/variant foundation: app bootstrap registers Pokémon/Magic
runtime values once in an app-scoped container. ContentView receives that
container, and Scanner/Browse reuse the module-owned coordinators through an
explicit legacy binding bridge. Runtime descriptors and game-owned policies
drive selectable variants and lock options. Scanner menus receive the injected
registry's labels/options, and unavailable or unregistered lock values are refused.
`VariantLock` replaces the source-level Magic-only name; a typealias preserves
existing callers, with unchanged lock IDs and treatment qualification.

Simulator evidence: the final runtime/game/scanner/variant run passed 136 cases
(12 compatibility, 91 scanner model, 33 variant resolver). Browse verification
passed all four classes in BrowseFeatureTests.swift: 61 feature, 35 collection,
6 loading refinement and 64 checklist cases. Two existing screen-construction
cases also passed. Artifacts remain on the external build drive.

`scripts/audit_game_boundaries.sh` is a strict final architecture gate. Shell
syntax validation passed; the audit currently fails on legacy catalog, Browse
and pricing switch labels, correctly showing that adapter extraction is unfinished.
It is not yet a passing CI gate. The runtime's catalog/browse/import
adapter contracts, unified coordinator events and historical fallback migration
remain open. This foundation does not complete B or the full variant slice.
No provider, physical-device, CloudKit, signing, or release gate is complete.

2026-10-03 pricing adapter extraction: registered Pokémon and Magic pricing
adapters own direct-provider refresh, exact identity validation and the Pokémon
bulk-market fallback. PriceQuoteService dispatches a game-neutral exact printing
request; runtime construction injects the service into scanner Price Check.
Unsupported capability or a missing adapter is terminal and cannot invoke an
override, provider refresh or foreground fallback. Unsupported pricing has its
own UI state rather than claiming a vendor has no exact listing.

Stored-card fallback checks capability before bulk/paid requests or product/price
observations. Background raw/graded refresh excludes unsupported games, and
camera slab lookup checks the injected graded capability before vendor lookup.
The generic request preserves physical printing ID, variant and language; the
legacy resolved-card bridge and Pokémon print-run extension remain transitional.
Background provider dispatch and shared fallback ownership still need extraction
into adapters. These changes do not complete B or L.

Verification: the initial service selection passed 104 cases; the foreground
capability/quote-cache selection passed 121. The expanded regression then passed
286 cases across nine classes, including unknown-game background raw/graded rows,
scanner, refresh lifecycle, exact bulk fallback and product fallback. Scanner
cases encountered provider timeouts but finished with zero failures. The final
camera slab capability guard was added after that regression; its final focused
run passed all 45 compatibility, quote-cache and slab-resolver cases. Project
parsing, local ledger links and diff whitespace checks pass. The
architecture audit now rejects only remaining catalog/Browse switch labels in
its designated central files. No One Piece pricing or production support enabled.

Corpus fixtures must record dated evidence and reviewed distinctions, not assert
historical vendor counts as current truth. Existing suite results are historical
until rerun against this worktree. In-progress slices retain all remaining scope.

2026-10-03 resolved-card/catalog foundation: [ResolvedCatalogCard](../../TradingCardScanner/Models/ResolvedCatalogCard.swift) is now an
immutable game-neutral exact-printing value. The IdentifiedCard name remains a
source-compatibility alias; existing provider payloads live in a transitional
LegacyResolvedCard projection, with factories in their game modules. Collection
keys, image metadata, Magic treatment/content extensions and catalog pricing
remain compatible. Generic printings retain app-owned IDs and finish-qualified
keys independently of future variant-count changes; absent legacy/provider
pricing produces no quote or inferred marketplace link.

[GameCatalogAdapter](../../TradingCardScanner/Games/Core/GameCatalogAdapter.swift) and its registry route immutable-generation lookups through
the runtime container. CatalogLookupOutcome distinguishes resolved payloads,
canonical-card printing choices and incomplete catalogs. The old one-card API
throws a choice/incomplete result instead of selecting a candidate. Selection
checks generation, candidate membership and the returned game/printing/canonical
identity/language, and preserves retrieval time, path and persistence eligibility.
Selection answers are not cached by canonical number. Tests cover independent
printing selections, stale generations, duplicate IDs and foreign choices.

Verification: the initial migration passed 97 cases. After correcting a new
test's marketplace-link helper name, the expanded resolved-card/catalog run
passed 333 cases across compatibility, Browse, collection keys/queries, import
resume, normalization, historical catalog and pricing classes. The final scanner,
variant, quote-cache, graded and fallback regression passed all 248 cases,
including the final duplicate-ID/foreign-choice test. Project parsing, ledger
links and diff whitespace checks pass. The picker and
recovery boundaries are still Pokémon-specific and must adopt the generic
candidate/outcome types next. Existing Pokémon/Magic catalog providers also
remain on their legacy bridge; speculative candidate caching, unified activation,
and full catalog adapter extraction remain open. B and D are not complete, and
no One Piece production support or sync/provider gate is enabled.

2026-10-03 printing-picker/recovery milestone: the live scanner now handles
generic catalog printing-choice outcomes through PendingPrintingChoice and
PrintingChoiceBar. Selection revalidates the candidate through CardCatalog and
passes the original catalog timestamp to finish resolution. Historical Pokémon
keeps its existing resolver bridge and candidate ordering. Dismissal retains a
recovery row; generic encounters use distinct recovery IDs, and committing a
generic card cannot broadly clear other rows sharing its canonical number.

Recovery records now retain generation-bound PhysicalPrintingCandidate values
alongside the versioned identifier snapshot. An installed catalog adapter makes
its generic records actionable; absent modules remain read-only. The recovery
selection path checks both saved membership and current catalog membership and
identity before finish resolution. Legacy record fields remain decodable.

The initial scanner/compatibility checkpoint passed 116 tests. The batched
recovery checkpoint passed 19 tests (three scanner cases and 16 persistence
cases), covering retained candidates, supported/absent adapters, recovery
selection and legacy/unknown record compatibility. No broader repeat run was
needed. D/E remain open: legacy candidate/hint bridges, bounded live
picker layout, complete catalog-activation/recovery migration, and full relaunch
UI coverage still need work. This is fixture-driven scanner integration; the
production One Piece catalog/runtime/OCR and creation/sync gates remain open.

2026-10-03 One Piece catalog-core milestone: [OnePieceCatalogCore](../../OnePieceCatalogCore/README.md)
now defines the canonical-card, artwork, permanent physical-printing,
product-appearance, source-observation/inventory, review/correction, variant,
market-mapping and release/index contracts. UUID allocation stays in the durable
reviewed registry input. The deterministic builder retains all IDs/candidates;
exact/perceptual image evidence does not automatically join physical printings.
The package is registered beside the existing local catalog packages in Xcode.

The candidate validator checks references, duplicate identities/aliases,
required reviewed distinction evidence, language, completeness, source discovery
inventories, retained IDs/history, reviewed alias reassignment, supersession and
split/merge graphs, product evidence, exact market SKU/finish/condition qualifiers,
and derived indexes. A provisional/conflicted row cannot manufacture unique
automatic authority. Market mapping changes classify as protected review and
report printing IDs whose cached quotes need invalidation. The content-only
allow-list permits display-name/product-label changes only.

The publisher builds local unsigned candidates without rewriting the registry
or allocating UUIDs. Bootstrap is explicit and revision-one-only; subsequent
builds require a previous release. Input overwrite is rejected, including
through symlinks. Synthetic fixture cases exercise the named historical stress
numbers, future OP/EB/PRB/ST prefixes, large promo lists, identical-art releases,
DON exclusion and correction/market boundaries without claiming source counts
or production completeness.

Verification: the initial package checkpoint passed 19 cases. Inspection found
retirement/product-evidence gaps; after tightening those, discovery completeness,
exact SKU proof and publisher protection, the batched package checkpoint passed
all 25 cases. The publisher executable compiled and its command contract ran in
the package test. Xcode project parsing, ledger links and whitespace checks pass.
No additional app build/regression was run for this package-only checkpoint.
G remains open: real permitted provider captures/adapters and reviewed durable
production data are not implemented. Signed publication/activation and asset
integrity remain H/F work; One Piece runtime/OCR and creation/sync gates remain
open. Catalog fixtures are not a production seed or rights/access evidence.

2026-10-03 One Piece local scanner milestone: the signature contract now creates
an immutable verified-release value after pinned-key verification, contract/index
validation, revision/time checks and bounded strict base64url decoding.
[OnePieceCatalogRegistry](../../TradingCardScanner/Services/OnePieceCatalogRegistry.swift)
accepts this verified value and builds dictionary indexes once. Its English
scope is separate from language confirmation on a physical scan.

OnePieceScanProfile and OnePieceRecognitionAdapter derive series vocabulary and
known numbered identifiers from the registry, apply character repair only in
numeric collector positions after an exact known prefix, deduplicate readings,
and report hard ambiguity for different numbers. The default recognizer marks
language unconfirmed. **Historical 2026-10-03 behavior, superseded by the
2026-10-05 scanner product correction above:** OnePieceCatalogAdapter required an explicitly
labeled English physical-printing choice even when one verified printing existed.
Automatic resolution additionally required confirmed English and complete,
entirely verified candidate scope. Selection retains the signed generation,
exact UUID, supported variants and original catalog retrieval time.

OnePieceGameRuntime registers its catalog, recognizer and game-owned variant
policy through the existing container. Additional recognizers are installed
between frames; vocabulary changes reset observations, while semantic generation
updates still replace the adapter. The scanner commit boundary now checks
collectionWrite capability before persistence. The One Piece module has scan
capability only, without pricing or shared-collection writes. It is not enabled
in production app bootstrap until its data/rollout gates are met.

Verification: the focused app checkpoint built successfully and passed 222
tests (seven One Piece integration, 82 parser, 23 compatibility, 94 scanner and
16 recovery cases). Signed synthetic fixtures exercised number recognition,
language/scope safety, physical choice before finish, different-printing copies
persisted separately in an in-memory test store, no synthetic market observations,
stale generation rejection, and refusal to write with the production capability
gate off. The package checkpoint passed all 27 cases including signature key,
tamper, time, encoding, payload-size and revision failures. Project parsing,
ledger links and whitespace checks pass. Existing unrelated test-target
concurrency/App Intents warnings remain; no physical-device or provider result
is claimed.

H/I/J remain open: current/previous storage, update activation/recovery and
in-flight generation handling, a signed reviewed seed, rollout configuration,
permitted real data, broader OCR/geometry corpus and unknown-number policy,
complete collection mutation/import guards, and mixed-client sync evidence still
need implementation/verification. The next milestone should complete catalog
activation and recovery across generation changes rather than repeat these
passing tests without new risk.

2026-10-03 signed storage and live activation milestone: SignedCatalogReleaseStore
now owns verified current/previous bytes, atomic rotation, failure reconciliation
and actor-serialized transition validation. Pokémon and Magic wrappers preserve
their filenames, wire/trust contracts and distinct revision policies. One Piece
adds independent bounded signed slots, optional verified bundled fallback,
rollback/same-revision collision rejection and durable-predecessor validation
of permanent printing identities. A failed write cannot publish an activation.
This is local storage/activation; remote conditional transport is not implemented.

GameCatalogActivationSource supplies immutable catalog, recognizer and variant
snapshots through the runtime container. The scanner model subscribes before
reading its initial snapshot, installs catalog semantics before the frame-queue
recognizer swap, updates game-owned variant options and reloads recovery records.
Revisions prevent buffered older events from replacing the current snapshot.
One Piece initial loads share one task; event buffers retain the newest snapshot
rather than retaining an unbounded history of entire catalog generations.

CardCatalog rejects an old lookup or printing resolution completing after a
generation change. An explicit recovery lookup asks the game adapter to revalidate
and rebind printed evidence to the current generation. It preserves language
confirmation, suppression identity and encounter/recovery IDs. Saved physical
choices are never silently rebased. One Piece rejects unknown namespace/field
semantics during rehydration; future records remain read-only. Local stale or
invalid catalog outcomes are classified as identity failures rather than
automatically retrying the same obsolete identifier as a network failure.

Verification: the batched app checkpoint built and passed all 57 selected cases
(One Piece integration 10, One Piece activation 5, shared storage 8, recovery 16,
Pokémon release store 9 and coordinator 9). It exercises current/previous recovery,
before/after-write failure injection, exact verified backup bytes, concurrent
revision activation, live scanner updates, retained old recovery evidence, fresh
printing choices after retry and an old lookup completing after activation.
Inspection then tightened initial-load concurrency, event buffering and local
failure classification. The focused follow-up built and passed nine cases
(One Piece activation 7, stale-choice classification 1, legacy successful recovery
lookup 1). No package or broad app suite was repeated for unchanged code.

F/H/I/J remain open: shared/One Piece conditional fetch and update configuration,
production signing/publication and reviewed seed/data, full game-service migration,
unknown-number recognition policy, stale-choice product messaging and full relaunch
UI evidence, all collection mutation/import guards, and mixed-client sync policy
still require work. Production bootstrap continues to omit One Piece. Its module
retains scan-only capability with no pricing or shared-collection writes. The
next product milestone is One Piece local Browse/search/details and import/export
through game-owned adapters, preserving exact-printing ownership semantics.

2026-10-03 One Piece Browse milestone: GameBrowseAdapter and its runtime registry
now route new-game sets, card pages, search and details through immutable local
catalog projections. Existing Pokémon/Magic paths remain on their legacy bridge.
OnePieceBrowseAdapter projects verified English physical printings, primary
releases and reviewed product appearances. A printing can appear in multiple
product checklists while unrestricted search returns its physical UUID once.
Human-readable treatment/distribution/stamp labels distinguish summaries; details
resolve the exact printing and supported variants with the original catalog time.
Printings without a product remain accessible in an explicit other-releases group.

Search/set pagination retains every printing and binds cursors to query/filter
scope and signed generation. Details carry an optional generation through the
backward-compatible CatalogCardSummary wire contract. Central detail caching and
coalescing include that generation and product appearance, and activation invalidates
local decoded details before fresh summaries can load. Old summaries/cursors and
late results cannot bypass generation checks. Runtime activation supplies Browse
snapshots through the same game-neutral source used by scanning.

CatalogSet optionally carries exact physical membership. Both ownership models
refuse printed-number/set-label fallback for generation-bound summaries. Product
completion counts distinct owned physical printings against that membership;
owning a different Shanks printing does not complete another physical slot.
Existing Pokémon/Magic number/master-set behavior remains unchanged. These totals
describe the active catalog's verified records, not independently certified
provider-universe completeness.

Browse menus/search/filter enumeration now comes from the injected runtime
registry. Release rails derive their games from supplied directories. Sealed
search runs only for games with sealed capability; an empty One Piece result
does not ask for unrelated provider setup. Raw/graded Browse additions enforce
the relevant collection-write/graded capabilities. One Piece has scan and Browse
capabilities when explicitly registered, without pricing or shared-collection
writes. App defaults still omit the module.

Verification: the batched app checkpoint built successfully and passed 75 cases
(61 Browse feature and 14 One Piece integration). Synthetic signed fixtures cover
offline product/details/search, many-to-many appearances, 61-printing pagination
without truncation, scope/generation cursor rejection, exact ownership/completion,
wire round trips, runtime enumeration and activation invalidation. A selection
correction then ran the actual legacy ownership/completion classes without
rebuilding: all 38 cases passed (35 Browse collection and three checklist
completion). The focused capability-state follow-up built and passed its one
One Piece case after tightening the sealed-setup prompt and raw-add affordance.
Project parsing, ledger links and whitespace checks pass. No package/broad app
suite, rendered UI or device checks were repeated or claimed.

K remains open: import/export/normalization and manual-correction adapter dispatch,
complete mutation gates, reviewed alias ownership, stale Browse recovery messaging,
game-qualified update metadata, relaunch/rendered accessibility and performance
evidence still require work. Shared legacy Browse extraction is unfinished.
Source/rights, production data/publication, sync and release gates remain open.

2026-10-03 exact import/export and normalization milestone: GameImportAdapter
is registered through the runtime alongside catalog/Browse adapters. Its pure
CSV validation runs before a row transaction can create ownership. Headless CSV
import carries the supplied game/capability registry and adapter registry through
its actor; default callers retain the production write gate. Runtime factories
provide normalization and current signed-generation import adapters.

2026-10-04 missing-adapter follow-up: CSV import now requires the registered
printing validator for every newly added game, even when a descriptor permits
collection writes. Only the original Pokémon/Magic modules retain the existing
legacy validation path. A missing One Piece or future-game adapter yields a
failed, retryable row before any ownership/history operation, rather than silently
skipping identity validation. Installing an adapter still does not grant writes.
The batched simulator checkpoint passes 72 cases: 37 One Piece integration,
five CSV resume and 30 forward compatibility. The new case verifies that both a
printed number and an otherwise valid physical UUID are refused without the
adapter, along with an explicitly writable future game, leaving ownership,
history and price observations empty. Existing adapter-backed fixture imports
and legacy resume behavior remain green; no production enablement is claimed.

OnePieceImportAdapter supports exact raw-card UUIDs from the verified catalog.
It checks canonical-number evidence, the printing's actual supported finish,
stable collection key and absence of conflicting legacy/market identities.
It never allocates a physical identity from OP01-120, a name, vendor suffix or
portfolio synthetic ID. Invalid or unsupported rows remain failed/retryable
entries with a specific validation reason. App CSV export and preview preserve
physical UUID, game, finish, key and catalog alias; a non-Pokémon first-edition
finish no longer becomes a Pokémon print-run field.

Normalization lookup and row grouping now use length-framed game, item-kind,
source-ID and attached-catalog-ID keys. It routes registered games through their
import adapters, retains the existing Pokémon/Magic strategies as legacy paths,
filters adapter results to the requested keys and discards results from superseded
signed generations. Exact metadata fills missing fields without changing ownership
keys or manufacturing market mappings/quotes. Contradictory physical UUIDs cannot
borrow another printing's metadata.

Input discovery, sealed-image repair and post-lookup application now enforce
collection-write capability and live game identity. Unsupported and production-gated
rows receive no normalization watermark, metadata update or provider lookup.
Known physical rows can be enriched through an explicitly writable fixture policy;
this does not enable One Piece writes in the app's shared collection.

Verification: the batched app checkpoint built and passed 75 cases (18 One Piece
integration, 18 normalization, 23 forward compatibility, 11 collection keys and
five CSV resume). Signed synthetic fixtures cover app CSV round trips, exact
fixture imports, unsupported-number/finish rejection, production write refusal,
unknown-game preservation, metadata without pricing observations and the
non-Pokémon first-edition preview case. Inspection then added item-kind/attached-ID
grouping, contradictory UUID rejection and specific failure messages. The focused
follow-up built and passed 21 cases (18 normalization plus three exact import and
metadata cases). No unchanged package/broad app suite was repeated. Project
parsing, ledger links and whitespace checks pass.

K/A/B remain open: shared Collection/Settings/recovery screens still need runtime
policy propagation instead of their legacy default normalizer/import constructors;
all ownership/metadata mutations need the common unsupported-game guard; reviewed
source-alias imports, ambiguous portfolio-row selection and manual correction need
their explicit identity policies. One Piece graded/sealed CSV creation is not
implemented. Existing Pokémon/Magic normalizer strategies still need extraction
behind their adapters. Production seed/data/publication, rights, CloudKit floor,
rendered UI/device/performance and release evidence remain open.

2026-10-04 collection transaction guard checkpoint: CollectionStore now uses
a container-scoped game write policy, with explicit policy injection for CSV
transactions. Scanner startup installs its runtime policy before constructing
writers. The common commit guard validates pending inserted, changed and deleted
ownership/history models, including staged transactions and scanner actor saves.
Raw/graded/sealed acquisition, quantity changes, removal, undo, restoration,
variant correction and bulk deletion reject unsupported ownership identities.
Quantity repair uses the guarded commit, and history backfill skips unsupported
rows rather than manufacturing legacy Pokémon history for them.

Verification: one app build passed 63 selected tests (27 forward compatibility,
17 collection continuity and 19 One Piece integration). Four new tests cover
saved/staged acquisition refusal, preservation of a synced unsupported row after
quantity/remove/restore/correction/delete attempts, undo refusal after policy
withdrawal, and history backfill preservation. The existing ownership/history
and graded/sealed classes then passed all 56 cases without rebuilding. This is
simulator transaction evidence; it does not prove mixed-client CloudKit safety.

Production defaults still omit One Piece and retain its collection-write gate.
Shared Collection/Settings runtime propagation, legacy empty-game activity and
ledger-only identity policies, direct metadata/artwork mutation paths, complete
manual-correction adapter dispatch and the enforceable sync floor remain open.
The container policy is shared across fresh store instances; previously created
store values retain their policy snapshot. Runtime policy replacement therefore
needs an explicit lifecycle decision before introducing dynamic write enablement.

2026-10-04 shared-screen runtime checkpoint: ContentView retains the app runtime
container and supplies it to Collection and Settings. Collection's view-owned
normalizer is constructed from that runtime; a small Settings environment wrapper
constructs its own normalizer from the same container without replacing an active
observable service. Legacy callers without a runtime keep their existing defaults.
Launch history backfill and Collection startup install the runtime's container
write policy before their work.

Settings CSV import obtains current signed-generation adapters before acquiring
the collection's exclusive write lock, rechecks storage/cancellation afterward,
and passes both adapters and capabilities into the isolated importer. Its
post-import normalizer uses the same activation sources and refreshes catalog
metadata from the current generation. This wiring does not enable a new game or
grant collection-write capability merely because its adapter exists.

Verification: one app build passed 70 selected cases (20 One Piece integration,
18 normalization, five CSV resume and 27 forward compatibility). The new signed
fixture test creates a shared normalizer before revision activation, obtains the
new importer afterward, imports a printing introduced in revision two through
the isolated CSV actor, and enriches that exact UUID without pricing observations.
It also verifies the environment default and container propagation. This proves
service/transaction behavior and compile-time view wiring, not rendered Settings
interaction, accessibility, physical-device behavior or provider readiness.

K/B remain incomplete: legacy Pokémon/Magic normalization extraction, reviewed
alias/ambiguous/manual import policies, remaining metadata mutation guards,
catalog activation during a long import transaction and rendered UI evidence
still need their acceptance work. Production data/signing/publication, conditional
update transport and mixed-client sync gates remain open; production registration
continues to omit One Piece.

2026-10-04 signed update transport checkpoint: SignedCatalogUpdateClient owns
generic HTTP envelope transport and conditional validators. Its delegate bounds
bytes during receipt (including unknown Content-Length and decoded chunks),
rejects redirects, validates HTTPS endpoints, retries transient network/server
failures and tears down cancelled transfers. OnePieceCatalogUpdateClient supplies
the envelope contract without introducing another game-specific transport copy.

OnePieceCatalogCoordinator accepts an optional update client and rollout policy.
Disabled mode makes no request; validation-only checks signatures, revisions and
registry transitions without activating or persisting the candidate. Authority
mode uses the existing durable activation path and retains the prior snapshot
on failure. Concurrent refreshes share one task. Rejected updates clear validators,
and an unsolicited 304 cannot stand in for a verified catalog. Missing/unknown
rollout configuration defaults to disabled.

Verification: one app build passed 43 selected cases (five update transport,
eight shared storage, ten One Piece activation and 20 integration). New cases
cover conditional requests/reset, advertised and streaming byte bounds, malformed
JSON/unsolicited 304, unsafe endpoints/redirect responses, cancellation of an
active transfer, coalesced verified activation, rejection/retry and disabled or
validation-only behavior. Project parsing, ledger links and whitespace checks
pass. URLProtocol fixtures prove local transport behavior; no live server,
production credentials, publication or device evidence is claimed.

F/H remain incomplete: Pokémon/Magic transport migration, production URL/config
and public-key wiring, signed reviewed seed/data, publisher signing/workflow and
app bootstrap/refresh scheduling still need implementation and acceptance. No
production endpoint or One Piece registration was enabled by this checkpoint.

2026-10-04 publication preparation checkpoint: CatalogPublication binds signing
to exact reviewed canonical payload bytes, a dedicated key ID, independently
pinned matching public key and verified signed baseline. Revision-one bootstrap
is explicit. It validates the registry transition and returns a manifest with
payload/envelope hashes, revision lineage, classification and mapping invalidations.
The publisher now supports sign/verify alongside its unsigned build command.
Private key input is environment-only; source files and differing existing
artifacts cannot be overwritten. Repeated signing revalidates and retains the
existing artifact instead of replacing its signature or manifest.

The [publisher operating guide](../../OnePieceCatalogCore/README.md) records the
commands and gates. The [workflow](../../.github/workflows/one-piece-catalog.yml)
tests the package and optionally prepares a main-branch artifact with dedicated
One Piece signing secrets. It verifies the output independently and retains its
manifest. It does not deploy. Signing-environment reviewer protection still needs
external configuration/evidence. The [production configuration](../../Config/OnePieceCatalogProduction.xcconfig)
is disabled with no endpoint or inherited keys; build/bootstrap wiring is open.

Verification: the package checkpoint ran 30 cases; 29 passed and the new CLI
case initially failed executable discovery. Focused reruns exposed incompatible
Foundation write options and artifact regeneration, which were corrected. The
final CLI case passes signing, independent verification, identical reruns,
different-artifact preservation and input collision refusal. All 30 cases now
have passing evidence across that checkpoint and its focused follow-up. YAML
parsing, workflow shell syntax, ledger links and whitespace checks pass. No app
build, GitHub job, live provider or production publication was run or claimed.

G/H remain open: reviewed durable production registry/source snapshots, exact
asset retention/rights, dedicated production key provisioning, signing approval
enforcement, atomic hosted revision/current-pointer deployment and preservation
of other games' hosting trees, signed seed and runtime/bootstrap integration.

2026-10-04 configured bootstrap checkpoint: the app's compile-time registration
can now create the One Piece runtime from an explicitly configured, verified
signed seed. Configuration rejects malformed/duplicate/foreign game key IDs,
public key reuse from configured Pokémon/Magic pins, unsafe/unapproved origins
and missing or invalid seeds. The configured endpoints use the repository's
catalog hosting origins and One Piece's separate pointer path. Disabled mode
does not read a seed or register the module. Validation-only mode retains its
refresh source while exposing no scan/Browse/write capabilities; authority mode
enables scan/Browse with collection writes and pricing still absent.

Production xcconfig values now flow into Info.plist. App startup asks registered
activation sources to refresh after storage bootstrap; One Piece makes at most
one launch attempt per coordinator even with repeated lifecycle calls. Invalid
One Piece bootstrap leaves existing games available. The seed directory contains
instructions only; a reviewed signed envelope must still be added explicitly to
Copy Bundle Resources. No synthetic data or generated production key was bundled.

Verification: one app build passed 61 selected cases (23 One Piece integration,
11 activation and 27 forward compatibility). Four new cases cover disabled
registration, safe key/origin/seed gates, validation-only capabilities and repeated
launch refresh. Inspection of the built plist confirms disabled rollout, empty
endpoint/pins and no production seed resource. Project/plist parsing, ledger
links and whitespace checks pass. No network/device/CloudKit evidence is claimed.

H remains incomplete until reviewed production data/rights, dedicated keys,
verified hosting publication and the real signed resource exist. Cold-start
seed decode/index construction and memory need measurement with realistic data;
current construction is synchronous and has only fixture/compile evidence.
Background/periodic update policy, remaining legacy service extraction, printing
picker UI/performance and the independent mixed-client write floor remain open.

2026-10-04 uncataloged-number recognition checkpoint: OnePieceScanProfile now
recognizes structurally valid printed numbers under registry-supported prefixes
without requiring canonical membership first. All distinct numbers in the band
participate in ambiguity, including missing catalog entries. A known Shanks
number beside an uncataloged One Piece number cannot manufacture one winner.
Unknown prefixes remain outside this recognizer; numeric-position repairs and
language confirmation retain their existing conservative rules. The profile no
longer duplicates the full canonical-number set solely for recognition filtering.

Catalog lookup remains a separate stage: a number missing from the local registry
returns catalogIncomplete(nil), and the scanner persists its exact identifier
for recovery without a printing choice, finish choice or owned row. This closes
the previously open unknown-number policy for supported series; it does not
establish completeness or accept an unregistered future series automatically.

Verification: one app build passed all 25 One Piece integration cases. Two new
cases cover known/unknown and unknown/unknown collisions, repeated-number
deduplication, unsupported-series rejection, incomplete lookup and live recovery
retention with collection and inventory still empty. Whitespace and ledger-link
checks pass. Error messaging still uses the generic unresolved reason; clearer
catalog-incomplete UI copy, recovery after later canonical ingestion, rendered
picker/accessibility and realistic performance remain acceptance work. No broad
unchanged scanner/package suite, network or device checks were repeated.

2026-10-04 recovery/identity validation follow-up: retry-lookup and retry-save
without a memory-only candidate now share explicit evidence revalidation against
the active catalog. Saved physical-printing hints are not reused as selections.
The retry task checks that its row still exists and is writable before enqueueing
or reporting a failure. In-memory exact commit retries retain their existing
behavior; this change does not establish a policy for every retained commit after
physical identity corrections.

One Piece live lookup, printing selection and persisted retry now share the same
payload contract. Unknown fields, unsupported language, invalid confirmation,
noncanonical numbers and inconsistent number/suppression identity are rejected.
Opaque malformed recovery records remain preserved read-only. Missing canonical
or verified printing data produces the existing retryable noCatalogEntry reason,
whose description now explains the missing confirmed printing. No new persisted
reason discriminator or game-specific central switch was added.

Verification: the batched app build/checkpoint ran 139 selected cases: 29 One
Piece integration, 94 ScannerViewModel and 16 UnresolvedScanStore. The first run
passed 138; the new later-release fixture omitted its new observation from the
source inventory and correctly failed candidate validation. After adding that
fixture inventory entry, only the failed case was rebuilt/rerun and passed.
Passing evidence covers all 139 selected cases across these two runs, not a new
whole-suite baseline. Logs: `/private/tmp/one-piece-recovery-validation-checkpoint.log`
and `/private/tmp/one-piece-later-catalog-recovery-followup.log`; xcresults remain
on the external artifact drive. No wider rerun was needed after the fixture-only
correction.

New cases cover consistent rejection across lookup/choice/retry, opaque recovery
preservation, relaunch with a changed generation followed by choosing a different
printing UUID, and an uncataloged number becoming explicitly selectable/owned
after relaunch with a later signed/verified fixture release. This last case is
local fixture evidence, not a real provider ingestion or production activation
rehearsal. Production support/write policy remains disabled; real corpus,
picker/accessibility, remaining write/backfill guards, Browse events, device,
performance, delivery and CloudKit gates stay open.

2026-10-04 public-source discovery follow-up for the next corpus milestone:
web-reader copies of the [official OP01 list](https://en.onepiece-cardgame.com/cardlist/?series=569101)
and Limitless entries for [Shanks](https://onepiece.limitlesstcg.com/cards/en/OP01-120),
[Nami](https://onepiece.limitlesstcg.com/cards/en/ST01-007) and
[Luffy](https://onepiece.limitlesstcg.com/cards/en/P-001) were inspected. These
copies expose multiple artwork/print rows; Shanks also has a separate reprint
appearance outside its five displayed market rows. Treat these as discovery
leads, not a one-to-one physical UUID inventory. The retrieval cache dates vary,
and no exact HTTP-byte captures, asset permissions, reviewed physical registry
or market entitlements were established. Next corpus work must retain original
capture provenance and reconcile these product appearances and hidden physical
distinctions instead of promoting the displayed row counts to completeness.

2026-10-04 compact printing-choice checkpoint: replaced the default metadata list
with the Pokémon/Magic header and equal-weight option-button format. Up to three
choices share a row; larger histories use a bounded two-column grid. Large text
uses a stacked header and one scrollable column. Labels omit shared metadata but
retain necessary release/stamp/footer distinctions; shortening collisions fall
back to full distinguishing labels. The shared Details sheet keeps complete
metadata/artwork and an explicit selection cue. Compact artwork-only choices are
unavailable until comparison in Details with a loaded distinct image; unknown or
failed artwork never selects a physical identity. Recovery uses the same concise
labels and Details surface. Canonical/printing/finish order and legacy keys remain.

Verification: one batched app checkpoint passed all 37 selected cases (34 One
Piece integration, three scanner printing-choice cases). A new label case covers
shared-metadata omission, identical-art block distinctions and shortening
collisions. After inspecting captures, shortest unique release labels and the
large-text layout were refined; only that affected label case was rebuilt/rerun
and passed. Two build-only follow-ups corrected rendered header compression and
light-tablet material contrast, without repeating unchanged tests. Final fixture
captures and native interactions cover phone/tablet, large text, footer choices,
missing-artwork failure, Details without selection, skip and exact selection of
choice 61. The [visual evidence checklist](one_piece_printing_choice_visual_checklist.md)
records logs, artifact paths and limits. Whitespace/link checks remain required
at handoff. No broad suite, actual VoiceOver, real corpus, provider, device or
CloudKit evidence is claimed. D remains open for those applicable acceptance
gates and owner review; production remains disabled. Next product milestone is
the reviewed real stress corpus and remaining unsupported-row protections.

2026-10-04 real source-review checkpoint: retained exact public HTML response
bodies for official OP01/ST01/promo and Limitless Shanks/Nami/Luffy pages outside
the repository on the external review drive. The capture manifest records exact
body hashes, byte counts, URLs and completion timestamps. The bounded offline
normalizer handles the observed Bandai modal/product/errata structure and
Limitless print tables, retaining the separate Shanks PRB01 appearance. Provider
suffixes and `aa`/`fa`/`manga`/`serial` markers remain source facts, not app finishes
or owned identities. Prices, affiliate market IDs and card rules text are omitted
from normalized output; no images were downloaded or bundled.

The durable review inputs contain 30 observations, six incomplete inventories
and three canonical cards. They contain no physical/artwork UUIDs, product joins,
market mappings or reviewed completeness. Observations of one artwork alias on
different captures remain separate; only identity review can bind such evidence
to physical UUIDs. This is actual source-discovery progress, not completion of
the real physical corpus or the local exact-ownership demonstration.

Verification: all 31 OnePieceCatalogCore tests passed in
`/private/tmp/one-piece-real-source-core-checkpoint.log`; eight Python parser/CLI
tests pass, covering errata/product separation, byte/path bounds, byte tampering,
foreign/Japanese links, schema loss, untruncated 61-row tables, separate reprint
appearances, current variant queries, overlapping observations and preservation
of existing output. The actual normalizer rerun retained identical output.
The already-built publisher produced an unsigned review candidate with zero
physical printings/automatic candidates at `2026-10-04T13:07:36Z`, SHA-256
`a18c3450d507e0d5f807e539b81bc124ad7a8d0ba84883e27d80be6983ebb66c`.
It remains at the external `OnePieceSourceReview/2026-10-04/review-candidate.json`.
No app build, simulator rerun, signing, live workflow or production deployment
was performed. CI now includes the normalizer tests; that local workflow edit is
not evidence of a completed GitHub run. Next: individual variant/product review,
permitted physical evidence, durable reviewed UUID assignments and the remaining
unsupported-row protections. G and all production/device/sync gates remain open.
