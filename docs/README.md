# Documentation map

**Status:** current navigation map — 2026-10-06

This map defines which repository documents are current authorities. Source code,
tests, build settings, and the latest recorded evidence outrank older plans and
chronological notes.

## Current sources of truth

| Concern | Current authority |
| --- | --- |
| Product behavior and supported scope | [`README.md`](../README.md), `TradingCardScanner/`, and `TradingCardScannerTests/` |
| Card coverage gaps and research priorities | [`audits/card-coverage-gaps-and-research.md`](audits/card-coverage-gaps-and-research.md) — dated source/data review separating explicit exclusions, unresolved printings and unverified completeness; game-specific plans retain implementation authority. |
| Useful card coverage data | [`research/card-coverage-gap-data/README.md`](research/card-coverage-gap-data/README.md) — three retained missing-data/regression tables, with duplicate and unsupported inputs excluded; no runtime adoption or completeness certification. |
| Historical Magic recognition | [`plans/magic_historical_recognition_plan.md`](plans/magic_historical_recognition_plan.md) and [general scanner evidence](research/magic-historical-corpus/general-scanning.md) — normal raw/slab scanning uses general historical OCR and current complete printing families, with explicit English/printing choice. All 27 reference images reach choices; no per-card activation list. Optional automatic index selection stays disabled. Held-out/device acceptance remains open. |
| Repository-wide status and stale-document decisions | [`plans/documentation_audit.md`](plans/documentation_audit.md) |
| Known production defects and their evidence | [`audits/defect_review_pass_2.md`](audits/defect_review_pass_2.md) |
| October boundary-failure remediation | [`audits/october-review-remediation.md`](audits/october-review-remediation.md) — per-slice implementation and simulator evidence; physical-device performance measurements remain pending. |
| October refinement follow-up | [`plans/october-refinement-implementation-plan.md`](plans/october-refinement-implementation-plan.md) — source-validated findings with implementation slices A–I and C1 committed on `fix/october-review-boundaries`; final verification and device/release acceptance remain open. |
| Additional production refinement review | [`plans/october-production-refinement-review-plan.md`](plans/october-production-refinement-review-plan.md) — A–J implemented against `dd2a1e3`; final regression has 1,707 passed, seven existing skips, zero failures; publisher package 74/74. Centering latency remains open. Further profiling/screenshots/device/native acceptance and live legal/support pages are owner-deferred. |
| Scanner module defects and measurement review | [`audits/scanner_module_review.md`](audits/scanner_module_review.md) |
| Raw / graded slab scanning mode | [`plans/explicit-raw-slab-scanning-mode.md`](plans/explicit-raw-slab-scanning-mode.md) — implemented in the 2026-09-23 working tree; initial focused simulator tests pass 166/166 and the review follow-up passes 11/11 targeted non-centering tests. The earlier full simulator run excluded centering-specific classes at the user's request; device/provider acceptance remains open. |
| Scanner recognition and Needs attention recovery | [`plans/scanner-recognition-remediation.md`](plans/scanner-recognition-remediation.md) — denominator-owned Pokémon inference, conservative fuzzy title agreement, and local-only persistent failure recovery; see the [2026-10-06 cross-game edge-case review](audits/scanner-cross-game-edge-cases-2026-10-06.md) and dated evidence in [`progress.md`](../progress.md). Physical-device and Instruments acceptance remain open. |
| Release validation and measurement backlog | [`plans/release_followups.md`](plans/release_followups.md) |
| Browse/Catalog contract | [`plans/browse_screen_spec.md`](plans/browse_screen_spec.md), [`references/browse_success_checklist.md`](../references/browse_success_checklist.md), and the current Browse source/tests |
| Automatic Pokémon set updates | [`plans/automatic_pokemon_catalog_updates_plan.md`](plans/automatic_pokemon_catalog_updates_plan.md) — Slices A–E implemented; F04 automatic discovery and the revision-1 authority rehearsal completed 2026-09-19; schema-1 additive fingerprints, canonical publisher/device parity, fail-closed classification, durable targeted reconciliation, parent-artwork metadata, and set-specific Browse updates were implemented 2026-09-20; protected baseline publication, auto-environment setup, four-hour schedule, live-provider, physical-device/offline, first real update, and release acceptance remain open |
| Magic catalog signing and publication | [`plans/magic_catalog_key_handling_runbook.md`](plans/magic_catalog_key_handling_runbook.md) — current authority for Magic-specific key custody, signed catalog releases, protected/automatic publication routing, Scryfall boundaries, and rollout safeguards; owner key-pin input remains open and rollout remains `legacy-live` |
| One Piece expansion | [`plans/one_piece_catalog_integration_plan.md`](plans/one_piece_catalog_integration_plan.md) — catalog design, source roles and acceptance; [`plans/one_piece_code_implementation.md`](plans/one_piece_code_implementation.md) records the full ordinary corpus, exact pricing and integrated local acceptance slice. [`plans/one_piece_release_acceptance.md`](plans/one_piece_release_acceptance.md) separates simulator evidence from device/provider/sync/publication gates. Production publication remains disabled. |
| Lorcana integration | [`plans/lorcana_code_implementation.md`](plans/lorcana_code_implementation.md) — current execution authority, recalibrated for the shared game adapters; first local print-family/footer/recovery slice has 44 focused passing tests. Production registration, exact physical resolution and provider/corpus gates remain open. [`audits/lorcana-data-variant-scanner-architecture-audit.md`](audits/lorcana-data-variant-scanner-architecture-audit.md) remains imported background research. |
| Browse set directory defects (artwork kind, set counts, price sort) | [`plans/browse_set_directory_remediation_plan.md`](plans/browse_set_directory_remediation_plan.md) |
| Artwork fallback contract | [`plans/artwork-fallback-plan.md`](plans/artwork-fallback-plan.md) and `TradingCardScanner/Services/ArtworkFallbacks.swift` |
| Per-card price history chart | [`plans/price_history_chart_plan.md`](plans/price_history_chart_plan.md) and `PriceHistoryChartModel` in `TradingCardScanner/Views/CollectionCardDetailView.swift` |
| Price-refresh scale backlog | [`plans/price_refresh_scale_plan.md`](plans/price_refresh_scale_plan.md) |
| Pokémon USD pricing coverage | [`plans/browse_pricing_coverage_plan.md`](plans/browse_pricing_coverage_plan.md) — device-local TCGCSV fallback for both 30th sets; 322 focused simulator tests and a live 188-card feed check passed 2026-09-30. General bulk-provider migration remains unresolved. |
| Finish-effect rendering performance | [`superpowers/plans/2026-09-12-foil-effect-performance.md`](superpowers/plans/2026-09-12-foil-effect-performance.md) |
| Future shared pricing backend | [`plans/shared_pricing_cache_plan.md`](plans/shared_pricing_cache_plan.md) |
| App Review remediation | [`app_review_fix_plan.md`](../app_review_fix_plan.md) and [`app_review_preflight.md`](../app_review_preflight.md) |
| Phase 0/1 release evidence | [`release/phase-1-integrity-evidence.md`](release/phase-1-integrity-evidence.md), [`release/cloudkit-compatibility-audit.md`](release/cloudkit-compatibility-audit.md), and [`release/cloudkit-release-matrix.md`](release/cloudkit-release-matrix.md) |
| Pro tab and eBay listing photos | [`plans/pro_tab_ebay_listing_photos_plan.md`](plans/pro_tab_ebay_listing_photos_plan.md) |
| Active card-centering work | [`audits/centering-guided-repair.md`](audits/centering-guided-repair.md) — current guided repair and verification; [`../review/opus-card-centering-implementation-plan.md`](../review/opus-card-centering-implementation-plan.md) retains automatic/held-out acceptance, with dated [`../review/centering-evidence/`](../review/centering-evidence/). |
| Chronological implementation record | [`../progress.md`](../progress.md) |
| Legal/support copy | [`legal/privacy-policy.md`](legal/privacy-policy.md), [`legal/support.md`](legal/support.md), and [publication checks](legal/README.md) — Scanstash drafts with owner-confirmed contact; live publication and provider/retention verification remain open. |

Integration review handoff: [One Piece merge-branch change report](audits/one-piece-integration-review-handoff.md)

One Piece owner approvals, local preparation and remaining device/release gates:
[v1 release acceptance](plans/one_piece_release_acceptance.md).
records the committed integration/finding fixes, subsequent local cleanup,
verification, historical transfer evidence, and open work.

## Legacy boundary

Documents that describe a completed, superseded, or stale snapshot live in the
[`legacy/`](legacy/) archive. They remain available for provenance and historical
comparison, but their branches, commit hashes, test counts, checkbox state, and
“current” wording must not be used as release evidence.

The active centering evidence directory intentionally contains dated baseline
artifacts as part of the current experiment ledger; its README and individual
artifacts identify which measurements are historical versus current.

When a current plan is replaced, preserve the old file in `legacy/`, add a
current pointer at the old authority path when callers depend on that path, and
update [`plans/documentation_audit.md`](plans/documentation_audit.md).
