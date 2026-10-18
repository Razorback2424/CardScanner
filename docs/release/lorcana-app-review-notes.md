# Lorcana review path without physical cards

**Prepared — 2026-10-14:** review notes for the intended free, on-device 1.0
candidate. Adapt the build identity to the actual submission. This is prepared
reviewer guidance, not evidence of App Store submission or approval.

## Suggested reviewer notes

No account, purchase or provider API key is required for the Lorcana Browse and
ordinary pricing workflow. A network connection is needed for fresh prices and
remote card artwork. Some in-app text uses the name CardScanner.

1. Open **Collection → Browse → Disney Lorcana**.
2. Open **The First Chapter** and select **Ariel — On Human Legs**, collector
   number **1/204**, or search for that name within Lorcana.
3. Open Details to inspect the exact printing and its Normal/Foil reference
   pricing. Prices can change; unavailable provider data is shown explicitly.
4. Use **Add**, choose **Normal** or **Foil**, then return to Collection to
   inspect the saved quantity and printing. The existing refresh and undo
   controls apply. This path requires no physical card or camera permission.
5. An unreviewed printing may appear in Browse with Add disabled and pricing
   unavailable. This is the supported-scope boundary, rather than a provider
   sign-in requirement.

Current ordinary Lorcana coverage is 1,616 reviewed English printings from the
first eight expansions, with 3,232 Normal/Cold Foil mappings. Premium, promo,
Quest, later-set and ambiguous records are not included in that pricing scope.
This app does not infer foil optically; users explicitly choose the finish.

Collection data stays on-device in 1.0. iCloud collection sync is unavailable.
CSV export is available; it is not a complete backup of artwork/settings/history.
Prices are market references and are not guaranteed transaction values or grades.

## Submission handoff

Use the [production checkpoint](lorcana-production-acceptance.md) for current
verification and remaining release limits. Confirm the actual submitted build's
privacy/support links and App Privacy answers after the
[Bluehost publication steps](../legal/bluehost-publication.md). The source/rights
gate, distribution signing and physical-camera acceptance remain separate;
these notes do not close them.

No App Store Connect metadata was changed and no reviewer message was sent.
