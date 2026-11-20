# One Piece signed catalog resources

**Source/configuration snapshot:** 2026-11-15, `main@a8d3103a`.
**2026-11-20 clarification:** Signed hosted One Piece production revision 7
is reported live by the
[reconciliation playbook](../../docs/catalog-reconciliation-playbook.md).
The bundled production seed in this folder is signed **revision 4**
(generated 2026-11-15); its payload is byte-identical to the
`publisher/one-piece/production/revision-4/candidate.json` described below as
unsigned, so that candidate was signed and bundled. The bundled seed,
owner-local catalog and live remote release remain distinct. Do not infer a particular phone's
activated revision or completed release acceptance from either repo file.

There are two distinct signed catalog paths. Do not treat their files, revisions,
keys, or storage boundaries as interchangeable.

- `TradingCardScanner/OnePieceOwnerCatalog/` contains the separately signed
  owner-local catalog and public keys used by local development configurations.
  The October 7, 2026 revision-2 mapping update is a **historical checkpoint**,
  not the latest statement about production coverage.
- `TradingCardScanner/OnePieceCatalogSeed/one-piece-catalog-release.json`
  contains a signed **production** seed bundled by the app. It is not a
  synthetic fixture or a substitute for verifying the installed app's exact
  payload and pinned key.

`Config/OnePieceCatalogProduction.xcconfig` currently sets
`ONE_PIECE_CATALOG_ROLLOUT_MODE = remote-authority`, a dedicated production
key pin and hosted catalog URL, and `ONE_PIECE_COLLECTION_WRITES = YES`.
Its comment scopes the Release build to **on-device storage (`NO_CLOUDKIT`)**.
These are source configuration facts, not evidence of successful device
activation, live-host publication, CloudKit compatibility, or distribution
acceptance. Any signed update still must pass the configured pin, prior-release
and activation checks. Older documentation saying production is universally
disabled describes a prior configuration.

`publisher/one-piece/production/revision-4/candidate.json` is a separately
retained **unsigned** candidate for OP-18 discovery. Its product/preview
observations must not be described as verified physical printings, exact price
mappings, or as activated on a particular phone merely because the candidate
exists. Consult its [release notes](../../publisher/one-piece/production/revision-4/README.md)
and the [One Piece publisher guide](../../OnePieceCatalogCore/README.md).

The additional `discovery-previews-v1.json` resources carry representative
official artwork evidence, not physical identity or acquisition authority.
A preview can be displayed for a record still marked "Printing needs review."
That record remains unavailable for collection writes and exact pricing until
independent printing/finish and mapping review succeeds.

For current release and test boundaries, see the
[documentation map](../../docs/README.md),
[catalog health guide](../../scripts/CATALOG_HEALTH.md), and
[launch contract](../../docs/release/launch-contract.md).
Never infer a verified iPhone install, successful catalog publication, or
completed release gate from the presence of a bundled artifact.
