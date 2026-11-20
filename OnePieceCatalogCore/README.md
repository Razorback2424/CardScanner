# One Piece catalog publisher

**Current source boundary — 2026-11-20:** The [One Piece reconciliation
playbook](../docs/catalog-reconciliation-playbook.md) records signed hosted
production **revision 7** as live, with 2,670 of 2,969 canonical cards
certified complete and 173 Bandai rows still awaiting printing review.
The November 15 configuration snapshot below remains valid for its stated
SHA but predates that publication. An unsigned candidate in the repository
is neither a signed release nor proof of an activated iPhone catalog.
Physical-device, rights and distribution gates remain separate.

The app includes a signed English catalog seed. As of `main@a8d3103a`
(2026-11-15), the production Xcode configuration uses `remote-authority`
with a dedicated One Piece pin and `ONE_PIECE_COLLECTION_WRITES = YES`,
while the Release app remains on-device-only (`NO_CLOUDKIT`). These settings
do not prove that a later candidate is signed, hosted, activated on an iPhone,
or accepted for distribution. In particular, the retained revision-4 OP-18
candidate is unsigned discovery evidence, not a deployed physical/price
expansion. The [seed resource guide](../TradingCardScanner/OnePieceCatalogSeed/README.md)
separates the local and production paths.

The retained review records identify the evidence and capture hashes for
individual physical printings. [English review corpus](ReviewCorpus/english-stress/README.md)

`one-piece-catalog-publisher build` takes a durable registry, normalized source
observations and source inventories. It retains app-owned printing UUIDs and
validates the candidate against the previous unsigned payload. A first build
requires `--bootstrap-registry yes` and revision one; later builds require
`--previous` and must preserve reviewed identity history.

```sh
swift run --package-path OnePieceCatalogCore one-piece-catalog-publisher build \
  --registry registry.json --observations observations.json --inventories inventories.json \
  --revision 1 --generated-at 2026-10-04T00:00:00Z \
  --bootstrap-registry yes --output candidate.json
```

Review the canonical candidate bytes and retain their SHA-256. Signing requires
that exact fingerprint, a dedicated One Piece key ID and an independently pinned
public key. The trusted-keys JSON file maps key IDs to base64 Ed25519 public keys.
Supply the base64 32-byte private key through `ONE_PIECE_CATALOG_SIGNING_KEY` in
the process environment; do not put private keys in command arguments or files.

```sh
swift run --package-path OnePieceCatalogCore one-piece-catalog-publisher sign \
  --input candidate.json --trusted-keys public-keys.json --key-id one-piece-production-KEY_ID \
  --reviewed-payload-sha256 REVIEWED_SHA256 --bootstrap-registry yes \
  --output release-envelope.json --manifest manifest.json
swift run --skip-build --package-path OnePieceCatalogCore one-piece-catalog-publisher verify \
  --input release-envelope.json --trusted-keys public-keys.json \
  --reviewed-payload-sha256 REVIEWED_SHA256 --bootstrap-registry yes \
  --manifest verified-manifest.json
cmp manifest.json verified-manifest.json
```

After revision one, replace `--bootstrap-registry yes` with `--previous` pointing
to the signed previous release for both sign and verify. Signing verifies that
baseline, revision monotonicity, retained identities and the registry transition.
The manifest includes payload/envelope hashes, change classification and market
mapping invalidations. Continuations also record the signed predecessor's
envelope hash so publication can compare it with the live head.

Use a private, fresh preparation directory. Existing identical artifacts are
retained after verification; differing artifacts and input/output collisions are
refused. Interrupted preparation may leave an incomplete artifact, which must
never be deployed and is rejected on retry. These commands do not publish files.

## English card list coverage

Use a fresh capture directory for a current audit. The report checks all series
in Bandai's English card-list directory and joins exact series, artwork alias,
and printed number. It records which rows still need physical printing or
product appearance evidence. DON!! designs require a separate inventory.

