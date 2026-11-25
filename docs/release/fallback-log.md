# Fallback log

**Status:** current release ledger. Opened 2026-11-24 under the
[launch contract](launch-contract.md) owner-choice amendment. The G06 quiet
window has not started.

This log records every time someone reaches for Collectr or another app for a
task Card Scanner promises, because ours was missing something, broken, slow or
confusing. It is the measurable form of the product bar: Card Scanner is
the app a collector chooses to come back to. [§6 of the launch contract](launch-contract.md#finding-intake-amendment-2026-11-24)
defines how entries are classified. [G06](launch-contract.md#8-final-release-decision)
requires this log to be closed and quiet.

## Declared jobs

Only these jobs count as in scope. A fallback for anything else goes to the
next-release section.

| Job | Covered by |
| --- | --- |
| Add cards I own, by scanning or by finding them in Browse | J02–J05, S02–S07 |
| Know what a card or my collection is worth, and how that changed | J05–J06, S09–S10 |
| Find a card or set and see what I'm missing | S06 |
| Compare both sides of a trade at a show | J13, S05.06–S05.08 |
| Move my collection in or out with a file | J07, S11 |
| Prepare listing photos and a centering estimate | J08–J10, S12–S14 |

## How to record an entry

Write one row as soon as it happens, even if you don't know the cause. The
**Why** column takes one of these: *missing* (we don't do it), *broken* (we do
it wrong or it fails), *slow* (it works but too slowly to wait for) or
*confusing* (it works, but I couldn't tell how or whether it did). Identify
external collectors by tester code only, never by name. Don't attach collection
exports or unredacted screenshots.

**Disposition** is one of: *open*, *fixed on build N* (verified in the real
workflow, not just merged), *limitation approved by Sean* (with the
support-manifest change), *defect → S/J ID* (also tracked as a defect) or
*next release* (out of scope).

## Quiet window

| Field | Value |
| --- | --- |
| Window start (owner's everyday use, no open in-scope entries) | Not started |
| Last new in-scope entry | — |
| External collector sessions logged | 0 of 5 |
| Closes (G06) | Window start + 14 days, with no new in-scope entry and all entries resolved |

## Entries

| ID | Date | Who | Job | Task attempted | Other app | Why | Class | Disposition |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| F-001 | Before 2026-11-23 (recorded retroactively) | Owner | Compare a trade | Weigh both sides of a card-show trade | Another app | Missing | Fallback gap | Implemented in `d7ce6665` / `5800704b`; device and live-price acceptance pending (J13) — **open** |
| F-002 | Before 2026-11-22 (recorded retroactively) | Owner | Find a card or set | Filter and sort catalog and collection results across games | Another app | Missing | Fallback gap | Implemented in `e970ef63` / `c3d186d5`; device acceptance pending (S06.01) — **open** |

## Next release

Improvements and out-of-scope fallbacks. These don't block launch.

| ID | Date | Source | Idea or gap | Notes |
| --- | --- | --- | --- | --- |
| — | — | — | — | — |
