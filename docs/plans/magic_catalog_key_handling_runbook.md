# Magic catalog signing and publication runbook

Status: current implementation companion — 2026-09-20

Magic and Pokémon use independent Ed25519 signing keys. The Pokémon private
key must not be provisioned into either Magic publication environment. Magic
catalog releases are signed authority for MagicCatalogSetDescriptor values;
card-level Scryfall data remains live and is outside this signed catalog.

## Key custody and public pin

Generate a Magic-specific Ed25519 key pair using the same raw 32-byte private
key representation accepted by MagicCatalogSigningKeyLoader. Keep the private
key only in owner-controlled secure storage and in the two GitHub Magic
publication environments. Do not place it in the repository, fixtures,
reports, artifacts, logs, shell history, or documentation.

The key ID must use the form:

    magic-catalog-production-YYYY-MM-DD-01

The repository needs only the non-secret key ID and the base64url public key.
Owner input is still required for this pin:

    OWNER INPUT REQUIRED:
    MAGIC_CATALOG_KEY_ID
    MAGIC_CATALOG_PUBLIC_KEY_BASE64URL

The read-only migration check of
https://scanstash-catalog-prod.web.app/magic/v1/current.json returned HTTP 404
on 2026-09-20. There is therefore no existing signed Magic release to migrate;
once the owner supplies the two values above, replace the temporary old pin in
Config/MagicCatalogProduction.xcconfig directly with the Magic-specific pin.
If a signed release exists during a future migration, verify it against the
old or new key before changing the accepted pins; an unexpected status or an
unverifiable release stops publication. Do not enable remote authority while
the old Pokémon key remains accepted by Magic.

Keep MAGIC_CATALOG_ROLLOUT_MODE = legacy-live until a separate rollout
decision.

## GitHub environments

magic-catalog-production is the protected environment. It contains the
Magic-specific private key, Magic-specific key ID, Firebase deployment
secrets, required reviewer(s), and a deployment branch restriction to main.

magic-catalog-production-auto contains the same Magic-specific signing and
Firebase secrets, has no required reviewer, and is restricted to main. It must
not contain POKEMON_CATALOG_SIGNING_KEY or POKEMON_CATALOG_KEY_ID. The
protected Magic environment should not need those Pokémon values either.
Environment settings are an operational boundary and are not enforced by YAML
alone; the code-level signing loader is a second enforcement layer.

Both production environments require all four context guards:

    GITHUB_ACTIONS == "true"
    GITHUB_EVENT_NAME != "pull_request"
    GITHUB_REF == "refs/heads/main"
    MAGIC_CATALOG_PUBLISH == "true"

The automatic environment additionally requires the recomputed change class to
be contentOnly. The protected environment may sign protected classes and may
also handle a content-only candidate. Staging remains non-publishable and is
not provisioned by this project.

## Safe automatic publication

The only automatic field allow-list is exactly:

    displayName
    releaseDate
    cardCount
    iconSVGURL

Magic cardCount is Browse metadata only.
Magic printedSize is the scanner denominator.

The classifier matches descriptors by normalized code, compares the complete
sorted-key JSON representation, and fails closed when an exact field
difference cannot be inspected. The surface invariant independently requires
that a content-only candidate have no scanner or routing projection changes
and that its Browse projection changes exactly match its content changes.

The resulting routing is:

| Change class | Publication path |
| --- | --- |
| none | no publication |
| contentOnly | magic-catalog-production-auto |
| authority | magic-catalog-production |
| newSet | magic-catalog-production |
| unknown | magic-catalog-production |

New Scryfall sets never mint scanner vocabulary automatically. Scanner,
routing, identity, membership, set-type, denominator, addition, removal, and
unclassifiable changes remain protected authority decisions. An active-set
removal must be explicitly authorized with allow-removal-codes during a manual
workflow dispatch; scheduled runs receive no removal authorization. A
successful authorized removal is still class authority.

## Provider and URL boundaries

Scryfall /sets is the only Magic catalog provider input. Magic has no provider
fingerprint, baseline migration, device fingerprint reconciliation, or
card-level Scryfall fetch in this publication system. No new card-level signed
authority is introduced.

Every non-nil iconSVGURL is revalidated in MagicCatalogReleaseValidator,
including downloaded signed releases. It must use HTTPS, have the exact host
svgs.scryfall.io, have no userinfo, port, query, or fragment, and have a
non-empty path. Suffix matches and arbitrary Scryfall-owned hosts are not
accepted.

## Publish-time security sequence

The publish job verifies the active signed Magic release, loads the candidate
catalog-payload.json and review-report.json, validates the candidate against
the active release, and independently recomputes the surface diff and
classification from those releases. It then checks both the workflow
requested change class and report changeClass against the recomputed result
before loading any signing material. The report hash protects transport
integrity between jobs; it is not publication authority.

The publisher writes an immutable higher revision before updating current.json.
Rollback is a new higher signed revision that restores the desired descriptors;
old revisions are not mutated or deleted.
