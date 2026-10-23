# One Piece production setup for owner approval

**Date:** 2026-10-23. **Source:** `c4e1198` plus the launch-readiness working tree.
**Status:** unsigned candidate prepared and validated. No production key created
or provisioned; no signing, workflow dispatch, deployment or activation performed.
Production configuration remains disabled, with empty pins and writes `NO`.

The owner explicitly requested preparation using the existing catalog host and
dedicated One Piece workflow, with approval before key creation/provisioning or
publication. This document is the concrete proposal for that approval. Source
rights and physical-device acceptance remain separate launch gates.

## Exact unsigned candidate

The [machine-readable receipt](one-piece-production-candidate-2026-10-23.json)
records the approval identity:

| Field | Prepared value |
| --- | --- |
| Production lineage | Revision **1**, unsigned bootstrap |
| Payload SHA-256 | `251165ad79ebe34e9b2d8a37919f711d8affb2d550386eac7a71bd27d8323c0b` |
| Payload size | 16,409,901 bytes |
| Generated timestamp | `2026-10-23T16:36:00Z` |
| Retained printings | 2,748: 2,493 verified, 224 provisional, 31 conflicted |
| Exact market mappings | 2,367; held disputes remain held |
| Proposed key ID | `one-piece-production-2026-10-23-01` — no key exists from this preparation |

External SSD artifact directory:
`CardScannerBuilds/OnePieceProductionPreparation-20261023/Candidate/`.
It contains `candidate.json`, `candidate-receipt.json`, the unchanged
`reviewed-source-r3.json`, and extracted `registry.json`, `observations.json` and
`inventories.json`. No signing material is present. The large payload remains
outside the repository pending publication/redistribution approval.

The retained reviewed revision-3 payload matches the
[earlier receipt](../research/catalog-variant-coverage-2026-10-15/one-piece-candidate.json)
at SHA-256 `65070cad955e848fefa91cd6c87d0e23a753d0b245b70a496c7b28fea2837822`.
The existing publisher, built from this checkout, validated the production
candidate with `build --revision 1 --generated-at 2026-10-23T16:36:00Z
--bootstrap-registry yes`. Classification is `protectedReview`.
An independent second CLI build, `candidate-replay.json`, is byte-identical to
`candidate.json` and has the same approval hash.
All 46 existing `OnePieceCatalogCore` package tests pass in the separate macOS
preparation build, including publisher signing/verification/immutable-output
fixtures. Those keys are test fixtures, not production authority. The normal
unsigned Release simulator build also succeeds; inspection confirms production
One Piece remains disabled and no production seed is bundled.

An independent decoded-object comparison proves only `revision` and
`generatedAt` changed from the reviewed revision-3 payload; registry, source
observations, inventories and indexes are identical. All 2,745 owner revision-2
printing objects are retained unchanged, not merely the same IDs. The three
reviewed alternates are the existing additions. These checks establish retention
and contract correctness, not complete physical coverage or publication rights.

Production revision 1 is a separate lineage. The local review revision 3 cannot
be passed as the first production bootstrap: `CatalogPublication` requires
revision 1. Do not import review public keys to manufacture a production parent.
The existing production host's `/one-piece/v1/current.json` returned HTTP 404
during this preparation. Recheck immediately before bootstrap; any existing
pointer requires independent verification and a new reviewed continuation plan.

## Protected signing configuration to provision after approval

Use the existing [dedicated workflow](../../.github/workflows/one-piece-catalog.yml),
whose manual signing job already uses `one-piece-catalog-signing`, requires main,
matches the reviewed SHA, independently verifies its output and does not deploy.

| Setting | Required configuration |
| --- | --- |
| GitHub environment | `one-piece-catalog-signing` |
| Protection | Required owner/release reviewer; prevent self-review; restrict deployment to `main`; disable administrator bypass where available. Verify effective protection before supplying a key. |
| Environment variable | `ONE_PIECE_CATALOG_KEY_ID=one-piece-production-2026-10-23-01` |
| Environment secret | `ONE_PIECE_CATALOG_SIGNING_KEY`: a fresh dedicated Ed25519 32-byte seed, base64 encoded. Environment scope only; do not create a repository/global fallback of that name. |
| Public trust | Independently verify the derived public key, then add only `key-id:public-key` to `Config/OnePieceCatalogProduction.xcconfig`; keep mode disabled and writes off. |
| Secret handling | Provision through an authenticated secret API or secure secret-entry flow without printing the seed, shell arguments, logs or artifacts. Keep production private material out of repository files and test fixtures. |
| Key isolation | Compare the public bytes against all owner/review, Pokémon and Magic pins; reject any reuse. No review key is an acceptable substitute. |

