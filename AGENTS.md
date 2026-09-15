# Repository Contribution Guide

**Scope:** the entire repository.

**Guiding principle:** Make the product fast, accurate, and a joy to use. Treat this as the default decision filter for architecture, UX, copy, testing, and documentation; when tradeoffs arise, protect all three qualities and make the tradeoff explicit.

Keep this file durable and repo-wide. User and developer instructions take precedence; a more-specific `AGENTS.md` governs its subtree. Documentation work must also follow [`docs/AGENTS.md`](docs/AGENTS.md).

## Repository shape

- SwiftUI/SwiftData iOS and iPadOS app in `TradingCardScanner/`.
- App and test targets are `TradingCardScanner` and `TradingCardScannerTests` in `TradingCardScanner.xcodeproj`.
- Use [`README.md`](README.md), [`docs/README.md`](docs/README.md), and the current audit/plan documents for product and release status. Source, tests, builds, and current evidence outrank stale plans.

## Working rules

- Inspect `git status --short` and relevant diffs before editing; preserve existing user changes and untracked files.
- Make the smallest focused change. Use `apply_patch`; do not rewrite unrelated files.
- Run the narrowest relevant `xcodebuild` build/test for code changes, then expand verification when risk warrants it. Report failures accurately.
- For documentation-only changes, validate links and run `git diff --check`.
- Do not claim physical-device, provider, CloudKit, archive, or release readiness from source inspection or simulator-only evidence.
- Do not commit, push, reset, broadly clean, or delete user work unless explicitly requested.
- Never commit credentials, API keys, private identifiers, unredacted logs, screenshots, or collection exports.

## Keep this file focused

Put current status, dated evidence, detailed design decisions, and historical findings in the appropriate current documents. Archive stale documentation under `docs/legacy/` with its required pointer/banner; do not silently delete it. Reconcile contradictory plans in the documentation audit instead of duplicating competing instructions here.
