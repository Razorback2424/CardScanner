# Pokémon catalog signing and publication runbook

**Status:** current Slice E/F implementation companion — 2026-09-20

The catalog signing key is the only credential that can authorize a new
scanner code. Treat the GitHub Actions secret as a use-only copy, not as the
backup.

## Key custody

1. Generate one Ed25519 signing key pair locally with a password-protected
   owner-controlled tool, using the raw 32-byte private-key representation
   accepted by CryptoKit's `Curve25519.Signing` API.
2. Store the private key in the owner's encrypted password-manager entry.
   Record its generation date, key ID, and public key fingerprint there.
3. Verify the backup once by deriving the public key from the stored private
   key and comparing it with the public key pinned by the app release.
4. Add only the private raw representation to the production publication
   environment secret `POKEMON_CATALOG_SIGNING_KEY`; add the non-secret key ID
   to `POKEMON_CATALOG_KEY_ID`. The automatic content-only environment must
   contain the same deployment and signing secrets. Never put either value in a
   fixture, report, site object, or pull-request log.

The committed production build pins
`pokemon-catalog-production-2026-09-18-01` to
`CEQfURmtxBTE170BLAk1hVcKgBmGAgVlR7hhSgO6CLI` in
`POKEMON_CATALOG_PINNED_KEYS`. The hosted revision-1 signature was independently
verified against that pin. The private signing value remains only in the
protected release locations; it is not in the repository, candidate artifact,
or app. The committed rollout mode is `remote-authority`.

The private `POKEMON_CATALOG_SIGNING_KEY` value is not PEM. It must decode to
exactly 32 raw private-key/seed bytes, supplied as unpadded base64url, standard
base64, or 64 hexadecimal characters. The loader derives the Ed25519 signing
key with `Curve25519.Signing.PrivateKey(rawRepresentation:)`; whitespace,
passphrases, and encoded PEM blocks are invalid. Keep the public pin in
base64url form so it matches the app's `keyID:public-key` parser.

## Publication gates

- Pull requests run the core tests and recorded-fixture validation without any
  signing secret.
- Ordinary expansions derive their code from validated TCGdex evidence. Promo,
  non-scannable, and exceptional cases use matching operator overrides in
  `publisher/catalog-input.json`; the fixture directory contains synthetic
  input for tests.
- The builder rejects missing or malformed provider metadata, conflicting or
  drifting codes, denominator mismatch, incomplete provider cards, unsupported
  URLs, duplicate identities, OCR-confusable code collisions, and unsupported
  rules versions.
- Schema 1 carries `providerFingerprint` as an optional additive descriptor
  field. A legacy descriptor decodes with `nil`; it is not an empty target and
  does not trigger device reconciliation. The publisher and device call the
  same canonical Core fingerprint implementation. The separate local probe
  fingerprint remains exclusive to the independent 24-hour sweep.
- The optional parentProviderSetID is protected configuration. The publisher
  resolves a configured parent's actual artwork into the signed child
  descriptor; the app's compiled parent rules remain only as a legacy fallback.
- The publisher writes an immutable revision first and changes `current.json`
  last. It refuses to overwrite a revision with different bytes.
- Scheduled runs automatically prepare an unsigned candidate. The explicit
  classifier routes the first nil-to-fingerprint population through the
  protected `pokemon-catalog-production` baseline migration. After that,
  content-only changes select `pokemon-catalog-production-auto`; a new set,
  authority change, or unknown/unclassifiable change selects the protected
  environment and waits for its required reviewer. `workflow_dispatch` with
  `publish=true` cannot force an authority change through the auto environment.
  Keep the required reviewer and auto-environment branch restrictions in GitHub
  settings; those settings are not versioned in this repository.
- The production workflow restores the previously served revision objects into
  the fresh runner before publishing, so a Hosting deploy does not discard the
  versioned release tree. It also retains the public review report as a
  private Actions artifact for 90 days.
  This starts retention from the first fixed deploy; objects already absent
  from the currently served Hosting version require an external backup or a
  deliberate rebuild.
- An unavailable or non-404 production pointer stops publication; only an
  explicit 404 is treated as the first publication.

## Rollback

Do not replace or delete an old revision. Rebuild the desired prior descriptor
set with a new, strictly higher revision, sign it, publish its immutable
object, and then update the pointer. The filesystem publisher tests this exact
sequence with revisions 1, 2, and 3. Firebase's versioned Hosting deploys add
an infrastructure rollback, but the signed catalog revision remains the app's
authoritative rollback record.

## Deferred staging

The staging public key and `Config/PokemonCatalogStaging.xcconfig` may remain
checked in as future rollout material, but the staging Firebase project,
Hosting site, DNS record, Firebase credentials, and deployment job are
intentionally deferred. The staging GitHub environment currently contains only
signing material and must not be treated as deployable until those resources
exist.

The production-host validation-only rehearsal and the `remote-authority`
rehearsal against hosted revision 1 are complete. The committed production
configuration now uses `remote-authority`; the deferred physical-device
acceptance rehearsal, including real offline behavior, remains open. Staging
remains optional/deferred and must use separate project/site/key material if
later provisioned; do not point a production App Store build at it.
