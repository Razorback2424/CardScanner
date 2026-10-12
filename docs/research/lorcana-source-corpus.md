# Lorcana provider observation checkpoint

**Status:** bounded source ingestion implemented; 60 focused simulator tests pass —
2026-10-12, `feat/lorcana-implementation` at base `b1959c6` plus local changes.
The [implementation plan](../plans/lorcana_code_implementation.md) remains the
execution authority. This checkpoint does not establish physical-printing,
finish, camera, whole-corpus or production acceptance.

## Reviewed provider contract

Rechecked Lorcast's [overview](https://lorcast.com/docs/api),
[card API](https://lorcast.com/docs/api/cards) and
[set API](https://lorcast.com/docs/api/sets) on 2026-10-12. Card searches must use
`unique=prints`; the default removes gameplay duplicates. Collector numbers are
strings. Set codes, language, rarity and layout remain provider observations.
The currently documented search and set-list envelopes contain `results`; both
documents warn about future pagination.

[`LorcastSourceNormalizer`](../../TradingCardScanner/Games/Lorcana/LorcastSourceNormalizer.swift)
accepts retained JSON and a receipt, with a 2 MiB response bound, 5,000-card and
512-set limits. It validates the exact HTTPS endpoint and all-print query, final
URL, HTTP status, media type, receipt timestamp and SHA-256 association. New
envelope fields or captured continuation headers require contract review;
partial pages, warnings or changed totals cannot silently become a successful
batch. Malformed rows, duplicate provider IDs and contradictory set joins reject
the whole batch. Distinct provider IDs sharing names or collector metadata remain
separate observations. Input order does not affect normalized observation order.

The receipt records public source URL, response URL, UTC receipt time, status,
content type, continuation headers and raw-body digest. A matching digest binds
the retained bytes to the receipt; it does not authenticate the provider or grant
publication rights. Prices and image URLs remain in the raw public JSON but are
excluded from normalized identity metadata. No images are downloaded, and no
price or artwork redistribution decision is made here.

[`capture_lorcana_sources.py`](../../scripts/capture_lorcana_sources.py) uses
bounded curl requests without redirects or retries, spaces requests by 100 ms,
and preserves existing capture files. The initial urllib request received HTTP
403; a public curl request succeeded and is the capture transport. Lorcast
encourages local caching for at least 24 hours; normal offline replay makes no
provider requests.

## Retained metadata

Raw responses and receipts live in the test-only
[`Fixtures/Lorcana`](../../TradingCardScannerTests/Fixtures/Lorcana/) folder and
are bundled only in `TradingCardScannerTests`.

| Capture | Request | Retained rows | Evidence boundary |
| --- | --- | ---: | --- |
| `cards-01` | `elsa set:1`, `unique=prints` | 5 | Includes Elsa — Spirit of Winter at collector strings `42` and `207`, with separate provider IDs. Neither record proves `/204`, a physical UUID or supported finishes. |
| `cards-02` | `distract`, `unique=prints` | 4 | Includes Distract in provider sets `3` and `11` and two Donald Duck — Distracted Traveler rows. Full-text search membership is preserved; no exact-name or gameplay-equivalence inference. |
| `cards-03` | `type:location set:3`, `unique=prints` | 22 | Provider landscape Location metadata, including premium collector strings. This does not validate camera orientation or a complete standard/oversized universe. |
| `sets` | `/v0/sets` | 26 | Provider inventory only, including promo/special codes and a future-dated row. Presence does not certify release, absence does not prove an unsupported physical class nonexistent. |

To reproduce a fresh source checkpoint into a new temporary directory:

```sh
python3 scripts/capture_lorcana_sources.py \
  --output /private/tmp/lorcana-source-review-new \
  --sets --query 'elsa set:1' --query 'distract' \
  --query 'type:location set:3'
```

Do not overwrite the dated fixtures with later market prices or provider edits.
Review new captures and record their own acceptance evidence.

## Remaining physical evidence inventory

| Class / concern | Current evidence | Still required |
| --- | --- | --- |
| Ordinary normal/foil pair | Ordinary provider print metadata | Reviewed physical finish evidence, stable app-owned UUID and complete candidate scope. Price columns cannot supply these. |
| Premium numerator | Provider collector string `207` | Reviewed physical footer, denominator and finish evidence. |
| Cross-set reprint | Separate Distract provider records | Reviewed footer mappings and canonical relationships without merging ownership. |
| Promo / stamp | Provider set-list entries such as `P1`, `cp` and `D23` | Permitted reference corpus, stamp/distribution distinctions and held discrepancies. |
| Landscape Location | 22 provider landscape rows | Physical footer/layout and camera observations. |
| Standard / oversized sharing a footer | No reviewed candidate universe | Separate stable physical UUIDs and size/distinction evidence before exact resolution. |
| Quest / special layouts | Provider inventory includes `Q3` and other special codes | Reviewed card records, physical layouts, footer mappings and explicit unsupported classes. |
| Releases / completeness | One 26-row provider directory | Independent release reconciliation and gaps; the directory includes future-dated `14` and is not a complete physical inventory. |
| Rights / production | Public metadata capture; provider API encourages caching | Review source/artwork/publication terms for the intended product before production delivery. |

No source observation feeds the runtime registry automatically. Schema-1 print
families remain provisional, unknown-footer recovery remains available, and
production registration, ownership and pricing remain disabled. The next task
is reviewed physical records and a versioned identity/finish transition contract.

## Verification

[`LorcastSourceNormalizerTests`](../../TradingCardScannerTests/LorcastSourceNormalizerTests.swift)
replay all four captures and exercise malformed/partial responses, request and
receipt tampering, duplicate/conflicting identities, literal collector strings,
metadata-only prices, deterministic ordering and bounds. Focused simulator
verification passes all 60 selected cases: 12 new ingestion, 13 Lorcana
integration, 31 forward compatibility and four suppression tests, with no skips
or failures. The app/test target builds using the local review scheme and an
isolated iOS 26.5 simulator. Results and derived data are retained on the external
SSD under `CodexBuilds/LorcanaImplementation-20261012/`.

XcodeBuildMCP's post-run parser failed to create its internal log because the
internal volume was full. Direct `xcresulttool` inspection of the completed
external result bundle confirmed `Passed`, 60 total/60 passed/zero failed/zero
skipped. The summary contains one internal QoS warning. Capture syntax, all four
receipt/body digests, documentation links, project syntax and whitespace checks
also pass. No full-suite, physical-card, camera, device or production acceptance
is claimed.
