# Opus Review Handoff

## Bottom line

The repository builds in Debug tests and Release simulator configuration, and the review universe is fully classified. The app’s core architecture has a coherent durable collection/activity/ledger model, append-only price evidence, explicit USD portfolio eligibility, revision fingerprints, migration gates, and bounded refresh checkpoints. The review nevertheless found fourteen evidence-backed findings, led by identity/provenance and current-vs-replay consistency rather than compile failures.

## Highest-risk findings to carry forward

1. **F-006 — currency transition divergence:** a newer non-USD `PriceStore.store` transition can make current valuation unpriced while replay retains the prior USD evidence, producing an unexplained portfolio residual. This is the most important cross-system accounting finding and is conditional on a provider path delivering a non-USD successful quote.
2. **F-010 — graded CSV identity drift:** production graded rows export a provider field that is already a graded collection key, while import treats it as an underlying printing ID and rebuilds a different key. This is a direct backup/restore identity failure.
3. **F-001/F-002 — slab evidence lifecycle:** unbound label-first evidence can bind to the first later identity, and lifecycle invalidation/background/interrupt paths do not clear active slab state. Both can place prior physical-object grading data on a new scan.
4. **F-011/F-012 — persistence boundary identity:** legacy sealed imports can split from canonical Browse rows after normalization, and activity backfill is globally watermarked despite storage changing per launch.
5. **F-004/F-005/F-007:** history range anchoring, late-event explanation, and local non-USD Price Check state can tell the user a semantically incomplete story even when the numeric data is otherwise preserved.

The complete evidence, counterevidence, and exact paths are in `04-findings.md`.

## Architecture judgment

The strongest design is the separation between durable current state (`CollectedCard`, `PriceRecord`), append-only evidence (`CollectionActivity`, `InventoryEvent`, `PriceObservation`), and derived consumers (`LogicalCollection`, projection, replay, history). The main challenge is keeping identity and semantic state consistent at every interchange/lifecycle boundary. The promoted findings are all cases where two consumers intentionally follow different policies or where an external representation is not the same identity used internally.

The Magic migration/projection concern was investigated and not promoted: treatment/key fields participate in `StoreRevisionMonitor`’s card fingerprint, and changed card fingerprints trigger projection rebuilding. D01–D08 from the prior audit were also rechecked and rejected as current defects; see `05-rejected-hypotheses-and-uncertainties.md`.

## Evidence index

- Current Debug suite: 1,005 tests, 1 skipped, 0 failures; result bundle recorded in `06-device-and-environment-validation.md`.
- Current Release simulator build: succeeded.
- Exact production Swift inventory: 105 files; every file is listed once in `02-coverage-ledger.md` (69 deep, 29 context, 7 device-dependent).
- Data/configuration inventory: manifests, 738 Magic set resources, 160 Pokémon set resources, assets, plist, privacy manifest, and entitlements recorded in `01`/`02`.
- Device/provider/release boundaries and required records: `06-device-and-environment-validation.md`.

## Independent challenge requested

An independent reviewer should first attempt to falsify F-006 with a full SwiftData scenario rather than a direct in-memory record mutation, then test F-010 using a production-created graded row, and finally exercise F-001/F-002 across a physical slab and scene/lifecycle interruption. After that, challenge the conditional import/store findings against real CloudKit/account behavior. These are verification priorities, not a source-change plan.

## Handoff status

- Review artifacts complete: `00` through `07`.
- No production source, tests, project settings, entitlements, schemes, or history changed.
- No commit or push performed.
- Remaining unknowns are explicitly external or unproven in `05` and `06`; no avoidable source-file `NEEDS-FOLLOWUP` remains.
