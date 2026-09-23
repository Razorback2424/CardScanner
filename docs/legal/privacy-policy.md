# CardScanner Privacy Policy

Effective date: 2026-09-22

This policy describes the CardScanner 1.0 release. The published privacy URL configured for the App Store must point to the deployed version of this document.

## Information stored on your devices

CardScanner stores your collection, card identity decisions, activity history, inventory events, price records, and app settings on your device. Value History, price observations, reference quotes, check days, and custom artwork are device-local in version 1.0.

The camera is used to process card images for scanning and centering checks. Card images and camera frames are not collected by the developer as an analytics feed. The app must be used with the device permissions shown by iOS.

## Collection storage and device protection

CardScanner 1.0 stores collection records, card identity decisions, activity history, inventory events, price records, Value History, price observations, reference quotes, check days, settings, and custom artwork on your device. iCloud collection sync is not available in this release.

To support scheduled price refresh after the device has been unlocked once, the small local storage manifest and opaque store-identity sidecar are available to the app while the device is locked after first unlock. The manifest can contain a local store identifier, attachment and migration state, an opaque account fingerprint, and restoration-checkpoint metadata. The sidecar contains an opaque store-file identity token. This metadata can reveal to CardScanner that a local collection exists and its prior storage state while the device is locked; it does not contain card records or images. Collection database files continue to use their existing iOS Data Protection behavior.

## Catalog and pricing requests

To identify cards and retrieve catalog or pricing information, CardScanner may send card, set, printing, and search identifiers to the providers used by the app, including TCGdex, Scryfall, Pokémon TCG API, and optional JustTCG requests. A user-provided JustTCG key is stored in the device Keychain. These requests are network transfers for the requested feature; they are not advertising or cross-app tracking.

To keep Pokémon set definitions current, CardScanner may also retrieve a small
signed catalog-control file from `catalog.scan-stash.com`. It contains app-owned
set descriptors and release metadata, not collection records, camera frames,
account identifiers, or a user profile. Production rollout diagnostics are
local OS logging and performance measurements; CardScanner does not upload them
as an analytics feed.

CardScanner 1.0 has no advertising tracking or analytics SDK. The app does not sell personal information.

## Retention, deletion, and portability

Collection data remains until you delete it or remove the app's data. CSV export is available from Collection & Portfolio settings so you can keep a copy you own. Deleting the collection is an in-app destructive action and does not claim to remove data held by an external catalog or pricing provider.

## Support

CSV export is available in Collection & Portfolio settings so you can keep a portable copy of your collection. Contact Support using the published support page for help with scanning, catalog, pricing, or local storage issues.

## Changes and contact

We may update this policy when the app's data practices change. The deployed privacy page supplies the current contact channel and effective date.
