# Stage 2: v2 price client (PR #65, publisher #70)

The existing shared TCGCSV product-price actor consumes the publisher's
schemaVersion 2 pointer, validates its content-addressed identity and bounded
relative paths, pins one build per group pair (and per explicit recheck),
and validates each group's exact SHA-256 and byte count before decoding it.
Same-day corrections are distinct from the previous sourceBuild. Existing
cache files decode with an optional verifiedBuildID; no cache reset or
additional storage policy is introduced. The original capture dates and
outage/collection refresh semantics remain authoritative.

Production configuration intentionally stays on v1 for this PR. To validate
against R2 staging, override TCGCSV_PRICE_BASE_URL at build time with
https://catalog-staging.scan-stash.com/market-prices/v2. Once the publishing
and rollback gates are met, a later release configuration change can select
https://catalog.scan-stash.com/market-prices/v2. A v2-configured client can
bootstrap using the sibling v1 endpoint only on a confirmed missing v2 pointer,
and only before accepting v2. Invalid pointers, hash mismatches, and outages
do not downgrade to v1.

No catalog authority, price provider, scope, mapping, quote, or DNS changes.
Production cutover requires a release using the v2 client, verified Firebase
v2 rollback parity, cache verification and the one-week dual-host gate.
