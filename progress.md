- Bulk intake Stage 0 (2026-10-07; `3fe972a` plus existing local changes):
  added the default-off, local, backup-excluded session metrics actor, ordered
  scanner event hooks and JSON ShareLink export in Settings → Scanning. The
  payload contains fixed outcomes, durations, interruptions and counters;
  runtime IDs, card names, prices and images are excluded. Unreadable evidence
  is preserved. Debug build and 118/118 selected simulator tests pass (4 new
  metrics-log, 97 scanner, 17 unresolved-store; no failures or skips), including
  dismissed-choice logging with baseline behavior unchanged. Build/test results
  use the external SSD at `TradingCardScannerDerivedData/bulk-intake-stage-0/`.
  Documentation links and whitespace checks pass. The
  [staged plan](docs/plans/bulk-intake-differentiation-plan.md) records the accepted
  later fixes; Stage 1 waits for the owner's pre-change device baseline. No
  physical-device, system share-sheet, provider, CloudKit or release acceptance
  is claimed. No commit or push was made.

- Cross-game scanner edge cases (2026-10-06; `412a09d` plus local changes):
  fixed explicit foreign Pokémon footer leakage into English recognition and
  secondary fallback, unknown Pokémon identity fields in live/recovery lookups,
  modern Magic future/missing/invalid printing metadata and provider-flagged
  oversized objects, and partially overlapping One Piece OCR bounds. Existing
  retro/multiface Magic, Pokémon subset/promo/collision rules, and One Piece
  alternate printing/finish/price/recovery behavior remain covered. Four focused
  tests, final Debug build-for-testing, and 619/619 affected simulator tests pass
  with no skips/failures, including all 27 historical Magic corpus references.
  A public French SVI footer was visually reviewed; this adds no physical-device
  or release acceptance claim. See the [dated edge-case report](docs/audits/scanner-cross-game-edge-cases-2026-10-06.md).

- Historical Magic edge-case review (2026-10-06; `412a09d` plus local changes):
  fixed excluded level-up cards (24 additional general titles), quoted names and
  old ligatures/typographic quotes. Same-title logical identities now remain
  separate exact choices, including B.F.M. halves. Unrelated recognized titles
  abstain; malformed ordinary provider rows fail incomplete rather than silently
  disappearing. Back-face/split aliases, suffixes/stars/leading zeroes, duplicate
  or truncated pages, changing totals and hydration drift have added regression
  coverage. The first provider replay caught Scryfall warnings from escaped
  embedded quotes; a warning-free query was verified for all three historical
  quoted names, with strict complete-name agreement retained. Final build,
  nine focused tests, 432/432 broader affected simulator tests (no skips/failures)
  and 22/22 Python checks pass. All 27 corpus titles/choices still pass; eleven
  captured provider searches resolve 29 exact printings through the shared catalog.
  New provider cases are metadata evidence, not new optical/device acceptance.
  See [edge cases and retained evidence](docs/research/magic-historical-corpus/edge-cases.md).

- General historical Magic scanning (2026-10-06; `412a09d` plus local changes):
  implemented the user's corrected scope, using the corpus as frame/layout
  references rather than adding individually activated cards. Normal raw/slab
  dispatch uses general OCR with 14,360 historical root/face titles, including
  title-only pre-Exodus, full-art, split/flip/transform, foil and planeswalker
  references. Complete current English paper printing searches drive explicit
  printing choice; collector OCR ranks without hiding alternatives. Encounter
  English confirmation, exact-ID hydration, refreshed choice membership and
  immediate pre-write checks preserve exact ownership/finish identity. Large
  printing families have native Details search. All 27 originals reach matching
  titles and printing choices without manual card framing or a per-card allowlist.
  An unlisted Counterspell fixture verifies the ordinary collection writer.
  Debug build-for-testing, 388/388 affected simulator tests (no skips/failures)
  and 22/22 Python checks pass. Three native search captures pass source/render
  HIG review, including accessibility3 wrapping. Static references do not certify live-camera or
  physical-device accuracy. Optional automatic index selection stays disabled.
  See [general implementation evidence](docs/research/magic-historical-corpus/general-scanning.md).

- Historical Magic corpus-backed OCR/save (2026-10-06; `412a09d` plus local
  changes): shared actual card-relative Vision requests between the local scanner
  pilot and private-corpus evaluator. Reconciled Survival of the Fittest `129/143`
  to its exact Exodus printing/current collision family, adding photographic
  visible-number evidence and a fourth dated complete key; retained 150 printing
  IDs and collision blockers. Hash-pinned staging keeps all original images on
  the external SSD and rejects changed/escaping/duplicate sources. Actual OCR on
  27 originals produces one calibrated positive and 26 scope abstentions. The
  normal scanner choice/writer saves its exact printing after English confirmation
  and writes nothing beforehand. Fixed the first run's duplicate source-receipt
  refresh defect with replacement/rerun coverage. Focused simulator 27/27,
  affected regression 316/316, Python 20/20 and Debug build-for-testing pass.
  Annotated framing/repeated stills do not certify held-out positive, independent
  camera-frame, live-provider acquisition or physical-device acceptance. Production
  remains disabled; broader frame templates are next. See the
  [corpus evidence and reproduction](docs/research/magic-historical-corpus/README.md).

- Historical Magic photographic corpus intake (2026-10-06; `412a09d` plus local
  changes): inspected the supplied sources-only archive without executing its
  embedded downloader; separately downloaded and decode-verified all 27 images
  on the external SSD. Visual review supports 20 photographic examples and seven
  clean-front controls. Recorded per-image hashes, preserved manifest labels and
  corrected the Unhinged Forest test-case assumption to black-border full-art.
  Survival of the Fittest has visible `129/143`, supplying an Exodus photographic
  review lead. Exact printing/face labels, held-out OCR evaluation and device
  acceptance remain open; no runtime/index changes or optical pass claims.
  See the [corpus review](docs/research/magic-historical-corpus/README.md).

- Historical Magic D integration (2026-10-06; `412a09d` plus local changes):
  reviewed three provider fronts for printed `number/143`; retained five complete
  all-era English/paper searches and seven exact-ID collision captures. Reconciled
  all 150 index identities, normalized Spanish/`es` and corrected PEXO's per-printing
  date before Exodus. Three dated key receipts expire 2026-10-07 UTC; outside-era
  and promo matches remain blockers. Added bounded same-frame OCR, historical
  namespace/profile pins, encounter-scoped English confirmation, exact hydration,
  printing choice, pre-save collision/activation checks and persisted recovery.
  Historical scanner/adapter production defaults remain off. Final selected
  regression passed 314/314 and Python importer/reconciliation passed 13/13.
  The real-store recovery recheck passed 10/10 after fixing identifier generation
  and correcting a fixture that bypassed held-card protection; exact row/finish
  keys remain unchanged. Evidence is retained on the external SSD under
  `CodexBuilds/MagicHistorical`. Final Debug build and standard/accessibility
  picker/Details captures pass the inspected UI checklist; English confirmation
  carries within an encounter and direct recovery applies the same gate. No known camera-photo folder is available;
  physical/device acceptance and broader plan gates remain open. See the
  [plan](docs/plans/magic_historical_recognition_plan.md) and
  [pilot report](docs/research/magic-historical-pilot/README.md).

- Historical Magic initial C index slice (2026-10-06; `412a09d` plus local
  changes): captured/hash-pinned dated MTGJSON AllPrintings/EXO and complete
  Scryfall EXO inputs on the external drive. Streamed 123,822 source rows into
  a full disposition ledger; source rows/faces are not a physical denominator.
  Bundled 143 exact-ID reconciled Exodus printings plus seven held cross-era
  collision records. Added dictionary lookup, explicit per-key all-era receipt
  membership/expiry/source-context checks and atomic compatible profile/index
  activation. Physical number visibility is unknown and actual completeness
  receipts are empty, so historical acquisition stays disabled. All 145 focused
  simulator tests and eight importer tests pass. Artifact size is 383,009 bytes;
  simulator load p95 68.3 ms and warm-query p95 0.036 ms. Memory/device/optical,
  current-source reconciliation and D adapter/save gates remain open. See
  `docs/research/magic-historical-pilot/README.md` and the current recognition plan.

- Historical Magic first implementation slice (2026-10-06; `412a09d` plus local
  changes): added versioned inert local recognition profiles, exact printing-ID
  overrides, deterministic catalog/profile/index generations and atomic
  compare-and-publish activation. Registry projection preserves schema-1 modern
  vocabulary and authority. Added six profile tests; 136 focused simulator tests
  and 18 MagicCatalogCore tests pass after a 130-test pre-change baseline.
  External drive holds DerivedData, package caches and result bundles. Retained
  a reproducible 910-set inventory (262 Phase-1 review leads), source/output
  hashes and explicit language/layout policy. Set counts do not establish a
  physical denominator. Historical acquisition remains disabled; physical corpus,
  reconciliation/index/freshness, historical adapter/OCR/picker/save and device
  gates remain pending in `docs/plans/magic_historical_recognition_plan.md`.

- Historical Magic plan review follow-up (2026-10-06): incorporated namespace-aware
  adapter preparation/lookup/choice/retry, candidate-universe completeness/freshness
  checks at lookup and save, printing-versus-finish/SKU identity rules, explicit
  encounter-scoped language evidence/confirmation and a reviewed legacy layout
  allowlist. Split B into app-local B1 and deferred signed schema-2 B2 after the
  bundled pilot; added failure/acceptance cases for each invariant. Documentation
  only; no app, catalog, schema, signing or rollout changes.

- Historical Magic implementation planning (2026-10-06; `412a09d` plus local
  documentation changes): source-checked the collector-number-era proposal and
  wrote `docs/plans/magic_historical_recognition_plan.md`. Corrected the scanner
  gate, set-versus-printing/profile assumptions, inventory-helper completeness,
  candidate uniqueness and exact scope claims. The plan covers inert profile
  contracts, a reconciled index, a bounded legacy OCR pilot, printing/finish
  choice, round-trips and device/rollout acceptance, with pre-Exodus deferred.
  No implementation, catalog adoption, build or rollout was performed.

- Card coverage data intake (2026-10-06; `412a09d` plus local changes):
  retained only 471 exact Pokémon parallel eligibility rows, two Magic PLG20
  filter regressions and 21 One Piece printing review leads. Retained hashes,
  sizes/counts, unique eligibility keys and negative cases pass. Compared
  existing NEO mappings and One Piece families; excluded duplicate data, stale
  aggregate counts, competing contracts and flawed helpers. Internal One Piece
  rows are available here despite the package's missing-input claim. No runtime
  adoption or release acceptance change. See the
  [intake note](docs/research/card-coverage-gap-data/README.md).

- Card coverage research report (2026-10-05; `f40e704` plus local changes):
  added `docs/audits/card-coverage-gaps-and-research.md` with known boundaries,
  unverified coverage, research priorities and closure criteria for Magic,
  Pokémon and One Piece. Direct Pokémon payload inspection corrected the
  earlier inference that low manifest cardCount values demonstrated missing
  cards; payload row counts meet the recorded standard slot counts for those
  eight entries. Magic token/art routes are distinguished from ordinary-path
  exclusions. Relative report links and diff whitespace checks pass. No source,
  catalog, device or release acceptance change is claimed.

- One Piece normal-app correction (2026-10-05): owner rejected the renamed app
  and isolated review collection. Built and installed the original
  TradingCardScanner identity/name with normal collection paths and a verified
  owner-local signed catalog enabling One Piece alongside Pokémon and Magic.
  Only the verified public pin is retained for subsequent ordinary local builds.
  The catalog copy and in-place installation succeeded without uninstall/export.
  Focused owner-catalog/storage selection executed 32 tests with zero failures
  and one expected simulator data-protection skip. Collection contents and camera
  behavior await phone confirmation. This supersedes the review-storage flow below.

- One Piece existing-app review update (2026-10-05; superseded): owner declined backup/app
  removal and explicitly requested reuse of the working scanner app. Added a
  signed debug-only opt-in for Home Screen review under the existing app identity,
  still using the separate OnePieceLocalReview storage root. The kit tool supports
  `--reuse-existing-app`; ordinary builds without the opt-in remain unchanged.
  Device build passed and two focused simulator tests passed. In-place install
  and signed catalog copy succeeded without uninstall/export. Remote launch was
  denied because the phone is locked; owner unlock/open and first physical scan
  remain pending. No production or shared-collection acceptance is claimed.

- One Piece physical-review preparation (2026-10-05; local changes): prepared a
  fresh full-corpus ephemeral signed kit and a separately identified “One Piece
  Review” DebugRemoteLocal app. Home Screen activation is restricted to the
  separate debug/local-only bundle and explicit public review pin; the kit tool
  now emits its review Info.plist. Device build passed with separate identity and
  no iCloud entitlements; two focused simulator tests passed. iPhone installation
  failed because its free developer-profile app slots are occupied. No existing
  app was replaced/deleted. Backup of the older scanner container was blocked by
  automatic approval review pending explicit export authorization; no backup
  ran. `docs/plans/one_piece_device_review.md` records the first-card checklist.

- One Piece v1 preparation (2026-10-05; uncommitted changes based on `534127f`,
  matching cached and live remote `main`): recorded owner approvals for private
  installs, English/verified/text-only scope and source roles in
  `docs/plans/one_piece_release_acceptance.md`. Moved seed preparation off the
  main actor, made recovery reload explicit and blocked during scanner work,
  retained authorities on no-change retries, and added the default-off production
  collection-write flag (remote-authority only). Added One Piece hosting cache
  rules and signed immutable namespace restoration, preserving existing publisher
  callers. Prepared deterministic printing/price/device samples and corrected
  local review pricing and CSV documentation. App build and 59 One Piece tests
  passed; final broader selection executed 159, zero failures and one expected
  simulator data-protection skip. Core suite 40 passed plus enhanced CLI case;
  seven focused Python tests and cache/link/diff checks passed.
  Rendered recovery QA preserved the Collection tab on no-op Retry and disabled
  Retry during Scan, restoring it after leaving Scan. This is simulator UI evidence.
  MCP's later export hit internal disk space; preserved this task's two bundles on the external SSD
  and reran directly there. No commits/push, production keys/publication, physical
  acceptance, CloudKit or archive evidence. Signing-key storage choice is pending.

- One Piece remaining-audit cleanup (2026-10-05; local changes on
  `merge/one-piece-integration@55dc1e4`, verified equal to freshly fetched
  `origin/main` before editing): removed three accidentally committed
  `undefined/` adapter copies, corrected model spacing and stale scope wording,
  accepted registered CSV display names while preserving unknown identities,
  moved fresh withdrawal-watermark reads off the main thread, and separated
  in-flight requests across withdrawals. Fetch-start timestamps and newer-cache
  retention prevent an older completion from replacing fresh data; the default
  cache moves to v2. Optional catalog failures now have a visible Retry action
  and retain update observers so later verified activation can restore the
  module without relaunch or weakening collection-write policy. The initial
  focused simulator selection passed 94/94; final pricing/cache, runtime,
  scanner/recovery, activity and CSV selection passed 257/257, zero failures or
  skips, with terminal `TEST SUCCEEDED`. Result:
  `<external-ssd>/CardScannerBuild/OnePieceAudit-2026-10-05/FinalRegression.xcresult`.
  The initial MCP test export uses its fixed app-support directory; derived
  data and the final run's result/logs use the external drive. A subsequent
  layout-only fix and final build passed; inspected the deterministic
  `CatalogUnavailable` screenshots on iPhone 17 Pro / iOS 26.5, checked Retry
  and Collection navigation, and verified headers/tabs remain visible. Local
  screenshots/checklist are ignored artifacts; prior `ui-latest` captures were
  preserved. The architecture audit still reports the same 37 existing legacy
  branches. No commit, push, device/provider/CloudKit or release certification.
  See the [current handoff](docs/audits/one-piece-integration-review-handoff.md).

- One Piece integration review fixes (historical checkpoint, 2026-10-05;
  uncommitted on `6b64abe` at verification time, subsequently committed through
  `55dc1e4`):
  isolate optional launch failures, reuse verified catalog snapshots/seeds,
  restore activity/CSV compatibility, preserve recovery copy state and purchase
  links, rehydrate current Pokémon definitions, batch history-write validation,
  make price-cache generation/freshness explicit, and verify signing against
  app-pinned keys. The activity finish picker now uses the bound registry and
  enables selection before Save. Final simulator regression: 300 passed, zero
  failures/skips across scanner, recovery, import, activity, pricing/cache,
  runtime, and signed-store suites. One Piece core/publisher: 40 passed; Python
  One Piece pipelines/trust anchors: 48 passed. Workflow YAML/shell syntax,
  165 local documentation links, and `git diff --check` pass. The expanded
  boundary audit reports 37 existing branches; legacy extraction and production
  rollout/collection-write/device/release gates remain open. Existing user
  edits are preserved; no commit, deployment, or release certification.
  See the [corrected handoff](docs/audits/one-piece-integration-review-handoff.md).

- One Piece plan/source reconciliation (2026-10-05; main checkout at `6b64abe`):
  updated the [implementation ledger](docs/plans/one_piece_code_implementation.md)
  and [catalog design](docs/plans/one_piece_catalog_integration_plan.md) for the
  committed integration, current corpus/base mappings, exact finish correction,
  container-bound withdrawal and catalog adapter extraction. Existing full-kit
  local base-case acceptance is next; legacy Browse/import and external gates
  remain open. Read-only boundary audit confirms eight Browse labels. Plan-only
  update; no implementation, build or app/package test rerun, and the recorded
  192-test selected checkpoint remains historical evidence.

- One Piece merge-branch review handoff (2026-10-05): transferred 183 integration
  files onto `merge/one-piece-integration` in the main checkout, preserving its
  existing whitespace edit and `undefined/` files. `main` and the source worktree
  remain unchanged; no commit was created. Added a factual
  [change report](docs/audits/one-piece-integration-review-handoff.md) identifying
  code boundaries, catalog/pricing scope, existing verification and remaining
  acceptance work. Documentation-only follow-up; no new build/test run.

