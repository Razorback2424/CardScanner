# Graded price lookup — fix plan

This is a functional lookup correction, separate from the performance
remediation plan and the shared pricing-cache plan.

## Progress

| Slice | Status | Evidence |
| --- | --- | --- |
| G1 — resolve the vendor set directory | Done | Raw and graded clients share a per-game TTL cache; the Magic divergence test uses the vendor directory slug. |
| G2 — never send a guessed set | Done | An unresolved set omits set and falls back to strict identity matching. |
| G3 — Japanese and edition identity | Done | The request uses pokemon-japan plus the Japanese set ID, and Base Set 1st Edition resolves to the shadowless vendor set. |
| G4 — pin outgoing requests | Done | Tests cover divergent Magic naming, no-guess fallback, Japanese Pokémon, and Base Set 1st Edition. |
| G5 — surface refresh misses | Done | Refresh counts owned graded targets without a matching vendor result and keeps the condition in the summary and attention state. |

## Boundary

Raw and graded pricing share one per-game ProductSetDirectoryProvider. Each
client remains responsible for its own response schema and pacing, while the
provider owns only the cached vendor set directory. A directory miss is not a
slug guess: the graded request omits set and filters returned cards through
GradedCardIdentity.matches.
