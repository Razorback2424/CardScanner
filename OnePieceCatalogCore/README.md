# One Piece catalog publisher

The app includes a signed English catalog seed. The production configuration
keeps remote activation and collection writes disabled. The retained review
records identify the evidence and capture hashes for individual physical
printings. [English review corpus](ReviewCorpus/english-stress/README.md)

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

The workflow runs a weekly read-only coverage report. Its manual jobs prepare
the reviewed signed artifact and publish it in separate environments. Publication
compares the predecessor while holding the shared hosting concurrency lock,
restores the other namespaces, and checks the live bytes after deploy.
[One Piece catalog workflow](../.github/workflows/one-piece-catalog.yml)
