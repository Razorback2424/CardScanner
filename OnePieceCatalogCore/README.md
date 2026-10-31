# One Piece catalog publisher

Status: local preparation tooling; production data, keys and deployment are not
configured. Physical-printing fixtures are synthetic and do not establish
provider rights or completeness. The [English stress review inputs](ReviewCorpus/english-stress/README.md)
now retain real Bandai/Limitless observation metadata and exact capture hashes;
their canonical-only registry has no reviewed physical printing authority.

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
mapping invalidations.

Use a private, fresh preparation directory. Existing identical artifacts are
retained after verification; differing artifacts and input/output collisions are
refused. Interrupted preparation may leave an incomplete artifact, which must
never be deployed and is rejected on retry. These commands do not publish files.

The repository workflow tests the package. Its optional main-branch manual job
prepares and verifies artifacts using the dedicated `one-piece-catalog-signing`
environment; required-reviewer protection must be configured and verified in
GitHub before production use. It has no deployment step. The disabled production
configuration contains no inherited Pokémon/Magic key. Hosting preservation,
current-pointer concurrency, reviewed production data/seed, public-key wiring,
rights and collection sync policy remain required gates.
