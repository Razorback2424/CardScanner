# Stage 2: immutable market price builds on R2 staging

Implements the v2 publication contract in PR #65. Source: the same validated
Firebase artifact mirrored by PR #69. The app and production Firebase hosting
are unchanged. The staging hostname additionally exposes:

- market-prices/v2/latest.json: schemaVersion 2, sourceBuild, build, files.
- market-prices/v2/builds/<build>/<path>: exact captured v1 feed bytes,
  index.json, last-updated.txt, and scopes/{one-piece,yugioh}.json.
- build is SHA-256 of the canonical pointer document without the build field
  (sorted JSON keys, compact separators, UTF-8, final newline). Each files
  entry binds a relative path, SHA-256 and byteCount. A corrected same-day
  capture gets a distinct identity. No data is deleted.

The R2 job verifies actual priced-product/finish coverage for all four mirrored
categories against the same v1 capture using catalog_parity.py. It stages
immutable objects, verifies public bytes and headers even for unchanged
objects, then confirms the artifact is still current on Firebase and checks
the existing R2 pointer before activating v2. The workflow is serialized.
Only then does it update R2's existing v1 paths, with the v1 marker last.
A failed v1 publish leaves a complete v2 build available; rerunning the
same still-current artifact repairs it, including skipped mutable price
objects whose metadata matched but whose public readback did not. Immutable
objects are never repaired by overwriting different bytes; failed integrity
checks stop publication. Pointer preflight and post-write readback use
distinct cache-busting URLs. An explicitly authorized empty catalog price
scope may omit that game's feed groups; unexpected missing or extra scope
groups stop publication. Superseded artifacts are rejected.

This PR does not enable app-side v2 consumption or change production DNS.
Before enabling production v2 clients, implement and test v2 client support,
Firebase rollback parity including retention of referenced builds across
Firebase deployments, and the Cloudflare cache rules/purges. The current
Firebase-first mirror remains an initial staging mechanism, not the final
R2-first publisher. The one-week dual-host parity gate and rollback rehearsal
remain mandatory. Historical R2 builds are retained; no lifecycle deletion
policy is introduced here.