```sh
python3 scripts/audit_one_piece_coverage.py \
  --capture-root "$AUDIT_DIR/source" --release "$VERIFIED_ENVELOPE" \
  --output "$AUDIT_DIR/coverage.json" --discovery-inputs "$AUDIT_DIR/inputs"
```

Use `--offline` to replay retained captures and a fresh output path. The
generated registry, observations and inventories feed the publisher's
`build` command with the previous candidate. Browse discoveries have no
collection identity or finish. Supply exact physical evidence through
`--reviewed-additions` once per accepted batch.

A release first found only in a Bandai card list gets a placeholder product
with the raw series label and no release date, so Browse lists it under
"Earlier". Its `productUpdates` entry sets the label and the release date from
the official English product page. The product ID and printing references stay
the same. Pass the retained
[product updates](../publisher/one-piece/product-updates.json) as another
`--reviewed-additions` file. The reviewed revision 2
inputs include the stamped `OP09-020` and two fixed products whose contents
Bandai explicitly identifies as holo and textured foil.
[Stamped printing](../publisher/one-piece/production/revision-2/printing-additions.json)
[Fixed product rules](../publisher/one-piece/production/revision-2/fixed-foil-products.json)

Replay those products from the retained Bandai card list, product pages and
artwork receipts. Build an intermediate candidate with the fixed product
additions before evaluating the retailer batch.

```sh
python3 scripts/reconcile_one_piece_fixed_foil_products.py \
  --rules publisher/one-piece/production/revision-2/fixed-foil-products.json \
  --cardlist-captures "$BANDAI" --specification-captures "$PRODUCT_SPECS" \
  --output "$AUDIT_DIR/fixed-foil.json"

python3 scripts/reconcile_one_piece_retail_printings.py \
  --release "$INTERMEDIATE_CANDIDATE" \
  --products OnePieceCatalogCore/ReviewCorpus/english-stress/products.json \
  --bandai-captures "$BANDAI" --retail-captures "$RETAIL" \
  --artwork-captures "$ARTWORK" --market-captures "$MARKET" \
  --output "$AUDIT_DIR/retail-printings.json"
```

The retailer replay requires Pillow, paginated CoreTCG product receipts, and
a complete TCGCSV snapshot with product and price data for those groups.
It compares each listing with all official artwork siblings for the same
number in that product. When the three-region comparison ties, matching digital
renders must agree on the pixels that distinguish each sibling, including
stamps and small footer differences. PRB-01 retries this same comparison at
higher resolution when small finish details disappear in the thumbnail. Its
manga reprints require the exact English Foil listing and a marketplace
reprint specification that distinguishes them from the original textured foil.
For named promos, the photo comparison
also checks the design after normalizing contrast. It holds same-art siblings
for exact digital evidence. The retailer supplies the explicit English finish,
and the marketplace check holds conflicting titles and finish lanes for review.
Inventory IDs include the reviewed observation membership, so later batches can
reuse the same captured page while retaining the earlier evidence.

For EB-05, pass `--eb05-retail-captures` for each retained Cardboard Colosseum,
Rocket City Toys or Weird Wolf Games capture directory. The comparison uses marketplace group
24820 and accepts only a product page with a matching reference image and an
explicit English finish. For named promos, pass `--promo-retail-captures` with
all pages of CoreTCG group 17675 and its marketplace snapshot. A promo needs a
single Bandai distribution, agreement on the distribution in both listings,
and an artwork match across the Promotion Card and Other Product Card lists.
Reviewed title aliases preserve the exact product, edition, and prize tier.
These options can run without the booster product manifest.

For reflective promo photographs that need visual review, pass
`--reviewed-promo-photos` with entries keyed by marketplace image product ID.
Each entry pins `number`, `series`, `alias`, `distribution`, `finish`,
`retailerImageSHA256` and `bandaiImageSHA256`. The English retailer lane,
official distribution and marketplace checks still apply. A changed photo
or official reference requires a fresh review.

