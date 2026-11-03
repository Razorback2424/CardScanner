# Eevee Cosmos, Charizard Jumbo, and marketplace links

**Status: implemented locally; unsigned and unpublished.** 2026-11-02,
checkout `9413e906cab65c1d8c61882d8eb6f137bf44617e` with pre-existing local work
preserved. The owner explicitly authorized introducing Jumbo, fixing Eevee,
minimal signed variant/product support, and links on every card detail screen.
That authorization supersedes the earlier catalog-only implementation hold for
these repairs. It does not authorize a commit, push, or publication.
The [subsequent batch review](pokemon-jumbo-products-2026-11-02/README.md)
expands the initial Jumbo repair to 19 reviewed objects, verifies Eevee's exact
Cosmos product, and records the full 75-set live publisher validation.

## Reviewed physical memberships

| Identity | Change | Independent evidence | Price binding |
| --- | --- | --- | --- |
| Eevee `30th-116`, 116/128 | Add Cosmos alongside ordinary Holo | [Iconic's own Cosmos single](https://iconic-tcg.com/products/eevee-cosmos-116-128-30th-celebration), [Cards Center's own Cosmos Holo single](https://cards-center.eu/products/30c-116-128-eevee-cosmos-holo), [TCGplayer's primary metadata](https://mp-search-api.tcgplayer.com/v1/product/717879/details) | Exact Cosmos product 717879, independently distinguished from Holo 714357. |
| Charizard ex `svp-196` | Add a separate **Jumbo** variant; treatment remains matching metadata | [TCGdex's size-specific record](https://api.tcgdex.net/v2/en/cards/svp-196), [TCGplayer Jumbo 196](https://www.tcgplayer.com/product/641615/pokemon-jumbo-cards-charizard-ex-196?page=1) | Exact TCGplayer product 641615, separately from standard-size 641610. |

Eevee's retailer listings explicitly distinguish the number and Cosmos treatment.
Iconic's product page was readable; Cards Center's indexed product description
was readable but direct opening returned a cache miss. These are independent
retailer inventory records, rather than duplicate price-feed aggregators.
No displayed market amounts from these pages were installed as catalog prices.
The previous [investigation](pokemon-retail-variants-2026-11-02.md) retains the
earlier failed lookups and bounded 394-record census as historical evidence.

## Signed delivery and consumption

The optional `additionalVariants` array is carried by human inputs and signed
set descriptors. Entries retain the exact provider card ID/name, supported
variant ID, provider treatment, optional exact product, and evidence URLs from
at least two distinct HTTPS hosts. Host validation does not independently
certify source authority; that remains the manual review represented above.
Only `jumbo` and Holo `cosmos` are enabled in this initial contract.

The publisher preserves supplements when omitted from a later input and accepts
an explicit empty array for withdrawal. It checks card identity/name, and a
Jumbo must have one matching English oversized provider record. Candidate
validation checks the reviewed card against the snapshot. These fields stay out
of the automatic publication allow-list and classify as protected authority.
The signing envelope, pinned keys, and signature checks are unchanged.
Older clients ignore the additive field and retain their existing behavior;
an updated app is required to expose these variants.

The catalog adapter reapplies current signed supplements after live, memory,
disk, and fallback resolution. Provider JSON cannot authorize them. Browse
projects Eevee's extra Grand Master slot at read time, leaving raw provider
snapshots/fingerprints intact so withdrawal does not strand a persisted slot.
Jumbo remains collectible but is excluded from standard-size Master/Grand
Master requirements. Activation invalidates affected resolved caches even when
the raw provider fingerprint is unchanged. Collection pricing and the Pokémon
price adapter also receive the active registry.

Jumbo uses stable ID `jumbo` and label **Jumbo**, with separate holding/price
keys. Exact quote lookup rejects foreign, conflicting, ambiguous, or shared
standard-size product evidence. It does not use a standard-size flat quote.
Eevee Cosmos now has signed product binding 717879. It does not borrow Holo
prices; an embedded Cosmos quote must match its own product evidence.

The PAF 054 face of the two-image Jumbo still needs a separately scoped
cross-printing alias; it is not globally redirected to SVP 196. The follow-up
corroborates 18 more Jumbo identities; numberless Terapagos & Friends remains
held because its provider number 500 is not printed on the physical object.

## Marketplace links

Collection, catalog (including loading/failure), Price Check, scan review,
movement details, saved unresolved scan, and printing-comparison detail screens expose a TCGplayer link. Known
products use **View on TCGplayer**; otherwise **Search TCGplayer** carries card,
set, number, and available variant/run text. Search URLs never become pricing
or stored product evidence. Existing exact-only URL APIs retain their contract.
Jumbo links use its exact size-scoped binding; an unselected standard/Jumbo
printing uses search rather than choosing a product.

The five supported game slugs were verified against TCGplayer's public
[product-line directory](https://mp-search-api.tcgplayer.com/v1/search/productLines):
`pokemon`, `magic`, `yugioh`, `lorcana-tcg`, `one-piece-card-game`.

HIG gate: **PASS** for the proposed shared link control. Platform patterns use
native SwiftUI Link; clear exact/search labels avoid an unsupported exact-match
claim; semantic headline text wraps with Dynamic Type; a minimum 50-point target,
VoiceOver label and browser hint provide accessibility; one tap adds no prompt;
no top-level navigation, purchase transaction, or permission flow is introduced.
Rendered checks are recorded separately in the task's visual checklist.

## Verification and limits

- Shared catalog suite: 86 cases, zero failures, one opt-in live CDN check
  skipped (85 passed). Includes a test-key signed round trip, protected change
  classification, metadata preservation, explicit withdrawal, provider mismatch,
  and rejection of two URLs on the same host.
- Final backend iOS milestone: 50/50 passed, including six retail integration
  cases, 40 resolver cases and four adjacent price-boundary regressions.
- Native publisher accepted an isolated recorded cohort of 158 30th + 226 SVP
  cards, with both supplements retained in its unsigned payload. Artwork omitted
  by the price-free census is not fresh live-provider fingerprint evidence.
- A CLI attempt to compare an unsigned fixture baseline was correctly rejected
  because active releases require an environment and signed envelope. The
  test-key signed authority comparison above passes; no verification was weakened.
- Final link milestone: 26/26 iOS cases passed (18 URL/link cases, six retail
  integration cases, two native rendering cases). Actual xcresult metrics
  confirm 26 executed, zero failures, zero skipped.
- Inspected final catalog and collection screenshots from `OwnedPriceReview`
  (`native-newer-catalog` and `price-chart-collection`) on iPhone 17 Pro.
  Both show the search link, price content and existing ownership controls.
  The initial four-second catalog capture showed startup; the final
  deterministic capture used 15 seconds and reached the intended screen.
- Inspected both exact/search controls at accessibility3, rendered at 320-point
  width. Both labels wrap legibly without clipping. `ImageRenderer` + OCR tests
  passed and retained image attachments. The modern xcresult attachment export
  failed on a Library/Caches write; the legacy object reader/export succeeded.

Screenshots and result bundles remain external generated artifacts under
`/Volumes/T7/CodexBuilds/`; no screenshot or raw log is added to the repository.
The [visual checklist](../../references/tcgplayer_link_success_checklist.md)
records the inspected scope. Other detail entry points are covered by source
integration and shared-control tests, not a claim of exhaustive screenshot QA.

Build/test products live on the external T7 SSD. No signing secret was accessed;
test signatures use ephemeral test keys. No full live 75-set production rebuild,
production signature/publication, physical-camera scan, or live paid-price
acceptance is claimed. The normal protected publisher workflow must build and
review the final production candidate before signing/publication.
