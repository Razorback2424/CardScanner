# One Piece v1 release acceptance

**Status:** owner app supports One Piece in its existing local collection;
production publication disabled, production writes off.
**Date:** 2026-10-05. Latest local acceptance: `merge/one-piece-integration`,
`f40e704` plus local changes; earlier preparation used `534127f`.
The [implementation ledger](one_piece_code_implementation.md) records code/tests;
the [catalog design](one_piece_catalog_integration_plan.md) governs identity.

## Owner-approved decisions

The owner requested the original app name, original collection and ordinary
launch with One Piece added. The [installed app record](one_piece_device_review.md)
supersedes the isolated review app as the owner's daily-use path. Its verified
local catalog permits writes in the existing collection; production rollout
gates below apply to publication and distribution.

| Decision | Approved policy | Remaining evidence |
| --- | --- | --- |
| Installed clients | Only the owner has older builds. Control distribution and retain existing entities. | Retire older installations on every synced device before writes; expire older TestFlight builds if any. |
| v1 scope | English, verified physical printings, text only, exact printing/finish market mappings; incomplete coverage goes to Needs attention. | Printing samples, unavailable pricing, recovery and accessibility acceptance. |
| Sources | TCGCSV/TCGplayer for market data; official One Piece card site for reconciliation; no shipped artwork. | Record source-use/redistribution terms and attribution review before publication. The choice does not establish permission. |

Provisional/conflicted records remain in the durable signed registry as
unselectable history. Do **not** prune their UUIDs to make a “verified-only”
payload. Verified-only describes acquisition eligibility. Held market decisions
stay unavailable and cannot borrow another printing's quote.

## Local preparation

- Seed preparation runs in a detached task after startup UI can appear. Production
  logs record envelope bytes, envelope decode time and combined verification/index
  time. Use Instruments to measure peak memory and first-frame timing on hardware.
- Remote recovery offers explicit reload instead of replacing visible screens.
  Reload explains its navigation reset and is unavailable during scanning,
  identification, pending choices or writes. No-change retries retain bindings.
- `ONE_PIECE_COLLECTION_WRITES = NO` is the default. Only explicit `YES` and
  `remote-authority` grant writes. Validation-only and disabled ignore that flag.
  Each rollout mode/write change requires another app build.
- Hosting uses no-cache `/one-piece/v1/current.json` and immutable
  `/one-piece/v1/releases/**`. Pokémon/Magic restoration also preserves One Piece,
  verifies signatures/contracts/revisions against app-pinned keys, requires the
  pointer to match its immutable release, and refuses conflicting artifacts.

## Kit and reproducible review samples

The [installed app checklist](one_piece_device_review.md) records the corrected
normal-app update and owner checks.

Follow the [local review instructions](../../TradingCardScanner/OnePieceCatalogSeed/LOCAL_REVIEW.md).
The isolated review tool remains optional developer test infrastructure. The
owner uses the same signed corpus in the normal collection. The current
preparation tool reads the full retained ordinary corpus; the earlier
306-printing kit is historical. Its key is ephemeral, storage is isolated, prices
use exact mappings and it performs no remote One Piece catalog updates.

The normal local Xcode project bundles that signed corpus and public pin, so
owner activation does not require retained preferences, custom Info.plist
settings or a copied Documents seed. Production builds do not activate this
local-only path.

```sh
python3 scripts/prepare_one_piece_acceptance_samples.py \
  --output /external/OnePieceAcceptance/samples.json
```

Supply a new output path. Deterministic selection records a semantic registry
SHA-256. Current source yields 60 retained product entries (52 with verified
candidates), up to ten eligible printings per entry, all 19 cards with multiple
verified printings, 50 exact price mappings and 50 device samples covering ST,
OP, EB and P. Empty groups remain visible; they do not become acquisitions.
This replaces the attachment's assumption that all 58 capture groups have ten
selectable cards. Record physical/official release, language, treatment and finish
matches, provider product/finish, observed quote and timestamp. Keep private
exports and raw account/device identifiers outside the repository.

## Reproducible simulator acceptance route

The `OnePieceAcceptance` route is compiled only with `DEBUG LOCAL_ONLY_SIGNING`.
It uses the verified bundled full corpus, the real scanner confirmation callback,
printing/finish controls and collection writer. Its test collection and unresolved
scans persist under `Application Support/OnePieceAcceptance`; ordinary launches
continue to use the owner's existing collection. It never starts the camera.
This is number injection and simulator UX evidence, not OCR/device evidence.

Launch with `-ui_debug_route OnePieceAcceptance`. Optional `-ui_debug_state`:

| State | Sample | Acceptance purpose |
| --- | --- | --- |
| `same-number` (default) | ST11-003 | Choose original ST11 and later ST16 separately; both support normal, only ST11 has an exact mapping. |
| `starter` | ST01-003 | Sole verified starter printing/normal finish saves directly. |
| `booster` | OP01-120 | Sole available verified Shanks/foil printing saves directly. |
| `unmapped` | P-001 | Verified winner/foil saves without manufacturing a quote. |
| `unknown` | OP01-999 | Missing number in a recognized series goes to Needs attention without ownership. |