For an official event with a finish note scoped to its featured card list,
the fixed foil reconciler accepts `eventSectionID` and reviewed
`artworkAliases` in the rule. The retained specification must name the exact
event product and explicitly specify holo and textured foil. Each accepted
alias must match one featured Bandai image pixel for pixel. The rule can
cover a subset of the cards when others already have verified printings.

Use `--fetch-missing-artwork` to extend an artwork capture with the missing
references from the retained product pages. Keep captures private. Review the
batch and the remaining gaps before adding it to the final build.

### TCGplayer product listings

CoreTCG pages list in-stock singles only. Pass `--tcgplayer-listings` to also
read every `--products` group from the complete TCGCSV snapshot. A TCGplayer
product counts as a listing only when it has one printed number and exactly
one Normal or Foil price lane. That lane is its finish evidence, and the
English One Piece category is its language evidence. `--retail-captures` is
optional in this mode. The replay holds a new printing whose release, card and
treatment already exist under another alias, so it cannot duplicate a printing
recorded by an earlier batch.

Early-set marketplace images are photographs. When the strict digital
comparison fails, the replay applies the photographic structure comparison
used for promos to every listing. It still holds siblings that share their art.

### Deck and premium-booster reprints

A card that a starter deck or premium booster reprints from another set is its
own physical printing. Its release is the product that reprinted it, not the
original set. TCGplayer files each one as a separate product in the reprinting
product's group, and the reprint carries print details the original lacks,
such as the English marker by the copyright line or a newer block icon. Bandai
lists it under that product with an `_r` artwork alias.

ST-23 to ST-28 and the premium boosters title these listings "(Reprint)".
ST-15 to ST-20 and ST-31 onward use the plain card name. The retail replay
accepts a plain-titled listing only when all three hold: the Bandai alias is
`_r`, the number belongs to another set, and the listing sits in the
reprinting product's own group. CoreTCG pages list in-stock singles only, so
use `--tcgplayer-listings` for reprints that have sold out.

### Stamped event-pack printings

Each English pre-release, release-event and anniversary-tournament pack holds
stamped copies of one booster's Common and Uncommon cards. Bandai's event page
states the stamp and the number of card types. A stamped copy is its own
printing, filed under its event product, which carries the TCGplayer group name
collectors use (for example "Paramount War Pre-Release Cards").
[`event-stamp-products.json`](../publisher/one-piece/event-stamp-products.json)
pins one rule per event to the exact specification lines on its page.

```sh
python3 scripts/reconcile_one_piece_event_stamps.py --release "$CANDIDATE" \
  --rules publisher/one-piece/event-stamp-products.json \
  --reviewed-photos publisher/one-piece/event-stamp-photo-reviews.json \
  --bandai-captures "$BANDAI" --event-captures "$EVENT_PAGES" \
  --artwork-captures "$ARTWORK" --market-captures "$TCGCSV_ALL" \
  --output "$AUDIT_DIR/event-stamps.json" --report "$AUDIT_DIR/event-stamps-report.json"
```

An event is held in full when its page no longer states the pinned lines, or
when its TCGplayer group lists a different number of cards. A single card is
held, and the report names the reason, in any of these cases:

- Bandai's base presentation is not a Common or Uncommon.
- The base printing is not uniquely verified.
- The TCGplayer title is not plain, or its finish lane is not Normal only.
- The TCGplayer photo does not match the base Bandai render.

On some Event cards the stamp overlaps the art enough to fail the automatic
image comparison. Those pairs are accepted only from the reviewed-photo file,
which pins both exact image hashes. A stamped printing shows the base Bandai
render; its stamp is recorded in the printing's `stamp` field. Event pages for
OP-16 to OP-18 were not available on 2026-11-18, so those events have no rule.
Capture requests are capped at 2,000 per run, so a first capture of every
event takes two runs. The second run reuses the retained files.

### Tiered promo printings

