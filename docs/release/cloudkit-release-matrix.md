# CardScanner CloudKit release matrix

This matrix is intentionally present before external enrollment. Every row is
`NOT RUN` until the exact signed TestFlight candidate, Production container,
and two physical devices are available.

| ID | Build | Device A/OS | Device B/OS | Account state | Preconditions/digest | Action | Expected | Observed | Final A digest | Final B digest | Result | Evidence |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| E1 | TBD | TBD | TBD | A available | fresh/no anchor | Fresh install claims anchor | One identity, no confirmation | — | — | — | NOT RUN | — |
| E2 | TBD | TBD | TBD | A available | remote anchor exists | Fresh install adopts remote | Restoring until affirmative readiness | — | — | — | NOT RUN | — |
| E3 | TBD | TBD | TBD | no account | fresh local store | Create, terminate, relaunch | Same local identity/data | — | — | — | NOT RUN | — |
| E4 | TBD | TBD | TBD | A → B | local data exists | Sign in to a different account | Confirmation before attachment | — | — | — | NOT RUN | — |
| E5 | TBD | TBD | TBD | A → B | B has different anchor | Attempt attachment | Conflict; no merge | — | — | — | NOT RUN | — |
| E6 | TBD | TBD | TBD | A available | same baseline | Offline independent mutations | Event/activity union converges | — | — | — | NOT RUN | — |
| E7 | TBD | TBD | TBD | A available | same baseline | Same-record quantity conflict | No ownership loss or synthetic repair fact | — | — | — | NOT RUN | — |
| E8 | TBD | TBD | TBD | A available | synced baseline | Delete versus edit | Deterministic preservation/reconciliation | — | — | — | NOT RUN | — |
| E9 | TBD | TBD | TBD | A available | synced baseline | Reinstall and restore | No false empty UI; digest converges after proof | — | — | — | NOT RUN | — |
| E10 | TBD | TBD | TBD | A available | converged baseline | CSV portability cross-check | Supported identity/quantity agrees | — | — | — | NOT RUN | — |

## Required evidence

Record only opaque store-ID suffixes, coarse account/attachment states, counts,
and digests. Do not commit raw CloudKit record names, account identifiers,
credentials, certificate IDs, collection exports, or card images.
