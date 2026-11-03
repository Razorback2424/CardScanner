# TCGplayer detail link visual acceptance

Target: shared marketplace link on collection and catalog card details; also
present in Price Check, printing comparison, and saved unresolved scan details.
Routes: `OwnedPriceReview` (catalog and collection states).
Device: iPhone 17 Pro simulator, iOS 27.1. Fixture data only.

- [x] Native link visible on both rendered detail surfaces.
- [x] Search label reads **Search TCGplayer** when no exact product is known.
- [x] Product label reads **View on TCGplayer** in the rendered exact-product control.
- [x] Link text is readable; no clipping, overlap, or safe-area obstruction.
- [x] Large Dynamic Type wraps without truncation (accessibility3, 320-point control render).
- [x] Minimum 50-point target and meaningful VoiceOver label/hint verified in source; no physical VoiceOver session claimed.
- [x] Layout retains existing card, price, and ownership controls.
- [x] Final catalog/collection screenshots inspected after the last UI change.

Verified 2026-11-02. Final captures: external SSD
`CardScannerDetailLinksUI20261102/catalog-final/ui-latest.png` and
`CardScannerDetailLinksUI20261102/collection-final/ui-latest.png`.
Exact/search accessibility renders are retained as test attachments in
`CardScannerDetailLinksFinal20261102.xcresult` and were inspected through the
legacy object export. The first capture caught startup; the final 15-second
route captures reached the intended screens. No UI change was required.

URL behavior is checked by `TCGplayerLinkTests`; signed Jumbo/Eevee destinations
and stable identity are checked by `RetailVariantTests`. Search navigation does
not certify a matching product or price, and screenshots do not certify an
external purchase or physical-device behavior.