Promo events often hand out several copies of one artwork with different
stamps: Participant, Finalist and Winner copies, or online and offline
regional copies. TCGplayer lists each one as its own product, while Bandai's
promotion list shows at most one.
[`reconcile_one_piece_promo_tiers.py`](../scripts/reconcile_one_piece_promo_tiers.py)
adds each TCGplayer promo product as its own printing under "One Piece
Promotion Cards". Each printing takes the TCGplayer event text as its
distribution and the bracketed tier as its stamp. Its docstring lists every
gate. A product whose art matches an existing printing of the same card is
held for review, because a stamped copy and an identical reprint look the
same in a photo. A product with no TCGplayer price lane is also held, since
it has no finish evidence.

```sh
python3 scripts/reconcile_one_piece_promo_tiers.py --release "$CANDIDATE" \
  --coverage "$AUDIT_DIR/coverage.json" --bandai-captures "$BANDAI" \
  --artwork-captures "$ARTWORK" --market-captures "$TCGCSV_ALL" \
  --output "$AUDIT_DIR/promo-tiers.json" --report "$AUDIT_DIR/promo-tiers-report.json"
```

The retail replay's `--tcgplayer-promos` option reads the TCGplayer promo
group for the one-to-one promo path. `PROMO_DISTRIBUTION_ALIASES` holds
reviewed name pairs for distributions that Bandai and TCGplayer name
differently.

### Known printings with a marketplace gap

A printing whose existence is documented, but which TCGplayer has never
priced (`marketplaceFinishLanes: none`) or lists without a photo
(`marketplacePhoto: none`), is added as provisional with no finish. It cannot
be collected, so its card is not a candidate for automatic selection. The
certifier treats it as known (`known_unpriced`), so it does not hold its card
family open. Browse labels its row "Not yet priced" or "Art not yet
confirmed" instead of marking the whole set "Partial catalog". A provisional
printing without one of these markers, such as a finish conflict, still
blocks.

### Other reviewed resolvers

- [`resolve_one_piece_errata_holds.py`](../scripts/resolve_one_piece_errata_holds.py)
  verifies printings held only for Bandai's "Errata Card" note. The original
  release's TCGplayer group must list exactly one plain product for that card;
  corrected text appears only in later reprints.
- [`resolve_one_piece_reprint_appearances.py`](../scripts/resolve_one_piece_reprint_appearances.py)
  records a starter-deck or PRB-01 `_r` reprint as an appearance of the
  original printing. It does so only when TCGplayer lists no separate product
  for it, so collectors trade it as the original card.
- [`bind_one_piece_promo_entries.py`](../scripts/bind_one_piece_promo_entries.py)
  connects a missing Bandai promotion-list entry to the promo printing whose
  photo matched its art.
- `reconcile_one_piece_promo_tiers.py --group <id>` replays a product group
  (deck sets, demo decks, revision packs, Super Pre-Release editions) as the
  reprinting product's own printings. Do not pass booster groups: their
  products already exist under the booster.

### Card family coverage certification

`printingCoverageComplete` marks a card whose complete physical printing set
has been verified. It removes the card from Browse's "Partial catalog" rule and
puts it in the automatic-selection index, so it is set only by
[`certify_one_piece_coverage.py`](../scripts/certify_one_piece_coverage.py).
Run it on a candidate that already contains the batch's printings. Then apply
its additions to that same candidate and build the next revision.

```sh
python3 scripts/audit_one_piece_coverage.py --offline --capture-root "$BANDAI" \
  --release "$CANDIDATE" --output "$AUDIT_DIR/coverage.json"
python3 scripts/certify_one_piece_coverage.py report --release "$CANDIDATE" \
  --coverage "$AUDIT_DIR/coverage.json" --market-captures "$TCGCSV_ALL" \
  --output "$AUDIT_DIR/certification.json"
# Edit only "resolutions" for products listed under unaccountedMarketProducts.
python3 scripts/certify_one_piece_coverage.py certify --report "$AUDIT_DIR/certification.json" \
  --release "$CANDIDATE" --coverage "$AUDIT_DIR/coverage.json" \
  --market-captures "$TCGCSV_ALL" --output "$AUDIT_DIR/certification-additions.json"
python3 scripts/audit_one_piece_coverage.py --offline --capture-root "$BANDAI" \
  --release "$CANDIDATE" --output "$AUDIT_DIR/coverage-certified.json" \
  --discovery-inputs "$AUDIT_DIR/inputs" \
  --reviewed-additions "$AUDIT_DIR/certification-additions.json"
```