The route's number menu and **Inject number** action allow repeated encounters.
Skip a printing, open Needs attention and retry it; the current full catalog must
ask again. Switch to Collection for Browse/add and price refresh. Relaunch with
the same route to reopen test storage. Real provider answers remain subject to
availability and are distinct from deterministic test-source prices.

For a capture using an already-built Debug binary, retain app data:

```sh
UI_PREBUILT_APP_PATH="$task_build_root/DerivedData/Build/Products/Debug-iphonesimulator/TradingCardScanner.app" \
UI_PRESERVE_APP_DATA=1 \
ARTIFACTS_DIR="$task_build_root/OnePieceAcceptance/same-number" \
bash scripts/ui_build_and_shoot.sh TradingCardScanner com.seankeller.CardScanner \
  OnePieceAcceptance same-number
```

Set `task_build_root` to the available external artifact drive and run from the
repository root. The helper waits for the route's resolved-state readiness
marker before capturing; it fails after 30 seconds if the state never settles.
The [acceptance checklist](../../references/one_piece_acceptance_success_checklist.md)
records the rendered checks. This developer route is optional test infrastructure;
it does not replace the owner's ordinary app launch.

## Signing, hosting and rollback

1. Choose protected storage outside the repository for production and standby
   Ed25519 private keys. Generate independent keys, for example production ID
   `one-piece-catalog-production-2026-10-05-01` and a distinct standby ID. Pin only
   public values in [the config](../../Config/OnePieceCatalogProduction.xcconfig).
   The app rejects reuse of Pokémon/Magic public keys. Key creation is pending
   the owner's storage choice; no production private keys have been generated.
2. Configure GitHub environment `one-piece-catalog-signing`, owner as required
   reviewer, secret `ONE_PIECE_CATALOG_SIGNING_KEY` (base64 32-byte seed) and
   variable `ONE_PIECE_CATALOG_KEY_ID`. Keep the standby private key offline.
   Never put secrets in commands, commits or logs.
3. Approve exact candidate bytes/SHA-256 after sampling. Run the
   [workflow](../../.github/workflows/one-piece-catalog.yml) with signing enabled,
   bootstrap only for revision 1, and no previous envelope. It signs and independently
   verifies against app-pinned keys; it does not deploy. Later releases require
   the previous verified envelope and increasing revisions.
4. Add the identical approved envelope to the app target as
   `one-piece-catalog-release.json` with resource membership. Prepare
   `publisher/site/one-piece/v1/releases/1/catalog-release.json` and
   `publisher/site/one-piece/v1/current.json` from identical verified bytes.
   Before complete-site deployment, preserve existing namespaces/revisions using
   `scripts/restore_catalog_hosting_site.sh`. Optional ninth argument is the
   existing One Piece pointer; otherwise it fetches that pointer. Validate cache
   rules with `scripts/verify_pokemon_catalog_hosting_config.sh`.
5. Rehearse staging revision 1 → changed revision 2 → revision 3 restoring
   revision 1's reviewed content. Preserve physical UUIDs and rebuild indexes.
   Publishing revision 1 after revision 2 is rejected; rollback creates a higher
   revision. Keep the app's production HTTPS origin allowlist enforced.
6. Rehearse a new build with rollout `disabled`. This is a build-time kill switch,
   not an instant remote toggle. Preserve existing collection rows.
7. Set the approved production origin and ship `remote-validation-only` first,
   then `remote-authority` with writes off, then an owner-only writes-enabled
   build after retirement/sync acceptance. External TestFlight and App Store
   follow device/provider acceptance and archive validation.

## Evidence still required

| Gate | Procedure | Status |
| --- | --- | --- |
| Camera/device | Oldest/current iPhone, 50 ST/OP/EB/P cards, lighting/glare, OCR rate, confirm time, offline/cold activation. | Pending hardware runs |
| Local durability | Scan, choose printing/finish, save, process relaunch, refresh; same number/different UUID; unmapped quote unavailable. | Integrated simulator disk-store/Browse/CSV and rendered checks recorded; hardware pending |
| Coverage recovery | Unknown number retained in Needs attention; dismiss/re-file/retry preserve evidence, session and commit provenance. | Full-corpus skip/reload/retry and gated startup/dismissal races pass; rendered controls inspected; hardware pending |
| Accessibility | VoiceOver on choices, Needs attention and recovery banner; Dynamic Type and disabled controls. | Pending device review |
| Performance | Device/OS, signed bytes, decode, verify/index, first-frame timing and peak resident memory. | Logging prepared; hardware measurements pending |
| Provider | 50 exact mappings, aggregate USD quotes/timestamps, rate limits, stale/offline cache and withdrawals. | Code verified; live-provider sampling pending |
| Mixed clients | Inspect pre-integration `69c714f` on a second test device before retiring it. Keep test rows out of the real production collection. | Pending two-device test |
| Sync | New↔new and new→capability-disabled: read-only preservation, metadata/prices, CSV, edit, delete/undo/restore and activities. | Pending CloudKit test |
| Release | Full app suite, archive, signed resource/pins/origin inspection, staging rollback and disabled-build rehearsal. | Pending release candidate |

Local work does not close hardware, rights, signing/publication, CloudKit or
archive gates. Production remains disabled with empty pins/origin until an
approved signed candidate is ready.
