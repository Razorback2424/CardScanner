# Privacy and support publication checks

**Status:** app copy reviewed against current source and Apple guidance on 2026-10-03; publication and owner/provider verification remain open.

The existing [privacy policy](privacy-policy.md) and [support page](support.md) are the canonical app-page drafts. The owner confirmed the public app name **Scanstash** and live contact **Info@scan-stash.com**. No website implementation was found in this iOS repository. The future website specification remains separate.

## Before publication and App Store submission

- Confirm the operator's public legal name and any contact details required in launch jurisdictions. Finalize the support email provider, its safeguards, and a routine retention period; replace the corresponding maintainer wording in the policy with the actual practice.
- Verify documented protections and request/log retention for TCGdex, Scryfall, Pokémon TCG API, TCGCSV, JustTCG, catalog/artwork hosting, and support email infrastructure. Apple's guideline 5.1.1(i) requires equal or greater protection by recipients. The policy's commitment is not evidence that provider diligence is complete. Change integrations or disclosure if evidence does not support the commitment.
- Verify live hosting logs, cookies, analytics, contact forms, and any waitlist. The drafts cover app behavior and voluntary email support; add the actual website practices before deploying them on a site with additional collection.
- Resolve public branding consistently with App Store metadata and the app. Current source/UI still uses CardScanner; this documentation change does not rename the executable or UI.
- Publish the completed pages at public HTTPS `/privacy` and `/support` routes without login. Remove maintainer status notes and convert repository-relative links to website routes. Verify both pages and the email link on mobile, including an actual mailbox delivery check.
- Set `CARD_SCANNER_PRIVACY_URL` and `CARD_SCANNER_SUPPORT_URL` in the submission configuration. They are currently empty; `CardScannerExternalLinks` requires exactly `/privacy` and `/support`. Verify Settings → Privacy & Support opens both live pages in the built release candidate.
- Enter the same privacy and support URLs in App Store Connect. Reconcile App Privacy answers and the privacy manifest with provider retention, the submitted build, and any website practices; local-only storage alone does not establish that all network data is uncollected.

## Apple requirements checked

[App Review Guidelines 5.1.1(i)–(ii)](https://developer.apple.com/app-store/review/guidelines/#privacy) require an accessible in-app and metadata policy covering collection/use, third parties, retention/deletion, and withdrawal of consent. The revised copy addresses local data, permissions, photos, provider requests and authentication, voluntary support, exports, and the actual partial deletion behavior.

[App Store Connect's Support URL requirements](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/) require a page with actual contact information for app issues, feedback, and enhancement requests. The revised support draft supplies the owner-confirmed email and practical help.

These source and documentation checks do not establish live-page availability, provider compliance, legal compliance in every launch jurisdiction, or App Review approval.