`$TCGCSV_ALL` must be a complete daily snapshot of every category 68 group.
The coverage report must cover every Bandai series for that exact candidate.
A card certifies only when all of the following hold:

- Every Bandai presentation of its number is a verified printing.
- Every active printing of the card is verified.
- No Browse discovery remains for the card.
- Every source observation for the number reconciles to exactly one printing.
- Every same-number TCGplayer product is accounted for by a reviewed mapping,
  by the printing's own retailer evidence, or by a unique title match in the
  printing's release group.

A product that is still unaccounted needs a resolution with a reason and an
https citation. A resolution either excludes the product or names the printing
it belongs to. The certification inventories list the family's source
observations, which the validator requires for automatic selection. The audit
re-checks these gates when it applies the additions. It also clears a
certification when Bandai later lists another presentation of that number.

### Per-artwork retail replay diagnostics

The retail reconciler can now write an **optional read-only evidence report** alongside its ordinary
additions file:

```sh
python3 scripts/reconcile_one_piece_retail_printings.py \
  --release "$REVIEWED_CANDIDATE" \
  --bandai-captures "$BANDAI" --artwork-captures "$ARTWORK" \
  --market-captures "$MARKET" --eb05-retail-captures "$EB05_RETAIL" \
  --output "$AUDIT_DIR/retail-additions.json" \
  --evidence-report "$AUDIT_DIR/retail-evidence.json"
```

Each unresolved artwork alias gets its same-number TCGCSV market products, captured
retailer-listing count, accepted retailer-artwork matches, and rejection-stage reasons.
A market product or its quoted Foil lane is **not** independent physical-printing
evidence; neither the report nor an artwork match grants an exact price mapping.
Missing images or listings mean they were unavailable **in this replay**, not
necessarily unavailable at the provider or in other capture directories.
The optional report does not change catalog contents or sign/publish anything.
Ensure each output path is new, and supply all relevant retained retailer roots
before treating a negative replay result as a source-data limitation.

### EB-05 mapping-only price candidate

`scripts/prepare_one_piece_eb05_market.py` only proposes exact marketplace
mappings for **already verified** English EB-05 physical printings that lack
one. It requires retained retailer artwork-and-finish evidence, an exact
marketplace product ID and acceptable treatment title, and **one** quote lane
for the requested Normal/Foil subtype. The feed validator rejects duplicate
lanes before matching. Missing lanes and previously claimed product IDs leave
the mapping held. The price feed itself grants no printing, artwork, or
finish authority. Its report distinguishes existing,
exact, and held rows. It does not sign, activate, publish, or fix the separate
unapproved discovery aliases. Relevant tests:
`scripts/tests/test_one_piece_eb05_market.py`.

A read-only external-image comparison is also available in
[`one-piece-eb05-artwork-audit.yml`](../.github/workflows/one-piece-eb05-artwork-audit.yml).
Image agreement is a research candidate, not permission to create an exact
price mapping. For the publisher-side exception classifications and the
different on-device report, see
[`scripts/CATALOG_HEALTH.md`](../scripts/CATALOG_HEALTH.md).

The workflow runs a weekly read-only coverage report. Its manual jobs prepare
the reviewed signed artifact and publish it in separate environments. Publication
compares the predecessor while holding the shared hosting concurrency lock,
restores the other namespaces, and checks the live bytes after deploy.
[One Piece catalog workflow](../.github/workflows/one-piece-catalog.yml)
