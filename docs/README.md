# Documentation map

**Status:** current navigation map — 2026-10-15

The [individual-card market history authority](plans/price_history_chart_plan.md)
records the 2026-10-18 decision to show JustTCG historical prices independently
of acquisition and local checks, replacing the archived continuity proposal.

The [four-game specialty coverage review](research/catalog-variant-coverage-2026-10-15/README.md)
records exact Pokémon eligibility repairs, six Magic promo-footer mappings and
132 enabled Lorcana Enchanted printings. Three new One Piece review printings
await approval for signed local activation. Its discrepancy ledgers separate
discovery, physical ownership, pricing and unresolved specialty scope.

The latest [Lorcana edge-case checkpoint](release/lorcana-production-acceptance.md)
records corrected offline batch handling, no-price accounting and invalid-cache
recovery, with 162/162 shared/live cases and all 3,232 enabled pricing lanes
passing. The earlier transport retry/cancellation fixes remain covered. Earlier full-target
and development archive results below predate these fixes. App Store exports
and web page/URL work remain owner-deferred.

The [Lorcana normal pricing rollout](research/lorcana-normal-pricing-rollout.md)
now records 1,616 ordinary mapped printings across eight sets in normal app
registration, using shared ownership and pricing workflows. The
[coverage checkpoint](research/lorcana-catalog-coverage.md) retains discovery and
sealed inventory authority. Older disabled-write/pricing claims are historical
for this mapped scope. The [production checkpoint](release/lorcana-production-acceptance.md)
records rebuilt iOS development archive/export, corrected centering timing and
a finalized full simulator run (2,188 passed, zero failed, 12 skipped);
physical-device, rights, live app pages and distribution gates remain open.
Live sync is deferred for current on-device 1.0.
The later independent continuation verifies all 3,232 enabled pricing lanes with
fresh feeds and passes 19 pricing cases. Local App Store export records a missing
distribution profile; deferred privacy/support work remains paused.
The [Bluehost publication guide](legal/bluehost-publication.md) and
[reviewer path without physical cards](release/lorcana-app-review-notes.md) are
prepared handoff materials, not published/submitted evidence.

This map defines which repository documents are current authorities. Source code,
tests, build settings, and the latest recorded evidence outrank older plans and
chronological notes.

## Current sources of truth

| Concern | Current authority |
| --- | --- |
| Launch commercial rationale and remaining batch-photo gaps | [`plans/CARDSCANNER_LAUNCH_MONETIZATION.md`](plans/CARDSCANNER_LAUNCH_MONETIZATION.md) — proposed free core/free single output and $9.99 one-time batch unlock; price and entitlement boundary pending owner approval. First genuine purchase target: November 2, 2026, Colorado time, without guarantee. |
| Bulk intake differentiation study | [`plans/bulk-intake-differentiation-plan.md`](plans/bulk-intake-differentiation-plan.md) — owner-approved stages; metrics first, then a required device baseline before behavior changes. Formal study protocol remains pending. |
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
| Lorcana integration | [`plans/lorcana_code_implementation.md`](plans/lorcana_code_implementation.md) — current execution and verification authority for ingestion, schema-2 physical resolution, signing contracts, normal ordinary ownership/Browse/CSV and shared pricing. [`research/lorcana-source-corpus.md`](research/lorcana-source-corpus.md) records provider observations; [`research/lorcana-physical-contract.md`](research/lorcana-physical-contract.md) records UUID/choice/finish contracts; [`research/lorcana-signed-activation.md`](research/lorcana-signed-activation.md) records protected remote updates. [`research/lorcana-real-card-corpus/README.md`](research/lorcana-real-card-corpus/README.md) retains unapproved physical scenarios. Public-source review and simulator/live-price evidence do not close physical-device/camera, publication/asset rights or distribution gates. Live sync is deferred for on-device 1.0. [`audits/lorcana-data-variant-scanner-architecture-audit.md`](audits/lorcana-data-variant-scanner-architecture-audit.md) remains background research. |
| Lorcana UI review launch | [`research/lorcana-ui-review.md`](research/lorcana-ui-review.md) — opt-in isolated debug workspace with synthetic scan/choice/finish/Browse/CSV flows; bounded phone/tablet rendering passed. Physical-device/camera and spoken VoiceOver acceptance remain open. |
| Lorcana normal pricing rollout | [`research/lorcana-normal-pricing-rollout.md`](research/lorcana-normal-pricing-rollout.md) — expanded ordinary mappings, persistent UUID ledger, exact source policy, normal app integration and live eight-set acceptance. Held/premium/promo/Quest/later records stay read-only and unpriced. |
| Lorcana production acceptance | [`release/lorcana-production-acceptance.md`](release/lorcana-production-acceptance.md) — rebuilt iOS development archive/export, catalog packaging, corrected centering timing and green full simulator regression; hardware, app legal-page publication, source rights and distribution remain open. CloudKit is deferred for on-device 1.0. |
| Lorcana earlier local pricing review | [`research/lorcana-pricing-review.md`](research/lorcana-pricing-review.md) — historical isolated Hades review/replay; its physical UUIDs and reviewed joins are retained in the expanded normal catalog. |
| Browse set directory defects (artwork kind, set counts, price sort) | [`plans/browse_set_directory_remediation_plan.md`](plans/browse_set_directory_remediation_plan.md) |
| Artwork fallback contract | [`plans/artwork-fallback-plan.md`](plans/artwork-fallback-plan.md) and `TradingCardScanner/Services/ArtworkFallbacks.swift` |
| Pokémon USD price gaps and legacy-feed successor | [`plans/pokemon_usd_price_gap_plan.md`](plans/pokemon_usd_price_gap_plan.md) — 2026-09-26 source-data validation and proposal; no pricing code implemented, live provider counts still open |
| Per-card price history chart | [`plans/price_history_chart_plan.md`](plans/price_history_chart_plan.md) and `PriceHistoryChartModel` in `TradingCardScanner/Views/CollectionCardDetailView.swift` |
| Price-refresh scale backlog | [`plans/price_refresh_scale_plan.md`](plans/price_refresh_scale_plan.md) |
| Pricing correctness and coverage sequence | [`plans/pricing_correctness_and_coverage.md`](plans/pricing_correctness_and_coverage.md) — USD enforcement, mapping/quote/failure distinctions and negative-cache recovery before reviewed mapping expansion and a complete census. |
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
