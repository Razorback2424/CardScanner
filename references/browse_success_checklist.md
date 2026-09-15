Target screen: Catalog root inside Collection
Route name: `Browse` debug route / `Collection → Catalog`
Expected device: PA Quality iPhone 17 Pro

Status: current deterministic Browse verification — 2026-09-14. Browse is a
push destination owned by the Collection tab, not a native top-level tab.

The current simulator evidence covers the root chooser and the bundled local
Pokémon lane. It does not claim the full remote/provider interaction matrix.

Visual checklist:
1. [x] Search field is first and clearly spans both games.
2. [x] Pokémon and Magic chooser cards have clear hierarchy and 44-point
   targets.
3. [x] Catalog opens as a Collection push destination; Collection remains the
   selected native tab without clipping.
4. [ ] Dynamic Type produces no clipped labels or overlapping controls
5. [ ] Loading, error, short-query, no-result, and populated states remain legible
6. [ ] Card artwork preserves trading-card aspect ratio and owned badges remain readable
7. [ ] Detail Add button and Undo banner respect safe areas
8. [ ] Light/dark contrast and VoiceOver labels meet the HIG baseline
9. [x] Every set row shows owned/total completion and an unclipped progress bar
10. [x] Set card screens expose native Sort and Filter menus without crowding the title or search field
11. [x] Price-loading feedback is non-blocking and hydrated prices remain legible on artwork tiles

Behavior checklist:
1. [x] Root search reaches both games and filters by game/multiple sets
2. [x] The game chooser opens the bundled Pokémon lane and its set/card surface;
   provider ordering remains covered by the catalog contract.
3. [x] Exact printing opens detail; finish choice appears only when necessary
4. [x] Add increments the correct variant and Undo reverses it
5. [x] Multiple quantities/finishes of one collector number count once toward set completion
6. [x] Set cards sort in both directions by collector number and published USD price, with unknown prices last
7. [x] Products Owned and Products Not Owned include normalized import aliases and remain compatible with name/number search
8. [x] Collection shows whether price fallback is off, unconfigured, running, budget-limited, or provider-paused
9. [x] Price fallback settings are reachable from Collection and remain synchronized with Scan settings
10. [x] A non-USD price reaches fallback immediately when enabled, while request 91 is refused locally and 429 responses stop the batch

Implementation verification (2026-09-14):

- [x] The prescribed `Browse` route builds and renders the settled Catalog root.
- [x] The inspected root capture keeps Collection selected, shows `Catalog`, `Search the catalog`, `Just released`, and `Browse by game`, with no top-level sealed section.
- [x] Focused `BrowseFeatureTests`, `SealedBrowseSurfaceTests`, and
  `ViewConstructionSmokeTests` pass.
- [ ] The repository-wide test target is not recorded as clean because unrelated centering/fixture and scanner-environment tests fail in this simulator environment.

Audit remediation verification (2026-09-14):

- [x] Card pagination keeps its sentinel mounted while loading and ignores cancelled pages instead of poisoning the lane.
- [x] Unconfigured sealed browsing reads a cached directory and does not call the provider when the directory is missing or cached.
- [x] The retained Cards subtree gates search requests while Sealed is active, preserving loaded card pages across the segment switch.
- [x] Unified ranking, card grouping, game-row artwork selection, Magic identity disambiguation, artwork retry, and trailing sort-chip chevron are implemented and build-verified.
- [x] Focused `BrowseFeatureTests`, `SealedBrowseSurfaceTests`, and
  `ViewConstructionSmokeTests` pass after adding pagination, cached-directory,
  duplicate-identity, and inactive-segment search regressions.
- [x] The prescribed `Browse` route renders a settled Catalog root after the final implementation build.

Remaining manual sign-off is intentionally limited to set-tile accessibility
output, DisclosureGroup expand/collapse behavior, dark-mode badge contrast, and
AX5 fit. Remote-provider and physical-device behavior remains a release gate,
not an unchecked claim in this deterministic checklist.
