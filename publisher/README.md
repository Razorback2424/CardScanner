# Pokémon catalog publisher

The publisher is the automatic-preparation and approval-gated boundary for the
signed catalog. TCGdex supplies evidence; only a validated signed release can
authorize scanner recognition.
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
production workflow uses [`publisher/catalog-input.json`](catalog-input.json)
as the owner-controlled override/fallback policy for the bundled catalog.
Ordinary new expansions can enter through the live discovery path when
`abbreviation.official`, the official denominator, release date, and complete
card details validate. Exceptional rows such as promos and non-scannable sets
remain explicit here.

`--live` replaces the recorded fixture with a bounded TCGdex fetch. The live
adapter fetches active sets, explicit override IDs, and due unknown sets after
applying `publisher/discovery-policy.json`; future sets remain pending and
historical IDs are not crawled for card detail. It is a review/diagnostic
command; it does not sign anything.

`discovery-policy.json` is a one-time migration inventory of historical
provider IDs plus the automatic-discovery boundary. It is not a recurring
per-set checklist: do not add announced or future IDs to the historical list.
Unknown IDs are still inspected at set level so historical backfills can be
reported and metadata anomalies can fail closed.

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

Local and pull-request jobs can validate and emit a public review report. The
production workflow prepares and uploads an unsigned candidate before the
publication environment gate. The first nil-to-fingerprint population is a
protected baseline migration. After that, only the explicit content-only
allow-list uses `pokemon-catalog-production-auto`; candidates that add a set,
touch scanner authority, or contain an unknown change use the protected
`pokemon-catalog-production` environment and wait for its required reviewer.
The approved job only loads that exact candidate, signs it, and deploys it. The
CLI refuses to load a signing key outside one of those matching GitHub Actions
production environments. The private key is never checked into the repository
or written to the site directory.

Firebase project selection and the Hosting service account are intentionally
outside this repository. The first deployment uses the protected
`pokemon-catalog-production` environment, and the automatic
`pokemon-catalog-production-auto` environment must carry the same deployment
and signing secrets, with
`POKEMON_CATALOG_SIGNING_KEY`, `POKEMON_CATALOG_KEY_ID`,
`FIREBASE_SERVICE_ACCOUNT`, `FIREBASE_PROJECT_ID`, and
`FIREBASE_HOSTING_SITE_ID`. The workflow creates the local production target
binding before deploying; `.firebaserc.example` shows the equivalent mapping
once the owner has the real project and site IDs. A separate staging project,
site, Firebase credential set, and deployment job remain deferred until a
distinct staging boundary materially reduces rollout risk.

Before the first production publication, keep `publisher/catalog-input.json`
limited to exceptional overrides and fallback policy. The recorded fixture and
its compatibility input are reserved for staging/synthetic rehearsal.

## Deferred staging app

`Config/PokemonCatalogStaging.xcconfig` and the staging signing key are retained
as future rollout material, but they are not part of the first production
deployment. Do not create a staging Firebase project, Hosting site, DNS record,
or Firebase credential set yet. Add them only when a separate project boundary
materially reduces rollout risk; keep its credentials and signing key distinct
from both production publication environments.

The earlier Slice F validation-only rehearsal used the production hostname and
discarded the candidate without changing production authority. The committed
production configuration now uses `remote-authority`; the remaining physical-
device/offline acceptance evidence is tracked in the current update plan.
