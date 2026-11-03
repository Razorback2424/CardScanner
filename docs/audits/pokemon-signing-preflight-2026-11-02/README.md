# Membership signing preflight

**2026-11-02 — read-only native verification passed; no publication.**

The earlier batch runs verified the isolated new memberships. This milestone
also checks their compatibility with the actual hosted production release.
The [native receipt](report.json) identifies the exact input and envelope hashes.
No production catalog input or app logic changed during this preflight.

## Verified evidence

- Downloaded the hosted current envelope and verified its Ed25519 signature
  with the existing native publisher, using the public key pinned in
  [PokemonCatalogProduction.xcconfig](../../../Config/PokemonCatalogProduction.xcconfig).
  The verified active revision is **19**.
- The [immutable revision 19 envelope](https://scanstash-catalog-prod.web.app/v1/releases/19/catalog-release.json)
  is byte-for-byte equal to the verified pointer. Its SHA-256 is
  `ba47f27434d48983218374538f84550101d70ab0f15e123ab691ae9708087333`.
- Materialized the previously validated 41-set / 794-card isolated batch with
  the normal native publisher. The shared `PokemonCatalogCandidateValidator`
  accepted its release, snapshot and review report as consistent artifacts.
- The [read-only native audit](../../../scripts/audit_pokemon_signed_membership.swift)
  independently verified the hosted signature, then validated an in-memory
  union of all **74 descriptors**: the exact active 33 plus the new 41.
  Existing descriptors were preserved, all 794 new provider-card IDs were
  unique, and membership objects matched the current production authoring input.
- The real `PokemonCatalogChangeClassifier` classified the union as **newSet**
  with 41 additions and no changed existing descriptors. This requires the
  protected production route, not the automatic content-only route.

The audit was compiled against the existing native Core library. Its executable,
module cache and prior Core build remain on the external SSD. No iOS build or
redundant regression-test run was performed. The final native audit invocation
passed; local links, report counts and `git diff --check` also passed.

## Limits and next gates

The union check is **not a fresh full production provider build**. It preserves
the active 33 descriptors exactly rather than recrawling all of their provider
cards. Consequently, it cannot certify current provider fingerprint freshness,
the full 74-set snapshot, exact prices or installed scanner behavior. The
41-set isolated artifact uses its own fixture-local revision; it must never be
published as a replacement for the 74-descriptor production catalog.

Normal publication must rebuild the full live candidate against the then-active
release and follow the protected signing route in the
[workflow](../../../.github/workflows/pokemon-catalog.yml) and
[runbook](../../plans/pokemon_catalog_key_handling_runbook.md). No signing secret
was accessed and no new signature, commit, push, workflow dispatch, deployment
or installed-app mutation occurred.

The [scope question from the residual promo audit](../pokemon-residual-promos-2026-11-02/README.md)
remains unanswered: current instructions prohibit the schema/consumer changes
needed to transport and apply the confirmed variant and product-binding repairs.
Automatic goal continuations are not approval for that scope change. The
Charizard display label remains **Jumbo**. Full English physical-printing,
scanner and exact-price completeness is unproven; the goal remains active.

## Reproduction

Generate the isolated candidate with the existing publisher's `validate
--candidate-root` option, using the complete 794-card recorded provider fixture
from the batch validation. Then compile the audit against the same Core build
and pass these positional arguments:

1. Downloaded production envelope.
2. Public-pin xcconfig.
3. Isolated candidate directory containing its payload, snapshot and review.
4. Current `publisher/catalog-input.json`.
5. Destination for the JSON receipt.

The temporary raw fixture is local validation evidence, not a committed signing
artifact. If reconstructed from current providers, verify all retained source
hashes and rerun the two-source comparisons before treating it as the same batch.
