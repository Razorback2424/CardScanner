# Lorcana implementation plan

**Current status — 2026-10-14:** normal app registration now enables exact raw
ownership, import and pricing for **1,616 ordinary printings / 3,232 Normal and
Cold Foil mappings across expansions 1–8**, using the existing scanner, Price
Check, Browse and collection refresh components. All 3,582 discovery card rows
and 177 sealed products remain visible; unsupported rows stay read-only and
unpriced. The owner authorized public online evidence and normal-workflow
enablement. The [normal pricing rollout checkpoint](../research/lorcana-normal-pricing-rollout.md)
owns mapping scope, held discrepancies and current acceptance results.

**Independent continuation — 2026-10-14:** all **3,232 enabled pricing lanes**
pass fresh-feed acceptance through the shared quote service/adapter; all 19
pricing cases pass with live opt-in, zero failures/skips and two internal QoS
warnings. A retained-source replay reproduces the catalog and permanent UUID
ledger exactly. The new full-matrix test remains opt-in for routine/offline runs.
Local App Store export was attempted without provisioning changes and failed
because the distribution profile is unavailable; development packaging remains
verified. No app/catalog behavior changed, and no physical-card or deferred
privacy/support work was performed. See the production checkpoint for exact
results, the pre-existing architecture audit failure and remaining boundaries.

The [production acceptance checkpoint](../release/lorcana-production-acceptance.md)
now records the rebuilt development-signed ReleaseLocal archive and verified
development IPA export. The complete final simulator run has **2,188 passed,
zero failed and 12 skipped across 2,200 cases**, with five runtime warnings.
Centering scalar-loop/median optimization preserves exact reference geometry
and profiles; REQ-022 passes unchanged limits with a final full-run upper median
of **0.586 s** and maximum **0.649 s**. Historical 2026-10-13 failures remain
recorded in that checkpoint. [Bluehost publication files and upload steps](../legal/bluehost-publication.md)
and [reviewer notes without physical cards](../release/lorcana-app-review-notes.md)
are prepared. Live privacy/support publication, verification and submission URL
configuration are **deferred at the owner's request (2026-10-14)**. Prepared
files remain available; the submission prerequisite is not marked complete. This is
a bundled release catalog; App Store publication, physical-device/camera and
publication/asset-rights acceptance remain open. Current 1.0 storage is on-device
with sync disabled; live mixed-client CloudKit is deferred to a future sync release.
Production
key/hosting setup applies to future remote updates, not loading this bundled
catalog. Earlier dated default-unpriced/disabled-write claims below are historical
and superseded for this ordinary mapped scope.

The archive compiler exposed a finish-chooser check against `nil` on a
nonoptional legacy enum. Matching its `.opaque` generic-card case now retains
the full Lorcana footer identifier. The final simulator build and inspected phone/
tablet rendering pass; rebuilt signed iOS archive, strict signature verification
and final development IPA export also pass in the
production checkpoint.

**Historical Hades checkpoint — 2026-10-13:** the owner requested online
evidence for the next bounded pricing slice. A separate local review seed now
maps ordinary English Hades Normal/Cold Foil and retains Oversized as an unmapped
comparison. The [mapping/provider checkpoint](../research/lorcana-pricing-review.md)
records evidence, exact joins and live replay. Its Hades UUIDs are retained in
the expanded normal catalog; the 12 physical specimen packets remain unapproved.

**Earlier local acceptance:** Slices 1–3 and Slice 4 local ownership/Browse/import code implemented;
253 distinct selected simulator cases have passing evidence across the regression
run and corrected ownership replay — 2026-10-12. The 2026-10-13 bounded
phone/iPad synthetic rendered pass is complete, with 204 final scoped tests
passing; real physical/device/provider acceptance remains open.
**Historical discovery-only checkpoint — 2026-10-13:** the owner-requested English completeness pass
adds default source discovery, real-footer recognition and offline sealed browse.
The [coverage checkpoint](../research/lorcana-catalog-coverage.md) owns this
inventory, the continuation's 322 passing focused tests and remaining gaps. Earlier statements here
that `appDefaults` omits all Lorcana support are historical for discovery;
reviewed physical acquisition, collection writes, production signed activation
and pricing remain disabled. Slice 4 physical acceptance gates remain open.
Current work is on
`feat/lorcana-implementation` at `8613a1d` plus local changes. See the
[source checkpoint](../research/lorcana-source-corpus.md) and
[local physical contract](../research/lorcana-physical-contract.md) and
[signed activation contract](../research/lorcana-signed-activation.md). Real physical
corpus acceptance remains open; synthetic review fixtures do not close it.
The [representative reference corpus](../research/lorcana-real-card-corpus/README.md)
now retains 29 unapproved candidates, 35 source references and 25 unexecuted
physical acceptance scenarios. Physical specimens and independent review remain
required for that camera/specimen evidence. They are not an additional packet
prerequisite for the 1,616 ordinary mappings already reviewed online and enabled
in the bundled normal catalog.
**Source review:** integration at `6b64abe` and subsequent review work through
`55dc1e4` on `merge/one-piece-integration`. The remaining-audit cleanup removes
the accidentally tracked `undefined/` adapter copies and corrects the extracted
model's spacing. These One Piece/runtime follow-ups do not enable Lorcana Browse,
ownership or pricing; this plan's Lorcana acceptance gates remain unchanged.
See the [One Piece review handoff](../audits/one-piece-integration-review-handoff.md)
for cleanup evidence and scope.

The 2026-10-04 first-slice checkpoint recorded 44 focused passing tests, including
13 Lorcana cases. It belongs to the earlier `one-piece-integration` worktree at
base `69c714f` with shared infrastructure changes; it is historical evidence,
not a newly executed result for this checkout.

This is the current implementation authority. The [imported Lorcana research](../audits/lorcana-data-variant-scanner-architecture-audit.md)
remains source/background research, with nonportable original citations and
unverified release timelines. Current code and new evidence outrank that snapshot.

## Historical recalibration against the code — 2026-10-05

