# Local One Piece base-case review

Status: implemented and simulator-tested against reviewed award and FILM RED
retail data — 2026-10-04. This is an opt-in `DebugRemoteLocal` launch, not a
production seed.

The debug binary must have `DEBUG LOCAL_ONLY_SIGNING`; release and entitled
builds ignore these launch flags. The review launch registers scan, Browse and
collection writes from an independently verified signed catalog. It performs no
remote One Piece update and has no price adapter. Collection databases, manifest
and unresolved scans use `Application Support/OnePieceLocalReview`, separate from
the ordinary collection. Keep the review flags on subsequent launches to reopen
that collection; ordinary launches retain the production disabled configuration.

## Prepare

Use the existing publisher executable after building `OnePieceCatalogCore` on
the external artifact drive. Supply a new output directory; the preparation tool
refuses to overwrite an existing kit.

```sh
python3 scripts/prepare_one_piece_local_review.py \
  --publisher '/external/OnePieceCatalogCore/debug/one-piece-catalog-publisher' \
  --output-dir '/external/OnePieceLocalReviewKit'
```

The tool uses the reviewed registry and combined retained observations/inventories,
validates a fresh candidate, and signs it with an ephemeral `one-piece-local-review`
key. Only the public key, signed envelope and manifest are retained. It retrieves
no provider data or image assets. The kit contains the verified P-001 winner,
twelve verified FILM RED retail printings, 34 standard cards across ST-01–ST-04
and 59 standard OP-01 printings, plus retained provisional/conflicted publisher
review records;
it is not the full English catalog.

## Launch

Install the already-built `DebugRemoteLocal` app on a booted simulator. Copy the
signed envelope into that app's Documents directory, then launch with its public
key. These commands assume the kit location above; substitute the actual paths.

```sh
review_app_data=$(xcrun simctl get_app_container booted com.seankeller.CardScanner data)
cp '/external/OnePieceLocalReviewKit/one-piece-local-review.json' \
  "$review_app_data/Documents/one-piece-local-review.json"
review_public_key=$(python3 -c 'import json; print(json.load(open("/external/OnePieceLocalReviewKit/public-keys.json"))["one-piece-local-review"])')
xcrun simctl launch booted com.seankeller.CardScanner \
  -one_piece_local_review \
  -one_piece_review_seed "$review_app_data/Documents/one-piece-local-review.json" \
  -one_piece_review_public_key "$review_public_key"
```

Scan P-001 and explicitly choose the English Super Pre-Release winner. Its sole
verified foil finish resolves automatically. Confirm the collection entry, close
and relaunch with the same flags, then confirm the retained printing and quantity.
Browse exposes the verified winner; participant acquisition remains unavailable.
You can also scan ST01-007 and choose its FILM RED retail printing. The original
starter-deck Nami is not yet an acquisition candidate; do not select the retail
printing for a physically different card.
For ordinary starter/booster base cases, scan ST01-003 (Karoo, normal), ST01-012
(Luffy, foil) or OP01-120 (Shanks, standard artwork, foil) and explicitly choose
the matching retail release. This catalog does not cover Shanks parallel, Manga
or identical-art PRB reprints. Original/revision records remain excluded until
their physical distinction is reviewed.
The later launch-starter expansion also supports ST02-001 (Eustass"Captain"Kid,
foil), ST03-008 (Trafalgar Law, normal) and ST04-005 (Queen, normal) as explicit
standard retail choices. Check the matching starter release before adding.
Other P-001 releases are still outside the reviewed coverage. A missing image
does not grant permission to substitute another artwork.

## Evidence and limits

`testRealLocalReviewScanChoiceCollectionRelaunchAndCSVBaseCase` uses the real
review data, signed-seed bootstrap, scanner confirmation callback, explicit
printing selection and the app's persistent on-device store factory. Reopening
the disk stores preserves the exact winner UUID, foil finish and quantity; CSV
export revalidates and offline Browse returns the same UUID with no manufactured
price observations. This is a deterministic pipeline test, not camera/device UX
acceptance or a full process relaunch.

The earlier focused checkpoint executed 68 cases: 67 passed, one existing storage
case skipped, zero failures. Kit preparation and publisher signing completed.
The later retail checkpoint passed 39 app integration cases and 38 core tests.

A subsequent rendered simulator review opened the expanded signed kit, searched
for Nami, selected the FILM RED detail and added one raw copy. The sole verified
foil finish resolved without an extra picker. Stopping and relaunching the app
with the same review flags retained Nami, the FILM RED release, foil finish and
quantity one; the collection correctly showed its price as not checked. This
closes that Browse-add/process-relaunch base case. It does not prove camera OCR,
rendered scanner printing selection, full English reconciliation or production/sync
acceptance, which remain open in the
[implementation ledger](../../docs/plans/one_piece_code_implementation.md).

The display follow-up passes all 102 selected One Piece/Browse tests. Browse
uses readable product labels and number prefixes; games without pricing support
show “Pricing unavailable” instead of retrieval and history claims. The updated
detail accessibility tree confirms that state and owned foil quantity one.
After reinstalling, resolve the app's current Documents path again before
launching: the simulator can move its data container while retaining its files.

Historical: the first starter/booster expansion passes 39 catalog-core and 40 One Piece integration
cases. New injected-recognition cases choose and save standard Karoo, starter
Luffy and booster Shanks with the correct finish/UUID and no price observations.
The kit has 82 verified acquisition candidates; its additional provisional and
conflicted records are publisher review data. This checkpoint does not add new
rendered scanner or physical-camera evidence.

Historical: the four-launch-starter follow-up passes the same 39 core and 40 integration
cases with the expanded data and base cases. Its kit contains 106 verified
printings, 89 provisional records and eight conflicted records. The latter two
groups remain review-only and cannot be selected for acquisition.

The current ST-01–ST-09 / OP-01–OP-02 kit contains 306 verified printings,
91 provisional records and eight conflicted records. It passes 40 core and 40
integration tests, including one injected-recognition acquisition per new product.
Its private artifact directory is `nine-starters-two-boosters-kit`; it expands
local review coverage without enabling production publication, pricing or sync.