Read-only GitHub API requests for the environment metadata and secret names
returned HTTP 404. That may mean absence or insufficient access; existing
protection/secret configuration is **unverified**, not assumed safe. No setting
was changed and no secret value was requested. The intended settings above must
be inspected/configured using owner-authorized access after approval.

GitHub's [environment guidance](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
explains plan/visibility limits on reviewer protection. Its
[deployment review guidance](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/review-deployments)
also makes self-review prevention consequential: the workflow initiator cannot
approve it. Use an independent reviewer for that policy. If only the owner can
review, obtain an explicit owner-approved protection policy instead of silently
claiming independent approval or configuring an unusable gate.

After approval, retain the same candidate bytes at a reviewed repository path
such as `publisher/one-piece/production/revision-1/candidate.json` before using
the existing workflow, which only accepts repository-file inputs. This transfer
requires the source/publication-rights gate; it is not performed here. Dispatch
with `sign=true`, `bootstrap=true`, empty `previous`, and the exact receipt SHA.
Do not regenerate metadata at dispatch: that changes the reviewed hash.

The resulting `release-envelope.json` and independently verified manifest will
have new hashes that cannot exist until production signing. Record both hashes
and verify the payload digest above before requesting publication approval.

## Deployment changes for a later, separate approval

The current One Piece workflow is sign-only. Publication needs a manual,
default-off job with these concrete changes; none is active in this preparation:

1. Consume the exact verified signing artifact, pinned by run identity and
   manifest/envelope/payload hashes. Verify again against checked-in production
   pins; never rebuild/re-sign from live provider responses in the deploy job.
2. Use a separately protected environment `one-piece-catalog-production`,
   required owner approval, main-only deployment and the same no-self-review
   policy. Scope hosting credentials here, not in the signing environment:
   `FIREBASE_SERVICE_ACCOUNT`, `FIREBASE_PROJECT_ID=scanstash-catalog-prod`,
   `FIREBASE_HOSTING_SITE_ID=scanstash-catalog-prod`. Use the existing hosting
   service account with the minimum required hosting permissions; its actual
   permissions have not been inspected here. Never duplicate another catalog's
   signing secret into this job.
3. Serialize the **entire read/restore/stage/deploy operation** with the existing
   concurrency group `scanstash-catalog-production-hosting`,
   `cancel-in-progress: false`, shared by Pokémon and Magic. Read the current
   pointer inside that lock. Require 404 for this bootstrap; do not overwrite a
   newly appeared or changed pointer.
4. Restore existing Pokémon, Magic, One Piece and Yu-Gi-Oh namespaces using
   [the shared restorer](../../scripts/restore_catalog_hosting_site.sh) into
   `publisher/site` from `https://scanstash-catalog-prod.web.app`. Fail on any
   required signature/ancestry/read failure. Preserve all immutable releases;
   a whole-site Firebase deploy must not erase another game's catalog.
5. Stage identical signed envelope bytes as both
   `publisher/site/one-piece/v1/releases/1/catalog-release.json` and
   `publisher/site/one-piece/v1/current.json`. Refuse differing existing immutable
   bytes. Check the complete site before deploy, then use the existing Firebase
   project/site and `hosting:production` target. Existing `firebase.json` already
   defines no-cache pointer and immutable release headers; no DNS/new-host change
   is proposed.
6. After explicit publication approval, deploy; fetch both hosted paths, verify
   signature and exact envelope/payload hashes and cache headers, and require the
   pointer to match immutable revision 1. Check equivalent reads through
   `https://catalog.scan-stash.com`. A failed upload/readback is not activation
   evidence; retain the previous verified site/pointer for operational recovery.

## App packaging and activation remain a later gate

After production signing, place the verified envelope at
`TradingCardScanner/OnePieceCatalogSeed/one-piece-catalog-release.json` and add
it to the app's Copy Bundle Resources at the bundle root. `configuredRuntime`
requires that exact resource name. An unsigned payload or owner seed does not
satisfy this contract.

The eventual configuration uses `https://catalog.scan-stash.com` and the new
dedicated public pin. In the xcconfig, preserve the existing URL-escaping pattern
`https:/$()/catalog.scan-stash.com` so `//` is not parsed as a comment.
Keep production **disabled** and writes **NO** throughout
this preparation. A later approved activation changes mode to `remote-authority`
and enables writes only after Release-path, storage compatibility, device,
offline/interruption and exact-pricing acceptance. Local-only owner bootstrap
does not count as Release acceptance. The
[existing release authority](../plans/one_piece_release_acceptance.md) retains
the physical, rights and distribution gates.