| Earlier proposal | Current code / decision |
| --- | --- |
| Add Lorcana to closed game/scanner switches | `CardGame.lorcana`, the display-only descriptor and `Games/Lorcana` already exist. Extend the Lorcana runtime and game-owned adapters; registration remains the composition point. No new central game cases. |
| Import every released set before a first usable checkpoint | The local print-family/footer-to-incomplete-lookup checkpoint is implemented. Next, review a bounded real corpus and exact physical records. Full coverage remains a separate deliverable; fixtures cannot establish completeness. |
| Build another persistence or candidate picker | Reuse `ScanIdentifierSnapshot`, generic unresolved storage, physical-printing choices, `ResolvedCatalogCard`, and the compact Pokémon/Magic-style finish picker when exact printing evidence becomes available. |
| Treat a provider set code as a printed marker | Store provider set code independently. Require an explicit footer mapping with an evidence reference; API set metadata alone cannot establish a denominator or the physical footer. |
| Put stamps/artwork/oversized identity into finish variants | Follow the existing physical-printing boundary: distinct artwork, distribution, stamps and size normally require separate physical UUIDs. Finish varies beneath that exact printing only. |
| Optical foil classification in the early path | Preserve explicit finish selection. Optical classification is deferred until measured deterministic evidence can justify it; no foil inference from price fields or rarity. |
| Extract shared adapters and signing infrastructure before Lorcana | Core runtime, catalog, recognition, variants, Browse, import and pricing interfaces already exist, as do shared signed storage/transport. Implement Lorcana's data contract and thin domain integration against them. No new adapter framework or generalized publisher is a prerequisite. |
| Treat One Piece implementation as Lorcana readiness | One Piece supplies working integration patterns, not Lorcana physical evidence, market mappings, keys, rights or sync approval. Its source normalizers and catalog-core domain remain game-specific. |
| Enable every feature when the game descriptor is added | Capabilities are independent. Explicit Lorcana injection supports scan and local Browse; the debug review kit can enable exact ownership only after checking isolated storage. Pricing and production registration remain disabled. |

### Shared foundation available now

Paths below are relative to the repository. These are source-confirmed seams,
not a claim that Lorcana already implements the corresponding feature.

| Current seam | Lorcana integration / remaining work |
| --- | --- |
| `Models/CardGame.swift`, `CardGameRegistry.swift` | Stable string identity and capability discovery are implemented. Standard registration names Disney Lorcana with no capabilities; `CardGameRuntimeContainer.appDefaults()` omits its runtime. Preserve unknown stored games and finish IDs. |
| [`CardGameRuntimeContainer`](../../TradingCardScanner/Games/Core/CardGameRuntime.swift) | Compose recognizer, catalog, variant policy and optional Browse/import/pricing/activation adapters. Runtime factories feed scanner, Browse and normalization; `bound(to:isCurrent:)` binds authority to the actual storage session before consumers are constructed. Extend this composition rather than adding global Lorcana services to shared screens. |
| [`GameRecognitionAdapter`](../../TradingCardScanner/Games/Core/GameRecognitionAdapter.swift), `Services/CardScanner.swift` | Registry evaluates every recognizer; ambiguity cannot be won by registration order. Adapter/vocabulary installation occurs between frames; semantic updates apply even when vocabulary is unchanged. Supply Lorcana evidence and measured camera support through this path. |
| [`GameCatalogAdapter`](../../TradingCardScanner/Games/Core/GameCatalogAdapter.swift), `Services/CardCatalog.swift` | Resolved, printing-choice and incomplete outcomes, prepared identifiers, generation checks, bounded caches and request coalescing already exist. Explicit retry rebases evidence; a user's physical-printing selection is not a default cached for the footer. Lorcana schema-1 remains incomplete; schema-2 locally injected reviewed records may resolve exactly or require physical choice. No real physical seed is activated. |
| [`ResolvedCatalogCard`](../../TradingCardScanner/Models/ResolvedCatalogCard.swift), `PhysicalPrintingCandidate` | Generic exact-printing metadata, finish evidence and stable game/printing/finish ownership keys are available. Allocate reviewed Lorcana physical UUIDs; a family ID, provider print ID or artwork URL cannot substitute for one. |
| `Services/UnresolvedScanStore.swift`, `Views/ScannerViewModel.swift`, `Views/ScanSessionOverlays.swift` | Versioned generic evidence, read-only recovery without a module, explicit printing choice and subsequent finish resolution are available. Reuse the compact choice bar/Details comparison, including unavailable-artwork and insufficient-distinction safeguards. Keep recovery encounter identity separate from footer suppression and ownership. |
| [`GameBrowseAdapter`](../../TradingCardScanner/Games/Core/GameBrowseAdapter.swift), [`GameImportAdapter`](../../TradingCardScanner/Games/Core/GameImportAdapter.swift) | Lorcana supplies local reviewed-printing sets/search/details, generation/scope-bound cursors, exact CSV validation and metadata. New-game imports require an installed validator; a writable descriptor alone is insufficient. |
| `GameCatalogSnapshot`, `GameCatalogActivationSource`, [`CollectionAuthorizedActivationSource`](../../TradingCardScanner/Games/Core/CollectionAuthorizedActivationSource.swift) | Publish one immutable catalog/recognizer/variant/Browse/import/price-authority snapshot. The container-bound wrapper installs collection validation and saves managed-price withdrawals before publishing; revisions and retired storage sessions are guarded. Lorcana publishes catalog, recognition, variants, Browse and import from the same registry through this boundary. Pricing remains a later slice. |
| [`GamePriceAdapter`](../../TradingCardScanner/Games/Core/GamePriceAdapter.swift) | Exact resolved and stored-printing refresh paths, provider-fallback policy and activation validation exist. Use reviewed Lorcana mappings and `GameCatalogPriceAuthority`; One Piece's TCGCSV joins and source policy are not transferable mappings. |
| [`SignedCatalogReleaseStore`](../../TradingCardScanner/Services/SignedCatalogReleaseStore.swift), [`SignedCatalogUpdateClient`](../../TradingCardScanner/Services/SignedCatalogUpdateClient.swift) | Shared two-slot persistence and bounded conditional HTTPS transport are implemented. Lorcana now wraps them with its own envelope, canonical encoding, verification/transition/recovery rules, namespace and explicit ephemeral debug seed kit. Real reviewed seed, production pins/hosting/bootstrap and performance acceptance remain open. |

Pokémon and Magic catalog lookup now lives under their game modules. Legacy
Browse/import extraction and signed legacy runtime activation remain incomplete.
The read-only `scripts/audit_game_boundaries.sh` run on 2026-10-05 fails on eight
Pokémon/Magic case labels, all in `Services/BrowseCatalog.swift`; it does not prove
the whole shared architecture is finished and its current pattern does not scan
for `.lorcana` cases. Lorcana must use the adapter branch already present in
Browse and add no central cases. Finishing unrelated legacy migration is not a
prerequisite for the next bounded Lorcana slice. The
[documentation reconciliation](documentation_audit.md) and
[One Piece ledger](one_piece_code_implementation.md) retain their own scope and
dated evidence; earlier worktree/uncommitted descriptions are historical relative
to this source review.

