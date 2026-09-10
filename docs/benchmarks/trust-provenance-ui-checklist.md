Target screen:
- Route name: `TrustCardDetail` / `TrustScanReceipt`
- Expected device: iPhone 17 Pro simulator (`PA Quality iPhone 17 Pro`)

Visual checklist (must verify against `./artifacts/ui-latest.png`):
1. [x] Card detail states finish and provenance together.
2. [x] `catalogSilent` says “Finish not published” and is visibly uncertain.
3. [x] `finishLock` states “Reverse · Finish Lock” in detail and “Reverse Holo · Finish Lock” in the receipt.
4. [x] `userConfirmed` states “Holo · You confirmed” in detail and “Holofoil · You confirmed” in the receipt.
5. [x] A routine `uniqueInCatalog` receipt remains visually quiet.
6. [x] No clipped text, overlaps, or unsafe-area occlusion.

Behavior checklist:
1. [x] Debug route and state are deterministic from launch arguments.
2. [x] Receipt provenance has an accessibility label (`Variant provenance: Finish not published` observed in the runtime snapshot).
