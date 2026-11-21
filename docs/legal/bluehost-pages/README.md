# Scanstash public launch pages (Bluehost upload files)

Prepared November 20, 2026. **These are repository copies, NOT a live website deployment.** Bluehost still hosts the live site independently of this repository.

| Host file | Purpose |
| --- | --- |
| `privacy.html` | Replace the existing website privacy page linked by the site's footer. Covers both website and iOS app. |
| `support.html` | Optional flat-file support route; deploy this alongside the directory page. |
| `privacy/index.html` | Extensionless `/privacy` route expected by the app. |
| `support/index.html` | Extensionless `/support` route expected by the app. |

Upload only these four files in Bluehost's actual `scan-stash.com` document root, preserving their relative paths. Back up the existing `privacy.html` first. Do **not** overwrite `index.html`, `styles.css`, `script.js`, or `.htaccess` and do not extract over the entire site indiscriminately. The pages are self-contained and do not add scripts or trackers.

After upload, confirm in a private window that `https://scan-stash.com/privacy`, `https://scan-stash.com/support`, and `https://scan-stash.com/privacy.html` all contain the new app privacy/support text; check both navigation directions, a narrow/mobile viewport, and the `mailto:Info@scan-stash.com` link. The same pages should be reachable without authentication.

**Legal/operational review remains required:** confirm website forms and analytics against reality, operator identity and privacy contact, email/provider retention, and any provider-data-protection claims before treating these pages as final. The text avoids internal draft notes and does not promise an unverified fixed support-email retention term. Check all wording for actual behavior before publication.

Only **after** both canonical routes are publicly live and verified, set `CARD_SCANNER_PRIVACY_URL = https:/$()/scan-stash.com/privacy` and `CARD_SCANNER_SUPPORT_URL = https:/$()/scan-stash.com/support` in `Config/PokemonCatalogProduction.xcconfig`, build/test Settings → Privacy & Support, and enter the same URLs in App Store Connect. These settings remain blank in this PR intentionally.

This does not change the website homepage or remove its existing waitlist form. See [the full publishing walkthrough](../bluehost-publication.md) and [legal checklist](../README.md).

## Content review — November 20, 2026

Reviewed the public draft against the source-controlled app privacy/support wording, the current website's waitlist/contact/terms/privacy pages, FormSubmit's published 30-day archive policy, and Apple's App Review Guidelines 5.1.1. Adjustments in this review:

- Clarified that FormSubmit's 30-day archive does **not** automatically delete email copies; distinguished website mail from optional app-support mail.
- Explained waitlist removal, message deletion and support-email handling without inventing a fixed mailbox deletion period.
- Clarified that catalog and pricing lookups share request identifiers/network metadata, not collection CSV or camera frames.
- Removed obsolete Lorcana availability language and corrected the public app branding.

**Remaining factual/compliance checks before submission:** confirm Bluehost logs and analytics/cookies, the actual email mailbox retention/deletion practices, current provider agreements and third-party protections for Apple's 5.1.1(i), and the legal operator/contact requirements for target countries. The site must actually follow its published retention and deletion commitments. This is an editorial and source-consistency review, not a legal opinion or evidence of third-party compliance.

**Version caveat:** the HTML date is November 20, 2026; update to the real publication date if these pages go live later. Reconcile copy if the app's commercial pricing architecture changes before submission.
