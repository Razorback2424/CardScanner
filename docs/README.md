# Documentation map

**Status:** current navigation map — 2026-09-20

This map defines which repository documents are current authorities. Source code,
tests, build settings, and the latest recorded evidence outrank older plans and
chronological notes.

## Current sources of truth

| Concern | Current authority |
| --- | --- |
| Product behavior and supported scope | [`README.md`](../README.md), `TradingCardScanner/`, and `TradingCardScannerTests/` |
| Repository-wide status and stale-document decisions | [`plans/documentation_audit.md`](plans/documentation_audit.md) |
| Known production defects and their evidence | [`audits/defect_review_pass_2.md`](audits/defect_review_pass_2.md) |
| Release validation and measurement backlog | [`plans/release_followups.md`](plans/release_followups.md) |
| Browse/Catalog contract | [`plans/browse_screen_spec.md`](plans/browse_screen_spec.md), [`references/browse_success_checklist.md`](../references/browse_success_checklist.md), and the current Browse source/tests |
| Automatic Pokémon set updates | [`plans/automatic_pokemon_catalog_updates_plan.md`](plans/automatic_pokemon_catalog_updates_plan.md) — Slices A–E implemented; F04 automatic discovery and the revision-1 authority rehearsal completed 2026-09-19; schema-1 additive fingerprints, canonical publisher/device parity, fail-closed classification, durable targeted reconciliation, parent-artwork metadata, and set-specific Browse updates were implemented 2026-09-20; protected baseline publication, auto-environment setup, four-hour schedule, live-provider, physical-device/offline, first real update, and release acceptance remain open |
| Browse set directory defects (artwork kind, set counts, price sort) | [`plans/browse_set_directory_remediation_plan.md`](plans/browse_set_directory_remediation_plan.md) |
| Artwork fallback contract | [`plans/artwork-fallback-plan.md`](plans/artwork-fallback-plan.md) and `TradingCardScanner/Services/ArtworkFallbacks.swift` |
| Per-card price history chart | [`plans/price_history_chart_plan.md`](plans/price_history_chart_plan.md) and `PriceHistoryChartModel` in `TradingCardScanner/Views/CollectionCardDetailView.swift` |
| Price-refresh scale backlog | [`plans/price_refresh_scale_plan.md`](plans/price_refresh_scale_plan.md) |
| Finish-effect rendering performance | [`superpowers/plans/2026-09-12-foil-effect-performance.md`](superpowers/plans/2026-09-12-foil-effect-performance.md) |
| Future shared pricing backend | [`plans/shared_pricing_cache_plan.md`](plans/shared_pricing_cache_plan.md) |
| App Review remediation | [`app_review_fix_plan.md`](../app_review_fix_plan.md) and [`app_review_preflight.md`](../app_review_preflight.md) |
| Phase 0/1 release evidence | [`release/phase-1-integrity-evidence.md`](release/phase-1-integrity-evidence.md), [`release/cloudkit-compatibility-audit.md`](release/cloudkit-compatibility-audit.md), and [`release/cloudkit-release-matrix.md`](release/cloudkit-release-matrix.md) |
| Pro tab and eBay listing photos | [`plans/pro_tab_ebay_listing_photos_plan.md`](plans/pro_tab_ebay_listing_photos_plan.md) |
| Active card-centering work | [`../review/opus-card-centering-implementation-plan.md`](../review/opus-card-centering-implementation-plan.md) and [`../review/centering-evidence/`](../review/centering-evidence/) |
| Chronological implementation record | [`../progress.md`](../progress.md) |
| Legal/support copy | [`legal/privacy-policy.md`](legal/privacy-policy.md) and [`legal/support.md`](legal/support.md) |

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
