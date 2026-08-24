Target screen: Browse root
Route name: Browse
Expected device: PA Quality iPhone 16 Pro

Visual checklist:
1. [ ] Search field is first and clearly spans both games
2. [ ] Pokémon and Magic chooser cards have clear hierarchy and 44-point targets
3. [ ] Browse appears as the fourth native tab without clipping
4. [ ] Dynamic Type produces no clipped labels or overlapping controls
5. [ ] Loading, error, short-query, no-result, and populated states remain legible
6. [ ] Card artwork preserves trading-card aspect ratio and owned badges remain readable
7. [ ] Detail Add button and Undo banner respect safe areas
8. [ ] Light/dark contrast and VoiceOver labels meet the HIG baseline
9. [ ] Every set row shows owned/total completion and an unclipped progress bar
10. [ ] Set card screens expose native Sort and Filter menus without crowding the title or search field
11. [ ] Price-loading feedback is non-blocking and hydrated prices remain legible on artwork tiles

Behavior checklist:
1. [ ] Root search reaches both games and filters by game/multiple sets
2. [ ] Game chooser opens newest-first set directory and set card grid
3. [ ] Exact printing opens detail; finish choice appears only when necessary
4. [ ] Add increments the correct variant and Undo reverses it
5. [ ] Multiple quantities/finishes of one collector number count once toward set completion
6. [ ] Set cards sort in both directions by collector number and published USD price, with unknown prices last
7. [ ] Products Owned and Products Not Owned include normalized import aliases and remain compatible with name/number search
8. [ ] Collection shows whether price fallback is off, unconfigured, running, budget-limited, or provider-paused
9. [ ] Price fallback settings are reachable from Collection and remain synchronized with Scan settings
10. [ ] A non-USD price reaches fallback immediately when enabled, while request 91 is refused locally and 429 responses stop the batch
