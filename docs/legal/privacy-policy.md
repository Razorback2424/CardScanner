# CardScanner Privacy Policy

Effective date: 2026-09-18

This policy describes the CardScanner 1.0 release. The published privacy URL configured for the App Store must point to the deployed version of this document.

## Information stored on your devices

CardScanner stores your collection, card identity decisions, activity history, inventory events, price records, and app settings on your device. Value History, price observations, reference quotes, check days, and custom artwork are device-local in version 1.0.

The camera is used to process card images for scanning and centering checks. Card images and camera frames are not collected by the developer as an analytics feed. The app must be used with the device permissions shown by iOS.

## iCloud synchronization

When you attach a collection to iCloud, CardScanner synchronizes the structured collection records to your private CloudKit database: collected cards, price records, product identities, collection activity, and inventory events. CardScanner does not use a separate CardScanner account. Account changes are handled by the system iCloud account and the app's collection-identity safeguards.

Custom artwork and Value History are not currently synced with iCloud.

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

## iCloud controls and support

You can manage iCloud availability and the signed-in system account in iOS Settings. If CardScanner detects a different existing collection, it will pause rather than merge or overwrite collections. Contact Support using the published support page for help with a storage or sync conflict.

## Changes and contact

We may update this policy when the app's data practices change. The deployed privacy page supplies the current contact channel and effective date.
