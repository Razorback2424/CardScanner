# Pokémon catalog publisher

The publisher is the human-gated release boundary for the signed catalog.
`PokemonCatalogCore` is the reusable macOS library and
`pokemon-catalog-publisher` is the command-line entry point.

## Local validation

Use the recorded fixture and a fixed timestamp when reviewing deterministic
output:

```sh
swift run --package-path PokemonCatalogCore pokemon-catalog-publisher validate \
  --fixture-dir publisher/fixtures \
  --generated-at 2026-01-01T00:00:00Z
```

The fixture directory's `catalog-input.json` is recorded test input. The
production workflow uses [`publisher/catalog-input.json`](catalog-input.json),
which is intentionally empty until an owner records the printed code (or promo
prefix) from the physical card or official product listing. A provider set that
is not in the active release cannot enter a release without that corresponding
human input. The builder then checks the provider's official denominator and
complete card details.

`--live` replaces the recorded fixture with a bounded TCGdex fetch. It is a
review/diagnostic command; it does not sign anything.

## Publication model

`publish` writes `v1/releases/<revision>/` completely before writing
`current.json`. The current rollout uses one Firebase Hosting project/site and
`publisher/site`. Existing revision bytes are immutable. A rollback is a newly
signed, higher revision whose descriptors match the prior good revision.

Each local revision contains four public artifacts — `catalog-release.json`,
`catalog-payload.json`, `pokemon-catalog-snapshot.json`, and
`review-report.json` — plus a local `.complete` marker. Firebase Hosting
ignores dot-files, so `.complete` is deliberately not part of the hosted
release contract.

Local and pull-request jobs can validate and emit a public review report, but
the CLI refuses to load a signing key unless it is running in the protected
GitHub Actions publication environment. The private key is never checked into
the repository or written to the site directory.

Firebase project selection and the Hosting service account are intentionally
outside this repository. The first deployment uses the protected
`pokemon-catalog-production` environment with
`POKEMON_CATALOG_SIGNING_KEY`, `POKEMON_CATALOG_KEY_ID`,
`FIREBASE_SERVICE_ACCOUNT`, `FIREBASE_PROJECT_ID`, and
`FIREBASE_HOSTING_SITE_ID`. The workflow creates the local production target
binding before deploying; `.firebaserc.example` shows the equivalent mapping
once the owner has the real project and site IDs. A separate staging project,
site, Firebase credential set, and deployment job are deferred until the
remote-authority cutover is actually approaching.

Before the first production publication, seed `publisher/catalog-input.json`
for every currently supported set; later releases need entries only for new
or changed sets. The recorded fixture and its human input are reserved for
staging/synthetic rehearsal.

## Deferred staging app

`Config/PokemonCatalogStaging.xcconfig` and the staging signing key are retained
as future rollout material, but they are not part of the first production
deployment. Do not create a staging Firebase project, Hosting site, DNS record,
or Firebase credential set yet. Add them when the production build is ready to
switch from `bundled-validation-only` to `remote-authority`; the separate
project boundary should be chosen at that point.

The first Slice F rehearsal therefore uses the production hostname with a
bundled-validation-only build: it downloads, verifies, validates, and discards
the candidate without changing production authority.
