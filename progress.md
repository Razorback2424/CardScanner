Original prompt: Implement Browse Sets and Cards across Pokémon/TCGdex and Magic/Scryfall.

- Added deterministic Browse launch route and QA checklist. Build/screenshot execution intentionally not run per user instruction.
- Implemented provider-neutral catalog browsing, both providers, global filtering/search, exact-printing add/undo, ownership aliases, release ranks, and unit-test coverage. Static checks only.
- Added at-a-glance unique-card set completion (`owned/total`) and progress bars to game set lists. Builds/tests/screenshots remain intentionally unrun.
- Added per-set card sorting by price or collector number plus owned/not-owned product filters. Price sorting hydrates exact-printing prices on demand with bounded concurrency and caching; execution checks remain intentionally unrun.
- Made the optional price fallback free-tier safe: fresh non-USD values become fallback work only when enabled, actual HTTP requests are capped at 90 per UTC day/run, 429 backoff is persisted, and Collection now exposes pending work, allowance state, and shared fallback settings. Builds/tests remain intentionally unrun.