- Base-case handoff / Pokémon catalog extraction (2026-10-05; One Piece worktree
  at `69c714f`): moved Pokémon provider/offline/disk-cache/historical behavior
  into game-owned catalog files, retaining persisted keys and captured modern
  definitions. Central catalog dispatch/coalescing is generic; eight remaining
  audited branches are all in Browse. All 192 selected tests passed in one
  checkpoint, including One Piece scan/save pricing, exact lanes and quote
  withdrawal, pricing/cache suites and legacy game compatibility. Result:
  `test_sim_2026-10-05T13-01-49-160Z_pid18958_cc372487.xcresult`.
  Installed and relaunched the simulator build with the unchanged full ordinary/
  base-pricing kit. Plan priority is local base-case acceptance before further
  framework or special-printing work; device/camera/production gates stay open.
  See [Package 3](docs/plans/one_piece_code_implementation.md#package-3-move-existing-behavior-behind-existing-adapters).

- Magic catalog adapter extraction (2026-10-05; One Piece worktree at `69c714f`):
  moved ordinary-card and signed/live token/art routing into `MagicCatalogAdapter`,
  registered by the runtime and legacy-compatible default factory. Central catalog
  now prepares/coalesces adapter identifiers, caches bounded lookup outcomes and
  preserves retrieval timestamps without storing the user's printing selection.
  All 55 focused Magic/forward-compatibility/historical-Pokémon/One-Piece cases pass
  in `test_sim_2026-10-05T12-37-17-792Z_pid18958_d68ce592.xcresult`. The strict
  boundary audit remains red at 11 matching labels. Signed Magic activation,
  Pokémon catalog, Browse/import extraction and release gates remain open.
  Updated app/full-kit relaunch retained the existing Shanks/portfolio $8.16
  display; no new provider request or camera acceptance was claimed.
  See [Package 3](docs/plans/one_piece_code_implementation.md#package-3-move-existing-behavior-behind-existing-adapters).

- One Piece withdrawal/retired-session acceptance (2026-10-05; existing worktree
  at `69c714f`): expanded the signed activation fixture to attempt actual
  single/multi-claim finish corrections after quarantine. Rows, acquisition
  claims, ledger operations, inventory events and price history remain unchanged.
  Added conflict/stale revision and retired/replacement storage-session coverage.
  All three focused tests pass in `test_sim_2026-10-05T12-24-13-145Z_pid18958_115e2d5a.xcresult`;
  no app behavior change or full regression run. The architecture audit still
  identifies 13 legacy Pokémon/Magic case labels. Full-plan/device/production
  gates stay open; local base-case testing remains the immediate handoff.
  See [Package 1 evidence](docs/plans/one_piece_code_implementation.md#package-1-implementation-checkpoint-2026-10-04).

- One Piece cached-price withdrawal (2026-10-05; existing worktree at `69c714f`):
  exact mapping fingerprints persist with owned/reference quotes. Catalog
  publication withdraws managed-provider values before exposing a changed
  generation; manual prices and permanent printing IDs stay intact. Older quote
  receipts cannot restore a withdrawn value. The app binds consumers to its
  authoritative storage container, using the coordinator's current snapshot.
  The consolidated One Piece/pricing selection passed 103/103; the focused
  same-container rebinding/quote-cache recheck passed 18/18. Relaunch found that
  older feed-cache receipts could delay restoration; feed caches are now bound
  to catalog generation. Its test caught default-protocol dispatch; explicitly
  async actor implementation fixed it and the affected test passed. Internal
  disk exhaustion during test packaging was resolved by retaining two generated
  bundles on the SSD. Final full-kit relaunch/Refresh Prices restored the saved
  Shanks copy and portfolio value to $8.16. Base-case local
  acceptance is next; production/device and special-printing gates remain open.
  See the [current handoff](docs/plans/one_piece_code_implementation.md#base-case-pricing-priority--2026-10-04).

- One Piece exact base pricing (2026-10-04; existing worktree at `69c714f`):
  reviewed 1,961 original base mappings across 48 retained price groups; 412
  ambiguous/qualified-title or missing-lane decisions remain held. Permanent
  physical IDs/counts preserved. Exact TCGCSV product/Normal-Foil quotes are wired
  through runtime, Price Check, Browse details/add and collection refresh; no
  condition SKU, base-card fallback or zero-dollar placeholder is invented.
  Four Python review tests and two affected core tests pass. The app checkpoint
  passed 56/59 initially; corrected three synthetic completeness claims, then
  all three pricing tests plus affected Browse registration passed. Full debug
  kit verifies (20,873,783-byte envelope); unsigned revision 14 validates against
  revision 13. Live simulator: Shanks Romance Dawn Foil showed $8.16, adding one
  copy persisted/displayed $8.16 in collection; unmapped FILM RED Nami stayed
  unpriced. Camera save now also routes to the exact adapter; its focused
  save/choice/quote/persistence test passes without paid credentials. There are
  61 distinct passing app cases across the checkpoint and affected rechecks.
  No production sync/rights/device gate closed.
  See the [base pricing ledger](docs/plans/one_piece_code_implementation.md#base-case-pricing-priority--2026-10-04).

- One Piece full ordinary app checkpoint/local kit (2026-10-04; existing worktree
  at `69c714f`): expanded scan/printing-choice/finish/save coverage through ST13,
  OP17, EB03/EB04 and PRB01/PRB02; held ST30/ST31 rows remain unowned. The 43-case
  app selection passed 41 initially, with two new assertions incorrectly assuming
  Browse exposed all retained products. Corrected to 52 verified-target groups;
  both affected rechecks pass. No full suite repeated. Generated and verified one
  full-corpus debug kit on the SSD; 2,745 printing records, 16,119,026-byte signed
  envelope, independent ephemeral key/revision-one local bootstrap. Unsigned
  publisher successor remains revision 13. Production, pricing, image rights,
  sync, rendered/device and activation/memory gates remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md#latest-full-ordinary-batch--2026-10-04).

- One Piece full ordinary corpus adoption (2026-10-04; existing worktree at
  `69c714f`): adopted all 58 ordinary product groups and 2,731 selected rows,
  including the retained legacy PRB01 release page. Current corpus: 2,692
  canonical cards, 2,745 printings (2,490 verified, 224 provisional, 31 conflicted),
  8,237 observations, 2,940 captures and 257 open discrepancies. All 817 earlier
  printing/artwork records, 794 canonical records and 19 product records remain
  unchanged. Exact replay matches all five artifacts; unsigned revision 13
  validates against revision 12 as protected review and is retained on the SSD.
  All 42 selected Python tests pass. Core: 39 passes and one assertion failure
  from the new test assigning base EB04-061 to OP17 instead of OP15; corrected
  and the affected recheck passes. App checkpoint/local kit remain pending; no
  production, rights, pricing or completeness gate closed. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md#latest-full-ordinary-batch--2026-10-04).

- One Piece full ordinary capture/source review (2026-10-04; existing worktree at
  `69c714f`): completed the 57-product capture with no availability/empty-page
  gaps and 2,935 retained source records. Extracted shared retained-source
  validation and added `--audit-only`: full-batch issue reporting without identity
  allocation or corpus adoption. Initial audit: 22 of 57 products source-ready;
  remaining issues include provider title annotations, special physical listings
  and missing starter finish evidence. Corrected exact printed-number title
  annotations while preserving treatment labels. New authored fixtures remain
  deferred to the consolidated checkpoint. No builds/suites, revised registry
  or successor candidate. Audit artifact:
  `/private/tmp/one-piece-bulk-source-audit-20261004/product-source-audit.json`.
  See the [execution plan](docs/plans/one_piece_code_implementation.md#ordered-work-packages-and-exit-evidence).

- One Piece full ordinary draft/capture (2026-10-04; existing worktree at
  `69c714f`): prepared a private unadopted 57-product, 2,730-row batch, preserving
  all 17 earlier product specifications. Combined-release base rows, selected
  starter reprints and held parallel artwork stay explicit; PRB-01 release-page
  evidence remains a scoped gap. Added whole-batch capture continuation for HTTP
  availability/empty retailer results while retaining fatal integrity checks.
  Corrected reuse of the already-retained OP17 series-index capture ID/filename
  without changing its bytes. Full-batch capture is running; no revised physical
  registry or catalog candidate yet. Authored fixtures are deferred to the final
  consolidated checkpoint; no builds or suites run. See the
  [execution plan](docs/plans/one_piece_code_implementation.md#ordered-work-packages-and-exit-evidence).

- One Piece bulk inventory implementation (2026-10-04; existing worktree at
  `69c714f`): added `scripts/discover_one_piece_products.py` using the retained,
  paced capture transport. Captured all 18 observed official product-index pages,
  58 ordinary series lists and 3,881 numbered artwork rows; 52 linked product
  pages include older PHP and directory-style release pages. Combined OP14/OP15
  and EB04 prefixes, shared deck pages, reprint aliases, future products and
  independent market-group candidates remain explicit discovery evidence.
  Private `bulk-product-discovery-v3.json` is retained on the external SSD.
  No physical UUIDs allocated, catalog coverage promoted, builds or suites run.
  Authored pagination/combined-release/reprint/offline fixtures and added the CI
  entry; execute them at the consolidated checkpoint. Next: review the complete
  product manifest and capture/reconcile ordinary printing evidence as one batch.
  See the [execution plan](docs/plans/one_piece_code_implementation.md#ordered-work-packages-and-exit-evidence).

- One Piece bulk execution change (2026-10-04; owner instruction): plan now
  batches all remaining ordinary OP/ST/EB/PRB products into one implementation
  deliverable with one consolidated replay/core/app checkpoint and one successor
  candidate/local kit. Bounded capture chunks remain resumable internal work;
  missing physical evidence stays held. The remaining physical distinctions form
  a second bulk pass. No implementation or tests in this planning update. See the
  [ordered execution plan](docs/plans/one_piece_code_implementation.md#ordered-work-packages-and-exit-evidence).

- One Piece OP-04/OP-05/ST-11/ST-12 batch (2026-10-04; existing worktree at
  `69c714f`): retained 270 new standard identities, 246 verified and 24 provisional.
  Missing retailer finishes remain held; OP-05 PSA Magazine/SP rows are explicitly
  excluded from base-art evidence. Preserved all 547 earlier printing records.
  Current corpus: 794 canonical cards, 817 printings (692 verified, 117 provisional,
  eight conflicted), 2,515 observations, 856 captures and 127 open discrepancies.
  Allocation-free replay matches all five artifacts. Unsigned revision 12 validates
  against revision 11 as protected review; no signed kit/publication. All 40 core
  and 35 Python tests pass. All 43 selected One Piece integration tests pass,
  including the four new product choice/finish/save flows and held-finish ownership
  exclusions. The unsigned revision-12 candidate is retained on the external SSD;
  see the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece capture/discrepancy pipeline (2026-10-04; existing worktree at
  `69c714f`): added bounded retained-byte product capture with observed pagination,
  exact source/group checks, four globally paced image workers, explicit orphan
  recovery and offline mode. Replayed all 13 real products/533 selected artworks
  without network or source-manifest changes. Added 103 durable held-record/scope
  discrepancies with retained resolution history; all five reconciler artifacts
  match replay. All 32 selected Python tests pass. No iOS/core build or new live
  coverage. Next: ordinary-product expansion and the remaining activation checks;
  see the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece reviewed-product manifest migration (2026-10-04; existing worktree
  at `69c714f`): replaced reconciler product/reprint constants with the durable
  13-product, 533-identity manifest. Preserved all 547 printing records, artwork,
  aliases, finish evidence and existing observation keys. Two retained-byte runs
  reproduce identical outputs; registry/observations/inventories also match the
  prior corpus. Updated only review scope and the inaccurate retailer-only finish
  limitation. Added seven authored pipeline tests and workflow coverage; all
  24 selected Python tests pass. No iOS/core build. Capture automation, further
  coverage and activation ordering remain open in the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece developer-handoff recalibration (2026-10-04; existing worktree at
  `69c714f`): reviewed uncommitted runtime, correction, capture/reconciliation and
  workflow source. Updated documentation only: distinguish implemented work from
  remaining activation ordering, specify the reviewed product/discrepancy schemas,
  split retained-byte manifest migration from capture expansion, and define replay
  and crash-recovery acceptance. Corrected the focused verification scheme and
  removed a nonexistent test-file requirement. No implementation, build or test
  run. See the [code/file-level handoff](docs/plans/one_piece_code_implementation.md#codefile-level-implementation-handoff).

- One Piece exact correction and evidence checkpoint (2026-10-04; worktree
  `one-piece-integration`, base `69c714f`): corrected the two ST-10 OP-01 review
  descriptions and reconciler output; replay retained all 533 standard identities
  and reproduced registry, observation, inventory and review JSON exactly. Added
  synchronous printing/finish validation to the One Piece adapter and all three
  collection correction mutations, with per-container adapters and monotonic
  activation revisions configured from the app root. The selected 42-case suite
  compiled with 41 passes and one test-fixture failure; after fixing its
  uppercase-UUID input and adding no-adapter/price-key assertions, the affected
  test passed in isolation. The full selected suite was not rerun after that
  test edit. A source audit also traced CSV, normalizer, detail-edit, quantity
  and removal writes to their capability/store gates. See the
  [Package 1 checkpoint](docs/plans/one_piece_code_implementation.md#package-1-implementation-checkpoint-2026-10-04).

- One Piece implementation handoff detail (2026-10-04; existing worktree at
  `69c714f`): expanded the current execution plan with prescribed files/APIs,
  collection authority and mutation ordering, product capture/manifest schema,
  Pokémon/Magic extraction targets, signed seed/hosting contract and focused
  verification inputs. External release decisions are explicit owner inputs.
  Documentation-only; no implementation, build or test rerun. See the
  [code/file-level handoff](docs/plans/one_piece_code_implementation.md#codefile-level-implementation-handoff).

- One Piece efficiency/plan audit (2026-10-04; existing worktree at `69c714f`):
  inspected current code, registry, publisher artifacts and existing test logs.
  Current state reaches ST-10/OP-03: 534 canonical cards, 547 printing records
  (446 verified, 93 provisional, eight conflicted) and 1,727 observations. Latest
  logs record 40 core and 40 One Piece integration passes. Updated only plans:
  retire small-demo-next priorities, batch catalog work, close exact correction
  and remaining routing gaps, and consolidate verification at milestones.
  Retained full physical coverage, rights, delivery, device and sync requirements.
  The two ST-10 reprint evidence descriptions still need manufacturer-only wording;
  no code/data fix, build or test was performed in this audit. See the current
  [execution plan](docs/plans/one_piece_code_implementation.md).

- One Piece next starter/booster coverage (2026-10-04; existing isolated worktree
  at `69c714f`): retained all 202 standard OP-02/ST-05–ST-09 rows, with 200 new
  verified printings and two provisional revision records. Current corpus: 394
  canonical cards, 405 printings (306 verified, 91 provisional, eight conflicted),
  1,284 observations. All earlier 203 printing records are unchanged; offline
  replay is exact and protected publisher revision 10 validates against revision 9.
  Prepared the expanded signed local kit externally. Fixed source timestamp
  validation to accept fractional ISO-8601 seconds; invalid values still fail.
  All 40 core and 40 One Piece integration tests pass, exercising one card per
  new product through recognition/choice/finish/save. Later products, revision
  reconciliation and production gates remain open in the
  [review corpus](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).

- One Piece remaining launch starters (2026-10-04; existing isolated worktree
  at `69c714f`): added all 51 standard numbered ST-02/ST-03/ST-04 records, with
  24 more verified acquisition printings. The corpus now retains 192 canonical
  cards, 203 printing records (106 verified, 89 provisional, eight conflicted)
  and 678 observations. Retained every duplicate retailer finish assertion;
  unresolved original/revision and normal/foil disagreements remain review-only.
  Publisher revision 9 preserves revision 8 identities, offline replay is exact,
  and the expanded signed debug kit is prepared externally. All 39 core and 40
  One Piece integration cases pass, now exercising all four launch starters.
  Later products, original/revision reconciliation and production gates stay open
  in the [review corpus](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).

- One Piece standard starter/booster expansion (2026-10-04; existing isolated
  worktree at `69c714f`): retained all 17 ST-01 and 121 OP-01 standard-art rows with
  permanent UUIDs and independent retailer finish evidence. Enabled 69 additional
  verified printings (ten starter, 59 booster); 68 errata records remain provisional
  and one conflicting starter leader remains excluded. The corpus now has 141
  canonical cards, 152 printing records and 518 observations. Offline replay
  reproduces all artifacts without UUID allocation; publisher revision 8 retains
  the earlier identities and an expanded signed debug kit is prepared externally.
  All 39 core and 40 One Piece integration tests pass, including ordinary Karoo,
  starter Luffy and booster Shanks choice/finish/collection paths. No app images,
  market joins, prices or production enablement were added. Remaining original/
  revision distinctions and further starter/booster products are still open in
  the [review corpus](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).

- One Piece rendered Browse base case (2026-10-04; existing isolated worktree at
  `69c714f`): launched the expanded signed review kit, searched for FILM RED Nami,
  added one raw foil copy and verified release/finish/quantity after stopping and
  relaunching the app. Reinstallation also retained the review collection. Fixed
  internal product IDs in Browse projections and replaced unsupported-pricing
  retrieval/history claims with “Pricing unavailable”; the updated detail
  accessibility tree confirms that state. All 102 selected One Piece/Browse tests
  pass with no skips or failures. Camera OCR, rendered scanner choice, broader
  English corpus and production gates stay open. See the
  [local review instructions](TradingCardScanner/OnePieceCatalogSeed/LOCAL_REVIEW.md).

- One Piece retail base-catalog expansion (2026-10-04; existing isolated worktree
  at `69c714f`): reviewed twelve FILM RED retail alternate-art printings against
  the manufacturer's product/card list and explicit foil specification. The
  durable corpus now holds 13 verified printings and one provisional record,
  14 canonical cards and 103 observations. Retained sixteen raw source responses
  privately on the external review drive; app artwork URLs and market joins stay
  absent. All 38 core tests and 39 selected app cases pass, including real retail
  Nami scanning, explicit choice, foil and collection identity. Publisher revisions
  6/7 retain UUIDs across protected expansion and unchanged replay; prepared an
  expanded signed local kit. Original starter Nami finish, ordinary booster/starter
  coverage, rendered/device and production gates remain open. See the
  [review corpus](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).

- One Piece real local base case (2026-10-04; existing isolated worktree at
  `69c714f`): debug/local-only launches can load a signed review catalog, scan and
  Browse One Piece and write an isolated persistent collection. Databases and
  recovery use a separate review directory; no remote One Piece updater or price
  adapter is created. Prepared a real small signed catalog on the external SSD
  with an ephemeral key. The real P-001 winner test covers recognition, explicit
  choice, sole foil resolution, disk save/reopen, CSV export and offline Browse.
  The checkpoint executes 68 cases: 67 passed, one existing storage skip, zero
  failures. The test runner shut down the simulator before separate installation,
  so rendered launch and physical-camera/process-relaunch acceptance stay open.
  See the [local review instructions](TradingCardScanner/OnePieceCatalogSeed/LOCAL_REVIEW.md)
  and [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece required import validator (2026-10-04; existing isolated worktree
  at `69c714f`): new-game CSV rows now require their installed printing adapter
  before any ownership operation. Writable capability alone cannot bypass exact
  identity validation; existing Pokémon/Magic legacy import behavior is retained.
  The simulator checkpoint passes all 72 selected One Piece integration, CSV
  resume and forward-compatibility cases, including refusal of numbered/UUID
  One Piece and future-game rows without an adapter. The plan records the remaining
  exact-printing finish-correction gap before write enablement. Links and diff
  whitespace pass; production remains gated in the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece normalization live-policy guard (2026-10-04; existing isolated
  worktree at `69c714f`): request discovery, legacy sealed-artwork repair and
  metadata application now honor current container write permissions. Both save
  paths validate pending game writes; sealed rekeying shares the configured store.
  A suspended One Piece lookup discards its result after permission withdrawal,
  preserving identity, metadata, artwork, history and price observations.
  The focused simulator checkpoint passes 84 cases across One Piece integration,
  normalization and forward compatibility. Plan links and whitespace checks pass;
  wider direct-save, physical reconciliation and production sync gates remain
  open in the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece Browse activation refresh (2026-10-04; existing isolated worktree at
  `69c714f`): updates now carry their own game and catalog revision, preserving
  older global provider events. Refresh only affected game directories; restart
  unchanged active searches through the existing debounce so old-generation rows
  and cursors are discarded. Open sets filter updates by game/set and rebase their
  descriptor on deliberate reset; pagination remains pinned. Withdrawn sets clear
  old selectable rows. The Browse checkpoint passes 104 selected tests, four
  focused rebase/scoping follow-ups pass, and the final withdrawal guard compiles
  in a build-only checkpoint. Whitespace and plan links pass. Rendered navigation,
  device, production and wider corpus gates remain open in the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece required finish evidence (2026-10-04; existing isolated worktree at
  `69c714f`): rules version 2 requires an explicit catalog-supported finish review
  for every verified physical variant, agreeing with canonical number, language
  and release. Missing/contradictory claims, market observations and image-only
  roles are rejected. Migrated the real winner review to its manufacturer finish
  specification; participant stays provisional with no finish. Unsigned publisher
  revisions 4/5 preserve both UUIDs across protected migration and replay.
  All 38 core/publisher tests and 43 selected app tests pass, with successful
  terminal processes. Plans, JSON/candidate hashes and whitespace checks pass.
  Production, corpus coverage, rights and device/sync acceptance remain open in
  the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece first real award reconciliation (2026-10-04; existing isolated
  worktree at `69c714f`): allocated durable P-001 winner and participation UUIDs
  from reviewed official event evidence. The manufacturer specifies the winner's
  silver foil; a grading-company physical photograph independently corroborates
  the award identity and WINNER lettering. Participation remains provisional
  with unknown finish. Five retained responses match recorded hashes; six new
  observations bring the combined review candidate to 67. Publisher revisions
  2/3 retain both UUIDs and evidence, with no automatic candidates or market joins.
  The package checkpoint passed 32/34 initially; both affected corpus tests pass
  after timestamp/canonical-order corrections. Three selected app tests pass for
  the real OCR/choice/finish/Browse boundary and existing scanner regressions.
  Image URLs, production sync and pricing remain disabled; coverage, rights,
  further physical reconciliation and device acceptance remain open. See the
  [reviewed award evidence](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).

- One Piece unresolved-finish contract (2026-10-04; existing isolated worktree
  at `69c714f`): unverified publisher review printings can retain an empty finish
  list without inventing a normal/foil variant. Verified printings still require
  registered variants. Two new core tests cover stable regeneration, exclusion
  from automatic authority, invalid variant rejection and protected promotion.
  All 34 core/publisher tests pass; no app build was run for this package-only
  change. Real physical evidence and reviewed UUID allocation remain unfinished
  in the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece collection-policy follow-up (2026-10-04; existing isolated worktree
  at `69c714f`): guarded commits now inspect blank-game history and inventory-only
  ownership, existing stores honor configured policy withdrawal, and backfill
  excludes unsupported rows/history. Local artwork overrides and removal survive
  relaunch without clearing unsupported synced legacy metadata. Simulator checks
  cover 66 distinct passing cases across one checkpoint and targeted follow-ups;
  initial failures were a retained-object rollback assertion and an import fixture
  that needed to enable its isolated container explicitly. Two artwork tests were
  rerun with their correct class selector. Plan links and diff whitespace pass.
  Remaining direct-save audit, physical reconciliation and mixed-client CloudKit
  enforcement stay open in the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece broad market discovery (2026-10-04; existing isolated worktree at
  `69c714f`): inspected and adapted the owner's English catalog kit, retained 90
  paced TCGCSV responses from the Oct. 3 daily build, and generated 7,408 review
  rows across 87 groups. One empty presale inventory remains explicitly incomplete;
  DON!!, unnumbered and metadata-conflict candidates are retained outside exact
  numbered-card authority. Added 31 hashed stress market observations and a
  no-ownership candidate crosswalk (Shanks 7, Nami 10, P-001 Luffy 14 products).
  Private source thumbnails support seven illustration correspondences; Nami's
  market image is a placeholder. Recorded digital/footer discrepancies without
  asserting original physical footer, finish, exact UUIDs or market joins.
  Nine Python tests and 32 core/publisher tests pass; offline replay produces all
  four CSV/JSON outputs byte-identically, with a focused unchanged-mtime follow-up.
  No app rebuild or production enablement. See the [review evidence](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).

- Lorcana first slice (2026-10-04; existing `one-piece-integration` worktree at
  base `69c714f`, including uncommitted shared infrastructure): recalibrated the
  [implementation plan](docs/plans/lorcana_code_implementation.md) and implemented
  validated local print-family mappings, content-derived generations, conservative
  complete-footer recognition and generic incomplete lookup/recovery. Provider
  set codes remain independent from printed markers, premium numerators and promo
  tokens remain literal evidence, and unknown/cross-game ambiguity cannot borrow
  an exact physical identity. The focused simulator checkpoint passes 44 cases,
  including 13 new Lorcana tests. An initial project-ID collision was corrected
  before the successful checkpoint. Production registration, physical UUID/finish
  evidence, real corpus normalization, pricing and collection writes remain open.
  No full suite or physical-device/provider/CloudKit certification was performed.

- One Piece real source-review checkpoint (2026-10-04; existing isolated worktree
  at `69c714f`): retained exact response bytes for six official/Limitless pages
  externally, with SHA-256/timestamp manifests and 30 normalized observations in
  the [stress-source review inputs](OnePieceCatalogCore/ReviewCorpus/english-stress/README.md).
  Added bounded fail-closed normalization, preserving separate reprint appearances,
  provider aliases and incomplete discovery inventories. Eight parser/CLI tests
  and all 31 core tests pass. Publisher accepts the canonical-only unsigned review
  candidate with zero physical printings/automatic candidates; identical reruns
  preserve normalized outputs. No app build or wider scanner suite repeated.
  Real physical UUID allocation/reconciliation, permitted image evidence, rights,
  signing/delivery and collection sync acceptance remain open.

- One Piece compact picker (2026-10-04; existing isolated worktree at `69c714f`):
  replaced the verbose default with Pokémon/Magic-style header and short option
  buttons, bounded grid for long histories and Details on demand. Recovery uses
  the same concise labels; exact-printing/artwork safeguards remain. One batched
  checkpoint passed 37 cases; the affected label test passed a focused follow-up.
  Rendered header/contrast fixes received build-only verification. Final phone,
  tablet, large-text, footer and missing-artwork captures were inspected; native
  checks reached/selected fixture 61, skipped, and opened Details without choosing.
  These are component-fixture checks, not real catalog or ownership/sync readiness.
  See the [visual checklist](docs/plans/one_piece_printing_choice_visual_checklist.md)
  for evidence and open loaded-artwork/device/VoiceOver/owner acceptance.

- One Piece plan reconciliation and picker direction (2026-10-04; existing
  isolated worktree at `69c714f`, tracked and untracked changes reviewed): plans
  now reflect bounded picker mechanics and recovery validation already present.
  Existing picker checkpoint log records 52 passing selected tests; no tests or
  builds were run in this documentation-only pass. The owner rejected the verbose
  picker and requires the existing Pokémon/Magic header/short option-button
  format, with bounded scrolling for long printing histories. UX acceptance stays
  open. Retain Lorcana-relevant seams and prioritize compact picker plus a small
  real reviewed corpus and remaining write guards over optional extraction.
  Production data/rights, delivery, device/performance and CloudKit gates remain
  open. See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece recovery/identity follow-up (2026-10-04; existing isolated worktree
  at `69c714f`): retry-save after relaunch now revalidates evidence against the
  active catalog and asks for a printing again. One Piece live lookup, choice and
  retry share strict payload validation; incomplete local catalogs retain a
  retryable explanation. A single batched simulator checkpoint passed 138 of
  139 cases; a missing inventory entry in the new later-release fixture was
  corrected and its one-case follow-up passed. Passing evidence now covers all
  139 selected cases (29 One Piece, 94 scanner model, 16 recovery store), not a
  full-suite/device/provider/sync gate. Production support remains disabled.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece plan/code audit (2026-10-04; existing isolated worktree at detached
  `69c714f`, including tracked/untracked implementation): documentation-only
  review confirms the shared identity/runtime/local fixture architecture is on
  track, with production support disabled. Updated the
  [implementation ledger](docs/plans/one_piece_code_implementation.md) with a
  slice status matrix, prioritized picker/write/backfill/recovery/Browse gaps,
  missing real corpus and shared-host publication hazards, and a KISS sequence
  retaining the seams needed for later Lorcana. Reconciled stale no-implementation
  wording in the design/audit. No implementation changes or builds/tests in this
  pass; historical checkpoint counts remain dated evidence.

- One Piece uncataloged-number recognition checkpoint (2026-10-04; isolated
  worktree based on `69c714f`): registry-supported series recognize valid printed
  numbers independently of catalog membership. Missing numbers participate in
  frame ambiguity and remain incomplete/recoverable instead of creating owned
  printings. Unknown series remain excluded. One app build passed all 25 One
  Piece integration tests, including live unresolved retention without ownership.
  Clearer incomplete-catalog messaging, later-catalog recovery and picker/device/
  performance evidence remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece configured bootstrap checkpoint (2026-10-04; isolated worktree
  based on `69c714f`): app registration can use a verified signed seed and
  dedicated configured keys/origin. Disabled mode omits the module;
  validation-only mode hides scan/Browse/write capabilities. Startup refreshes
  registered sources once per coordinator. One app build passed 61 selected
  tests; built plist/resource inspection confirms One Piece remains disabled
  with no endpoint, keys or production seed. Real reviewed data/signing/hosting,
  cold-start performance and independent sync policy remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece publication preparation checkpoint (2026-10-04; isolated worktree
  based on `69c714f`): signing binds reviewed canonical payload hashes to pinned
  public keys and verified revision baselines, with explicit initial bootstrap.
  Publisher sign/verify produces identity/change manifests and protects inputs
  and existing artifacts. Optional workflow signing prepares artifacts without
  deploying; production configuration remains disabled and unprovisioned.
  The package checkpoint passed 29 cases; the initially failing CLI case passed
  after focused discovery/write/idempotency corrections, giving passing evidence
  for all 30 cases. Workflow YAML/shell, ledger links and whitespace checks pass.
  Real reviewed data/keys/rights, hosting publication, bootstrap and sync gates
  remain open. See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece signed update transport checkpoint (2026-10-04; isolated worktree
  based on `69c714f`): generic bounded HTTP envelope transport supports conditional
  fetch, cancellation, redirect refusal and transient retries. One Piece refresh
  coalesces callers, validates or durably activates signed candidates, retains
  last-known-good data on rejection and clears rejected conditional validators.
  Disabled rollout makes no request. One app build passed 43 selected tests.
  Production URL/keys/seed/publication, bootstrap scheduling, legacy transport
  extraction and provider/device/sync gates remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece shared-screen runtime checkpoint (2026-10-04; isolated worktree
  based on `69c714f`): Collection and Settings now receive the app runtime and
  construct their normalizers from its adapters/capabilities/activation sources.
  Settings resolves current import adapters before acquiring the exclusive
  ownership lock and passes them into the isolated CSV actor. One app build
  passed 70 selected tests, including a signed revision activation followed by
  importing and enriching a newly introduced exact printing UUID. No rendered
  UI/device/provider evidence is claimed. Legacy adapter extraction, remaining
  mutation/import policies, production data/update publication and sync gates
  remain open. See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece collection transaction guard checkpoint (2026-10-04; isolated
  worktree based on `69c714f`): container-scoped game write policy now reaches
  scanner writers and explicitly configured CSV transactions. Common commit
  guards cover saved/staged ownership and history changes; unsupported rows
  reject acquisition, quantity/removal/undo/restore/correction/bulk deletion.
  Quantity repair uses the guarded commit and history backfill skips unsupported
  rows. One build passed 63 selected tests, including four new guard cases;
  56 existing ownership/history and graded/sealed tests passed without rebuilding.
  Shared-screen runtime propagation, remaining metadata/ledger-only policies,
  production data and mixed-client sync gates remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece exact import/normalization milestone (2026-10-03; isolated worktree
  based on `69c714f`): registered game import adapters and runtime factories;
  CSV row validation/headless import preserve exact UUID/finish/ownership keys.
  One Piece accepts verified raw printing identities, with specific failures
  for unsupported finishes and conflicting evidence; no number/name inference
  allocates a printing. Normalization keys include game, item kind and exact
  attached ID; unsupported/gated rows receive no metadata/watermark writes.
  Unknown non-Pokémon first-edition CSV finishes retain their own identity.
  The batched app checkpoint passed 75 tests; the focused identity follow-up
  passed 21. Project parsing, ledger links and whitespace checks pass. Runtime
  propagation into shared screens, complete mutation guards, legacy adapter
  extraction, alias/ambiguous/manual and graded/sealed import policies remain
  open. App defaults still omit One Piece; production data/publication, rights,
  mixed-client sync, rendered/device/performance and release gates remain open.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece local Browse milestone (2026-10-03; isolated worktree based on
  `69c714f`): added game-owned Browse adapters/runtime dispatch, verified English
  product/card projections, local search/details and generation-bound pagination.
  Product appearances share one physical UUID; exact ownership and physical
  completion cannot borrow another printing's matching number/set label.
  Runtime catalog updates invalidate old details/summaries. Browse enumeration
  uses injected game capabilities; One Piece requests no sealed provider setup
  and its raw/graded additions remain gated. The batched app checkpoint passed
  75 tests; 38 affected legacy ownership/completion tests passed without rebuilding;
  one focused capability-state follow-up passed. Project parsing, ledger links
  and whitespace checks pass. Import/export/normalization, complete mutation
  guards, production data/publication, rendered UI/performance and sync/device
  gates remain open. App defaults still omit One Piece. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece signed storage/live activation milestone (2026-10-03; isolated
  worktree based on `69c714f`): extracted shared verified current/previous
  storage while retaining Pokémon/Magic contracts and revision policies; added
  bounded One Piece signed slots, durable transition validation and activation.
  Generic runtime activation now updates scanner/catalog/variant snapshots and
  recovery. Explicit retry revalidates printed evidence against the new generation;
  saved choices and old lookup completions cannot silently cross generations.
  Initial loads share one task and slow subscribers retain only the newest event.
  The batched app checkpoint passed 57 selected cases; the follow-up passed nine
  targeted concurrency, stale-choice and legacy recovery cases. Remote updates,
  production seed/data/publication, Browse/import, complete mutation guards and
  mixed-client sync/device gates remain open. One Piece remains disabled in app
  bootstrap with pricing and shared-collection writes off. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece local scanner milestone (2026-10-03; isolated worktree based on
  `69c714f`): added pinned-key signed-release verification, an immutable indexed
  One Piece registry, registry-derived numbered recognition, game-owned catalog
  and variant adapters, and runtime recognizer installation between frames.
  Number recognition leaves language unconfirmed; English physical choices are
  explicit, and incomplete/conflicted scope cannot manufacture automatic
  uniqueness. The scanner commit boundary now checks collection-write capability;
  One Piece remains scan-only with pricing and shared-collection writes off.
  Focused app build/tests passed all 222 cases. Synthetic signed fixtures
  exercised recognition, printing/finish ordering, separate physical copies in
  an in-memory collection, stale choices and write-gate refusal. Package tests
  passed all 27 cases including signature failure checks. Project parsing,
  ledger links and whitespace checks pass. Production seed/data, current/previous
  storage, activation/recovery, full mutation guards and sync/device gates remain
  open. See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece catalog-core milestone (2026-10-03; isolated worktree based on
  `69c714f`): added OnePieceCatalogCore contracts, durable-registry builder,
  reconciliation/index validator, protected change classification, market quote
  invalidations, normalized provider captures and a local unsigned publisher.
  Synthetic stress cases preserve every printing, identical-art reprints,
  product appearances, reviewed alias/supersession/split/merge history and exact
  SKU qualifiers; they do not claim vendor counts or production completeness.
  The final batched package checkpoint passed all 25 tests, including publisher
  baseline/input/symlink protection. Project parsing, ledger links and whitespace
  checks pass. No app build was run for this package-only checkpoint. Real
  ingestion/data review, signed activation, One Piece runtime/OCR and sync gates
  remain open. See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece printing-picker/recovery milestone (2026-10-03; isolated worktree
  based on `69c714f`): generic catalog choices now open a game-neutral picker;
  selected printings proceed to finish resolution with the original catalog
  timestamp. Dismissed generic encounters retain separate recovery rows and
  generation-bound candidate lists. Reload keeps absent game modules read-only;
  supported recovery selections revalidate catalog membership and identity.
  Scanner/compatibility checkpoint passed 116 tests; the batched recovery
  checkpoint passed 19 tests. Full D/E migration, bounded live picker layout,
  production One Piece catalog/OCR, and sync gates remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece execution-priority clarification (2026-10-03): the owner plans
  Lorcana next, so retain shared identity, recognition, printing-choice/recovery
  and pricing-capability boundaries. Prioritize a complete One Piece local
  scan-to-collection/relaunch flow over finishing all legacy adapter migration
  or shared transport extraction first. Lorcana implementation is not added to
  this goal; the full One Piece checklist and production gates remain intact.
  This is a sequencing decision, not additional implementation or test evidence.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece generic resolved-card/catalog foundation (2026-10-03; isolated
  worktree based on `69c714f`): ResolvedCatalogCard replaces the closed downstream
  card enum, with a source alias and legacy provider projection preserving
  existing keys, metadata, treatment and pricing behavior. Generic printing
  keys remain stable across variant-count changes. Runtime catalog adapters
  expose resolved/printing-choice/incomplete outcomes, retain provenance and
  payload timestamps, validate generation and candidate membership, and keep
  different copies' printing selections independent. Expanded simulator
  regression passed 333 cases; final scanner/variant/pricing/fallback regression
  passed all 248 cases. Project parsing, ledger links and diff whitespace checks
  pass. Scanner choice/recovery UI and existing catalog providers still need
  migration; no One Piece production or sync/provider gate enabled. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece pricing adapter extraction (2026-10-03; isolated worktree based on
  `69c714f`): Pokémon/Magic module adapters now own exact-provider refresh and
  Pokémon bulk fallback. Runtime injection routes scanner Price Check through
  the generic pricing service; absent capability/adapter stops foreground
  fallback with a distinct unsupported-game state. Stored-card fallback and
  background/camera graded paths check capabilities before provider work.
  Expanded simulator regression passed 286 cases; the final slab capability
  change passed a focused 45-case rerun. Tests cover exact printing/variant
  forwarding, missing adapters, zero bulk/vendor requests and no synthetic
  price/product observations for unsupported games. Project parsing, ledger
  links and diff whitespace checks pass. The architecture gate still rejects
  catalog/Browse switches; background provider dispatch, generic resolved cards,
  and the remaining full-plan slices are unfinished. No One Piece production,
  provider, device or CloudKit gate enabled. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece runtime/variant foundation (2026-10-03; isolated worktree based on
  `69c714f`): app bootstrap and ContentView now use the registered runtime
  container, retaining existing coordinator behavior through an explicit legacy
  bridge. Game-owned policies supply variants and generic VariantLock options;
  scanner menus and lock validation use the injected registry. Final simulator
  runs passed 136 runtime/scanner/variant cases, all 166 Browse cases across four
  classes, and two screen-construction cases. Added the strict game-boundary
  audit: shell syntax passes, but existing catalog/Browse/pricing switches still
  fail its architecture gate pending adapter extraction. Full scope remains
  active; no One Piece production support, device/provider or sync gate enabled.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece recognition adapter foundation (2026-10-03; isolated worktree
  based on `69c714f`): primary recognition dispatches through registered adapters
  with explicit same-game/cross-game ambiguity and soft fallback rejection.
  Magic spatial rejection moved behind its adapter. Added semantic catalog
  generation to identifiers/snapshots; confirmation cannot merge generations,
  while suppression remains stable across activation. Focused simulator runs
  passed 99 recognition/historical cases and 107 parser/game/recovery cases.
  App bootstrap/runtime extraction and historical fallback context migration
  remain unfinished; One Piece catalog/support remains disabled.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece generic identifier/recovery foundation (2026-10-03; isolated
  worktree based on `69c714f`): replaced the closed scanner identity with generic
  canonical fields and separate suppression identity, retaining a typed
  Pokémon/Magic migration bridge. Added versioned recovery snapshots, legacy
  decoding, read-only future-game/version handling, original unknown-field
  retention, and malformed-neighbor isolation. App build passed; 120 unique
  focused simulator cases passed across final per-suite runs. One new test
  initially expected an empty plan instead of the existing `noCards` rejection;
  corrected it and reran all 25 game/recovery cases successfully. Full runtime,
  recognition, printing, catalog, provider, and rollout work remains incomplete.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- One Piece implementation foundation (2026-10-03; isolated worktree based on
  `69c714f`): started open game identities, capability enumeration, explicit-game
  CSV preservation/write refusal, and unsupported JustTCG mapping guards. Eight
  isolated Swift identity/capability checks passed. Registered app regressions
  have not run; simulator compilation still fails at unknown-game unresolved
  rehydration pending the generic identifier/recovery slice. Full implementation
  remains in progress. No CloudKit, provider, device, or release readiness claim.
  See the [implementation ledger](docs/plans/one_piece_code_implementation.md).

- Uncommitted-change review follow-up (2026-10-03; working tree against
  `dd2a1e3`): tightened edition quote matching by size/language/stamp and physical
  finish; validated catalog recovery finishes, retained raw vintage edition
  choice, and preserved validated slab edition evidence. Added five regression
  cases using existing pricing/resolution paths. Corrected offline support copy
  and historical F2 status wording. All 418 affected simulator cases passed
  across the final per-suite runs, and the Pokémon package passed 74/74. Two
  initial new-fixture decoding failures were corrected before the pricing rerun.
  Relative links and `git diff --check` passed. Artifacts are on the external
  SSD; no new full-suite, device, provider, or release acceptance is claimed.
  See the [review evidence](docs/plans/october-production-refinement-review-plan.md).

- Privacy/support page review (2026-10-03; working tree at `dd2a1e3`): found
  existing Markdown drafts and in-app link surfaces. Updated the drafts to
  Scanstash and the owner-confirmed Info@scan-stash.com contact, corrected partial
  collection deletion, and added photo/permission, provider/authentication,
  support-data, export, and privacy-request disclosures. Added
  [publication checks](docs/legal/README.md) against Apple's current 5.1.1 and
  Support URL requirements. Documentation only; operator details, routine support
  retention, provider safeguards, live hosting, and empty Release URL settings
  remain open. No deployment or App Review approval is claimed.

- Production refinement slice A / F1 (2026-10-03; uncommitted working tree on
  `fix/october-review-boundaries` at `dd2a1e3`): both pricing paths now apply the
  same persisted fifteen-minute cooldown to headerless transient/unrecognized
  429s, honor numeric/date retry headers, and preserve next-day rechecks for
  explicit quota errors. Request ceilings and interactive reserves remain;
  duplicate parser/reset helpers were removed. Six new mocked-response cases
  cover both paths, persistence, cross-lane blocking, and expiry. The complete
  JustTCG contract and product fallback classes passed 121/121 on a disposable
  iPhone 17 Pro / iOS 26.5 simulator with normal signing; existing simulator data
  was preserved. Build artifacts, log, and result bundle use the external SSD.
  Monthly-period accounting and other slices remain open; no full-suite,
  physical-device, live-provider, or release acceptance is claimed. See the
  [production refinement review plan](docs/plans/october-production-refinement-review-plan.md).

- Production refinement review documented (2026-10-02;
  `fix/october-review-boundaries` at `73898e8`): recorded the repository-wide
  source review's ten additional findings, minimum remedies, confidence/risk/
  complexity, acceptance cases, and independent implementation slices in the
  [production refinement review plan](docs/plans/october-production-refinement-review-plan.md).
  Linked the plan from the documentation map and reconciled prior authority
  boundaries in the documentation audit. Existing uncommitted centering/code/
  test/script changes were preserved; overlapping export work needs revalidation.
  This is documentation only, not implementation or fresh app/runtime evidence.

- Browse supplemental quote retention (2026-10-02; uncommitted working tree on
  `fix/october-review-boundaries` at `55b2d40`): failed supplemental refresh now
  preserves cached Pokémon prices and their provenance. The regression covers
  fresh and expired details plus replacement by a successful missing quote.
  Focused simulator pricing/Browse tests pass 30 cases, and the existing shared
  detail waiter cancellation case passes separately. Build caches, results, and
  command logs are on the external SSD; full-suite and device/provider gates
  remain unchanged. See the [refinement implementation plan](docs/plans/october-refinement-implementation-plan.md).

- October refinement review and plan (2026-10-02; `fix/october-review-boundaries`
  at `55b2d40`): validated the ten supplied follow-up findings against current
  source, tests, and configuration; documented minimal slices, regression cases,
  centering test/confirmation-contract reconciliation, owner-controlled URL
  dependency, and measurement-only targets. No application code changed and no
  new build, test suite, simulator/device capture, provider, or Photos check ran.
  Prior centering failures remain historical evidence, not a current rerun.
  See the [refinement implementation plan](docs/plans/october-refinement-implementation-plan.md).

- October review boundary fixes (2026-10-01–02; `fix/october-review-boundaries`,
  `cdd60e1` → `248a61d`): committed slices 1–10 separately. Checked grade
  conversion, export-container ownership, unrestricted Needs attention
  retention, certless Pokémon graded print-run identity including CSV and
  price preflight, interrupted recognition and duplicate-prompt recovery,
  Browse filter retention, stable collection destinations, catalog activation
  retries, artwork failure/cache behavior, and essential Dynamic Type text.
  Inventory ledger, serialized fresh-context writes, conservative matching,
  and explicit ownership confirmation remain in place. Focused simulator
  selections passed 14, 17, 40, and 124 tests; the final build-for-testing passed.
  The full suite after slice 4 executed 1,732 tests with 7 skipped and 25
  assertion failures across 10 centering cases. The required full follow-up
  after slice 5 executed 1,743 tests with 7 skipped and 25 failures across the
  same 10 centering cases; no other test cases failed. Scoped default and
  largest-text screenshots were inspected; existing wider contrast/toolbar
  risks and remaining manual share/save acceptance are recorded. The export
  interaction check reached the photo picker with synthetic fixtures, then
  native UI control was blocked by the locked Mac. Build and
  result artifacts use the external drive; an isolated task simulator preserves
  existing simulator data. No physical device was connected, so slice 11 and
  its conditional slice 12 remain pending, without performance or release claims.
  No push or PR. See the
  [October review ledger](docs/audits/october-review-remediation.md).

- Two-set TCGCSV pricing fallback (2026-09-30; working tree based on `a707356`):
  added reviewed exact TCGplayer product mappings for all 158 `30th` and 30
  `30th-c` cards and one shared device-local daily feed client. Browse sorting
  and card details, scanner background quotes, Price Check, and collection
  refresh now use the exact Holofoil quote when existing USD evidence is absent,
  independently of JustTCG credentials/settings or legacy secondary-set matching.
  Product ID, group, name, printed number, and finish are validated; unrelated
  products and other finishes cannot supply a price. Daily downloads coalesce,
  persist atomically, preserve original retrieval time for unchanged exports,
  and back off after failures. Export timestamps are not market-price timestamps.
  Reviewed finish metadata corrects upstream generated Normal flags, including
  old Browse slots. Automatically assigned collection finishes can be corrected
  and priced in one refresh with existing ledger/ownership safeguards; explicit
  user choices remain protected. Recent legacy misses cannot suppress trying
  the new source after upgrade. Registered the new service/mapping/test files
  and recorded JSON fixture in their Xcode targets. The final normally signed
  iPhone 17 Pro / iOS 26.5 focused selection passed 322/322 (21 new TCGCSV tests);
  result bundle: `/private/tmp/cardscanner-tcgcsv-verified.xcresult`. The unchanged
  production feed client, exercised on macOS with minimal value-type adapters,
  validated all 188 quotes against live build `2026-09-30T20:05:12+0000`.
  No external SSD was available, so generated build data used `/private/tmp`.
  No full suite, physical-device run, catalog signing, deployment, commit, or
  push was performed. See the
  [current pricing contract](docs/plans/browse_pricing_coverage_plan.md).

- Classic Collection authority review corrections (2026-09-30; working tree
  based on `7db2e18`, reviewing `82d0611`): added the missing bundled main-set
  `30th` / `30C` / 128 scanner definition, tested all 30 bundled membership
  rows against production publisher input, used parent `30C` display metadata
  for offline and live membership results, and narrowed stale-cache eviction
  to one key with a same-set persistence regression. Historical identifiers
  already have no persistent key in this checkout, so the stale-cache branch
  is defensive. All 30 numbers agree with rendered TCGplayer listings and all
  provider IDs/canonical names agree with TCGdex; the evidence explains LEGEND
  and the provider's `Palkia` name versus marketplace `Palkia LV.X`. A publisher
  test confirms explicit revision 11 replacement corrects revision 10 while
  omitted membership preserves authority. The focused iPhone 17 Pro / iOS 26.5
  simulator run passed 50/50; focused publisher tests passed 3/3. With no
  external SSD mounted, generated build data used `/private/tmp`; result bundle:
  `/private/tmp/cardscanner-review-20260930/catalog-verified.xcresult`.
  First-launch Classic resolution remains unavailable offline until its
  checklist downloads; the new bundled-snapshot test verifies fail-closed
  behavior. No physical-card inspection, signing, deployment, archive, or full
  suite was performed. See the
  [membership evidence and correction boundary](publisher/classic-collection-evidence.md).

- Scanner recognition remediation review corrections (2026-09-25; working tree
  based on `main@6747859f5e8c`): fixed the async candidate-list writeback by
  looking rows up again by ID, kept Needs attention rows until a successful
  commit or a verified existing collection entry, and carried slab identity
  through candidate choice. Exact chosen Pokémon printings now resolve from the
  offline checklist before broad historical matching. Cleanup is conservative
  for shared denominators and ignores candidate suggestions; historical rows
  are scoped across sessions, while a list-originated retry updates its source
  row by ID across that boundary. Persistence preserves records that an early
  registry cannot yet rehydrate, deduplicates row IDs, waits for ordered saves
  before catalog reloads, and retains Magic language. Retry-save checks the
  exact collection entry before routing, and Price Check/retry messages now
  reflect what actually happened. Same-number historical title evidence starts
  fresh after its TTL to prevent OCR from carrying over to a second card. The
  app-scoped Browse catalog is passed into Needs attention search, and Magic
  no-confirmed-match rows can retry lookup. The focused iPhone 17 Pro / iOS 26.5
  Simulator selection passed 229/229 tests with 0 skipped, including scanner,
  parser/latch, historical catalog, Pokémon catalog, retry-bound, and unresolved
  store coverage. Result bundle: `ReviewFixes-final-r3-2026-09-25.xcresult`
  under the external SSD's
  `CardScannerBuild/ScannerRecognitionReview-2026-09-25/Results/` folder. The
  full non-centering suite was not rerun for this follow-up; its 1,561 pass / 7
  skipped result is from the preceding source-review snapshot. Physical
  Ascended Heroes recognition, failure/relaunch actions, and the Instruments
  comparison remain open; simulator evidence does not establish device
  readiness. The plan records the review decisions in
  [`scanner recognition remediation`](docs/plans/scanner-recognition-remediation.md).

- Scanner recognition remediation review follow-up (2026-09-25; working tree
  based on `main@a55f4df83e5cab`): completed a source-to-plan audit and fixed
  several correctness gaps. Denominator ownership now includes active registry
  official counts as well as checklist overrides. Same-key unresolved rows keep
  unioned evidence and candidates while updating to the latest failure reason;
  merging a direct set-code read keeps inferred-name validation disabled, and
  only rows first created in the current session count in its summary. The
  focused iPhone 17 Pro / iOS 26.5 simulator selection passed 227/227 tests;
  the full non-centering suite passed 1,561 tests with 7 skipped and 0 failures.
  Result bundles are `Focused-final-2026-09-25.xcresult` and
  `Full-noncentering-2026-09-25.xcresult` under the external SSD's
  `CardScannerBuild/ScannerRecognitionReview-2026-09-25/Results/` folder.
  Physical ASC-stack recognition, forced-failure/relaunch actions, and the
  Instruments comparison remain open; these simulator results do not establish
  device readiness. The current merge and inference behavior is described in
  [`scanner recognition remediation`](docs/plans/scanner-recognition-remediation.md).

- Scanner recognition and Needs attention remediation (2026-09-24; working tree
  based on `main@a55f4df83e5c`): implemented denominator-owned modern Pokémon
  set inference with a unique fuzzy title agreement gate, Pokémon footer-code
  spacing support, historical OCR matching and evidence merging, scoped latch
  retries, and post-commit label OCR. Collection failures now file immediately
  to the capped local unresolved-scan store, survive Scan-tab departures and
  relaunch, expose candidate/retry/save/search/dismiss actions, and clear when a
  matching card is resolved or committed. The record also preserves graded
  label identity evidence so a relaunch cannot downgrade a slab retry into a
  raw-card add. Collection lock-wait signposts and 25-patch writer batches are
  included. Focused iPhone 17 Pro / iOS 26.5 simulator suites pass 225/225; the
  full non-centering suite passes 1,559 tests with 7 skipped and 0 failures.
  The injected unresolved-store suite passes 5/5, including corrupt-file,
  50-row-cap, unknown-set read-only, and slab-evidence round trips. Result
  bundles are `Test-TradingCardScanner-2026.09.24_22-27-41--0600.xcresult`
  (focused) and `Test-TradingCardScanner-2026.09.24_22-28-18--0600.xcresult`
  (full non-centering), under the external SSD result folder.
  The plan's “9 known pre-existing failures” referred to the superseded first
  2026-09-23 snapshot; the later same-day baseline at the top of this file had
  0 failures, and the current rerun also has 0. Result bundles are under the
  external SSD's `CardScannerBuild/ScannerRecognitionDerivedData/Logs/Test/`
  folder. The physical ASC stack, forced-failure/relaunch flows, and Instruments
  comparisons remain open; simulator evidence is not device readiness. Details
  are in [`scanner recognition remediation`](docs/plans/scanner-recognition-remediation.md).

- Systems-review pass-2 follow-up (2026-09-23; working tree based on
  `main@c1837b2`): fixed the refresh/migration-gate deadlock, made refresh
  suspension clear to idle when no work remains, prevented a cancelled
  background caller from starting a refresh after shared migration completes,
  resumed CSV imports by deterministic ledger operation ID after rows are
  rekeyed, preserved all-again CSV salts across interruption, and kept graded
  price identity promotion canonical across repeated passes. Added tap guards
  for graded/sealed adds, limited identity pauses to actual promotions,
  required a saved quantity before detail edits, and moved launch history
  backfill waits off the main thread. Native-currency evidence remains visible
  while being excluded from USD valuation and sorting. Updated the stale slab,
  currency, chart-envelope, and storage-copy assertions. Final non-centering
  iPhone 17 Pro / iOS 26.5 simulator run: 1,510 tests executed, 7 skipped, 0
  failures. The separate Debug simulator build succeeded. Centering tests were
  excluded. Physical-device/background expiration, large-fixture signposts,
  and the manual flows in [`RF-12`](docs/plans/release_followups.md#rf-12--collection-write-refresh-and-lifecycle-acceptance)
  remain open.

- Historical first-pass checkpoint (2026-09-23; superseded by the follow-up
  evidence above): Systems-review pass-2 remediation (working tree based on
  `main@c1837b2`): implemented the storage retry marker, monotonic price
  freshness, Magic migration trigger, USD-only portfolio valuation, server
  clock cutoff, and unproven-readiness local preflight; added the fresh-context
  `CollectionWriteSerializer`, guarded refresh-row patches and resumable pass
  suspension, resumable/idempotent CSV import, foreground/background refresh
  ownership, relevant-save filtering, and per-context artwork cleanup with a
  launch orphan sweep. Added concurrency, lifecycle, structural-refresh, CSV,
  detail-deletion, and artwork sweep coverage, plus the one-shot Debug
  first-container-failure launch argument. The non-centering iPhone 17 Pro /
  iOS 26.5 simulator run executed 1,520 tests: 1,504 passed, 9 failed, and 7
  skipped. Those same nine failures occurred in the Phase 0 baseline (1,444
  passed, 9 failed, 7 skipped); no new failure remained after updating the
  Magic migration test to re-fetch through a fresh context. The unchanged
  failures are `ScannerViewModelTests.testCertificateReadAfterCertlessSlabCommitRefinesTheSameCollectionEntry`,
  `PrivacyAndSupportSurfaceTests.testCollectionStorageStatusDistinguishesTransientLocalFallback`,
  `CardLatchTests.testDifferentConfirmedCertificateOnSameFooterCanRelatchQuickCopySwap`,
  `PortfolioReconciliationTests.testFastAndAuthoritativeValuationAgreeAcrossCurrencyAndInvalidationTransitions`,
  `CardLatchTests.testHeldSlabIgnoresGradeFlickerAndEnrichesCertificateWithChangedCardText`,
  `PriceHistoryChartModelTests.testNearFlatExpensiveHistoryUsesMinimumVisualEnvelope`,
  `OpusImplementationPlanTests.testREQ005NonUSDTransitionDepricesCurrentAndReplaySymmetrically`,
  `OpusImplementationPlanTests.testREQ006NonUSDLocalPriceRecordIsCheckingButStillVisible`,
  and `OpusImplementationPlanTests.testRM006NonUSDTransitionAcrossDayBoundaryKeepsCurrentAndReplayAligned`.
  The targeted
  storage suites passed 56 tests with 1 skipped. The Debug simulator build
  succeeded, and the first-open injection reached Retry then opened the
  existing collection. No centering tests ran. OS background expiration,
  device timing, large-fixture signpost comparison, and the remaining manual
  flows remain open in [`RF-12`](docs/plans/release_followups.md#rf-12--collection-write-refresh-and-lifecycle-acceptance).

- Raw / Slab scanner review follow-up (2026-09-23; working tree based on
  `main@30bd84e`): fixed held-slab duplicate saves by accepting only same-grade
  certificate refinement or a distinct confirmed certificate for a copy swap,
  and rekeyed the latch when cert evidence arrives. Slab label OCR now requires
  a matching footer and runs at most every 0.5 s before confirmation and every
  2.0 s afterward; one footer miss ages the 2-of-4 commit window, and a single
  footer-key misread preserves label progress. Raw post-commit reads require
  the saved footer identity. Restored the missing-row graded-price fallback,
  FIFO evidence eviction, no-key guidance, and wider footer ROI. Simulator
  `build-for-testing` succeeded; 11 selected non-centering regression tests
  passed on iPhone 17 Pro / iOS 26.5. No centering tests ran, and the earlier
  full-suite failures were not rerun.

- Explicit Raw / Slab scanning mode implementation (2026-09-23; working tree
  based on `main@30bd84e`): added the session-only mode picker, separate raw
  and slab recognition paths, slab-gated commits, post-save raw-to-graded
  conversion, and asynchronous graded price binding. The focused iPhone 17 Pro
  / iOS 26.5 Simulator selection passed 166 tests with 0 failures. The broader
  selection excluded all seven centering-specific test classes at the user's
  request and executed 1,445 tests: 1,427 passed, 7 skipped, and 11 failed;
  the failure names are recorded in
  [`explicit-raw-slab-scanning-mode.md`](docs/plans/explicit-raw-slab-scanning-mode.md).
  Generic iOS build and simulator build/run succeeded. The menu and Slabs pill
  were visually confirmed; the simulator back camera is unavailable, so live
  framing and recognition remain device checks.

- Explicit Raw / Slab scanning mode plan (2026-09-23): added
  [`docs/plans/explicit-raw-slab-scanning-mode.md`](docs/plans/explicit-raw-slab-scanning-mode.md)
  word for word as provided. Updated the documentation map and audit to identify
  it as the current proposed scanner architecture, and marked the archived
  scanner workflow review's conflicting slab auto-detection and blocking-price
  recommendations as superseded. Documentation only; no implementation or
  verification claims were added.

App-review follow-up fixes (2026-09-22): Settings opened from Scan now releases
the scanner's session-wide bulk interval and reacquires it after dismissal;
the sheet cannot close through Done or a swipe while import/delete owns the
exclusive token. Fallback eligibility is independent from price-observation
storage: identity-confirmed cards with no catalog quote can reach JustTCG while
`.unavailable(nil)` is still never persisted as an observation. A pending
forced retry survives same-collection coalescing, re-fingerprints after the
active pass, and clears if fallback is disabled. Deletion copy now states that
removal activity, price records, and Value History stay on-device. The focused
iPhone 17 Pro / iOS 26.5 Simulator selection passed 4/4 tests; same-collection
live-toggle timing and device behavior remain unverified.

App-review remediation worktree (2026-09-22): implemented session proof
retention across automatic, Add Another, held-repeat, and undo flows; kept
unqueried prices out of persistence while making fallback eligibility explicit
for identified catalog cards; bounded unpriced, missing-artwork, and
no-supported-provider automatic retries; made exact-row
catalog enrichment fill-only while retaining canonical normalization for
synthetic CSV rows; skipped CloudKit account probes while restoration readiness
is unproven and reused the matching active local container; enabled locked
background access to small metadata files with a privacy-policy disclosure;
delivered store notifications on the main run loop; and moved collection
deletion to a model actor with mutually exclusive import/delete coordination.
The affected iPhone 17 Pro iOS 26.5 simulator selection passed 99 tests with 1
data-protection-attribute test skipped because Simulator exposes no such
metadata. The separate delete-actor integration test passed 1/1. A wider
intermediate normalization run exposed and led to a fix for CSV set-code
canonicalization; that broader run also reported a Cardmarket test expectation
that conflicts with the current `CardPricing` implementation. The full suite, locked-device behavior,
physical scanner stack, actual privacy/support URLs, archive/TestFlight,
provider behavior, and release status remain open. See
[`app_review_fix_plan.md`](app_review_fix_plan.md) and
[`docs/plans/documentation_audit.md`](docs/plans/documentation_audit.md).

Browse pricing coverage Stage 4A (2026-09-22): implemented the revised
`browse_pricing_coverage_plan.md` Stage 4A slice. Browse now has a separate
device-local, per-set `BrowsePriceHistoryStore` under Application Support with
atomic writes, corrupt-file isolation, excluded-backup storage, 90-day
provider-day retention, versioned finish descriptors, restricted USD market
sources, and UTC/provider timestamp normalization. Existing Pokémon bulk and
TCGdex normalized price paths feed history without changing current-price
behavior; Magic uses a 24-hour Scryfall bulk-dataset stamp and labels that day
as approximate. Added the Browse detail chart with independent gap segments,
history diagnostics, migration coverage, and 104 focused history/Browse/pricing
tests passing on the iPhone 17 Pro iOS 26.5 simulator. The full external-SSD
baseline after the stale test compile repair was 1,442 passed, 18 failed, and 6
skipped; remaining failures are pre-existing centering, fixture, Keychain
environment, and legacy pricing-expectation failures. Phase 6.0 remains
unresolved because the current TCGdex service has no supported set-level
pricing response; pokemontcg.io remains authoritative. Stage 4B remains
disabled, and no provider, device, CloudKit, or release-readiness claim is
made.

Browse Pokémon pricing join/fallback hardening (2026-09-22): implemented the
attached follow-up plan. Bulk set requests now resolve TCGdex ids through the
existing conservative secondary-set matcher, cache the mapping, and decline
ambiguous/unresolved joins. Bulk card keys are canonicalized as
`<tcgdexSetID>|<localNumber>` so unpadded pokemontcg.io payloads join padded
TCGdex summaries. Pokémon fallback work is one card per six-wide worker slot
with incremental progress; the browse banner now separates unresolved cards
with Retry from resolved cards with no USD quote. Bulk requests use the
existing transient retry budget and have injectable recorded-response seams.
The app target builds cleanly with `CODE_SIGNING_ALLOWED=NO`. The test target
remains blocked before execution by the pre-existing missing
`CardCenteringMeasurement.confirmManualPlacement()` references in
`CenteringExportTests.swift:941` and `OpusImplementationPlanTests.swift:2434,
2506`; no provider, device, CloudKit, or release-readiness claim is made.

Browse pricing coverage stages 1–3 (2026-09-22): completed the USD-only
catalog rule and Settings coverage-gap diagnostics, persisted Magic page price
maps, added cached per-set Pokémon USD bulk pricing with exact-finish mapping
and per-card fallback, removed the 400-key prefetch cap, and made Browse price
loads queueable/retryable with a terminal “no USD price” state. Added focused
regression coverage for cache persistence, finish isolation, and one bulk
request per set. The app target builds cleanly; the test target remains blocked
by the pre-existing `CenteringExportTests.swift:941` reference to the missing
`CardCenteringMeasurement.confirmManualPlacement()` API. Stage 4 remains behind
the written redistribution-licensing gate; Stage 5 history remains pending.

Automatic set artwork on new-set release (2026-09-21): implemented the
zero-official-count browse-only admission path, 448 KiB publisher payload guard,
status/MIME/body artwork probe, gated derived-parent artwork, optional
pokemontcg.io/Scrydex set and card-art enrichment with whole-directory
fail-closed matching, signed descriptor card-art fallbacks, and app preference
for published fallbacks while preserving the snapshot fallback. PokemonCatalogCore
passes 54/54 tests and the fixed-timestamp offline publisher validation is
repeatable. A clean iOS test build is currently blocked by an unrelated existing
centering test/source mismatch (`confirmManualPlacement` is referenced by a test
but absent from the current `CardCenteringMeasurement` source); the app source
build itself completed successfully. No physical-device, provider, or release
readiness claim is made.

Centering remediation checkpoint (2026-09-20, current working tree): followed the required
order without changing contract thresholds. Formalized the ten-image `HOLDOUT-INTERIM` split
with a machine-readable `holdoutFreeze` block, kept its final REQ-040 gate open, and redirected
centering diagnostic writers to simulator temporary storage (or the explicit
`CENTERING_DIAGNOSTIC_OUTPUT_ROOT`) instead of tracked review paths. Implemented the registered
Pokémon/Magic back-template branch using observed border registration, then the separate
front-bottom art-window candidate generator with role-tagged alternatives and deferred joint
selection. Verification passed 4/4 focused manifest/source/semantic/outer checks and 1/1 REQ-042
ledger diagnostic; the temporary ledger measured 34/40 outer and 34/36 gradeable inner edges,
with remaining misses at IMG_0352 left and IMG_0780 right. All five development backs selected
the registered branch and IMG_0782 remained `none`/declined. The public L1 accuracy test still
failed with 53 assertions, so accuracy, metamorphic invariants, latency, final holdout
generalisation, joint selection, and physical-device gates remain open. The redirected REQ-041
profile passed 1/1 over 20 analyses with 2.7409/3.2918 s median/max wall time; the 0.80/1.50 s
budget remains unmet. No tolerance was loosened.

Centering remediation follow-up (2026-09-21): gated the discarded front-bottom candidate
generator call to DEBUG, then ran a same-session ten-fixture A/B on the pinned iPhone 17 Pro /
iOS 26.5 simulator. Without/with generator inner-generation medians were 0.7869/1.0085 s and
wall medians were 2.5304/2.7284 s; Release no longer executes that observational work, but the
0.80/1.50 s contract remains open. Added diagnostic-only identity telemetry and scored the five
development fronts: the maximum winning family score was 0.5500 versus the unchanged 0.72 gate,
and no front passed the full registered-back gate. Inventoried the new branch constants in the
centering plan. The interim holdout remains sealed; at that checkpoint joint selection was the
next permitted perception change, and the public L1/recall/device gates remained open. The later
REQ-045 entry records the bounded attempt and its failed pre-registered bar. No tolerance was
loosened.

Centering REQ-045 safety decision (2026-09-21): development evidence is now treated as a
fail-safe release decision, not a holdout result. Inner candidate recall is 34/36 (94.4%) against
the 95% gate, 0/8 confident numeric fixtures meet both ratio tolerances, and front T/B error is
19–22 pp across tested resolutions. The decision stopped automatic release and authorized one
bounded, development-only joint-selection experiment measured against L1; the sealed capture-diverse
holdout must not be evaluated to confirm this development-visible failure. The pre-registered
bar is zero confidently-wrong outputs and at least 80% confident-and-correct coverage; if it were
met, it could only expand a reliable automatic subset after the remaining REQ-045 gates. The
REQ-045 hybrid path is the product path now, with automatic starting geometry, user-placed inner
guides, exact ratio/rendering math, and guided manual correction. The selector outcome is recorded
in the following entry; no tolerance was loosened.

Centering REQ-044 experiment and hybrid implementation (2026-09-21): ran the one authorized
DEBUG-only joint selector over all ten development fixtures without reading the sealed holdout.
Nine fixtures had gradeable inner ground truth; 0/9 candidate readings met both ≤2.0 pp ratio
tolerances and 9/9 remained wrong under the pre-hybrid automatic-confidence interpretation, so
the zero-wrong / ≥80% pre-registered bar failed and the selector was not promoted. The analyzer
and view now expose a manualConfirmationRequired state: automatic outer/best-inner geometry
remains an editable starting guide, while ratio reporting and export require explicit confirmation
or adjustment of both frames; unsupported cases remain declined. Focused hybrid L1, confirmation,
and selector-evidence tests passed. The holdout remains sealed and no tolerance was loosened.

Centering hybrid verification (2026-09-21): reran the complete centering test selection after
making outer-frame confirmation explicit. On the pinned iPhone 17 Pro / iOS 26.5 simulator with
`CODE_SIGNING_ALLOWED=NO`, the seven centering classes executed 92 tests: 72 passed and 20
failed in 1,077.241 s. `CardCenteringAnalyzerTests` passed 21/21, `CenteringExportTests` 19/19,
`CardCenteringGroundTruthTests` 12/12, `CardCenteringSurfaceTests` 2/2, and the corpus manifest
1/1; the remaining failures are the already-open INV-2/4/5/7/8, REQ-022 latency, and E0/E-E
profile diagnostics. The new confirmation contract and REQ-045 confirmation test passed. The
holdout was not read; no tolerance was loosened. Result bundle: `/tmp/TradingCardScannerCenteringFull-20260921-v2.xcresult`.

Centering hybrid seed-prior diagnostic (2026-09-21): measured the detector's seeded inner
depths against a leave-one-out median prior from the same game family over the nine gradeable
development fixtures (36 edges). Depths were normalized by the annotated outer width for
left/right and height for top/bottom. The result was mixed: the family prior was clearly better
for Pokémon bottom edges (`0.10` versus `0.75` pp median; 5/6 per-edge wins), while the
detector was better for Pokémon top (`0.07` versus `1.21` pp) and Magic top/bottom (`1.18/2.77`
versus `2.54/16.99` pp). Magic left/right favored the prior, and Pokémon left/right were mixed
(the Pokémon-left median was effectively tied, `0.25` versus `0.24` pp). No blanket T/B seed
replacement is justified by this small family/side split; no production seed, threshold, or
selector behavior changed. The sealed holdout remains untouched. The focused
`testHybridSeedAgainstLeaveOneOutFamilyPrior` passed 1/1 on the pinned simulator.

Magic semantic publication hardening (2026-09-20, current working tree): added
shared Magic surface-diff and fail-closed semantic classification, with only
displayName, releaseDate, cardCount, and iconSVGURL eligible for the automatic
content-only lane. Added origin validation for signed icon URLs, explicit
removal authorization, publish-time candidate/report recomputation, dynamic
protected-versus-automatic workflow routing, and Magic-specific environment
guards. Verification passed: MagicCatalogCore 18/18, PokemonCatalogCore 39/39,
Magic release build, recorded fixture validation, hosting configuration
validation, and a serialized Debug iPhone 17 Pro Simulator build whose app
bundle was produced under external-SSD DerivedData. The hosted Magic pointer
check returned HTTP 404. The old Pokémon public pin remains temporary pending
owner input for the Magic key ID and public key; rollout remains legacy-live.

Magic catalog signing and domain-separation safeguards (2026-09-20, current
working tree based at `080db79`): brought `MagicCatalogSigningKeyLoader` to
parity with Pokémon's four GitHub publication-context checks, added the
explicit `MAGIC_CATALOG_PUBLISH` workflow marker, and made the variable source
injectable for unit coverage. Added an additive optional Pokémon schema-1
`catalogKind` marker: publisher-generated releases emit `pokemon`, the
verifier rejects a present wrong domain, and legacy releases that omit it stay
readable. Updated the key runbook to document Magic's second protected
environment and separate-key custody boundaries. Verification passed:
MagicCatalogCore 10/10, PokemonCatalogCore 39/39, Debug iOS Simulator build,
and `git diff --check`.

Documentation freshness reconciliation (2026-09-20, current `main` at
`31eb97e`): updated the current App Review/release ledgers, launch plan, and
repository audit to distinguish the clean current checkout from historical
candidate evidence; recorded the committed F01–F03 source remediation while
keeping entitled-device/runtime and release gates open; and updated the Pro/
eBay plan and centering contract to reflect their merge into `main`. Dated
historical evidence and older progress entries were preserved. Documentation
only; no source, tests, or build settings changed.

Pokemon catalog artwork fingerprint parity fix (2026-09-20, current working
tree): preserved raw provider `logo`/`symbol` values while carrying resolved
artwork in transient fields used only by descriptor construction. `v1` now
hashes the decoded provider payload, including the distinct `nil`/empty-string
tokens, so directory fallback, CDN resolution, and resolver failure cannot
make publisher and device fingerprints diverge. Added a Core parity test that
drives the real fixture fetch through the directory, CDN, and empty-string
paths and verifies both fingerprint equality and descriptor artwork delivery.
Verification passed: PokemonCatalogCore 38/38, the focused parity test,
`xcodebuild` Debug simulator build, and `git diff --check`. Two non-blocking
follow-ups are recorded in
[`docs/plans/release_followups.md`](docs/plans/release_followups.md): document
the load-bearing directory-row artwork fallback and add an iOS test covering
the device-side `canonicalFingerprint` mapping.

Catalog schema-1 provider-content propagation (2026-09-20, current working
tree): kept `PokemonCatalogCoreContract.releaseSchemaVersion == 1` and added
`providerFingerprint` as an optional additive descriptor field. Legacy
schema-1 releases decode it as `nil`, while new releases can carry a signed
desired content value without requiring an app update. Added one canonical
Core fingerprint for publisher/device parity, a distinct local-only probe
fingerprint for the independent 24-hour sweep, and fail-closed change
classification for content-only, baseline, authority, new-set, and unknown
changes. The first nil-to-fingerprint population is therefore protected
baseline migration; only later explicit content-only changes select
`pokemon-catalog-production-auto`.

The device now persists `(providerSetID, desiredFingerprint)` reconciliation
targets, retries mismatches without clearing them, publishes a set overlay only
after the computed canonical fingerprint matches, preserves full-sweep state,
and emits a set-specific Browse update. Activation events also carry content
change IDs and invalidate the existing resolved-card cache path. Verification
passed: PokemonCatalogCore 36/36 and 37/37 focused catalog app tests on the
arm64 iPhone 17 Pro simulator, with DerivedData, module caches, temporary files,
and the xcresult on the external SSD. Protected baseline publication, auto
environment setup, four-hour scheduling, live-provider, and physical-device
acceptance remain open.

F04 automatic Pokémon catalog preparation (2026-09-19, isolated branch
`codex/automatic-catalog-discovery-f04` from committed `edd8dc6`): added TCGdex
series/official-abbreviation evidence decoding, provider-side image-MIME-gated
CDN artwork resolution, safe active-descriptor metadata merges, automatic
ordinary-expansion code/count/release-order derivation, discovery policy and
due-set CLI preparation, card-art fallback hints, explicit `30th-c` support,
and scheduled workflow preparation with protected approval still required.
The signed release remains the only scanner authority; production config was
not changed. Verification passed: PokemonCatalogCore 22/22, recorded CLI
validation, BrowseFeatureTests 49/49, PokemonChecklistBrowseTests 56/56,
Slice B 29/29, Slice C 6/6, Slice D 4/4, Slice F 8/8, focused legacy snapshot
compatibility 1/1, and DebugProduction build. Live TCGdex candidate generation,
production approval/deployment, and device acceptance remain open. The main
working tree was left untouched.

Catalog authority rehearsal completed (2026-09-19): commit `54960fd` was
pushed with the same-revision coordinator fix and its production-configured
catalog suites passed 8/8 focused and 64/64 broader. The validation-only
production binary fetched hosted revision 1 from `catalog.scan-stash.com`,
validated 28/28 descriptors, ran validate-and-discard, and kept remote-store
disk usage at zero. A one-off external-SSD build with
`POKEMON_CATALOG_ROLLOUT_MODE=remote-authority` then activated revision 1,
persisted `current` with no `previous`, survived relaunch, and treated the
identical HTTP 200 envelope as `notModified`. The committed production
xcconfig remains `bundled-validation-only`; physical-device and genuine
offline evidence remain open.

Revision-2 candidate intentionally not published (2026-09-19): workflow run
[35443012617](https://github.com/Razorback2424/CardScanner/actions/runs/35443012617)
passed core validation and production candidate preparation from `54960fd`.
Its revision-2 candidate matched hosted revision 1 across all 28 descriptors,
provider card counts, provider fingerprints, and snapshot entries, with zero
added/changed/excluded IDs. The protected publish job was canceled before
signing or deployment, so hosted revision 1 remains current and the candidate
and reports are retained as external-SSD evidence only. The first real catalog
change should become revision 2.

Centering diagnostics slices implemented (2026-09-18): added REQ-049 positional
consistency diagnostics that report left/right and top/bottom ratios at five
evenly spaced positions with min/max/spread, without feeding the result into
selection or confidence. Added REQ-050 numerical-parameter injection with
unchanged production defaults plus a standalone recorded-grid harness under
`review/centering-harness/`; the harness has not yet been run over the corpus
or holdout, so REQ-050 completion and signed evidence remain open. Focused
simulator verification passed 19 `CenteringExportTests` and the two new
REQ-049/REQ-050 invariant tests on iPhone 17 Pro, iOS 26.5. The full suite,
corpus sensitivity sweep, and REQ-051 resolution comparison were intentionally
deferred. See
[`review/opus-card-centering-implementation-plan.md`](review/opus-card-centering-implementation-plan.md).

Catalog infrastructure state verified (2026-09-18): recorded the actual
deployment prerequisites in the plan's "Resume here" table after checking them
directly rather than inferring them. All catalog work for Slices A-F is in the
working tree and is **uncommitted and unpushed** at `db50515`, so
`.github/workflows/pokemon-catalog.yml` has never run and its `validate` job has
never executed on a runner. `catalog.scan-stash.com` does not resolve;
`scan-stash.com` resolves to Bluehost, which serves the marketing site and is
deliberately not the catalog origin. The `pokemon-catalog-production` GitHub
environment does not exist (HTTP 404); `pokemon-catalog-staging` exists but
holds only `POKEMON_CATALOG_KEY_ID` and `POKEMON_CATALOG_SIGNING_KEY`, and no
environment holds `FIREBASE_SERVICE_ACCOUNT` or `FIREBASE_PROJECT_ID`, both of
which the publish job requires. Also recorded one open gap the plan had been
claiming as a control: `PokemonCatalogUpdateClient.defaultBaseURL` validates
HTTPS, host presence, and unexpanded build variables, but implements no host
allowlist, so the plan's "release origin is a separate allowlist entry" claim is
aspirational until either the allowlist is added or the claim is dropped. The
earlier duplicated environment-path mapping in the publisher CLI is confirmed
fixed: `PokemonCatalogPublicationEnvironment.path` is now `public` and
`main.swift` consumes it instead of its own ternary. Documentation only; no
code, tests, or build settings changed. See
[`docs/plans/automatic_pokemon_catalog_updates_plan.md`](docs/plans/automatic_pokemon_catalog_updates_plan.md).

Catalog publication first-channel readiness (2026-09-18): kept the publisher
on one Firebase Hosting target and one local site root (`publisher/site`) for
the first Slice F rehearsal. The publisher environment path is public and is
the single source used by the CLI and filesystem publisher; staging retains its
future `staging/v1` namespace but is not wired into the current workflow.
Added production-only restoration with the existing 404-versus-corruption
semantics, dot-file Hosting ignores, local `.complete` markers, and a checked-
in Firebase target example. The app remains `bundled-validation-only`, so the
production hostname is acting as the rehearsal origin without granting remote
authority. Core tests pass 8/8 and the DebugProduction simulator build passes;
the focused Slice F simulator test target built but the runner exited before
XCTest bootstrapped, so its assertions remain unverified. GitHub PR validation,
Firebase project/DNS provisioning, production credentials/key pin, and the
ordered live rollout remain owner-controlled gates. Staging is deferred until
remote authority is close. The first validation-only GitHub Actions dispatch
after the push passed all four validation steps in 40 seconds (run
35394732002); publication was skipped because `publish=false`.

Catalog publication review remediation (2026-09-18): production publication is
now workflow-dispatch-only while Slice F is incomplete; scheduled runs remain
validation-only. The production job reconstructs the previously served
versioned release objects before deploying the fresh Hosting tree, and retains
the public review report as a 90-day Actions artifact. The Slice E checklist
now labels its publisher/filesystem and configuration evidence separately from
the still-open device rehearsal; Slice F records that privacy/support updates
are complete while App Store metadata confirmation remains open. Pointer fetch
failures now stop publication; only an explicit 404 is accepted as an initial
deployment.

Measured catalog rollout guard (2026-09-18): implemented Slice F's bundled-authority rollout mode. Production/default builds now fetch the signed catalog pointer for validation but never load or persist a remote registry; remote authority remains disabled until the future staging boundary and no-op rehearsal are ready. Added fail-closed public-key build configuration, launch/network/validation/activation/disk/memory diagnostics, and focused simulator coverage for validation-and-discard, explicit activation, persisted-release isolation, and configuration parsing. The focused Slice F target built, but its simulator test runner exited before XCTest bootstrapped, so those assertions remain unverified; the app build passes. The live Firebase pointer, production key ceremony and signing secrets, real new-set clean-install/upgrade/offline/cancellation/rollback run, physical-device measurements, and App Store evidence remain open. See [`docs/plans/automatic_pokemon_catalog_updates_plan.md`](docs/plans/automatic_pokemon_catalog_updates_plan.md).

Slice E checkpoint (2026-09-18, before Slice F rollout guard): automatic Pokémon catalog updates Slices A–D are implemented, and Slice E publisher/staging implementation has begun. Slice D makes the shared signed `PokemonCatalogCoordinator` the production Browse activation authority: TCGdex remains transport for authorized provider IDs, provider-only discoveries stay out of Browse until activated, and the checklist refresh validates official counts before publishing. Browse reloads on registry/checklist updates, preserves the previous complete directory on provider failure, uses registry release ordering through rollback, and removes the obsolete UserDefaults ordering authority and Pocket request. Pending sets intentionally render as nothing until active; legacy/diagnostic representations use `Code pending`, never a provider ID. Added `PokemonCatalogSliceDTests.swift`; the focused Slice D run passed 4/4 on the iPhone 17 Pro simulator. Slice C installs the same registry into Scanner; the app build and existing Slice A/B/C catalog/coordinator suites pass. Slice E adds the UIKit-free `PokemonCatalogCore` package, deterministic publisher fixtures, human-input gate, guarded signer, immutable filesystem publication, Firebase cache policy, CI workflow, and staging configuration. Its focused core run passed 7/7, recorded CLI validation passed, and the compile-only iOS build passed. The live Firebase deployment, production signing secret, populated production input, app `pinnedKeys`, provider/device/archive/release gates remain open; no full simulator suite or centering tests were run. See `docs/plans/automatic_pokemon_catalog_updates_plan.md`.

Historical checkpoint (2026-09-17): automatic Pokémon catalog updates Slice A is complete. Created `PokemonCatalogRelease.swift`, `PokemonCatalogRegistry.swift`, `PokemonCatalogSignatureVerifier.swift` (contract, bundled registry, signature verifier); added `PokemonCatalogDiagnostics` diagnostic counters on both `set.id.uppercased()` fallback paths (`PokemonChecklistSnapshot.swift:192` and `CollectionCatalogNormalizer.swift:741`); migrated all nine disposition-table consumers from `SetCodeMap`/`PokemonPromoCodeMap` to the registry (`ScanParser`, `RecognitionProfile.customWords`, `CardCatalog` officialCount, `BrowseCatalog` sort, `PriceRefreshController`, `CollectionCatalogNormalizer`, `PokemonChecklistSnapshot` display code, `TCGdexCard` release order); the generator coverage list at `PokemonChecklistSnapshot.swift:1203` stays on the seed. `CollectionCatalogNormalizer.resolvePokemonSet` receives the registry as a parameter, pinned for the pass. `PokemonCatalogTests.swift` (40 tests, 0 failures) covers round-trip/malformed envelopes, signature success/wrong-key/changed-byte/unknown-key/replay/future-skew, registry collision (expansion, promo, provider ID, cross-namespace) and `scanEnabled`/`.notScannable`, promo pad-width parity for all six series, and the parity gate across all migrated consumers including end-to-end ScanParser parsing. The targeted existing-suite run (ScanParser, BrowseFeature, CatalogNormalization, CardLatch plus all new tests) passed 227 tests with 0 failures. Slices B–F remain unimplemented. See `docs/plans/automatic_pokemon_catalog_updates_plan.md`.

Previous checkpoint (2026-09-16): the current branch is `main`; the focused
Browse/cache and PBX resource correction verification ran on the tree based at
`c381c99`. Browse selectors pass 133/133, the A8/B6 light/dark visual checks
are closed, and C7/RF-9 live-provider measurement remains open. The PBX fix
restored all 57 committed centering corpus files to the test bundle.

The latest complete full simulator run remains the pass-2 run at `a4375df`:
1,277 executed, 6 skipped, and 40 failures (36 fixture-resource lookup, 1
load-sensitive, 3 substantive). A focused post-fix centering run produced 38
results: 28 passed, 9 test cases failed on known centering assertions, and 1 profile-dump
test canceled; it was not a full-suite baseline. Card-centering accuracy,
invariant, latency, and device-only gates remain open, as do App Review
storage/CloudKit, physical-device, provider, archive/TestFlight,
ownership-ledger, and release-candidate evidence. The current documentation
boundary and contradiction matrix are in
[`docs/plans/documentation_audit.md`](docs/plans/documentation_audit.md).

## Historical checkpoint — 2026-09-12

Current checkpoint (2026-09-12): the repository-wide documentation and artifact
audit remains tracked in `docs/plans/documentation_audit.md`. The active
card-centering contract and evidence are tracked in
`review/opus-card-centering-implementation-plan.md` and
`review/centering-evidence/`. The current signed post-E-REQ044 full suite on
the pinned iPhone 17 Pro / iOS 26.5 simulator reports 1,095 result entries:
1,085 passed, 1 skipped, and 9 failed. All nine failed entries are centering
gates; the known pre-existing Magic-treatment failure from an older baseline
did not recur in this run. No Keychain entitlement failures occurred. The
current production accuracy, invariant, semantic-role, and latency gates remain
failing.

The rederived ground truth is adjudicable. The current E-A/E7 branch is 9
confident and 1 declined, with IMG_0782 correctly declining, but 3/10
development records meet the descriptive ratio target at 1200/1600/2000/2400.
The corrected REQ-042 ledger finds 34/40 outer candidates (85.0%) and 28/36
gradeable inner candidates (77.8%) under the exact role-specific tolerances;
the eight inner misses are generator failures, not selector measurements.
All nine non-none outputs still report `art_window`, including the five backs.
The screenshot batch remains a pre-E-B historical 3/7 snapshot. The 34-image
supplementary intake is now covered by a SHA-256 manifest: 24 new files are
development data and 10 are sealed as `HOLDOUT-INTERIM` before new analyzer
work. This is an interim safeguard, not final generalization evidence: the
HEICs are from one iPhone model, the PNG capture role is unknown, and no new
ground truth has been assigned. The capture-condition-diverse REQ-040 gate
therefore remains open; see `review/opus-card-centering-implementation-plan.md`.
Historical “pending” entries below are retained as chronology, not as the
current status.

Original prompt: Implement Browse Sets and Cards across Pokémon/TCGdex and Magic/Scryfall.

- Portfolio history Phase 2: fixed closed-close half-open attribution, unified state replay with the deterministic timeline, added pure value snapshots/history engine, cached SwiftData flattener, history card, Audio Graph/VoiceOver descriptor, and focused accounting/TWR tests. Source compile reached the new files; simulator build/capture is pending CoreSimulator availability.

- Added deterministic Browse launch route and QA checklist. Build/screenshot execution intentionally not run per user instruction.
- Implemented provider-neutral catalog browsing, both providers, global filtering/search, exact-printing add/undo, ownership aliases, release ranks, and unit-test coverage. Static checks only.
- Added at-a-glance unique-card set completion (`owned/total`) and progress bars to game set lists. Builds/tests/screenshots remain intentionally unrun.
- Added per-set card sorting by price or collector number plus owned/not-owned product filters. Price sorting hydrates exact-printing prices on demand with bounded concurrency and caching; execution checks remain intentionally unrun.
- Made the optional price fallback free-tier safe: fresh non-USD values become fallback work only when enabled, actual HTTP requests are capped at 95 per UTC day with background work capped at 75, 429 backoff is persisted, and Collection now exposes pending work, allowance state, and shared fallback settings. Builds/tests remain intentionally unrun.
- Unified camera, finish lock, price fallback, and collection deletion in one shared SettingsView accessible from all four tabs; Collection refresh is now a compact icon beside the green collection value. Build/test verification stopped at the user's request.
- Sealed-artwork loop target: `SealedArtwork`. Done means priced and null-price responses persist artwork independently, existing rows receive one backfill, terminal provider misses stop artwork retries, and the real remote image plus diagnostic placeholder pass `artifacts/sealed_artwork_checklist.md` in a simulator screenshot.
- Sealed-artwork loop 1: focused tests passed; screenshot harness failed because the named iOS 18.2 simulator was combined with an implicit `OS=latest`. Updated the harness to target its stable simulator UUID.
- Sealed-artwork loop 2: app compiled for the correct device, but workspace-local DerivedData inherited iCloud resource metadata and failed code signing. Moved the disposable screenshot build cache to `/tmp`.
- Sealed-artwork loop 3: screenshot rendered the network image and terminal diagnostic correctly, but exposed that fixture ID `610553` is a Suicune single. Replaced it with TCGplayer product `98580`, verified as Legendary Treasures Booster Box and returning HTTP 200 JPEG.
- Sealed-artwork loop 4: verified product `98580` rendered the correct Legendary Treasures Booster Box. HIG review found the name squeezed beside the five-digit price, so the tile now gives the name and price separate full-width lines.
- Sealed-artwork loop 5: final screenshot passed every visual and behavior item. Missing legacy sealed artwork may backfill with a configured vendor key even when general fallback pricing is off; ordinary fallback pricing remains opt-in. Full test suite and Release build passed.
- Whole-card scanner loop 1: replaced modal historical title capture with an on-demand same-frame title request, added a whole-card guide/footer band, and added conservative assistance models. Debug build and focused whole-card tests pass; visual route added for screenshot verification.
- Whole-card scanner loop 2: first deterministic capture reached the correct Scan tab but the reinstall-triggered camera permission alert obscured the guide. Updated the harness to grant camera permission after install for this route.
- Whole-card scanner loop 3: simulator privacy grant still surfaced the authorization sheet. Made the DEBUG-only `WholeCardScanner` route render the production scanner surface without starting capture; normal app launches still request and use the camera.
- Whole-card scanner loop 4: view-level bypass was insufficient because authorization still occurred below SwiftUI lifecycle ordering. Added the same DEBUG-route guard at `CardScanner.start()`, the single authorization entry point.
- Whole-card scanner loop 5: scanner-focused tests pass and the Release simulator app builds. The full suite passes 356/359; the only failures are existing Keychain tests rejected by the simulator with entitlement error `-34018`. Visual verification remains unclaimed because the simulator retained a camera-permission sheet over the deterministic route.
- Whole-card scanner loop 6: corrected the whole-card guide's normalized geometry for the portrait 16:9 source-pixel aspect. The old constants produced the ~0.40 aspect seen on device; the guide now resolves to the physical 2.5:3.5 card ratio, with footer/title ROIs expressed card-relatively.
- Portfolio stabilization loop target: `PortfolioToday`. Done means the deterministic normal-day fixture renders whole-collection value, reconciliation rows, honest checked/not-refreshed coverage wording, and no clipping or hidden residual in `artifacts/ui-latest.png`.
- Portfolio stabilization loop 1: the explicit-device harness built and launched `PortfolioToday`; the screenshot passed the checklist with a $125 whole-collection hero, $125 Added/Total reconciliation, an Aug 24 close, “1 of 1 checked today,” and no clipping, overlap, or unexplained residual. The harness now installs, launches, and captures from its requested simulator UUID instead of an arbitrary booted device.
- Portfolio populated-store migration: built d23347b in a detached temporary worktree, seeded its `SealedArtwork` route (2 cards, 2 inventory events, 2 price records), installed the stabilized build in place, and launched successfully. All six synced rows survived; the new local-knowledge backfill created 2 observations and 2 check rows, while close count remained 0 on migration day as required.
- Portfolio stabilization loop 2: added the explicit Current row required by the accounting-card contract and recaptured the route. The final artifact shows prior close and current together, still fits above the secondary collection grid, and passes the complete checklist.
- Portfolio stabilization loop 3: after the final epoch durability, earliest-baseline, and CSV attribution fixes, `PortfolioToday` was rebuilt and recaptured. The $125 hero, Added/Total, Aug 24 close, Current, and “1 of 1 checked today” remain correct with no clipping, overlap, or visible residual.
- Portfolio final populated-store migration: rebuilt and seeded d23347b with 2 cards, 2 inventory events, and 2 price records, then updated in place to the final hardening build. The app remained running, all six synced rows survived, 2 local observations and 2 check rows backfilled, and migration-day closes remained 0.
- Portfolio history hardening: closes now plot at their next-midnight economic instant with separate display days, the portfolio engine publishes a monotonic history refresh revision, the chart has a visible snapped-point inspector, Audio Graph and VoiceOver strings use correct percentage interpolation, and the Phase 2 acceptance tests cover new assets, nonmarket observations, reversals, DST, live deduplication, empty states, and shuffled-input reproducibility. Full scheme compilation passed; runtime tests and screenshots remain blocked by CoreSimulator service/device availability.
- Portfolio F: one computation per input change (history consumes the engine's replay result instead of building its own snapshot and replaying 47k observations again), SwiftData materialization moved off MainActor onto a @ModelActor with stale-result versioning, and the PortfolioHistory route captured for the first time. Two bugs surfaced only in the real UI: inputRevision was published before the result existed so the history card never refreshed, and the QA fixture seeded fabricated zero-valued closes that the replay correctly overwrote. Verified on simulator: Performance 25% traces the seeded 100/104/101/112/118/125 with the $100 acquisition excluded, Collection Value shows +$25 with $0 net collection activity, mode switching is instant, and scrubbing snaps to published closes. Real-device timing remains unverified.
- Marketplace link: persisted TCGplayer product/SKU identity from the JustTCG batch path and sealed browse, added TCGplayerLinkBuilder (product id + printing, else provider-supplied URL, else no button — never a name/set search), and a "View on TCGplayer" action directly under the price on card detail. Verified on simulator. The observation log records explicit invalidations on marketplace-variant changes, while the grid and portfolio now share record-backed instrument selection and keep observation-aware valuation. Holding detail was moved onto the grid's rule deliberately; see performance_review_remediation_plan.md R2/C2.
- Device signing: Debug now uses TradingCardScanner-Local.entitlements (no iCloud, no Sign in with Apple) so a personal Apple Developer team can provision and install on a real device; Release keeps the full entitlements for a paid team. LOCAL_ONLY_SIGNING skips the CloudKit container attempt and replaces the sign-in button with an explanation. Verified: generic/platform=iOS Debug build signs, and the signed app carries no iCloud or applesignin entitlements.
- Phase 3 explainability loop target: `PortfolioToday`. Done means the existing portfolio hierarchy retains its Today and Phase 2 surfaces, then presents Impact-ranked Biggest movers and Largest holdings with no clipping. The current fixture now seeds four deterministic positions with positive and negative contributions for visual QA.
- Centering camera/measurement fix: centering now follows the scanner's macro-first lens and near-focus configuration; captured image orientation is normalized before edge detection so portrait cards are not stretched into false desk-edge measurements. Simulator verification remains blocked by CoreSimulator service availability.
- Price Check implementation: added purpose-captured scanner routing, a device-local quote cache isolated from portfolio evidence, a dedicated result view and forced exact-card refresh, plus the deterministic `PriceCheck` screenshot route/checklist. Build, tests, and screenshot validation intentionally deferred at the user's request.
- Pokémon checklist snapshot loop: bundled 159 checklist resources across 148 supported provider sets, added local-first Browse loading and atomic opportunistic refresh, and passed focused plus non-keychain full-suite tests. The simulator rendered-test path passed, but the standalone screenshot helper could not capture after CoreSimulatorService disconnected.
- Scanner chrome loop 1: removed unused presentation state from published assistance, added downward hysteresis and a focused regression test, scoped transient scanner animations to mutation sites, stabilized Menu/control identities and 44pt hit targets, and narrowed CameraPreview observation to rotation/debug-box state. Build and screenshot verification pending.
- Scanner chrome loop 2: generic simulator build passed with the scanner changes compiled; the focused runtime test and deterministic screenshot were blocked when CoreSimulatorService disconnected and the configured device UUID was unavailable. Unrelated temporary compile workarounds were restored exactly.
- Scanner chrome loop 3: removed the sealed-set `releaseDate` stored-property default and updated its undated fixture, capped presentation hysteresis, animated slow-identification state at the mutation sites, preserved 34pt pill visuals inside 44pt targets, and added long-run hysteresis coverage. Full `build-for-testing` and the full simulator test suite pass; real-device interaction and screenshots remain pending.
- Collection navigation fix: compact-width Collection now uses the grid as the NavigationStack root, so card detail Back returns directly to the grid instead of exposing the split-view placeholder. The simulator build passed; screenshot capture is pending CoreSimulator availability.
- Portfolio market-movement simplification: primary Portfolio now uses one canonical additive market series for the headline, chart, movers, and all five existing ranges; full value reconciliation remains behind Details and contributor residual labels are clarified. The later cleanup removed the unused presentation-mode plumbing while retaining performance factors as internal replay data. App build passed; the focused history test target was previously blocked by unrelated `PortfolioReconciliationTests.swift` compile errors, and the user requested no further screenshot captures.
- Centering controls loop 1: rotation is now a display-only transform that preserves existing red/cyan guide positions and measurements; outer/inner guide rows accept direct numeric entry alongside steppers; the card preview remains pinned above a scrollable controls pane. Final Debug build and focused centering export tests pass; expanded simulator capture inspected before CoreSimulatorService disconnected again.
- Magic treatment Slice 4 loop 1: composed Magic finish/treatment labels now feed scan receipts and catalog card detail, explicit finish/treatment contradictions are read-only diagnostics, and a deterministic DEBUG route is ready; screenshot capture remains pending CoreSimulator availability.
- Magic treatment Slice 4 loop 2: finish-aware labels now suppress a foil-only treatment on a selected nonfoil copy, while browse detail presents dual-finish treatments without silently choosing foil; FIC #10 is the deterministic QA fixture.
- Magic treatment Slice 5: persisted forward-compatible treatment ids through collection rows, activity history, removal snapshots, prices, reference quotes, and vendor identities; centralized independent collection/price key codecs across raw, graded, sealed, and CSV paths; treatment-qualified rows refuse generic price read-through. Generic iOS build passed; simulator suite passed 692 tests with only the three pre-existing Keychain-entitlement tests excluded.
- Magic treatment Slice 6: made catalog pricing treatment-aware through the shared finish-filtered derivation; quarantined pre-existing generic treatment-keyed prices from collection, quote, portfolio, and replay reads; blocked generic JustTCG matching and scoped vendor misses by treatment; kept ordinary finish pricing independent; and hid unproven treatment marketplace links across both detail paths. Focused and full simulator suites passed, with the full suite at 710 tests under normal signing and no exclusions; visual/device capture remains pending.
- Magic treatment Slice 7: carried exact treatment identity, publisher qualifiers, and printed content kind through Browse summaries, ownership/completion, collection badges and filtering, history, removal/rekey paths, and lossless CSV export/import. Collector-number ordering keeps bare numbers before `a`/`b` suffixes, treatment remains a qualifier rather than a new set slot, and pre-/post-Slice-5 CSVs use the collection read-through. Full scheme suite passed 723 tests under normal signing with no exclusions; visual/device capture remains pending.
- Magic treatment Slice 6–7 review hardening: treatment capability gaps now return a distinct non-evidence outcome through product fallback and never create a 30-day vendor-miss identity; ProductPriceSubject requires an explicit treatment axis; and completion canonicalization maps zero-padded suffixed numbers such as `0523a` to `523a`. Full scheme suite passed 725 tests under normal signing with no exclusions; visual/device capture remains pending.
- Magic treatment Slice 8: added a per-row exact-printing migration that understands raw, graded, certified, sealed, and imported collection identities; enriches only from embedded Scryfall ids; preserves opaque vendor price bases without moving generic evidence into treatment keys; repairs safe canonical/legacy collisions with deterministic, idempotent correction legs; retains activities, removal snapshots, content kind, and ledger lineage; skips certified slabs; clears stale treatment-qualified vendor negatives; and handles pre-ledger collections before portfolio baseline creation. Launch now performs local repairs before portfolio startup, then batches deferred exact-id Scryfall enrichment in groups of 75 with pacing and recomputes afterward; optional identity fields require agreement rather than treating missing metadata as a match. Full scheme suite passed 742 tests under normal signing with no exclusions; visual/device capture remains pending.
- Magic treatment Slice 9: completed the cross-slice regression gate for all four audited NEO Neon Ink qualifiers, FIN collector-number suffix identity and completion, dual-finish FIC keying and treatment-aware pricing, deterministic two-device migration correction payloads, quantity/ledger conservation, and the existing parser, star, rescan, collision, CSV, and generic-price-substitution matrix. The first requested simulator build succeeded with no warnings, followed by 746/746 full-suite tests passing with zero failures or skips; visual/device capture remains pending.
- Magic treatment post-Slice-9 audit fixes: serialized local/network treatment migration with foreground, automatic, and background price-refresh planning; rebuilt foreground targets from the live model context after the gate; preserved queued portfolio recomputes across cancellation; centralized catalog retry-watermark writes in CollectionCatalogNormalizer; and invalidated completed migration results when observed Magic collection inputs change, including stale in-flight results. Added deterministic gate, cancellation, and migration-invalidation coverage. Simulator build and 750/750 full-suite tests pass with zero failures or skips; visual/device capture remains pending.
- UI Updates: centralized iOS 26 scanner glass with tinted locked/unresolved states, carried catalog unit price through scan receipt/review, and refactored collection card detail into grouped List sections with honest checked-day step/gap history and instrument-key predicates. Debug simulator build plus affected tests pass; screenshot capture deferred at the user's request after CoreSimulatorService became unavailable.
- UI Updates hardening: the scanner tab bar now hides only while a choice, duplicate confirmation, or receipt occupies the thumb zone and reappears when idle; legacy tinted-pill fallbacks preserve the red lock and 0.85 orange attention chip. Debug build and affected tests pass; screenshot remains deferred.
- Performance remediation slices 1-4, 6, 7, 11 (branch `perf/remediation-slices`, see performance_review_remediation_plan.md §0): holding detail projects from price records instead of the ledger, with a test pinning which of the three instrument-resolution rules it now follows; LedgerIntegrityLog and the unused epoch context parameter removed; Portfolio and Collection stopped observing PriceRefreshController from whole screens and share one activity row, and Collection's pull-to-refresh returns instead of awaiting the pass; the refresh write path (applyVendorBatchHit, ProductIdentityStore, ProductIdentityIndex and five transitive helpers) is context-owned rather than @MainActor, which is the prerequisite audit for moving refresh persistence to a @ModelActor; background task identifiers derive from the bundle id in both code and Info.plist; catalog fallback quotes dedupe by instrument instead of cancelling the previous card's; the Magic scan vocabulary is no longer recompiled on every Scan-tab appearance. Slice 4 bounds PriceCheckDay coverage to a 400-day window and prunes behind it, with pruned days' coverage read back from the published closes so ALL still renders — measured flat at 1.66s for an 800-day store where the unbounded read would have cost ~3.3s and kept climbing. Signposts and an opt-in aged-store fixture (PERF_BASELINE) produce the numbers. 851 tests, 1 skipped, 0 failures. Slice 5 is now implemented and simulator-verified; its live-provider event-count profile remains recommended. Slice 9's P1/U2/U3 items remain hardware gates, and Slice 10 is closed by the current iOS 17 deployment decision; Slice 8 is recorded below.
- Performance remediation correction: `PortfolioEngine.publish` now carries `carriedForwardValue` from pruned `PortfolioDailyClose` rows alongside the three coverage fields already carried. `testPrunedDaysKeepPublishedCoverage` uses a published `$2` versus pruned `$9` fixture and confirms both the no-revision and late-revision cases preserve the original value/coverage.
- Performance remediation Slice 8 (R4): refresh persistence now runs through a dedicated `@ModelActor`; the main-actor controller retains only the migration gate, queue, cancellation, status/progress, and fallback-budget UI. Targets, both whole-table indexes, `PriceStore`, identity/artwork writes, checkpoint saves, and background refresh target construction are actor-owned; only value requests/results and `PersistentIdentifier`s cross. Target-build failures remain retryable for the automatic stale check, and queued unlimited limits are preserved. Full simulator build/test passed: 850 tests, 1 skipped, 0 failures in 24.561 s. Runtime Instruments capture against a live provider remains recommended; device-gated slices are unchanged.
- Performance remediation Slice 5 (R3): the portfolio observer no longer hashes local price fetch/check timestamps, and the collection projection token preserves only freshness-presence bits plus exact `fetchedAt` for unstamped providers. Focused freshness tests and the full simulator suite pass: 851 tests, 1 skipped, 0 failures. No seeded-store number is substituted for the planned live-provider `makeCachedProjection`/`startRecompute` event count.
- Performance remediation Slice 8 (R4): refresh persistence now runs through a dedicated `@ModelActor`; the main-actor controller retains only the migration gate, queue, cancellation, status/progress, and fallback-budget UI. Targets, both whole-table indexes, `PriceStore`, identity/artwork writes, checkpoint saves, and background refresh target construction are actor-owned; only value requests/results and `PersistentIdentifier`s cross. Target-build failures remain retryable for the automatic stale check, and queued unlimited limits are preserved. Full simulator build/test passed: 850 tests, 1 skipped, 0 failures in 24.561 s. Runtime Instruments capture against a live provider remains recommended; device-gated slices are unchanged.
- Performance remediation closeout evidence: the app-only iPhone build and signed physical test bundle build succeed. The physical test run reached 851 tests with 1 skipped but failed only at `BrowseFeatureTests.testBrowseSearchDebouncesBeforeStartingBothSearchLanes` (a focused retry reproduced its provider-start count mismatch, `0` vs `2`); no P1/U2/U3 code was changed or claimed verified. R5 `#Index` is closed without code because both targets remain iOS 17.0 and `#Index` requires iOS 18; raising the target remains a separate product/migration decision.
- Performance remediation fourth-pass correction (2026-09-05): `ContentView` now keeps `PriceRefreshController.shared` as a plain reference; only the small refresh controls, attention badge and activity row observe progress, so 250 ms status publications no longer invalidate the whole tab tree. Graded v2 requests are also bounded by `JustTCGQuota.maximumPageSize` (20). Focused post-correction simulator tests pass 62/62, the generic test build succeeds, and the full suite passes 857 tests with 1 skipped and 0 failures in 24.814 s. Live SwiftUI/Instruments body and signpost counts remain unmeasured.
- Card-detail redesign S0 (2026-09-06): promoted the shared Liquid Glass surface into `AppGlass.swift`, renamed the scanner-prefixed modifiers to app-scoped names, and kept the iOS 17 fallback plus iOS 26 material branch unchanged. The simulator app build succeeds.
- Card-detail redesign S1–S6 (2026-09-06): rebuilt owned-card detail around a full-bleed hero, unified identity and accessible badges, a single price/movement surface, a bounded treatment-aware finish sheen, and one Market/History/Quantity action strip. Collection tiles and Portfolio holding/contribution rows now reuse the same badge vocabulary; the scoped instrument-key queries, chart step/gap rules, observation kinds, and collection actions remain unchanged. The simulator app build succeeds and the full suite passes 861 tests with 1 skipped and 0 failures. The deterministic CardDetail route launched, but CoreSimulatorService disconnected before screenshot capture, so the visual checklist remains pending a healthy simulator/device session.
- Card-detail visual follow-up (2026-09-06): nil remote artwork now terminates in the existing diagnostic placeholder, the pushed detail destination hides the collection tab bar so the resting identity block is not occluded, and quantity-one movement summaries no longer repeat the same dollar amount per card. The deterministic CardDetail fixtures now carry direct Charizard artwork, and the debug auto-open waits for the seeded snapshot instead of racing it. The inspected dark-mode capture shows the real hero and fully visible identity block. Full simulator suite passes 861 tests with 1 skipped and 0 failures. The clustered-data chart axis remains unchanged pending real multi-day data.
- Card-detail follow-up (2026-09-06): artwork actions now live in the navigation toolbar instead of covering printed hero content. The CardDetail fixture no longer duplicates the current price and successful check day already recorded by `addSealed`, so its chart has exactly two observations and one checked day; a DEBUG surface test pins the stored rows and `2 changed prices across 1 checked day.` summary. The settled dark-mode CardDetail capture was inspected after the cold-launch frame and shows the menu outside the artwork. Full simulator suite passes 862 tests with 1 skipped and 0 failures. Dominant-colour extraction, finish-qualified fixture data, and the clustered-data axis remain explicitly deferred.
- Card-detail deferred-item closure (2026-09-06): artwork accents are now extracted asynchronously from the existing local/remote artwork source, cached by source key, and applied to the hero backdrop without work in `body`; the DEBUG fixture now uses a catalog-resolved holo card with direct artwork so the treatment-aware finish path is exercised; and clustered price observations use their observed span plus bounded padding for the plot domain while preserving step/gap semantics. Focused chart, fixture, and accent tests pass; the settled dark-mode CardDetail capture shows the loaded hero, visible identity block, and menu outside the artwork. Full scheme suite passes 864 tests with 1 skipped and 0 failures.
- Card-detail chart accessibility follow-up (2026-09-06): x-axis tick dates now derive from the fitted plot span, short spans include date-plus-time context, and accessibility-large caps the axis at two labels; fitted charts identify that the selected range is wider than the available data. Dark, light, and accessibility-large route captures were inspected, focused chart tests pass, and the full suite remains green at 864 tests with 1 skipped and 0 failures. The simulator was restored to dark appearance and default text size.
- Card detail finish and holding controls: replaced the foil overlay, which drew a hard-edged rounded rectangle at 82% of the card's width and screen-blended it at 0.72 opacity — a translucent box sitting on the artwork, showing its own corners and lifting the art's blacks. It is now a directional band wider than the card's diagonal, masked to the card so no edge is ever in frame, soft-light blended so the sheen blooms on highlights and leaves shadows alone, with a single narrow additive specular core. Surge Foil renders three bands out of phase, Neon Ink two hue-shifted, reverse holo is masked to the border the printing actually foils. Motion was running the whole time but peaked at 3.6pt of travel on a 400pt card; it now derives from device attitude against a reference captured on appear, tracks rather than lags, and sweeps most of the card. Reduce Motion keeps the finish and rests the band at centre. Quantity moved from a menu at the bottom of the page into the identity block as a stepper, removal moved to the overflow menu, and holding total appears beside the unit price when quantity exceeds one. The artwork is inset with the card's own corner radius, edge and shadow rather than bleeding square-cornered to the screen edge, and the extracted accent is layered over the system background weighted to the top instead of a single 20% stop that was invisible on device. 864 tests, 1 skipped, 0 failures; verified in the simulator in both appearances.
- Card-detail identity block (2026-09-06): relocated printing provenance and rarity to one glance row, reduced copy condition to the most specific true description, kept quantity beside it, and disclosed all remaining metadata through a collapsed-by-default `LabeledContent` fact list. Unknown finish now becomes an actionable confidence note; treatment, graded, unclassified, and sealed branches preserve their evidence without badge clutter. Added tolerant rarity-token coverage, a local artwork accent, and Reduce Motion handling. Dark/light, expanded, and accessibility-large captures were inspected; the full simulator suite passes 864 tests with 1 skipped and 0 failures.
- Card-detail identity review follow-up (2026-09-06): rarity tokens now retain the provider's exact label while classifying only for tint, so named rarities such as `Illustration Rare` are not flattened. The glance palette now uses neutral/silver common families, gold rare, and orange-red mythic; the condition row is semibold primary text. Focused rarity coverage passes; the full simulator suite passes 872 tests with 1 skipped and 0 failures. Settled dark and light CardDetail captures were inspected and the simulator was restored to dark.
- Scan receipt layout fix (2026-09-06): the receipt's `Undo Scan` label had a large intrinsic width and no compression limit, so it beat both the name and the price for space — the price column collapsed and `$62.47` typeset one character per line as a vertical strip, which set the card's height, while the name and identifier both truncated. Undo is now an icon-only 44 pt bordered button keeping its full VoiceOver label and hint; the price is `lineLimit(1)` + `fixedSize` with priority above the title column; the 40 pt thumbnail is gone in favour of a leading green check, since at that size it could not identify a card and cost the name the width that confirms a fast scan; treatment diagnostics moved to their own full-width line. The `WholeCardScanner` DEBUG route now seeds a receipt fixture, because this surface could not previously be captured without a camera, which is how the defect shipped. Capture in `artifacts/scan-receipt-card.png`; full suite passes 873 tests with 1 skipped and 0 failures.
- Card-detail history/options follow-up (2026-09-06): the per-card history destination now captures its collection key in a stable local before building the SwiftData predicate, matching the safe query pattern used by the rest of the app; this removes the dynamic-query crash path when opening history. The artwork actions menu no longer adds a custom black circle behind its label, leaving the navigation toolbar's single Liquid Glass surface in charge. The patched CardDetail route built successfully, opened History, opened the artwork actions menu, and the full simulator suite passed 872 tests with 1 skipped and 0 failures. Direct screenshot-harness capture lost CoreSimulatorService during `simctl` output, so the loaded XcodeBuildMCP frame was inspected instead.
- Graded slab scanning review hardening (2026-09-06): vendor binding now matches company + numeric grade + qualifier, with the label used only to break stable-axis ties; slab suppression, consecutive identity, held-repeat publication, and catalog-miss verification all carry `ScanSubject`; confirmed slab framing remains sticky until the band exits; non-TAG bare numbers cannot become grades; legacy unbound graded price keys remain readable; graded Price Check refreshes cache exact vendor keys and retries unavailable states; and dismissal paths clear pending graded outcomes. The latch compatibility overloads were removed and the regression suite now exercises the subject-aware APIs directly. Focused tests, the generic iOS simulator test build, and the full simulator suite pass. Per-company slab geometry remains a shared calibration hook, and TAG/SGC calibration plus real-device slab capture remain pending hardware verification.
- Scanner pipeline and session UX implementation (2026-09-06): footer OCR now wins same-frame scheduling, tracking defaults to 8 Hz on non-OCR frames, first-plausible confirmation is pulled forward, slab-label OCR is gated, and signposts cover frame, tracking, OCR, confirmation, catalog, persistence, and success UI. Collection writes use an ordered `ScannerCollectionWriter` `@ModelActor` with value-only commit routing and honest Recognized/Added/Failed feedback. Scan keeps a five-card rail plus full session review with async undo/correction, and departure publishes known/unpriced/unresolved counts while clearing the session; backgrounding does not finalize it. Generic app/test builds pass; simulator tests and visual capture remain blocked by the locked Mac/CoreSimulatorService connection.
- Scanner pipeline review hardening (2026-09-06): JustTCG graded requests now send documented uppercase company tokens, omit unsupported TAG and malformed/named grade filters, normalize numeric grade lists, enforce the v2 `type` discriminator, and consume `grading.canonical` for Authentic display. Refresh matching normalizes stored numeric grades. Scanner finalization now has a bounded drain and per-session write fencing so late actor completions cannot contaminate a later visit. Generic build, focused contract/resolver tests, and the full booted-simulator suite pass; real-card timing and visual capture remain hardware validation work.
- Release follow-up backlog (2026-09-07): removed the dead `PortfolioHistoryMode` plumbing and centralized the remaining launch, scanner hardware, projection profiling, and graded-parser test debt in `release_followups.md`.
- Portfolio movers display redesign loop 1 (2026-09-07): contributor rows now label the right-side amount as total movement and show exact replay-derived per-card movement for consistent multi-copy holdings, with a total-only fallback when the affected quantity is unavailable or varied. Debug build and `PortfolioPhase3` screenshot capture passed; the full simulator suite passed 916 tests with 1 skipped and 0 failures.
- Collection tile plan loop 1 (2026-09-07): collection footer hierarchy, footer quantity badges, finish/treatment display suppression, target-sized remote image decoding, high-resolution collection artwork, bounded local artwork storage, and deterministic CollectionTiles QA route implemented. Debug build, focused treatment/downsampling tests, dark/light accessibility-large captures, and the full simulator suite passed 917 tests with 1 skipped and 0 failures.
- Centering keyboard dismissal (2026-09-07): guide numeric fields now track local focus and expose a keyboard-toolbar Done action that clears it, so the number pad can be dismissed while editing outer or inner guide values. Debug simulator build passed; live screenshot capture was blocked after CoreSimulatorService disconnected.
- Most valuable cards owned (2026-09-08): split per-card market price from total position value, rank the dashboard section by the former, and keep duplicate quantity obvious with the existing badge plus total and per-card values. Added focused ranking coverage and a deterministic duplicate-heavy screenshot route; the settled simulator capture shows the higher single-card price above the larger two-copy total.
- Finish lock menu (2026-09-08): replaced the flattened cross-game picker with native per-game submenus, added game-qualified collapsed summaries, and verified the `WholeCardScanner` route on the iPhone 17 Pro simulator. The initial render showed separate `Pokémon Auto` and `Magic Auto` submenu rows; each opened only its own variants, and an active two-game state announced `Pokémon Reverse · Magic Foil`.
- Finish lock global Auto follow-up (2026-09-09): made `Auto` one top-level reset action that clears every per-game lock, removed duplicate Auto rows from the Pokémon and Magic variant submenus, and labels unlocked game rows only by game. The iPhone 17 Pro simulator shows top-level `Auto`, `Pokémon`, and `Magic`; Pokémon exposes only its ten lockable variants, Magic exposes only its three, and selecting `Magic Foil` then global `Auto` restores the unlocked state.
- Documentation/artifact audit (2026-09-09): reconciled stale checklist language with the current additive market-movement and choice-time Price Check designs, recorded deterministic simulator evidence for collection navigation, movement, portfolio, Browse, centering, Price Check, and Magic treatment surfaces, and separated genuine hardware/provider/review gates into the live follow-up documents. The audit also found and fixed the missing `CollectionProjectionStore` environment injection on the `MagicTreatmentSlice4` debug route; the route now builds, launches, scrolls, and renders its receipt and catalog-detail evidence.
- Scanner cancellation recovery (2026-09-09): dismissing a variant, print-run, or identity choice now clears only that encounter's pending "Saving to your collection..." acknowledgement, so a cancelled no-write scan cannot leave the scanner latched indefinitely. Added regression coverage plus a deterministic `ScanChoiceCancellation` DEBUG route; the focused test and full 955-test simulator suite pass. The rendered capture reached the scanner but was covered by the simulator's notification-permission prompt.
- Scanner choice transition follow-up (2026-09-09): the visible "Saving to your collection..." acknowledgement now begins only at the authorized collection-write boundary, after identity/print-run/variant resolution. Recognition haptics and counting remain immediate, while choice-required scans go directly to their choice bar without a transient save banner. The gated timing regression, focused scanner tests, and full 955-test suite pass; the final `ScanChoiceCancellation` capture was inspected with clean scanner chrome and no save banner, choice, or receipt after cancellation.
- Portfolio tab redesign loop 1 (2026-09-09): implemented the mockup refresh on `portfolio-tab-redesign` with split hero currency, gated period-change badge, direction-tinted capsule range control, gradient area chart with start/today captions, horizontal best-card rail, and pill-based mover rows. The app build succeeds; simulator visual and focused Portfolio test verification are next.
- Portfolio tab redesign loop 2 (2026-09-09): settled iPhone 17 Pro captures were inspected for the full Portfolio, movers, and best-cards states; range switching and the accessibility chart surface were verified; focused Portfolio tests passed 146 with 1 skipped and 0 failures. The existing chart scrub overlay, haptics, and descriptor paths remain intact.
- Portfolio tab redesign remaining polish loop 1 (2026-09-09): restored composed VoiceOver labels for best-card tiles and the hero change badge, removed the obsolete axis-precision helper and its stale test, and added `1D` as the leftmost history range with explicit previous-day/live-endpoint coverage. The iPhone 17 Pro shows a sane two-point 1D chart and all six per-card history segments without truncation; the full Contributors sheet intentionally keeps the shared pill-only rows because its range header and movers explanation already provide the context formerly supplied by the redundant per-row caption.
- Portfolio tab redesign remaining polish loop 2 (2026-09-09): suppressed the published-history caveat for the live-only `1D` window and aligned best-card VoiceOver output with the visible movement line by omitting zero-valued per-card movement from the composed label.
- Portfolio tab redesign remaining polish loop 3 (2026-09-09): rebuilt and reran the focused Portfolio suites after the 1D caveat and zero-movement accessibility fixes; the post-fix 1D capture shows the two-point chart without the misleading “History is being recorded.” message.
- Portfolio tab remaining redesign (2026-09-09): completed the palette, value-series chart, full-bleed layout, labeled market-movement total, distributed six-range control, best-card rail, mover row geometry/dividers, direction badge, and arrow-only pill accessibility pass. Live iPhone 17 Pro captures were inspected at the PortfolioToday, PortfolioPhase3, and PortfolioMostValuable routes; the movers popover exposes Full accounting. Portfolio-focused verification passed 174 tests with 1 skipped and 0 failures.
- Portfolio tab mockup completion: implementing the remaining palette, value-chart, full-bleed layout, mover accounting, rail, and badge polish from AppScreen.dc.html; screenshot loop and focused verification pending.
- Portfolio chart fill boundary (2026-09-09): changed the AreaMark from Swift Charts' padded axis baseline to the accounting anchor value, so positive and negative fills terminate at the dashed period-start rule and cannot tint the sections below the chart. Build/run and live PortfolioToday/PortfolioPhase3 captures pass.
- Collection tile footer plan (2026-09-09): replaced variable badge wrapping with four fixed footer rows, added compact rounded/tabular prices, unpriced caveats and counts, appearance-aware finish dots, relative artwork glow, and shared 30/60 Hz finish motion. Added slab/sealed-first status resolution and focused treatment/specular coverage. Standard dark/light and accessibility-large captures were inspected; the full simulator suite passes 959 tests with 1 skipped and 0 failures.
- Collection tile follow-up (2026-09-09): motion now refuses to start and stops on Reduce Motion changes, the grid only requests motion when filtered content has a specular row, and accent extraction follows both remote artwork URLs plus stale-local fallback. DEBUG logs confirmed all four CollectionTiles fixture accents loaded; the settled capture shows the low colored halo below the artwork. Full simulator suite passes 959 tests with 1 skipped and 0 failures.
- Trust-hardening execution (2026-09-10): committed the design spec and created the adversarial benchmark template; the focused pre-change baseline passed 171 selected tests with 1 skipped and 0 failures. Implementation checkpoints follow.
- Trust-hardening UI loop (2026-09-10): beginning the deterministic `TrustCardDetail` capture with `catalogSilent`; checklist is in `docs/benchmarks/trust-provenance-ui-checklist.md`.
- Trust-hardening UI loop (2026-09-10): fixed the replay helper's missing explicit return exposed by the first UI build and rerunning `TrustCardDetail/catalogSilent`.
- Trust-hardening UI loop (2026-09-10): build passed; simulator screenshot output is being staged in `/tmp` because the sandbox rejects direct `simctl` writes to `artifacts`.
- Trust-hardening UI loop (2026-09-10): app-aware simulator capture reached the `catalogSilent` detail state; it visibly shows “Finish not published” without duplicating the finish row.
- Trust-hardening UI loop (2026-09-10): starting the `finishLock` detail capture after the simulator bridge recovered.
- Trust-hardening UI loop (2026-09-10): made the detail route target the exact seeded collection key and wait for projection readiness; the rebuilt `catalogSilent` capture now opens the intended detail and visibly shows “Finish not published.”
- Trust-hardening UI loop (2026-09-10): the rebuilt `finishLock` detail capture opens the exact fixture and shows the finish together with “Finish Lock” in the identity block.
- Trust-hardening UI loop (2026-09-10): the rebuilt `userConfirmed` detail capture shows “Holo · You confirmed” beneath the exact card identity, with no duplicate finish row.
- Trust-hardening UI loop (2026-09-10): the rebuilt `catalogSilent` scan receipt keeps the provenance line prominent in orange; the receipt also exposes the unknown finish as intended.
- Trust-hardening UI loop (2026-09-10): the rebuilt `finishLock` scan receipt shows “Reverse Holo · Finish Lock” as an attention state.
- Trust-hardening UI loop (2026-09-10): the rebuilt `userConfirmed` scan receipt shows “Holofoil · You confirmed” as the attention state.
- Trust-hardening UI loop (2026-09-10): the rebuilt routine `uniqueInCatalog` receipt stays visually quiet—no attention icon or orange emphasis—while still stating “Holofoil · Only variant printed.”
- Trust-hardening UI loop (2026-09-10): final visual pass is captured through the XcodeBuildMCP simulator workflow; the checklist covers deterministic routing, provenance/accessibility text, attention hierarchy, and safe-area layout.
- Trust-hardening verification (2026-09-10): focused trust suites pass 283 tests with 1 skipped and 0 failures; the full simulator suite passes 980 tests with 1 skipped and 0 failures on the final rerun; the compile-only simulator build also passes. The manual 150–300-card adversarial benchmark remains intentionally not executed and is recorded in `docs/benchmarks/trust-adversarial-benchmark.md`.
- Browse screen loop 1 (2026-09-13): implemented the codebase-corrected Catalog root and set-directory spec with Browse kept as a Collection push destination, an all-lane search model, set rail/game fan, adaptive year-grouped set grid, local sort/filter controls, ownership progress treatment, dark-safe asset tints, and Magic SVG fallbacks. App build and focused BrowseFeatureTests pass; deterministic screenshot capture is next.
- Browse screen loop 2 (2026-09-13): inspected the final deterministic Catalog capture, confirmed the title/search/rail/game hierarchy and sealed entry point, then fixed set-list formatting and deterministic completion-sort ties. Final simulator build and focused BrowseFeatureTests pass; alternate appearance capture was unavailable after CoreSimulatorService became unstable.
- Browse screen loop 3 (2026-09-14): reran the deterministic Browse capture, inspected settled Catalog root, Pokémon set directory, search ordering, sort menu, Started filter, and Magic fallback states, and refreshed the Browse checklist. XcodeBuildMCP build and focused BrowseFeatureTests pass (22/22); the repository-wide run reached 1,163 passed and 1 skipped but still reports 45 unrelated missing-fixture/source-environment failures.
- Browse catalog remediation loop 1 (2026-09-14): fixed non-chronological set sorting/grouping, tile progress and hairline layout, dark progress/badge contrast, lazy sealed search gating, hot-path artwork/set-ordering work, rail readiness, and related accessibility/polish details. The focused BrowseFeatureTests suite passes 28/28 and the app build succeeds; a fresh screenshot attempt was blocked by a recurring CoreSimulatorService connection failure.
- Browse catalog close-out (2026-09-14): removed the lazy sealed-search trigger and stale directory mirror, restored ordered card-then-sealed search, capped fan artwork defensively, simplified recent-row ordering, and added oldest-first/Started-filter coverage. BrowseFeatureTests passes 30/30 and the iOS Simulator build succeeds. Pre-release manual pass remains: confirm set tiles announce their set name and button trait without exposing artwork/progress internals, DisclosureGroup expands and collapses cleanly, and BrowseSetBadgeFill remains legible in dark mode with tiles fitting at AX5.
- Scanning workflow review (2026-09-14): completed roadmap Slices 1–5 and Slice 6 instrumentation: invalidated identification tasks are cleared immediately, scan counter resets no longer flash, dead scanner state was removed, catalog-miss observation hops are gated, informational receipts keep the tab bar stable, and fallback-price queue cost is signposted. ScannerViewModel, CameraPreview, and catalog-miss regressions pass; the WholeCardScanner receipt capture confirms tab-bar/safe-area behavior. The XcodeBuildMCP full simulator run discovered 1,256 tests and reported 48 unrelated fixture/source-environment or signal-kill failures, so the repository-wide suite is not recorded as clean.
- Browse implementation close-out (2026-09-14): implemented the unified card/sealed Catalog search, game-level Cards/Sealed navigation, cached-credential sealed states, dated release rail, game summaries, set sorting/progress copy, missing-art fallback, and grouped Pokémon finish tiles. The prescribed Browse route built and rendered a settled Catalog root with the Collection tab selected, release rail peek, and one row per game. `BrowseFeatureTests` plus `UncoveredSurfaceTests` pass; the full target remains non-clean only in unrelated centering/fixture and scanner-environment tests.
- Browse implementation visual recheck (2026-09-14): after the final grouped-tile cleanup, the simulator briefly returned a black frame while CoreSimulatorService disconnected; a delayed capture after service recovery again rendered the settled Catalog root correctly.
- Browse audit remediation (2026-09-14): stabilized unified pagination task identity and cancellation handling, made cached sealed directories load without credentials, gated inactive card search, cached ranking/grouping hot paths, pre-sorted game-row artwork, added tile re-appearance artwork retry and grid card-count fallback, hardened Magic display identities, and completed the Browse cleanup. Focused `BrowseFeatureTests` plus `UncoveredSurfaceTests` pass; the Debug Browse build and settled iPhone 17 Pro capture pass.
- Browse audit verification follow-up (2026-09-14): corrected the sealed credential test ordering so its provider-call and error-copy assertions are independent, added regression coverage for the inactive Sealed-segment card-search gate, and verified the real `BrowseFeatureTests`, `SealedBrowseSurfaceTests`, and `ViewConstructionSmokeTests` selectors (46 tests, 0 failures). The final Debug Browse build and settled iPhone 17 Pro capture pass; the full target remains non-clean only in the previously identified unrelated suites.
- Collection header redesign (2026-09-14): implemented the Collection-scoped leading navigation row, full-collection value hero, source-aware refresh status, inline search/filter/sort controls, mixed-scope footer semantics, and Settings-based activity entry point. Focused Collection/view tests pass 43/43; dark, light, accessibility-size, and CardDetail navigation captures were inspected.
- Production defect audit pass 2 (2026-09-14): reviewed the repository against `a4375df` for real and highly probable defects; no application code, tests, schemas, or build settings were changed. The findings are recorded in `docs/audits/defect_review_pass_2.md`: six findings, five confirmed and one suspected. F01 — the shipped `UnprovenCloudRestorationReadinessSource` default makes every `openCloud`/`adoptRemoteCollection` decision terminate in `.restoringFromCloud(.failed)` without installing a session, so a clean install on an iCloud-signed-in device reaches a state whose only affordance reproduces itself; the failed attempt has already written `attachmentState = .attached`. F02 — `CollectionStorageHeadlessPreflightDependencies.production` selects `backgroundMode` from the entitlement alone, so the background refresh builds a CloudKit-mirrored container for exactly the `.neverAttached`/`.suspended` stores it then reports as `.onDevice`. F03 (suspected) — `beginPendingResolution` returns without running its operation after the caller has already cleared the pending choice. F04 — `PortfolioEpoch.establishIfNeeded` writes `initialBalance` events with no matching `CollectionActivity`, which `CollectionActivity.integrityDefects` rejects; production is masked only by a `try?`-swallowed `backfillExistingCollectionIfNeeded` running first. F05 — `InventoryLedger.quantities(from:)` retains negative nets and has no production callers. F06 — 36 of the 40 suite failures are absent-fixture failures that `XCTUnwrap` rather than skip, so the exit status cannot carry gate evidence. Build passes; the full simulator run executed 1,277 with 6 skipped and 40 failures, triaged per suite rather than in aggregate, with the three substantive failures reproduced in isolation. The documentation map, repository audit (C-09/C-10/C-11), release framework §14, ownership-ledger audit, and release follow-ups (RF-6, RF-7) were updated to point at the new audit. No physical device, entitled CloudKit container, live provider, second device, or real camera was exercised.
- Per-card price history chart plan (2026-09-14): traced why the card detail chart renders as isolated dots and recorded the plan in `docs/plans/price_history_chart_plan.md`. No code changed; nothing in the plan is implemented. Cause is coverage, not a chart bug: `allDaysChecked` joins two samples only when every calendar day between them has a `PriceCheckDay` row, those rows exist only for days a refresh actually succeeded for that instrument, and `BackgroundPriceRefresh.appRefreshTargetLimit` prices three cards per `BGAppRefresh` launch. Slice A adds a derived carried-forward bridge between adjacent segments, rendered dashed and step-end, so the chart reads as a line while keeping measured spans visually distinct from last-known ones; it introduces no sample, date, or amount, and leaves `samples`/`segments`/`hasGaps` unchanged. Slice B replaces the background count cap with an elapsed-time budget and is blocked on pass-2 F02 plus the new RF-8 device measurement. Provider history backfill was investigated and rejected for this plan: `PriceObservation`/`PriceCheckDay` are the portfolio valuation ledger, so backfilled rows would rewrite published closes; JustTCG does publish a per-day `priceHistory` array and the `include_price_history` parameter is already plumbed with every caller passing `false`, while Scryfall publishes current prices only and TCGdex exposes rolling `avg7`/`avg30`/`trend` aggregates. The documentation map, repository audit, and release follow-ups were updated to point at the plan.
- Follow-up reference wiring (2026-09-15): bound the open pass-2 findings and the per-card chart plan into the active launch plan so they cannot be orphaned when Phase 0/1 execution resumes. The launch plan gains §0.1.1 (a finding→task table: F01/F02 bind Task 4 and Task 8, F04/F05 bind Task 12, F06 binds Task 1 and Task 11, F03 has no owning task and is triaged before RC) and §0.1.2 (current plans outside launch scope, recording that chart Slice B is blocked on F02). Its §0.1 locator was corrected from `0b4ac34` to `a4375df`, §1.5 no longer repeats the "48 unrelated failures" characterisation that documentation audit C-11 marked partially incorrect, and §7 execution discipline now requires re-reading both new sections before a task is started. Back-references were added from the pass-2 audit, the chart plan, and the documentation-audit roadmap row so either document leads to the other. Documentation only; no code, tests, or build settings changed.
- Pro tab and eBay listing photos plan (2026-09-15): recorded `docs/plans/pro_tab_ebay_listing_photos_plan.md` after reading the separate `/Users/seankeller/Documents/eBay Photos` Flask tool and the current Pro/centering source. No code changed; nothing in the plan is implemented. The plan replaces the Centering tab with a Pro tab hosting card centering plus a new card-independent eBay listing-photo module, and ports only the tool's live path: its worker always calls `process_scans(..., use_full_frame=True)`, so contour detection, perspective warp, OCR, and Pokémon-TCG auto-naming are dead code and are not ported; the ported geometry is `create_quadrant_crops`' four overlapping corner crops at `int(dimension * ratio)` truncation, ratio 0.60 front and 0.63 back. Five deliberate divergences are recorded: the ratio throws outside `0.5...0.9` instead of being silently clamped, JPEG quality matches OpenCV's default 95, EXIF orientation is applied during the single decode (the original ignores it and would crop a rotated photo at the wrong physical corners), exports are numbered `01-Front.jpg`…`10-Back-BL.jpg` because eBay uploads in arrival order, and multi-pair batching is scheduled as Slice C rather than dropped. Outputs are native-resolution slices with no resampling: one decoded side is held at a time, `CGImage.cropping(to:)` is relied on as a non-copying view, orientation is baked by decoding through ImageIO with `kCGImageSourceThumbnailMaxPixelSize` set to the image's own longest edge, and file-size pressure is answered by stepping JPEG quality rather than dimensions. Two source facts drive required changes: `CardCenteringView` owns its own `NavigationStack` and must give it up to be pushed, and `CenteringCameraView` sets no `maxPhotoDimensions` and prefers the ultra-wide macro lens, so the capture path would silently produce ~12 MP while the library path produces 48 MP. An earlier draft's claim that `CenteringCameraView` is too coupled to reuse is corrected in the plan; it already exposes `onCapture: (Data) -> Void`. The plan is sequenced after the release candidate is certified.
- Documentation reconciliation (2026-09-15): synchronized the current documentation set with the new Pro tab plan without changing any status claim. The documentation map and repository audit gained Pro tab rows; the active launch plan's §0.1.2 open-plans table now carries the plan with a "must not begin before Task 18" constraint drawn from its own §7 evidence-invalidation rule; `review/opus-card-centering-implementation-plan.md` gained a presentation-scope note stating that the plan may move where centering is presented and add a camera configuration parameter defaulting to today's macro/`.near` capture, but may not loosen, renumber, or waive any centering requirement; and `browse_screen_spec.md`'s "do not change Centering tab structure" constraint and the audit's C-01 evidence line now name the planned rename as proposed and not implemented. Markdown links in the touched files were validated and `git diff --check` is clean.
- Pro tab and eBay listing photos implementation (2026-09-15, isolated `pro-implementation` worktree based at `523f3e2`): implemented Slices A–C from `docs/plans/pro_tab_ebay_listing_photos_plan.md`. The fourth tab is now a Pro module list; centering is pushed without a nested navigation container; the shared camera keeps its centering default while listing-photo capture selects the main wide lens and active format's maximum still dimensions; the eBay workflow captures or picks front/back data, decodes one side at a time with ImageIO orientation, preserves eligible JPEG bytes, emits native-resolution numbered full/corner JPEGs with eBay's 12 MB byte ceiling and quality step-down, and builds sequentially packaged batch folders/archives without SwiftData persistence. Added cropper/export tests plus view-construction coverage and registered all new files in the Xcode project. Focused simulator verification passes 27/27 (17 centering export, 9 cropper, 1 listing-export), and the compile-only simulator build succeeds. Screenshots were intentionally skipped at the user's request; manual, physical-device, provider, archive, and release-readiness gates remain open, and the implementation is not merged back into `main`.
- eBay listing-photo review remediation (2026-09-15, isolated `pro-implementation` worktree): applied F1–F7 from `review/ebay-listing-photos-review-plan.md`. Batch moves and archive creation now run off the main actor; export quality steps continue through `0.45`; camera max dimensions are applied after session commit and read back from the photo output; in-flight batch controls are disabled and batch start is re-entrancy-safe; EXIF orientation transcode coverage was added; both feature temp roots are swept on entry; and the dead `CenteringCameraView` configuration property was removed. The focused remediation selectors pass 14/14 and the Debug simulator build/run succeeds. F3 hardware capture, manual, archive, provider, and release-readiness gates remain open; the implementation is not merged back into `main`.
- eBay listing-photo follow-up remediation (2026-09-15, isolated `pro-implementation` worktree): fixed N1's stale archive publication after cancellation by re-checking generation/cancellation after the detached archive worker returns; fixed N3 by clearing `isPreparingBatch` on an early `processBatch` exit; and fixed N2 test hygiene by injecting the byte budget and using a small high-frequency fixture. The focused remediation selectors pass 14/14 in 12.2 seconds, and the Debug simulator build/run succeeds. Hardware capture, manual, archive, provider, and release-readiness gates remain open; the implementation is not merged back into `main`.
- Browse set-directory remediation (2026-09-15): completed the artwork fallback, checklist-backed denominator, empty-set, incremental price-sort, shared-detail cancellation, truthful price-load, completion-index ownership, and deterministic candidate-priority slices. The focused Browse selectors pass 127/127 with 0 failures; the regenerated external-SSD snapshot contains 157 entries with standard/expanded denominator parity and no `rc`/`sp`/`wp` entries. All derived data, build products, module caches, temporary files, and result bundles for this verification were redirected to the external SSD. Screenshots A8/B6 and live-provider/device measurement C7/RF-9 remain intentionally open.
- Browse set-directory remediation hardening (2026-09-15): fixed case-folded duplicate set-ID checklist reuse, one-pass ownership ranking across provider aliases, retry-triggered completion rebuilds, single price-request identity, memory-warning detail-waiter safety, and artwork candidate deduplication/data-driven parent ordering. The focused Browse selectors pass 128/128 with 0 failures; the regenerated external-SSD snapshot contains 157 entries with standard/expanded denominator parity and no `rc`/`sp`/`wp` entries. All derived data, build products, module caches, temporary files, and result bundles for this verification were redirected to the external SSD. Screenshots A8/B6 and live-provider/device measurement C7/RF-9 remain intentionally open.
- Browse set-directory sort-price cache correction (2026-09-15): fixed two defects found reviewing the second hardening pass. `BrowseCatalog.produceSortPrices` wrote back only the slots the current request covered, so the C5 first-page prefetch truncated a fully priced set's stored ordering map to one page on every cold open and re-crawled the remainder — it now merges into the stored map and carries forward only a fresh envelope, so a stale map's age is never reset without re-pricing the slots the request skipped. Its early returns on cancellation and on a task-group throw also skipped `continuation.finish()`, which would leave the set screen suspended in `for await` with the price banner stuck; the finish moved to a `defer`. Added `testNarrowerSortPriceRequestDoesNotTruncateTheStoredMap`, confirmed failing against the pre-fix write path before the fix was restored. The focused Browse selectors pass 129/129 with 0 failures on the external SSD. Plan C4 and its C6 box were reconciled. A8/B6 visual verification and C7/RF-9 provider measurement remain open.
- Browse set-directory visual close-out (2026-09-15): completed the authorized settled light/dark simulator capture at the Pokémon set directory, confirmed the A8 logo-weight/wordmark/plaque checks, HIF's non-zero `69 cards` count, CRI's `203` completion-denominator parity, and the absence of `rc`/`sp`/`wp` tiles. The same scroll session visually confirmed all eight remaining bundled-logo identities; their exact MD5s are recorded in the remediation plan. Evidence is linked from [`artifacts/pokemon_browse_checklist.md`](artifacts/pokemon_browse_checklist.md). A8/B6 are closed; C7/RF-9 remains open.
- Browse set-directory artwork fallback correction and final revalidation (2026-09-15): the initial A8 frame exposed SVI's dead stored `.png` derivative, so the artwork chain now tries the stored `.png`, its extensionless stem, and the explicit TCGdex `.webp` image derivative in that order, including for older downloaded overlays and inherited parent artwork. The focused Browse selectors pass 130/130 with 0 failures. The final settled light/dark `rerun2` capture shows SVI rendered normally, confirms the logo-weight/wordmark/symbol-plaque checks, HIF's non-zero count, CRI's `0/203` detail denominator, and the absence of `rc`/`sp`/`wp`; A8/B6 are closed again. The eight bundled-logo MD5 results and visual identity checks are recorded in the remediation plan. All build products, caches, temporary files, and result bundles remained on the external SSD; C7/RF-9 remains open.
- Browse artwork/cache hardening (2026-09-16): added TCGdex-only host gating for extensionless candidates, `/univ/`↔`/en/` symbol-prefix fallback, decode-before-persist with eviction/retry for undecodable legacy cache entries, and regression coverage for both invalid and valid cache bodies plus concurrent fetch coalescing. The focused Browse selectors pass 133/133 with 0 failures. A storage-controlled `xcodebuild` rerun routed `TMPDIR`, Clang/Swift module caches, DerivedData, and the `.xcresult` to the external SSD; the result is `.codex-cardscanner-build/browse-set-remediation-20260915/results/browse-artwork-hardening-20260916-external.xcresult`. The XcodeBuildMCP test-products bundle and logs from the initial run were also moved onto the SSD. No screenshots were taken in this follow-up. A8/B6 remain closed and C7/RF-9 remains open. Xcode emitted one non-failing warning that `CardFinishRenderPlanTests.swift` is in the Copy Bundle Resources phase.
- Browse artwork batch / F06 project-resource correction (2026-09-16): verified the 57-file centering corpus is tracked and fixed the duplicate PBXBuildFile/PBXFileReference UUIDs plus the dangling fixture-group reference. The simulator build succeeded and fixture-reachability and corpus-manifest tests passed. The focused selection produced 38 results: 28 passed, 9 test cases failed on known centering accuracy/invariant/performance assertions, and 1 profile-dump test was canceled; this was not a full-suite rerun. Diagnostic-dump tests wrote seven tracked outputs in the repository; exact generated versions were copied to `.codex-cardscanner-build/browse-set-remediation-20260915/results/f06-generated-diagnostics-20260916/`, and tracked copies were restored. DerivedData (including Xcode's module and compilation caches), TMPDIR, result bundle (`f06-fixture-copy-20260916.xcresult`), and preserved generated diagnostics are on the external SSD; the package-source clone path was also directed there (no package fetch was needed). No screenshots were taken. F06's missing-bundle cause is corrected; centering assertions and a complete suite baseline remain open.
- Pass-2 storage/scanner remediation (2026-09-19): implemented F01's safe local fallback and delayed `.attached` manifest claim, F02's manifest-derived headless container mode plus active-mode publication, and F03's pending-answer retention when the identification pipeline is busy. Focused iPhone 17 Pro iOS 26.5 simulator verification passes 64 storage/policy/continuity tests in Debug, the same 64 in DebugProduction with one intentional entitlement-gated skip, 20 readiness tests, and the new pending-resolution regression. Entitled-device clean-install, background-refresh, CloudKit production, archive, and full-suite gates remain open; F03 chose recoverable retry rather than a formal reachability proof.
Exact-branch evidence pass (2026-09-20, candidate `7dbaf40`): focused iPhone
17 Pro iOS 26.5 simulator selection covering scanner, Browse/UI,
collection/projection, Pokémon catalog, and Magic catalog suites executed 581
tests: 579 passed, 1 skipped, and 1 failed in
`ScannerViewModelTests/testCatalogMissVerificationStillFilesUnresolvedCard`.
The storage-safe full simulator suite used external-SSD DerivedData, module
caches, package cache, and result bundle; it executed 1,278 tests with 6
skipped and 4 failures (1 unexpected), spanning current centering,
ownership-ledger, and the scanner catalog-miss test. Result bundles are under
the external-SSD `exact-7dbaf40` directory. The earlier `a4375df` run remains
historical.
- Ownership-ledger gate close (2026-09-20, candidate `7dbaf40`): reproduced and
  fixed F04 by writing baseline `CollectionActivity` alongside each
  `initialBalance` event, fixed F05 by excluding negative reconstructed nets,
  and made source-inventory verification independent of the test runner's
  working directory. The exhaustive mutation/restart/rollback matrix passed
  105 of 106 selected tests with one intentional opt-in skip and zero
  failures. Evidence is in the external-SSD
  `exact-7dbaf40/ownership-matrix.xcresult`; simulator ownership is closed,
  while entitled CloudKit production and two-device convergence remain open.
- Collection card detail redesign (2026-09-22): restructured the detail page into
  centered artwork/identity/valuation, truthful chart, marketplace, ownership,
  and printing-details sections; added the minimum-envelope chart-domain tests;
  the external-SSD Debug simulator build succeeded. The focused chart test
  selection remains blocked by the pre-existing `CardCenteringMeasurement`
  API mismatch in `CenteringExportTests`; screenshot iteration was stopped at
  the user's request after the detail route was visibly reached.
- MEP 095 unresolved-scan messaging (2026-09-22): distinguish explicit
  provider not-found results for exact identifiers from unconfirmed matches,
  preserve the cautious reason when rows merge, and show provider-unavailable
  retry copy. The focused HistoricalTitleCapture, ScannerViewModel, and
  ScanParser selections pass 115 tests; iPhone 17 Pro iOS 26.5 simulator
  screenshots confirmed mixed-row and catalog-only copy plus combined row
  accessibility labels. No physical-device or later TCGdex publication check
  was performed.
- Guided centering repair verification (2026-10-02; uncommitted working tree
  based on `73898e8`): implemented perspective-preserving guide edits, shared
  finite/nested geometry eligibility, request-scoped diagnostics, newest-input
  fencing, and immutable export snapshots. Seven centering classes executed
  109 cases with only the latency case failing (two unchanged assertions);
  the remaining target executed 1,661 cases with seven existing skips and zero
  failures. Original automatic transform research gates remain open; independent
  reviewed annotations validate the guided path. The owner accepted latency
  deferral. Initial phone/default and maximum accessibility captures were
  inspected; toolbar crowding and preview height prompted focused UI refinements.
  Final visual/build verification continues in the
  [repair ledger](docs/audits/centering-guided-repair.md).
- Guided centering final verification (2026-10-02; same repair working tree):
  final regression selection passes 1,692 cases with seven existing skips and
  zero failures; the preceding 109-case centering selection retains only its
  unchanged latency failure. ReleaseLocal builds for both simulator architectures.
  Final phone/tablet light/dark, rotation, zoom/pan, numeric-control, and maximum
  accessibility-text captures were inspected. Native simulator confirmation,
  live edge updates, phone share-sheet presentation, and anchored iPad export
  popover were verified. Temporary appearance/text-size settings were restored.
  Physical-device test launch was blocked by a locked-device/runner connection;
  no device pass is claimed. The owner accepted latency deferral; automatic
  accuracy, actual VoiceOver/share/save, and release gates remain open in the
  [repair ledger](docs/audits/centering-guided-repair.md).
- Uncommitted-change review (2026-10-02; `73898e8` plus the repair working tree):
  fixed crossed-guide coordinate relabeling, unrecoverable coincident guides,
  double-inversion eligibility, confirmed control-route expansion, and numeric
  fields embedded in Stepper labels. Three geometry regressions were reproduced
  before fixing them. Seven centering classes execute 111 cases with only the
  existing latency case failing; the final UI/export/input rerun passes all 33
  correctness cases, with the isolated latency recheck still failing at
  1.5814/1.8764 seconds median/maximum. Final ReleaseLocal simulator build passes
  for arm64 and x86_64; project parsing, shell syntax, 202 local Markdown links,
  and diff whitespace checks pass. Final outer controls were visually checked;
  the locked Mac blocks the final accessibility-tree and incomplete inner-capture
  rechecks. Current evidence and limits are in the
  [repair ledger](docs/audits/centering-guided-repair.md).
- Production refinement B–J implementation (2026-10-03; uncommitted tree on
  `fix/october-review-boundaries` against `dd2a1e3`): separate local monthly
  spending from provider billing counts; fence batch/certificate publication;
  route catalog recovery through the original scan; refresh live Magic
  directories; display slab grades and exact vintage quotes; preserve complete
  activity snapshots on read failure; reject duplicate publisher IDs safely.
  Final signed simulator regression: 1,714 cases, 1,707 passed, seven existing
  skips, zero failures; Pokémon package: 74/74 passed. The initial full run's
  mock and edition-price defects were corrected; its centering latency case
  remains open with unchanged limits. The retry-save harness now waits for the
  task to become idle before answering. The owner deferred further screenshots,
  profiling/device/native acceptance and confirmed legal/support placeholders.
  No commit, deployment, speed improvement, or release certification is claimed.
  See the [implementation and evidence record](docs/plans/october-production-refinement-review-plan.md).

- One Piece scanner choice/UI correction (2026-10-05; `534127f` plus local
  changes): one available verified printing now resolves automatically, matching
  Pokémon/Magic's choice rule; multiple printings and supported finishes still
  ask. The bundled Shiki OP17-047 saves without either picker. Persisted singleton
  choices remain valid only after exact adapter revalidation. The remaining
  picker uses a smaller headline, stacked set subtitle, compact rounded actions,
  and two columns from three choices. Two passing simulator runs cover 118
  distinct cases (97 plus 56 overlapping); phone captures verify long titles,
  accessibility3, 61 choices and unavailable artwork. Native fixture checks
  verify Details without selection, choice 2/61 and skip. The screenshot helper
  accepts an optional capture delay for catalog preparation. Logs/captures remain
  on the external drive; no physical-device or release acceptance is claimed.

- One Piece integrated local acceptance (2026-10-05; `f40e704` plus local
  changes on `merge/one-piece-integration`): implemented the plan's next major
  slice using the full signed owner catalog and actual scanner callbacks,
  printing/finish selection and collection writer. The optional Debug route
  isolates test collection/recovery storage and starts after initial projection;
  ordinary owner launches retain their storage. Initial captures exposed startup
  projection and recovery-load races. The route now waits for readiness; shared
  recovery serializes disk reloads, defers saves and retains removals while loading.
  Full-corpus regressions verify distinct same-number UUIDs, exact mapped/unmapped
  pricing and overdue refresh, Browse/details/add, disk reopen, CSV and skip/retry.
  Nine-class regression: 315/316 passed; its monitor fixture enabled observation
  before starting Portfolio. After correcting the fixture, all five monitor cases
  passed. All 70 One Piece and 96 scanner cases passed in the broader run. Final
  Debug simulator build and helper syntax check pass. Inspected settled picker,
  Normal starter and Foil booster receipts; native recovery/details/retry and
  relaunch checks are recorded in the
  [acceptance checklist](references/one_piece_acceptance_success_checklist.md).
  Evidence remains on the external SSD. The next code slice is explicit
  supersession migration and failed-save collection evidence; hardware/provider,
  CloudKit, rights and release gates remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md).
  The ready-marker loop caught an unsupported unknown-sample series; replaced
  it with OP01-999. The affected real-catalog sample regression passes for every
  route state in `Acceptance-Samples.xcresult`.

- **2026-10-05 — One Piece variants/catalog edge-case audit:** reviewed the
  retained 2,692 canonical cards and 2,745 printings across admission, scan,
  printing/finish choice, Browse, CSV, recovery and exact pricing. Fixed external
  SKU qualifier/numeric alias collisions, duplicate mappings, unanchored product
  appearances, invalid product/finish metadata, missing CSV finish, foreign
  price authority, primary-release order, older persisted printing choices and
  exact One Piece finish-lock identity. Negative cases reproduce the defects;
  full core 44/44 and offline Python 49/49 pass. The broader selected app run
  passed 389/389, including all 2,490 eligible English printings across Browse,
  recognition/choices and CSV finishes. After the final finish-lock fix, the
  affected recheck passed 204/204 (74 One Piece, 96 scanner, 34 variant), including
  the full-corpus walk again. These are separate passing selections. Evidence
  is retained on the external SSD under
  `CardScannerBuild/OnePieceVariantAudit-2026-10-05/`. Catalog statuses, permanent
  UUIDs and ownership/payload formats are unchanged; no retained rows were
  migrated. See the [edge-case audit](docs/audits/one-piece-variants-catalog-edge-cases.md)
  and [implementation ledger](docs/plans/one_piece_code_implementation.md).

- **2026-10-06 — One Piece existing-save reliability** (`230a55f` plus local
  changes on `merge/one-piece-integration`): added disk-backed real-writer
  failure/retry coverage for scanner insert/increment, same-session and relaunch
  recovery, an unrelated subsequent save, six finish-correction combinations,
  and signed catalog price-withdrawal publication. Failed writes preserve
  ownership, claims, ledger lineage, price/history and artwork; retry commits
  once. Withdrawal failure retains installed authority and manual/imported
  values. Source artwork remains available for undo. Scoped Debug hooks throw
  immediately before the normal save; no production save defect was reproduced.
  The initial compile and fixture-expectation errors were corrected. Final
  focused tests pass 5/5; the affected twelve-class Debug simulator selection
  passes 380/380 with no skips/failures, including all 80 One Piece and 96 scanner
  cases. These are separate runs with overlapping tests, not 385 distinct cases.
  Debug and generic `ReleaseLocal` simulator builds pass; the release executable
  contains arm64/x86_64, and its arm64 symbols omit the Debug failure hooks.
  All 149 checked local links and diff whitespace checks pass; no screenshots
  were required for this unchanged interface.
  Results and synthetic fixtures are on the external drive under
  `CodexBuilds/OnePieceSaveReliability-20261006/`. The owner deferred speculative
  supersession under KISS/YAGNI; the retained registry has no correction records
  or superseding printings. Next recommended acceptance slice: existing One Piece
  physical-camera scan/choice/save/relaunch. Mid-save crash recovery across two
  SQLite configurations, full storage/account, device/provider/CloudKit and
  release gates remain open. See the
  [implementation ledger](docs/plans/one_piece_code_implementation.md) and
  [priority reconciliation](docs/plans/documentation_audit.md).

- **2026-10-06 — One Piece camera acceptance preparation** (clean `3fe972a`,
  `merge/one-piece-integration`, before these evidence-document edits): built
  the ordinary signed Debug iOS app with all build data on the external SSD.
  Build and signature verification pass; original name/bundle identity and
  unchanged owner seed hash are verified. In-place installation succeeds on
  iPhone 15 Pro Max / iOS 26.6.1. Launch without review flags is denied because
  the phone is locked. Five compile warnings, no errors; no application code
  changed or tests rerun. Prepared six bounded sample records using the retained
  registry and the existing parent sample selector. All physical observations,
  existing-collection confirmation, camera/save/relaunch, offline/recovery,
  accessibility, provider and sync acceptance remain pending. No uninstall,
  data reset or collection export occurred. Evidence is external under
  `CodexBuilds/OnePieceCameraAcceptance-20261006-3fe972a/`; raw device logs and
  identifiers are not in the repository. Next: unlock/open the usual app and
  present an exactly matched owner card for the first checkpoint in the
  [camera plan](docs/plans/one_piece_camera_acceptance_slice.md); see the
  [device record](docs/plans/one_piece_device_review.md).

- **2026-10-07 — Catalog artwork, visual iteration 1:** initial simulator
  capture confirmed deliberate Magic code tiles, missing One Piece artwork
  projection and card-fan overflow. Reused real Magic card/illustration URLs,
  and constrained fan alignment. Existing regression coverage established that
  One Piece source images are review evidence by default. The owner explicitly
  requested real One Piece cards, so the owner bootstrap now opts into exact
  recorded manufacturer image URLs tied to each artwork's hash; general review
  and production defaults are preserved. One Piece does not use the nautical
  emblem. Missing-art visual QA uses a Debug-only fixture with no collection
  writes. Evidence is external under
  `CodexBuilds/CatalogArtwork-20261007/`.

- **2026-10-07 — Catalog artwork, final visual verification:** corrected the
  illustration bounds so NEW/game badges stay visible, and suppressed failed
  fan slots instead of showing gray card backs. Inspected the settled real
  catalog in light and dark, accessibility-extra-large text, the deterministic
  missing-artwork state and the repeated final dark capture. The owner catalog
  shows actual One Piece card renders; absent One Piece game artwork leaves a
  text-only row. Decorative fans hide at accessibility text sizes. The focused
  browse/One Piece/Pokémon suites passed 216 tests; a final selected rendering
  recheck passed 7 overlapping tests, and the final app build succeeded.
  `git diff --check` passed. The scoped visual/HIG checklist and screenshots
  remain on the external SSD under `CodexBuilds/CatalogArtwork-20261007/`.
  General review/production artwork defaults remain unchanged; this enables
  recorded artwork in the owner's local configuration. No physical-device
  installation or verification was performed.
