# Publish the Scanstash app pages on Bluehost

**Deferred by owner — 2026-10-14:** pause this walkthrough, hosting publication,
live verification and app/App Store Connect URL configuration until resumed.
Prepared files remain available; no publication or URL setup is marked complete.

**Status — 2026-10-14:** upload package prepared and browser-checked locally;
not published. The owner identified Bluehost as the host. The public page uses
custom static files (`styles.css` and `script.js`), without WordPress markers.
The live `/privacy` still covers only the website, and `/support` returns 404.

The [privacy policy](privacy-policy.md) and [support copy](support.md) are the
canonical drafts. The new privacy copy preserves website/waitlist disclosures
and adds the actual 1.0 app practices. Website forms still use
`hello@scan-stash.com`; app support uses the owner-confirmed `Info@scan-stash.com`.
The [publication checks](README.md) retain operator, mailbox, provider-retention
and rights confirmation. Preparing HTML does not close those checks.

## Files and preview

This session's package is `scanstash-bluehost-pages.zip`, generated under
`/private/tmp/LorcanaRollout-20261014/`, with a retained local copy in the repo's
ignored `artifacts/lorcana-rollout-20261014/` directory. It contains two logical pages in both
flat-file and directory-index layouts:

- `privacy.html` and `privacy/index.html`
- `support.html` and `support/index.html`

Use the privacy layout that matches the existing site. The support directory
can supply `/support` through ordinary directory-index serving, without changing
the homepage, styles, scripts or broad rewrite rules. On Apache it may redirect
to `/support/`; the app's configured URL can remain `/support`.
The flat copies also support an existing extensionless `.html` route.

The pages are self-contained and add no JavaScript, trackers, fonts or other
remote assets. Maintainer notes are excluded from the public HTML; review the
canonical copy and existing publication checks before uploading. Update the
effective date if actual publication occurs later than 2026-10-14.

## Bluehost walkthrough

1. Sign in to Bluehost yourself; sharing a password is unnecessary.
2. Open **Websites → Manage Site** beside `scan-stash.com`, then **Files & Access**.
3. Read **Document Root**, then open **Manage** in the File Manager card. Use that
   exact directory; an addon domain may have its own folder under `public_html`.
4. Find the existing privacy file. Download a backup to your computer before
   editing it. Keep its existing filename/path and replace its page content with
   the matching prepared privacy HTML. Do not replace the homepage or stylesheet.
5. Upload the support page using `support/index.html` in a `support` folder in
   that same document root. If the site's existing routing expects
   `support.html`, upload that copy too. Preserve any existing files; do not
   blindly extract the ZIP over a site directory.
6. Open `https://scan-stash.com/privacy` and `https://scan-stash.com/support`
   in a private browser window. Verify app privacy sections, contact links,
   readable mobile layout and working Privacy ↔ Support navigation. Check that
   the main website still works. A remaining 404 needs inspection of the site's
   existing route configuration; do not overwrite `.htaccess` wholesale.
7. Once the actual pages are verified, configure the submission build's
   `CARD_SCANNER_PRIVACY_URL` and `CARD_SCANNER_SUPPORT_URL` with those HTTPS
   URLs, test Settings → Privacy & Support, and enter them in App Store Connect.
   They remain empty until publication is verified.

These steps follow Bluehost's current
[File Manager instructions](https://www.bluehost.com/help/article/edit-website-files-via-the-file-manager)
and [addon-domain document-root guidance](https://www.bluehost.com/help/article/where-to-upload-files-for-an-addon-domain).
No login, website upload, email delivery test or App Store Connect change was
performed by this session.

## Local browser verification

Flow: Privacy page → Support navigation → support/contact content → Privacy.
Playwright was used because the Browser plugin/skill was not available.
Screenshots remain outside version control in the temporary artifact directory.

| Check | Result |
| --- | --- |
| Page titles and nonblank main content | PASS — Privacy Policy / Support — Scanstash |
| 390 × 844 mobile and 1280 × 900 desktop layouts | PASS — inspected captures, readable wrapping, no horizontal overflow |
| Framework error overlay | PASS — none; plain HTML/CSS |
| Console health after favicon correction | PASS — zero errors/warnings |
| Privacy ↔ Support navigation | PASS — directory routes resolve to the matching page |
| App contact and website contact links | PASS — correct `mailto:` targets; no messages sent |
| Public-copy hygiene | PASS — no repository status note, publication-draft label, or maintainer checklist text |
| Live deployment, mailbox delivery, actual Bluehost routing | NOT RUN — owner upload/access required |

The full source/artwork publication gate remains separate. Public TCGCSV JSON
access is documented; LorcanaJSON's community-code notice and code license do
not themselves prove a broad artwork sublicense for this app.