[Lorcast's card API](https://lorcast.com/docs/api/cards) documents string collector
numbers, language, layout, set identifiers and `unique=prints`; its default
search grouping removes gameplay duplicates. Those provider fields are separate
from reviewed printed-footer evidence. Its normal/foil price fields do not prove
the complete set of supported physical finishes. The [set API](https://lorcast.com/docs/api/sets)
documents set codes and release metadata, and warns that pagination may be added.
These documents were read on 2026-10-04; no live corpus or release completeness
was validated for this slice.

## Slice 1: local print-family identity and recovery — implemented

The current code implements this bounded research path:

```text
explicit normalized local manifest
  → validated immutable Lorcana registry
  → complete footer evidence in one OCR observation
  → generic ScanIdentifier (printed-footer)
  → local print-family summary or unknown
  → catalogIncomplete
  → existing unresolved snapshot/recovery
```

`Games/Lorcana/LorcanaCatalogRegistry.swift` owns schema-1 manifests, validated
printed identities, source aliases and provisional family metadata. Numerator,
denominator/token, language and printed marker are separate strings. Premium
numerators may exceed the denominator; denominators and release tokens have no
hard-coded `/204` or set-number horizon. Rarity and layout remain open strings.
Family evidence keys are reproducible lookup keys, **never ownership keys or
physical UUIDs**, and do not imply gameplay equivalence across reprints.

Reject unsupported schema versions, invalid fields, duplicate footer identities,
reused provider aliases and oversized inputs. Require a footer mapping reference;
its presence records a review claim, not verified physical authority. Derive the
generation from normalized manifest content so metadata changes invalidate stale
lookups; ordering of families and aliases does not change that generation.
Lookup and vocabulary-scope validation use immutable dictionaries.

`LorcanaRecognitionAdapter` accepts the narrowly supported contiguous format
`number/denominator LANGUAGE marker` within one valid ROI-relative observation.
It does not combine fragments from unrelated lines, infer English, use names to
repair numbers or globally rewrite OCR text. Numeric `O/I/L` repair requires a
known language/marker scope; denominator repair additionally requires a matching
catalog numeric denominator and never rewrites an existing literal promo token.
Two distinct footer identities, including unknown numbers/markers/languages,
produce ambiguity; repeated identical evidence deduplicates. A complete unknown
footer remains recoverable evidence, without a closest-match fallback.

`LorcanaCatalogAdapter` validates the full payload, display and suppression key.
Lookup is pinned to the content generation. Explicit retry can rebase the same
printed evidence; unexpected fields or tampered evidence are rejected. All
families remain provisional physical evidence, so lookup returns
`catalogIncomplete(summary)` or `catalogIncomplete(nil)`. It never manufactures
an exact card or physical choice from a provider family ID.

`LorcanaGameRuntime` plugs into existing registration with research scan
capability only and an empty variant policy for schema-1. The schema-2 follow-up
supplies only reviewed eligible finishes. Production `appDefaults` does not
register it. The standard descriptor supplies a display name only. Browse,
pricing, import enrichment, sealed products and collection writes stay disabled.
No schema changes to collection or unresolved records, provider requests, signed
seed, production configuration, keys, image redistribution or UI framework are
part of this slice.

### Slice 1 recorded acceptance — 2026-10-04

- [x] Local manifest and content-derived generation; duplicate mappings fail closed.
- [x] Set code / marker separation, numerators above denominator, alternate denominators and promo tokens.
- [x] Generic runtime and catalog integration without central game switches.
- [x] Conservative complete-footer parser, ambiguity, unknown evidence, literal promo tokens and invalid geometry handling.
- [x] Generic recovery with installed module and read-only recovery without it; stale lookup and retry validation.
- [x] Production defaults, write capability, finish lock and pricing remain unavailable.
- [x] Focused app/test target checkpoint: 44/44 tests pass, including 13 Lorcana cases.
- [x] New plan links and whitespace checks; pre-existing missing audit/artifact links remain outside this slice.

These are fixture contracts. They do not prove real card accuracy, orientation,
ROI coverage, split-line OCR, printed separators, physical-size detection,
source completeness, device performance, rights or CloudKit compatibility.

## Remaining execution plan

Prioritize one reviewed local end-to-end slice after the existing research
checkpoint. Build source evidence and exact physical resolution first, then wire
activation and local ownership/Browse/import through the existing adapters.
Public delivery, whole-corpus coverage and optical classification are separate
milestones. Explicit local ownership review must use isolated local storage;
production/shared-sync writes remain disabled until their own acceptance gates
close. A local test capability is not authorization to enable production.

### Slice 2: reviewed source corpus and exact physical resolution

- [x] Recheck provider contracts when implementation starts. Add bounded Lorcast
  DTO/normalization using all-print results, pagination/continuation detection and
  retained response provenance. Keep provider set codes separate from reviewed
  printed footer mappings. Reuse capture/replay mechanics where appropriate;
  One Piece's Bandai/Limitless parsers and package rules are not Lorcana contracts.
  The 2026-10-12 implementation adds offline card/set DTO normalization and a
  bounded capture tool with raw-body receipts, all-print queries and fail-closed
  continuation/envelope detection. Four retained responses contain 31 card rows
  and 26 provider set rows; 60 focused simulator tests pass, including 12 new
  ingestion cases. Provider ingestion
  does not promote these observations into verified physical records.
- [ ] Establish a small permitted real corpus: ordinary normal/foil pair, premium
  numerator, cross-set reprint, promo/stamp ambiguity, landscape Location,
  same-footer standard/oversized ambiguity and Quest/special-layout records.
  Unsupported classes stay explicitly incomplete. Maintain a separate inventory
  of releases/classes still to reconcile; fixture coverage or a provider set list
  cannot close physical-universe completeness.
  The 2026-10-12 supplied reference package is retained in the
  [real-card corpus](../research/lorcana-real-card-corpus/README.md). Its offline
  structural validator passes, but no specimen photographs, reviewed physical
  UUIDs or authorized finishes exist; this checkbox remains open.
  The [minimum physical acceptance batch](../research/lorcana-real-card-corpus/minimum-acceptance/README.md)
  adds 12 unapproved specimen slots and maps all 25 runtime scenarios. Local
  replay passes 23 offline checks and 16 Python precheck tests, with 0/12 approved
  packets and 0/25 iOS scenarios executed. This is acquisition preparation only.
- [x] Extend the research data model with reviewed canonical relationships,
  permanent app-owned physical UUIDs, artwork/distribution/stamp/size distinctions,
  retained aliases, corrections and per-printing finish evidence. Schema-1
  families remain provisional; promotion needs an explicit versioned contract and
  transition validation. Preserve prior footer recovery rather than rekeying it
  as an owned card or treating a provider alias as a permanent UUID.
  Schema-2 now implements this contract and previous-registry transition checks;
  all test review claims are synthetic. Real reviewed physical records remain
  part of the unchecked corpus gate above.
- [x] Extend `LorcanaCatalogAdapter` to produce `needsPrintingChoice` or exact
  `ResolvedCatalogCard` only from verified physical records. Unreviewed,
  conflicted, missing-finish or incomplete candidate universes cannot establish
  uniqueness. Same-footer standard/oversized records need additional evidence or
  explicit distinction; complete footer evidence alone does not establish size.
  Singleton oversized records also ask for explicit size choice. Current
  acquisition and exact candidate/metadata validation reject stale or tampered
  evidence; indistinguishable alternatives remain incomplete.
- [x] Supply evidence-backed `LorcanaVariantPolicy` options and override
  `validateVariantCorrection(printingID:variantID:)` against the exact installed
  printing. A game-wide finish menu does not validate every printing. Reuse the
  existing printing choice followed by finish selection; optical foil inference
  is not required for this milestone.
  The menu uses reviewed eligible finishes, while corrections validate the exact
  printing. Synthetic normal/foil/stamp/size fixtures validate these boundaries;
  no production finish evidence is inferred from Lorcast prices or rarity.

**Exit evidence:** retained source/footer/finish claims replay deterministically;
UUIDs survive regeneration and alias/metadata updates; recognition reaches
verified choice → supported finish → exact resolution. Tests reject false
uniqueness, ambiguous size/stamps, contradictory finishes, tampered/stale choices
and cross-game collisions. The existing unknown-footer/read-only recovery
contracts continue to pass. Collection writes and prices are still independently
gated.

### Slice 3: signed local activation and coherent runtime publication

- [x] Define the Lorcana signed contract, bounded payload, canonical bytes,
  key namespace, revision/content collision policy and protected identity/finish
  corrections. Wrap the existing shared store/client; retain independent domain
  paths, verification and fallback rules. Create an explicit debug local kit with
  an ephemeral review key and validated seed. Production defaults remain disabled.
  Release schema 1 carries the physical schema-2 manifest; canonical payload and
  pin ID define equal-revision content after independent signature verification.
  Durable transitions retain UUIDs/evidence/finishes; supersession requires a new
  reviewed UUID and retained correction history. Recovery validates against the
  verified predecessor or seed. The debug kit requires a supplied manifest and
  isolated cache root; synthetic fixtures do not establish real seed acceptance.
- [x] Add a Lorcana coordinator implementing `GameCatalogActivationSource` and
  publish `GameCatalogSnapshot` values from one immutable registry. Bind through
  `CardGameRuntimeContainer.bound(to:isCurrent:)`; let its collection-authorized
  wrapper install authority before scanner, Browse, normalization or pricing sees
  the next generation. Avoid parallel screen-specific activation subscriptions
  that bypass this boundary.
- [x] Install recognition semantics/vocabulary between frames through the
  current scanner path. Reject in-flight old-generation catalog results and
  physical choices; explicit retry may rebase the same footer but must ask again
  when printing evidence changes. Clear/rebase affected Browse cursors and import
  metadata through existing activation consumers.
  Existing scanner activation is reused; Lorcana tests cover bound publication,
  metadata-only generations, stale completions/choices and explicit recovery
  retry. No new scanner dispatch cases were added. Slice 4 adds coherent local
  Browse/import snapshots; production rollout remains gated.
- [ ] Accept the real reviewed seed and measure selected-corpus activation
  time/memory; capture rendered review/device evidence. The code foundation and
  synthetic tests do not close these acceptance gates.

**Exit evidence:** invalid signature/schema, rollback/revision collision,
interrupted writes, previous-slot recovery, concurrent updates and metadata-only
generation changes fail or recover deliberately. Same-container rebinding and
storage-session retirement cannot install stale authority. Startup is offline
with the validated local seed. Measure activation time/memory on the selected
corpus; shared transport tests do not replace Lorcana contract tests.

### Slice 4: local ownership, Browse and import/export acceptance

- [x] Implement `LorcanaBrowseAdapter` and `LorcanaImportAdapter`; attach them to
  the runtime and activation snapshot. Browse uses verified physical targets;
  gameplay completion and physical-printing completion remain distinct. Import
  validates exact UUID/reviewed alias, footer/language, raw item kind, supported
  finish and ownership key before writes, using current runtime import adapters.
  Local rails count reviewed physical printings, not whole-set gameplay coverage.
  Import writes require an explicit exact UUID; a reviewed source alias can
  enrich metadata only when accompanied by that UUID. Duplicate CSV keys retain
  conflicting identity evidence, including in failed-row re-exports, rather than
  silently merging it away. Unknown supplied raw item kinds remain available to
  the validator before legacy enum projection.
- [x] Exercise the existing container-scoped collection authority and transaction
  guards for scan, printing/finish correction, Browse add/undo, CSV,
  normalization and recovery. Missing adapters, withdrawn capabilities or
  quarantined printings must reject mutation without changing ownership/history.
  Preserve readable unknown-game/finish rows when the module is unavailable.
  The catalog adapter supplies a synchronous final mutation validator; collection
  commits and CSV transactions recheck installed container authority before save.
  Deterministic cases cover scan printing/finish acquisition, finish correction,
  add/undo, quantity changes, stale CSV adapters, missing catalog authority and
  withdrawn write capability. Physical fixtures cover held/unreviewed universes;
  forward-compatibility tests retain unavailable-module rows. Real mixed-client
  acceptance remains open; bounded synthetic rendering is recorded below.
- [x] Enable `.collectionWrite` only in the explicit isolated local review setup
  once these contracts pass. Use stable game + physical UUID + finish keys;
  adding a finish or changing a market alias must not split existing ownership.
  Recovery export/retry remains available when exact resolution is incomplete;
  resolving one encounter must not remove another copy's recovery row.
  `LorcanaLocalReviewKit.make(...allowCollectionWrites: true)` requires subsequent
  checked container binding; the public unbound runtime remains read-only.
- [x] Verify local scan/choice/finish/save, disk-backed storage relaunch,
  Browse/add/undo and CSV round-trip against the same reviewed registry.
- [x] Render the existing compact choice/Details and finish flows on phone/tablet
  and large text; inaccessible artwork or identical labels cannot permit an
  unsupported selection. The [debug UI review route](../research/lorcana-ui-review.md)
  is now implemented with isolated persistent collection/recovery/cache storage,
  an ephemeral synthetic seed and real scanner callback injection. Its sample
  menu reaches size/stamp choices, finish selection and incomplete outcomes.
  The 2026-10-13 synthetic portrait simulator pass covers both form factors,
  default light and accessibility dark layouts, explicit printing/finish actions,
  incomplete recovery and local ownership. An accepted physical seed, spoken
  VoiceOver interaction and real-device/camera acceptance remain open.

#### Rendered UI checkpoint — 2026-10-13

Verified at `8613a1d` on `feat/lorcana-implementation` plus local changes in
DebugRemoteLocal. The [UI review checkpoint](../research/lorcana-ui-review.md)
records the complete matrix and evidence boundary. Dedicated iPhone 17 Pro and
iPad Pro 11-inch M4 simulators ran iOS 26.5; all eight fixture outcomes were
visually inspected. Accessibility-extra-large (AX3) dark captures confirm stacked,
reachable choices and wrapped mode/finish labels; phone choices remain reachable
through scrolling. Device rotation and spoken VoiceOver were not accepted here.

Fixed camera/Details contrast, title and control truncation, explicit oversized
labeling and neutral incomplete-resolution copy. A rendered first-save failure
also exposed a launch-projection/revision-monitor baseline race; a loaded stale
projection now reconciles on first observation. The iPad first save updates
Collection/Browse without relaunch. Standard/Foil save and immediate scan Undo,
Browse Normal add/Undo, repeated-card suppression, retained unresolved encounters/retry and
review-store relaunch were exercised through the existing app surfaces.

Final `accessibility-final-tests.xcresult`: **204 passed, 0 failed, 0 skipped**,
verified with `xcresulttool`; a QoS priority-inversion warning is recorded. This
is scoped regression evidence, not a new full-suite or performance baseline.
External SSD evidence: `CodexBuilds/LorcanaUIAcceptance-20261013/`, including the
final device state directories, Details/ownership/recovery captures and success
checklist. Earlier launch-transition/finding frames are historical diagnostics.

Real physical seed/corpus approval, camera and device acceptance, spoken
VoiceOver, production signed activation, mapped live pricing/provider rights,
CloudKit/mixed-client and release gates remain open. The synthetic route has no
approved market mappings; readable unavailable pricing does not close Slice 5's
real mapped/unmapped pricing acceptance.

**Exit evidence:** deterministic storage/recovery and import tests plus rendered
local interaction/relaunch evidence for representative base cases. Record real
camera, VoiceOver, device and mixed-client gaps separately. Sealed products,
graded support and shared-sync production writes remain independently gated.

### Slice 5: exact pricing through the current shared authority

- [x] Select a permitted provider and review exact physical-printing/finish,
  currency and condition or aggregate-price joins. Provider price columns are
  neither finish authority nor proof of a complete market mapping. Do not inherit
  One Piece's TCGCSV provider choice or promote Lorcast family prices to all
  corresponding physical UUIDs.
  Completed for the owner-authorized public-reference ordinary scope across
  expansions 1–8 using TCGCSV's documented public access. Card-in-hand verification,
  premium/promo/Quest/later-set mappings and publication/asset rights remain
  separate gates; [the rollout checkpoint](../research/lorcana-normal-pricing-rollout.md)
  records the exact reviewed join policy.
- [x] Implement `LorcanaPriceAdapter` for resolved and stored-printing refresh;
  withhold unmapped prices and disable name/number fallback. Register `.pricing`
  separately, with mappings in `GameCatalogPriceAuthority` and catalog mapping
  fingerprints on managed quotes. Use the runtime's activated price wrapper for
  pre/post-request validation and persisted withdrawal before new activation.
- [x] Cover Price Check, scanner post-save quotes, Browse detail/add and collection
  refresh. Changed/withdrawn mappings reject cached and in-flight quotes; manual
  values remain intact. Preserve feed receipt times and bind caches to reviewed
  catalog semantics when needed. No capability means no provider requests.
- [x] Execute the bounded mapped/unmapped live-provider workflow through existing
  Price Check, scanner save, Browse and collection refresh, including relaunch,
  cache receipt reuse and persisted mapping withdrawal. Source review and live
  results are separate from physical-camera/device and production acceptance.

**Exit evidence:** one reviewed mapped base case and one unmapped/special printing
save and refresh independently, including relaunch and mapping withdrawal.
Deterministic tests and permitted live-provider evidence are recorded separately;
One Piece's price/UI checkpoint is not Lorcana evidence.

#### Pricing code checkpoint — 2026-10-13

Implementation on `feat/lorcana-implementation` at `8613a1d` plus local changes:

- Optional `marketMappings` on schema-2 physical printings preserve decoding and
  canonical signed bytes for older unmapped catalogs. Each mapping records an
  exact product ID, group, title, marketplace Number, selected finish/lane,
  US/USD aggregate scope and review references. Mapping edits change the catalog
  generation and price fingerprint without changing physical UUIDs or ownership.
  Duplicate active product/finish lanes, unsupported scope and incompatible
  physical finishes are rejected.
- [TCGCSV](https://tcgcsv.com/) documents public product/price feeds and explicitly
  excludes condition-specific SKU data. Independently inspected category **71**,
  group **22937** products/prices on this date contain `Normal`, `Cold Foil` and
  `Holofoil` lanes. The Lorcana join uses the explicitly reviewed lane; generic
  `foil` does not infer which market lane applies. Product 510153's `207/204`
  Number and Holofoil row verify the feed contract, not a physical UUID mapping.
- `TCGCSVProductPriceSource` reuses One Piece's bounded transport, pacing,
  coalescing, daily disk cache, failure backoff, generation scope and withdrawal
  watermark. Category/group cache keys keep games separate. Existing unscoped
  One Piece cache files are refreshed once rather than promoted into the shared
  cache. Feed receipt times remain unchanged on reuse; no source-update timestamp
  or condition-specific price is invented.
- The physical runtime registers `.pricing` separately from collection writes;
  `pricingEnabled = false` suppresses the adapter/capability. Schema-1 families
  and pure source-only discovery cannot request physical prices. Normal app
  discovery now composes the reviewed physical catalog. Unmapped exact printings
  and finishes return unavailable without provider I/O or name/number fallback.
- Signed snapshots publish `GameCatalogPriceAuthority`. Container binding saves
  withdrawals before new catalog publication; mapping fingerprints and current
  physical resolution reject changed/withdrawn in-flight quotes. PriceStore and
  reference-quote withdrawal preserve manual imported values.

The later normal-workflow checkpoint expands the mapping/provider slice beyond
Hades. Unsupported classes, physical-device acceptance and production rights
remain open. A market-bearing signed payload requires this updated reader; older
readers fail canonical verification rather than silently dropping its mappings.
Production activation and mixed-client acceptance remain separate gates.

**Verification:** Debug build and 125 Lorcana/Lorcast plus 88 One Piece simulator
tests pass on iPhone 17 Pro / iOS 26.5, including 13 new Lorcana pricing cases.
Shared pricing, quote-cache and refresh lifecycle tests also pass. The broader
selection executed 322 cases: **321 passed, 1 failed, 0 skipped**. The unchanged
`PokemonTCGCSVPriceTests.testBrowseDetailsRetainSupplementalQuoteAndProvenanceWhenOffline`
fails with `unknownSet`, also reproduced when selected alone. This is not a
green full-suite baseline. Build data, results and public-feed captures are
external under `CodexBuilds/LorcanaPricing-20261013/`; the broad result is
`regression-4.xcresult` and isolated failure is `pokemon-isolated-5.xcresult`.
This earlier code checkpoint did not claim real mappings or rendered/live pricing.
The public-reference checkpoint below supersedes that gap only for its bounded
local seed. Physical-device, CloudKit, production signed activation and release
acceptance remain open.

#### Public-reference live pricing checkpoint — 2026-10-13

At `8613a1d` plus local changes on `feat/lorcana-implementation`, added a separate
DebugRemoteLocal `LorcanaPricingReview` seed/store, with two explicit market lanes
for one standard Hades UUID. Publisher footer/artwork/finish/size sources and
TCGCSV category/group/product/Number evidence were reviewed independently of
price amounts. Standard and oversized share the known footer but remain distinct
physical IDs; oversized has no mapping in this slice. The owner authorized
public online evidence; no card-in-hand measurement or two-person specimen
approval is claimed. See [the review and replay](../research/lorcana-pricing-review.md).

Live TCGCSV retrieval passes the existing adapter/price authority, Price Check
without ownership, scanner post-save quote, Browse detail, collection refresh,
disk-backed relaunch/receipt reuse and mapping withdrawal without ownership loss.
Actual receipt observations were **$0.19 Normal / $0.35 Cold Foil**, USD aggregate;
they are dated evidence, not constants in the implementation. The expiring,
seed-bound test opt-in is removed after acceptance; a separate no-opt-in replay
skips as intended. Final `live-final.xcresult` is verified with `xcresulttool`:
**86 passed, 0 failed, 0 skipped**, with two internal QoS warnings. Rendered phone
Price Check, scanner quote, Collection/Browse, withdrawal and restored refresh
pass; tablet choice rendering is inspected but its pricing taps did not advance.
This is a focused live/local checkpoint, not a full-suite or device certification.

Evidence is external at `CodexBuilds/LorcanaLivePricing-20261013/`; Xcode's
post-test finalization took about ten minutes after all cases passed. At this
historical checkpoint default discovery remained unpriced. Its source IDs still
cannot become physical ownership keys. The retained physical-corpus scenarios, production rights/keys/activation,
spoken VoiceOver, camera/device, sync and release gates remain open.

#### Normal-workflow expansion checkpoint — 2026-10-13

The [offline builder](../../scripts/build_lorcana_market_catalog.py) and persistent
[UUID ledger](../../TradingCardScanner/LorcanaCatalogSeed/physical-id-assignments.json)
promote exact English ordinary joins into the bundled `market.json`. Normal
registration combines its physical authority with existing discovery and sealed
inventory. Scanner resolution, Browse summaries/details and collection writes
use the same physical UUID; source IDs never gain mutation authority. Footer,
title, marketplace Number/group and both exact finish lanes must agree. Source
collisions and qualified product siblings remain held. Amounts do not determine
the supported finishes, and no fuzzy pricing fallback is added.

Live normal-runtime acceptance obtained **16 exact USD quotes across eight sets**,
then saved eight foil rows and refreshed them through the common collection
worker. The 260-case pricing/ownership/catalog/activation/One Piece regression
passes, followed by a 100-case Lorcana/Browse replay and a 66-case Browse replay
after the rendered held-printing fix; each has zero failures/skips. These are
overlapping scoped runs, not additive full-suite totals. Twelve Python source
builder tests pass. See the rollout checkpoint for final rendered/build evidence
and receipt paths. Normal iPhone and iPad Browse display both price lanes and save
the chosen finish into ordinary Collection; relaunch preserves copies and quotes.
Held details disable Add and display unavailable pricing. Native Device Hub
controls completed iPad interaction after semantic simulator taps failed.
The final relaunch pass also fixed shared empty automatic refresh queues leaving
an updating indicator visible: queue ownership now publishes its lifecycle, with
a regression for the idle-to-idle completion. Phone/tablet relaunch and explicit
tablet refresh render cleanly without changing pricing or freshness policy.
The finalized post-fix bundle confirms 239 passing cases, zero failures and two expected
live-opt-in skips; the earlier live replay passed before the opt-in was removed.
Debug build-for-testing and arm64 ReleaseLocal rebuild pass. The bundle has one
internal QoS warning; its finalization took about ten minutes after the cases ended.
The prior isolated Pokémon `unknownSet` failure was closed in the later
[production checkpoint](../release/lorcana-production-acceptance.md): the fixture
now includes its requested card in its set, with 25/25 Pokémon TCGCSV tests passing.
The production membership guard is unchanged. This is not full-app certification.

### Slice 6: measured camera support, broader coverage and production gates

- [ ] Measure actual footer ROI, orientation, separators, typography and
  split-token association on real reference observations and devices. Extend the
  Lorcana recognizer only with deterministic spatial evidence; preserve unknown
  complete footers, conservative numeric repair and cross-game ambiguity.
  Parser fixtures cannot prove camera capture accuracy or landscape support.
- [ ] Expand release/product/promo/Quest/oversized coverage with explicit held
  discrepancies, reviewed physical evidence and rights. Treat research timelines,
  set counts and hypothetical serial fields as background requiring fresh review.
  Add optical ranking/stamp/foil assistance only after measured benefit; explicit
  printing and finish selection remain the usable base path.
- [x] Register the owner-authorized bundled ordinary catalog in the normal app,
  with per-printing ownership/import/price validation and unchanged storage models.
- [x] Build actual iOS archives and verify bundled catalog/privacy resources;
  strict development signature verification and development IPA export pass.
  Unsigned Release and development-signed ReleaseLocal are packaging evidence,
  not distribution/TestFlight acceptance.
- [x] Close the known Pokémon Browse supplemental-quote regression and run local
  storage/schema/forward-compatibility checks; see the production checkpoint for
  finalized counts and skipped hardware/live assertions.
- [ ] Complete release-candidate physical-device camera/performance and spoken
  VoiceOver acceptance. No physical cards are currently available; the paired
  iPhone was locked. Simulator evidence does not close these checks.
- [ ] Complete publication/asset-rights review and distribution/TestFlight acceptance.
  Unsupported printings remain held.
- [ ] **Deferred by owner — 2026-10-14:** deploy and verify app privacy/support
  pages, configure verified build URLs and reconcile App Store Connect URLs. Current
  `/privacy` covers only the website/waitlist and `/support` returns 404; the
  submission build URLs remain empty. Unsupported printings remain held.
  The 2026-10-14 self-contained upload package and Bluehost walkthrough are
  prepared and browser-checked; publication/live verification and URL configuration
  are paused until the owner resumes this step.
- [x] Execute full simulator regression and final corrected provider/parser/scanner
  replay; the finalized 2026-10-14 complete target passes 2,188 cases with 12
  skips and zero failures. The checkpoint retains earlier failures and setup replay.
- [x] Fix the reproduced simulator centering timing failure without weakening
  the existing contract: native scalar loops/median sorting retain exact fixture
  geometry/profiles and unchanged resolution/thresholds. REQ-022 passes 0.8/1.5 s
  limits. Physical-device latency remains part of the unchecked hardware gate.
- [x] Prepare a normal-workflow reviewer path that requires no physical cards;
  this handoff does not imply App Store submission or camera acceptance.
- [x] Revalidate every enabled printing/finish through fresh provider feeds:
  3,232 priced lanes across eight sets, zero unavailable/mismatched. Retain the
  opt-in full-matrix test and exact catalog/UUID replay evidence. Fresh retrieval
  does not imply real-time market data or authorization for held printings.
- [x] Run local distribution-export preflight without portal changes/uploads;
  record the missing distribution profile. This completes the check, while
  obtaining a distribution-signed candidate and TestFlight acceptance remain open.
- [ ] Before a future sync release, complete mixed-client CloudKit acceptance.
  This is deferred for current on-device 1.0; no sync activation or schema change
  was made. Minimum-version metadata alone is not CloudKit enforcement.
- [ ] Configure dedicated keys and hosting/update delivery if remote signed
  catalog updates are enabled. The bundled catalog does not depend on this work;
  do not invent credentials or silently enable unsigned remote updates.

**Exit evidence:** dated Lorcana corpus/camera/provider/device and ownership-policy
acceptance with explicit unsupported classes, followed by archive/release checks.
Keep full-suite regression separate from targeted checkpoints. Use an external
SSD for build artifacts when available; current iOS archives and tests are
recorded in the production checkpoint. Remote delivery and live sync are not
prerequisites for the current bundled, on-device release.

## Verification evidence and limits

### Local ownership, Browse and import checkpoint — 2026-10-12

At `9d7c780c` plus local changes on `feat/lorcana-implementation`, completed the
partly implemented Slice 4 adapters, runtime/snapshot integration and checked
debug collection binding. Browse exposes only acquirable reviewed physical UUIDs
with distinct labels and exact printing completion. CSV validates physical UUID,
supplied footer/language and raw item kind, finish and ownership key. Duplicate
keys preserve conflicting source evidence across merge and failed-row export.
The final container catalog guard protects collection and CSV saves even when
an earlier lookup or import validator used a stale registry.

Final app/test builds pass. The 253-case selected regression run passed 252 cases
and failed one new test assertion that incorrectly expected normalization to
replace an imported set name. Normalization supplies catalog ID and set code;
the corrected assertion verifies those fields. After rebuilding, all 13
`LorcanaOwnershipTests` pass with no failures/skips. The other 240 selected cases
already passed and were not repeated: 24 Lorcana activation (including new
coherent Browse/import activation coverage), 22 physical, 13 integration,
31 forward compatibility, 35 Browse collection, five CSV resume, 32 activity
history, 26 item kind, 11 collection key, 17 collection continuity, 16 imported
item kind and eight One Piece import/normalization regressions. Together these
runs provide passing evidence for 253 distinct selected cases, not a single
253/253 final replay or a full-suite checkpoint.

Ownership cases exercise scanner printing → finish → save with independent
recovery encounters, exact Browse add/undo, unsupported finish rollback,
disk-backed CSV save → normalization → relaunch → export/import, pagination
scope/generation changes, incomplete catalogs, finish correction, quantity/history
preservation after authority withdrawal, missing adapters and read-only binding.
All physical records and review claims remain synthetic.

Used `TradingCardScanner-ProfileLocal` / `DebugRemoteLocal` on the isolated iOS
26.5 QA simulator. Derived data, package cache, build logs,
`ownership-regressions.xcresult` and `ownership-final.xcresult` are under the
external SSD's `CodexBuilds/LorcanaImplementation-20261012/`. Simulator startup
delayed the first focused run; it subsequently passed all 12 initial cases.
Final fixture setup creates its own store directory before opening SwiftData.
The saved results retain an internal QoS warning; these runs are not device or
selected-real-corpus performance evidence.

Rendered phone/tablet/large-text and VoiceOver flows, the real reviewed seed,
camera/corpus/performance, provider/rights/hosting/keys, exact pricing, production
ownership/CloudKit and release acceptance remain open. Production app defaults
still omit Lorcana. No commit or push was made.

### Signed local activation checkpoint — 2026-10-12

At `9d7c780c` plus local changes on `feat/lorcana-implementation`, added the
Lorcana signed release, canonical bounded payload, independent pins/paths,
protected durable transitions/recovery, shared conditional transport wrapper,
coherent activation coordinator and explicit ephemeral debug seed kit. Scan-only
runtime injection binds through the existing collection-authorized source.
Supersession retains old UUIDs/evidence and never migrates ownership automatically.
See the [signed contract](../research/lorcana-signed-activation.md).

The final app/test build and 129/129 selected simulator cases pass with no
failures/skips: 23 new Lorcana activation, 22 physical, 13 integration, 12 source,
31 forward compatibility, four suppression, eight shared store, five shared
transport and 11 One Piece activation regressions. Cases cover invalid signatures,
canonical/schema/time/byte bounds, revision collisions/rollback, protected
identity/finish corrections, interrupted writes/recovery, concurrency, metadata
generations, container rebinding/retirement, stale completions/choices and actual
scanner/recovery callbacks. The result records one internal QoS warning in the
write-fault test; it does not establish selected-corpus/device performance.

Used `TradingCardScanner-ProfileLocal` / `DebugRemoteLocal` on the isolated iOS
26.5 QA simulator. Derived data, dependency cache, temporary build data, full and
selected prepared packages, build logs and `activation-final.xcresult` are under
the external SSD's `CodexBuilds/LorcanaImplementation-20261012/`. The selected
package omits only unused centering/Magic/CSV test resources, retaining all app
resources, Lorcana fixtures and compiled code. Original package symlinks and
executable text sections were verified after ad-hoc signing. The full package
and omitted source fixtures remain intact.

The first build found missing `try` annotations in test fixtures. Several launch/
install attempts then failed before executing tests due to internal simulator
storage or its leftover install placeholder. Task-generated prior app bundles
were preserved on the SSD. An attempted external relocation of QA runtime data
was denied by macOS; its original directory was restored and boot verified.
The placeholder was removed after backing up matching QA app data, which was
restored to the reinstalled app. A shutdown cleared temporary speech cache before
the planned cache move, so that move made no filesystem change. No simulator
erase or main-simulator change occurred.

The first complete replay passed 128 cases with one signature-round-trip fixture
failure: payloads matched while signatures differed. Equal-revision content now
compares the verified canonical payload and pin ID, and tests independently
verify re-signatures. The final replay passes all 129 cases. Production defaults,
real reviewed seed/corpus, rendered review launch, activation time/memory, device/
camera, rights/hosting/keys, ownership/Browse/import/pricing, sync and release
acceptance remain open. No commit or push was made.

### Local physical-contract checkpoint — 2026-10-12

At `9d7c780c` plus local changes on `feat/lorcana-implementation`, schema-2 adds
explicit canonical relationships, permanent physical UUIDs, protected physical
identity, retained aliases/evidence/corrections and previous-registry transition
validation. The catalog now returns exact resolution or physical-printing choice
from complete reviewed local universes, with per-printing finish validation.
Incomplete/conflicted/unreviewed universes and indistinguishable alternatives
remain incomplete; oversized acquisition needs explicit size choice. Known exact
verified UUIDs retain finish authority independently of footer discovery.

The app/test target builds and the final prepared-package run passes 82/82 cases
with no failures/skips: 22 `LorcanaPhysicalCatalogTests`, 13 Lorcana integration,
12 source normalization, 31 forward compatibility and four suppression tests.
The physical cases include real recognizer input, exact choice/finish resolution,
relaunch/missing-module recovery, metadata/alias/finish additions with stable
keys, stale/tampered choices, correction history and false-uniqueness rejection.
All physical evidence references/UUIDs in these cases are synthetic fixtures.
See the [local contract](../research/lorcana-physical-contract.md) for scope.

Used `TradingCardScanner-ProfileLocal` / `DebugRemoteLocal` and the isolated iOS
26.5 review simulator. Derived data, package cache, prepared packages, build logs
and `physical-final.xcresult` remain under the external SSD's
`CodexBuilds/LorcanaImplementation-20261012/`. The wrapper's first build hit
internal disk exhaustion while copying its test package; this task's partial and
earlier packages were preserved by relocation to the SSD. Direct/prepared runs
were interrupted during investigation of buffered output; one interrupted
prepared run had 52 passes and one canceled test. A later complete run had 81
passes and one fixture failure because textual JSON replacement did not mutate
an escaped footer. Decoded-field mutation corrected the fixture; the final
82-case run passes. The result retains one internal QoS warning, not device
performance evidence.

Project syntax, new/changed documentation links and whitespace checks pass. No
central game cases, new UI framework, collection schema changes, real physical
seed, production registration, ownership, Browse/import, pricing or signed
activation was added. Real corpus, rendered/device/camera, rights, sync and
release acceptance remain open. No commit or push was made.

### Bounded provider-ingestion checkpoint — 2026-10-12

On `feat/lorcana-implementation` at base `b1959c6` plus local changes, rechecked
Lorcast's API contract and captured four public metadata responses with exact
bytes and receipt digests. Added offline all-print card/set normalization,
continuation/envelope rejection, response/request bounds, literal collector
strings and duplicate/conflicting provider-identity validation. These
observations do not become physical records or confer footer/finish authority.
The [source checkpoint](../research/lorcana-source-corpus.md) retains the inventory.

The app/test target builds and all 60 selected simulator cases pass, with no
skips or failures: 12 `LorcastSourceNormalizerTests`, 13 `LorcanaIntegrationTests`,
31 `CardGameForwardCompatibilityTests` and four `ScanSubjectSuppressionTests`.
Used `TradingCardScanner-ProfileLocal` / `DebugRemoteLocal` on the isolated iOS
26.5 review simulator, with derived data and `source-checkpoint.xcresult` under
the external SSD's `CodexBuilds/LorcanaImplementation-20261012/` directory.
XcodeBuildMCP's post-run report parser could not write its internal log because
the internal disk was full; direct `xcresulttool` inspection confirmed the saved
bundle's `Passed` result and 60/60 counts. Its summary also records one internal
QoS warning; this is not a device performance checkpoint.

Capture-tool syntax, four receipt/body digests, documentation links, project
syntax and whitespace checks pass. Existing Browse/Collection edits are
preserved. No commit/push, production registration, new physical UUIDs, finish
policy, ownership, pricing or signed activation was added. Real footer/finish,
rights/publication, camera, device, CloudKit and release gates remain open.

### Current documentation/source review — 2026-10-05

Reviewed the Lorcana module and its 13 test cases, shared runtime/adapter contracts,
catalog/printing/recovery surfaces, collection-bound activation and the current
signed store/client. The expanded architecture script reports 37 existing game
branches across Browse and collection normalization; legacy extraction and full
manual switch review remain open. No Lorcana feature gate was closed. The One
Piece ledger's later selected checkpoints cover its own integration; they do not
supersede the Lorcana-specific checkpoint or establish Lorcana
camera/ownership/pricing acceptance.

### Historical first-slice simulator checkpoint — 2026-10-04

`/private/tmp/lorcana-first-slice-checkpoint.log` records 44 passing cases:
13 `LorcanaIntegrationTests`, 27 `CardGameForwardCompatibilityTests`, and four
`ScanSubjectSuppressionTests`. The `TradingCardScanner-ProfileLocal` scheme with
`DebugRemoteLocal` built and tested against the existing iPhone simulator, using
the external SSD derived-data cache. The initial attempt stopped before
compilation because newly added project object IDs collided with existing
transport references; unique Lorcana IDs corrected that integration error. The
successful checkpoint includes the literal-promo-token normalization safeguard.
No unchanged tests were repeated after this successful checkpoint.

No full suite or physical-device, real-camera, provider, CloudKit, archive or
release certification was performed. No production default registration, keys,
catalog seed or sync enablement was added.
