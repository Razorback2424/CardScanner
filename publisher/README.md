# Pokémon catalog publisher

The publisher prepares the signed catalog for review and publication. TCGdex
supplies evidence. The app ships a bundled registry, and a validated signed
release authorizes remote recognition updates.
`PokemonCatalogCore` is the reusable macOS library and
`pokemon-catalog-publisher` is the command-line entry point.

Missing card artwork is resolved from exact card details, then from the card's
own TCGdex CDN path, before considering the secondary provider. CDN recovery
uses the provider's series, set, and padded local ID; each recovered image must
return a successful image response and decode. PNG and WebP derivatives are
checked independently, and a single healthy size can serve both placements.
The app shares this resolver for live lookups and saved collection repair.
Recovered URLs remain separate from raw provider fingerprint data. Recorded
fixture validation never performs live artwork probes.

The opt-in CDN regression check is
`POKEMON_LIVE_ARTWORK_TESTS=1 swift test --package-path PokemonCatalogCore --filter TCGdexCardArtworkResolverTests/testLiveManifestOmissionsWhenRequested`.

## Local validation

Use the recorded fixture and a fixed timestamp when reviewing deterministic
output:

```sh
swift run --package-path PokemonCatalogCore pokemon-catalog-publisher validate \
  --fixture-dir publisher/fixtures \
  --generated-at 2026-01-01T00:00:00Z
```

The `verify-candidate` command checks a prepared directory against a verified
active release. Pass `--candidate-root`, `--active-release`, and `--environment`
to check an upgrade without signing it.

The fixture directory's `catalog-input.json` is recorded test input. The
production workflow uses [`publisher/catalog-input.json`](catalog-input.json)
as the owner-controlled override/fallback policy for the bundled catalog.
Ordinary new expansions can enter through the live discovery path when
`abbreviation.official`, the official denominator, release date, and complete
card details validate. Exceptional rows such as promos and non-scannable sets
remain explicit here.

MEE Basic Energy is an explicit denominator-free Energy override. Its reviewed
secondary printings and maintenance boundary are documented in
[MEE onboarding evidence](mee-energy-evidence.md).

The [English McDonald's 2026 set](pokemon-mcdonalds-2026.json) is bundled
with the app while TCGdex has no M26 entry. Its 15 cards keep the printed
`M26` numbers and use `tcgplayer:<productID>` as stable card identities. The
price publisher reads the same table to scope group `24938` to the eight
Normal and seven Holofoil listings. If TCGdex adds the set, reconcile the
provider IDs with these existing holdings before enabling a signed entry for
the same printed code. [TCGCSV products](https://tcgcsv.com/tcgplayer/3/24938/products),
[market price lanes](https://tcgcsv.com/tcgplayer/3/24938/prices).

The proposed revision 10 Classic Collection membership was checked against
public provider names and marketplace printed numbers on 2026-09-30. See the
[row evidence and revision 11 correction boundary](classic-collection-evidence.md).
Bundled membership parity is tested; first-launch offline selection still
requires a downloaded Classic checklist to resolve a card.

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

The signed payload authenticates the checklist inputs. The app stages those
inputs before activating the revision. Separate provider fingerprints let the
publisher identify artwork updates and changes to numbered identities or finish
evidence. The first fingerprint baseline and subsequent acquisition changes
require review.

Scheduled runs prepare an unsigned candidate and publish eligible content-only
updates. A manual run with `publish=false` prepares a candidate for review.
After reviewing its artifacts, dispatch on `main` with `publish=true`, the
candidate's workflow run ID, and the manifest SHA-256 from its summary. The
publication job rechecks those bytes against the current production release
before signing and verifies the deployed pointer, envelope, and checklist on
both catalog hosts.

Firebase project selection and the Hosting service account are configured on
the `pokemon-catalog-production` environment. It carries
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
from the production publication environment.

The earlier Slice F validation-only rehearsal used the production hostname and
discarded the candidate without changing production authority. The committed
production configuration now uses `remote-authority`; the remaining physical-
device/offline acceptance evidence is tracked in the current update plan.

## Daily TCGCSV coverage audit

The local audit retains every Pokémon TCGCSV group and its product and price
files. It reuses the One Piece capture code to verify the upstream build and
retained bytes. The app test uses the signed production catalog and local
app sources to export installed Browse slots, supported Scan lookups, and
exact pricing and card-detail bindings. The audit also checks the hosted
price mirror for the reviewed product and finish pairs.

Run from the repository root with an available iOS simulator and DerivedData
on the external SSD.

```sh
python3 scripts/audit_pokemon_tcgcsv.py run \
  --root .codex_build_pokemon_tcgcsv \
  --destination 'platform=iOS Simulator,id=<audit-simulator-id>' \
  --derived-data '/Volumes/<external-ssd>/<audit-derived-data>'
```

Follow `.codex_build_pokemon_tcgcsv/latest-run.txt` to the latest successful
run. `summary.json` records the source and catalog versions, source changes,
and coverage changes. `review-queue.csv` prioritizes Deck Exclusives, promos,
and Prize Packs. `comparison.json` retains the exact matches and candidate
matches behind the review queue. A name or number match only suggests which
card to inspect. Hosted price checks cover the reviewed TCGCSV mirror scope.

The daily Codex automation runs on the local Mac after the scheduled market
refresh. It reuses an export when the app inputs and signed catalog bytes are
the same. A ProfileLocal `.xctestrun` can also be supplied with `--compiled-test`
when it has a matching app source fingerprint in its companion `.sha256` file.
Otherwise Xcode builds the audit test from the checkout. The audit writes its
reports to the ignored local directory. See the
[first comparison](../docs/audits/pokemon-tcgcsv-first-pass-2026-11-12.md).

The app and price publisher share the
[Delta Reign printing table](pokemon-delta-reign-printings.json). The
[evidence ledger](pokemon-delta-reign-evidence.md) records the deck finishes,
the MEP 111–117 variants, and the pending Staff Kommo-o market binding.
