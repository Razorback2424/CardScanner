# Classic Collection artwork recovery

**Status — 2026-10-28:** implemented; 12 optimized native tests passed. Signed
build installed in place on the physical iPhone; scoped Classic grid artwork
recovery verified, including Charizard and Lugia.

**Source:** `main` at `e92db19` plus the existing working-tree Browse repair and
this focused patch. Existing user changes are preserved. No commit or push.

## Failure evidence

The owner reported blank artwork in Browse → 30th Celebration Classic
Collection, including Charizard and Lugia. Live checks on 2026-10-28 reproduced
missing primary artwork: TCGdex returned HTTP 200 for `30th-c-001` and
`30th-c-029`, with `image: null`. Checked Scrydex secondary paths, including
`me55c-4/large` and `me55c-149/large`, returned HTTP 403. These are endpoint
checks from the development machine, not the phone's HTTP logs.

The existing signed per-card map can fill missing URLs, but its availability
depends on the downloaded catalog and its URLs can fail. The bundled registry
has no Classic card-image map. Classic is deliberately outside the guessed
Limitless expansion fallback. Clearing caches cannot supply a missing source.

## Repair

`CatalogCardArtworkSource` now accepts the exact provider-card and provider-set
identities. For Pokémon / `30th-c` only, it appends image candidates from the
existing reviewed TCGplayer product mapping. Existing provider URLs remain
first. A grid tries the 400-pixel image before the full image; detail reverses
that order. Unknown IDs, other sets, other games and missing identity do not
gain candidates. Repeated printed numbers never determine the product join.

Browse card tiles, global card-search rows and catalog card detail pass these
identities into the common source. No model/schema, provider identity, scanner
authority, finish, price, ownership or user-photo change is involved. The
existing loader performs fallback, coalescing, bounded decoding and disk
caching; its MIME/HTTP checks and eviction policy are unchanged. No collection
or cache reset is needed or performed.

All **60** reviewed URLs (400-pixel and full-size for all 30 cards) returned
HTTP 200 with image MIME types. Charizard and Lugia's full images were visually
checked for the 30th-anniversary artwork. Availability was checked at this date;
this is not a guarantee of future third-party availability or device access.

## Verification

Three focused source-candidate regressions cover missing/failed provider candidates, exact
Charizard/Lugia products, all 30 distinct identities, repeated printed numbers,
and rejection of wrong-game/wrong-set/unreviewed identities. Existing provider
ordering, signed-map enrichment, cache rejection/recovery/persistence and
hosted fallback tests are included in the optimized selection.

The ProfileLocal / ReleaseLocal (`-O`, whole-module) simulator selection passed
**12 tests**, zero failures/skips, with no finalized runtime warnings. It uses
the existing `DEBUG LOCAL_ONLY_SIGNING` test seams and `ENABLE_TESTABILITY=YES`.
The normal signed device build (no DEBUG fixtures) initially waited on Keychain
access. After the owner handled the protected prompt, it completed successfully
and was installed in place on iPhone 15 Pro Max / iOS 27.0.1. The source hashes
still match the tested patch. Executable/dSYM identities were recorded externally.

Normal launch and Device Hub observations confirmed rendered Classic grid
artwork for Charizard, Delcatty and neighboring cards. Filtering to Lugia showed
its correct 30th-anniversary image. Progress/finish rows remained present, and
the existing collection was retained. No uninstall, seeding, collection edit or
cache-clear operation was used. Keyboard capture and mirroring were released
after these observations. All-30-card phone rendering, global search and the
full-size detail route were not physically verified; their candidate construction
is covered by the scoped native and endpoint checks above.

Compared with the earlier Browse follow-up's file metadata, all **174** prior
Application Support paths remained (three additional paths). Of 647 prior cache
paths, 646 remained, with 18 new paths and one removed under normal cache use.
This checks path retention, not collection-content integrity; no collection
contents were exported.

Evidence is external on
T7 under `CodexBuild/TradingCardScanner-BrowseRepairEvidence/` and
`CodexBuild/TradingCardScanner-BrowseDeviceEvidence/`, including
`classic-artwork-tests.*`, `classic-artwork-build.*`, and
`classic-artwork/endpoint-checks.json`, source/binary hashes and install/launch
results. Downloaded artwork and device evidence
are not repository assets.

The [keyboard/snapshot repair](browse-performance-repair-2026-10-28.md#keyboard-and-snapshot-remediation--2026-10-28)
remains separate: its focus cleanup passed 15 native tests and is now included
in the installed binary. Its direct-on-phone snapshot comparison remains open;
this artwork verification does not close that gate.
