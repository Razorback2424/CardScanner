# Scanstash Privacy Policy

Effective date: 2026-10-03

This policy describes Scanstash 1.0, the trading-card scanning and collection app referred to as CardScanner in its source code. For privacy questions or requests, email [Info@scan-stash.com](mailto:Info@scan-stash.com). See also [Scanstash Support](support.md).

**Repository publication status:** revised app-policy draft; not a live website. Complete the [publication checks](README.md) before using this policy for App Store submission. This status note is for maintainers and should not appear on the published page.

## Information stored on your devices

CardScanner stores your collection, card identity decisions, activity history, inventory events, price records, and app settings on your device. Value History, price observations, reference quotes, check days, and custom artwork are device-local in version 1.0.

Camera images are processed on your device for card recognition, centering checks, and listing-photo preparation. Scanstash does not upload camera frames or selected card photos to its catalog or pricing providers for recognition. You can select photos through Apple's photo picker for centering, custom artwork, or listing-photo preparation. Saving prepared listing photos to your photo library requires permission. Photos you save or share remain in the location or service you choose; recipients then handle them under their own policies. Preparing listing photos does not automatically publish an eBay listing.

You can withdraw camera and photo-library permissions in iOS Settings under the app's permissions. This disables the affected feature. You can stop choosing photos or sharing exports at any time.

## Collection storage and device protection

CardScanner 1.0 stores collection records, card identity decisions, activity history, inventory events, price records, Value History, price observations, reference quotes, check days, settings, and custom artwork on your device. iCloud collection sync is not available in this release.

To support scheduled price refresh after the device has been unlocked once, the small local storage manifest and opaque store-identity sidecar are available to the app while the device is locked after first unlock. The manifest can contain a local store identifier, attachment and migration state, an opaque account fingerprint, and restoration-checkpoint metadata. The sidecar contains an opaque store-file identity token. This metadata can reveal to CardScanner that a local collection exists and its prior storage state while the device is locked; it does not contain card records or images. Collection database files continue to use their existing iOS Data Protection behavior.

## Catalog and pricing requests

To identify cards and retrieve catalog, artwork, or pricing information, Scanstash sends card, set, printing, product, and search identifiers to the providers used by the feature, including TCGdex, Scryfall, Pokémon TCG API, TCGCSV, and optional JustTCG requests. Automatic price refresh can make requests for cards in your collection. Providers and their hosting infrastructure receive the network information needed to serve requests, such as your IP address, request time, and requested resource; their retention practices govern any server logs. These requests support catalog and pricing features and are not used by Scanstash for advertising or cross-app tracking.

A user-provided JustTCG key is stored in the device Keychain and sent to JustTCG to authenticate requests. It may associate requests with your JustTCG account. Remove the key using the pricing settings' key-removal control; do not rely on uninstalling the app to remove Keychain entries. You can limit background updates using iOS Background App Refresh settings. This does not disable requests made while using the app, including manual lookups and catalog downloads.

Our policy is to use providers that protect shared user data at least as well as this policy and Apple's App Review privacy requirements. We do not authorize providers to use shared data for advertising or cross-app tracking. Provider protections and retention must be verified before release; see the maintainer publication checks.

To keep Pokémon set definitions current, CardScanner may also retrieve a small
signed catalog-control file from `catalog.scan-stash.com`. It contains app-owned
set descriptors and release metadata, not collection records, camera frames,
account identifiers, or a user profile. Production rollout diagnostics are
local OS logging and performance measurements; CardScanner does not upload them
as an analytics feed.

CardScanner 1.0 has no advertising tracking or analytics SDK. The app does not sell personal information.

## Support information

If you email us, we receive your email address, message, and any attachments you choose to send. We use that information to respond to your request and investigate the issue. Email delivery and storage also involve the email service providers handling the conversation. Support is voluntary and does not require sending a collection export, API key, or photo. Ask us at [Info@scan-stash.com](mailto:Info@scan-stash.com) to access, correct, or delete support information you have supplied.

## Retention, deletion, and portability

On-device collection data remains until you delete it or remove the app's data. In Settings → Collection & Portfolio, Export CSV gives you a portable copy of collection records. CSV is not a full backup of custom artwork, settings, or all historical data.

Delete Collection removes card records and current ownership. Removal activity, inventory events, price records, and Value History remain on the device; this action does not erase all app data. To remove the app's local files, use iOS Delete App rather than Offload App. Remove your JustTCG key separately before deleting the app. Copies you saved to Files, Photos, another service, or a device backup must be deleted separately using that service's controls. Device backup and restoration are separate from the app's unavailable iCloud collection sync.

We cannot remotely read or erase your device-local collection. Contact us for help with local deletion or to request deletion of support correspondence. Provider request logs are managed by those providers; deleting your collection does not delete their records. Stop using network features to stop new requests, and contact the relevant provider about previously retained data.

Support information is used while handling your request. We will delete it on request unless retention is required by law or necessary to resolve an outstanding dispute; if an exception applies, we will explain it in our response. A fixed routine retention period and email-provider details must be finalized before publication, as recorded in the maintainer checks.

## Support

Email [Info@scan-stash.com](mailto:Info@scan-stash.com) for help with scanning, catalog, pricing, local storage, or privacy. See [Scanstash Support](support.md) for troubleshooting and what to include.

## Changes and contact

We may update this policy when the app's data practices change. The current policy will carry an updated effective date. Any future collection or use requiring permission will require that permission before it begins.
