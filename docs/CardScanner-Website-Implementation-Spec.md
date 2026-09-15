# CardScanner Website — Executable Build Specification

**Status:** current future-website specification — reconciled 2026-09-14. The
canonical public routes are `/`, `/privacy`, `/terms`, and `/support`; no
website source or deployment is present in this iOS repository.

## 1. Objective

Build a polished, production-ready public website for CardScanner.

The immediate business objective is to establish CardScanner as a credible, legitimate early-stage startup with:

- a fully functioning company website
- a clear description of the product
- authentic evidence that the product exists
- professional company-domain email
- working contact and waitlist mechanisms
- Privacy and Terms pages
- consistent product/company positioning suitable for an AWS Activate Founders application

The website must also be good enough to serve as the foundation of the eventual public CardScanner product website.

This is not a temporary AWS landing page and must not look like one.

Do not expand the scope into a full SaaS marketing website.

---

# 2. Non-negotiable product positioning

CardScanner is a trading-card scanning, collection-management, and value-tracking application.

The website must communicate three things within the first screen:

1. Scan trading cards.
2. Maintain an accurate collection of the cards actually owned.
3. Understand the collection and its value.

The principal product thesis is:

> A digital collection should accurately represent the physical collection you actually own.

Supporting product qualities:

- fast, accurate identification
- accurate printing/variant selection
- physical collection organization
- transparent pricing information
- portable collection data
- authentic product rather than conceptual mockups

Do not reposition CardScanner primarily as:

- an investment app
- a price tracker
- a marketplace
- a card-grading app
- an AI product
- a Pokémon-only product
- an inventory system for professional dealers

It is first and foremost a collector-focused scanning and collection-management application.

---

# 3. Scope

Build exactly four public routes:

```text
/
├── Home
├── /privacy
├── /terms
└── /support
```

Also implement:

```text
/404 behavior
/robots.txt
/sitemap.xml
favicon
Open Graph metadata/image
```

Do not add additional public routes without explicit approval.

Specifically do not build:

- Blog
- Documentation
- Pricing
- User accounts
- Login
- Interactive app demo
- Investor page
- Press page
- Careers
- CMS
- Testimonials
- Reviews
- Customer logos
- Large FAQ
- SEO landing pages
- Marketplace
- App download page
- Dashboard
- Authentication
- Payment system

---

# 4. Technical implementation

Use:

- Next.js
- TypeScript
- Tailwind CSS
- Vercel deployment
- Git-based source control

Use the current stable production release of the framework rather than pinning the implementation to a version specified in this document.

Prefer static rendering wherever possible.

JavaScript should be used only where it adds clear value.

The site should not depend on a custom persistent application backend.

The waitlist may use either:

1. a lightweight serverless endpoint integrated into the Next.js application, or
2. a reputable managed form/email-list service

Choose whichever solution requires the least ongoing infrastructure while satisfying all requirements in this specification.

The rest of the site must operate without a backend.

---

# 5. Global design direction

## Overall aesthetic

The site should feel:

- premium
- calm
- precise
- restrained
- Apple-native
- product-led
- contemporary
- trustworthy

The target visual territory is closer to:

- Apple
- Linear
- Arc

and explicitly not:

- generic SaaS template
- Webflow startup template
- neon AI startup
- crypto site
- gradient-heavy landing page
- card-game fan site
- hobby-store ecommerce site

CardScanner should look like professionally designed consumer software.

---

# 6. Visual system

## Background

Primary background:

- near-white or white
- neutral rather than tinted
- no full-page gradient

Dark sections may be used sparingly where they improve presentation of actual app screenshots.

Do not alternate random section colors.

---

## Typography

Use a high-quality system-first sans-serif stack.

Preferred:

```css
font-family:
  -apple-system,
  BlinkMacSystemFont,
  "SF Pro Display",
  "SF Pro Text",
  "Helvetica Neue",
  Arial,
  sans-serif;
```

Do not load an imitation Apple font.

Typography should rely primarily on:

- scale
- weight
- spacing
- hierarchy

rather than decorative treatment.

Hero typography should be large but not oversized merely for visual drama.

Avoid:

- gradient text
- outlined text
- all-caps marketing headlines
- excessive letter spacing

The small CARD SCANNER brand eyebrow in the hero may use uppercase.

---

# 7. Layout system

Use a centered page container.

Maximum primary content width:

```text
1200–1280px
```

Text-heavy sections should use substantially narrower readable widths.

Recommended body-copy maximum:

```text
680–760px
```

Desktop horizontal page padding:

```text
32–48px
```

Tablet:

```text
24–32px
```

Mobile:

```text
20–24px
```

Major section vertical spacing on desktop:

```text
120–160px
```

Mobile:

```text
72–96px
```

Whitespace is a major part of the visual design.

Do not solve empty space by adding unnecessary components.

---

# 8. Header

Create a minimal sticky or semi-sticky navigation header.

Desktop contents:

```text
CardScanner logo/wordmark

How it works
Why CardScanner
Collections
About

[ Join the waitlist ]
```

Behavior:

- Logo returns to `/`.
- Homepage navigation items scroll to their corresponding sections.
- On Privacy, Terms, and Support pages, homepage-section links navigate to `/#section-id`.
- CTA scrolls to the final waitlist section on the homepage.
- Header becomes subtly more opaque or gains a very light border/backdrop treatment after scrolling.
- Do not use a large shadow.

Mobile:

- Logo/wordmark
- one compact menu control
- accessible expandable navigation

Do not attempt to fit the full desktop navigation across a narrow mobile screen.

---

# 9. Brand treatment

Until a final custom logo exists, use a professionally styled text wordmark:

```text
CardScanner
```

Do not invent a complex logo.

Do not create:

- playing-card clip art
- scanner-corner iconography
- Pokémon-inspired graphics
- generic sparkle AI marks

A simple temporary geometric mark is permissible only if it is exceptionally restrained and visually useful.

Text-only branding is preferred over mediocre invented branding.

---

# 10. Homepage structure

The homepage must contain exactly these eight content sections, in this order:

1. Hero
2. Product visual
3. Scan / Organize / Understand
4. Built differently
5. How it works
6. Supported collections
7. About
8. Final waitlist CTA

The global header and footer are not counted as homepage sections.

---

# 11. Section 1 — Hero

Anchor:

```text
#top
```

## Desktop layout

Use a two-column composition.

Left:

- brand eyebrow
- headline
- supporting copy
- primary CTA
- secondary CTA

Right:

- primary real CardScanner application screenshot composition

The image should occupy significant visual area.

Do not create a hero consisting mostly of text with a small phone floating in empty space.

---

## Exact hero copy

Eyebrow:

```text
CARD SCANNER
```

Headline:

```text
Your collection.
Accurately cataloged.
```

Body:

```text
Scan trading cards, organize what you own, and understand what your collection is worth.
```

Supporting line:

```text
Built for collectors who want their digital collection to accurately reflect the cards they actually own.
```

Primary CTA:

```text
Join the waitlist
```

Secondary CTA:

```text
See how it works
```

Primary CTA behavior:

Scroll to:

```text
#waitlist
```

Secondary CTA behavior:

Scroll to:

```text
#how-it-works
```

Do not add:

- “Coming Soon!!!”
- fake launch date
- fake user count
- fake App Store badge
- fake reviews
- fake ratings
- “Powered by AI”
- “Revolutionizing collectibles”
- similar startup filler

---

# 12. Hero product visual

The hero must use actual CardScanner UI.

Do not invent UI screens.

Required composition:

### Primary device

One large iPhone presentation showing the strongest available CardScanner scanner experience.

Preferred screen:

```text
live scanner / successful card identification state
```

### Secondary device 1

Collection screen.

### Secondary device 2

Card detail or pricing/value screen.

The primary phone should visually dominate.

Secondary phones/screens may sit partially behind or beside it.

They should not compete equally for attention.

---

# 13. Screenshot requirements

Use screenshots from the actual application.

Before placing screenshots:

- crop cleanly
- remove simulator chrome unless intentionally useful
- ensure status bars are internally consistent
- ensure no debug information appears
- ensure no personal information appears
- ensure no broken or temporary UI appears
- use internally consistent example cards/collection data
- ensure displayed values are believable
- ensure screenshots represent functionality that actually exists

Do not Photoshop product functionality that does not exist.

Phone frames may be generated around authentic screenshots.

The website may adjust:

- perspective
- shadow
- scale
- crop

It may not alter the functional contents of the app screens in a misleading way.

---

# 14. Mobile hero

On mobile:

1. eyebrow
2. headline
3. body
4. supporting line
5. primary CTA
6. secondary CTA
7. product visual

Do not place text and phone mockup side-by-side.

The hero must fit naturally without requiring horizontal scrolling.

The product visual may extend close to the viewport edges but must not be clipped incorrectly.

---

# 15. Section 2 — Product visual

This section expands on the hero visual without becoming a full feature gallery.

Use one strong product composition.

Headline:

```text
Built around the collection you actually own.
```

Body:

```text
CardScanner connects identification, collection management, and pricing in one place—so adding a card is the beginning of keeping an accurate collection, not the end of a scan.
```

Use a large screenshot or device composition.

Preferred visual:

```text
Collection screen or collection-detail workflow
```

A subtle label may identify authentic UI:

```text
Actual CardScanner interface
```

Do not label screenshots “concept” unless they actually are conceptual.

No invented feature callouts.

---

# 16. Section 3 — Scan / Organize / Understand

Anchor:

```text
#capabilities
```

Section eyebrow:

```text
THE ESSENTIALS
```

Headline:

```text
From card to collection.
```

Supporting copy:

```text
CardScanner is designed around the full job of maintaining a collection—not simply recognizing a card.
```

Create exactly three capability items.

They may appear as columns on desktop and stacked items on mobile.

Do not create oversized floating SaaS cards unless necessary.

## Capability 1

Title:

```text
Scan
```

Copy:

```text
Quickly identify cards and add the correct printing to your collection.
```

## Capability 2

Title:

```text
Organize
```

Copy:

```text
Keep an accurate inventory of the cards you own and where they're stored.
```

## Capability 3

Title:

```text
Understand
```

Copy:

```text
Track pricing, collection value, and the information behind each card.
```

Visuals should be restrained.

If icons are used:

- use simple line icons
- one per capability
- consistent visual weight

Do not use emoji.

---

# 17. Section 4 — Built differently

Anchor:

```text
#why-cardscanner
```

Eyebrow:

```text
BUILT DIFFERENTLY
```

Headline:

```text
Accuracy should continue after the scan.
```

Primary copy:

```text
CardScanner is being built around a simple idea: a digital collection should accurately represent the physical collection you actually own.
```

Supporting copy:

```text
That means caring not only about identifying a card, but about the exact printing, the information attached to it, where it belongs in your collection, and whether you can take your collection data with you.
```

Show exactly four principles.

### Principle 1

```text
Fast, accurate identification
```

Supporting line:

```text
Identify cards quickly without treating a plausible match as good enough.
```

### Principle 2

```text
Physical collection organization
```

Supporting line:

```text
Keep the digital collection connected to how your cards are actually organized.
```

### Principle 3

```text
Transparent pricing information
```

Supporting line:

```text
Understand the pricing information behind the value you see.
```

### Principle 4

```text
Your collection stays portable
```

Supporting line:

```text
Import and export collection data without locking the collection inside CardScanner.
```

Do not make comparative claims such as:

- “most accurate scanner”
- “best scanner”
- “industry-leading”
- “more accurate than Collectr”
- “#1”

unless separately substantiated and explicitly approved.

---

# 18. Section 5 — How it works

Anchor:

```text
#how-it-works
```

Eyebrow:

```text
HOW IT WORKS
```

Headline:

```text
Three steps from card to collection.
```

Create exactly three steps.

## Step 1

Number:

```text
01
```

Title:

```text
Scan a card
```

Copy:

```text
Point the camera at a card and let CardScanner identify what you're holding.
```

## Step 2

Number:

```text
02
```

Title:

```text
Confirm the printing
```

Copy:

```text
Review the identified card and make sure the exact printing matches the physical card in front of you.
```

## Step 3

Number:

```text
03
```

Title:

```text
Add it to your collection
```

Copy:

```text
Save the card with the collection information you need to keep your inventory accurate over time.
```

Use real UI imagery if appropriate.

Do not create illustrations showing functionality that is not implemented.

---

# 19. Section 6 — Supported collections

Anchor:

```text
#collections
```

Eyebrow:

```text
SUPPORTED COLLECTIONS
```

Headline:

```text
Built for trading card collectors.
```

Body:

```text
CardScanner is being built to support multiple trading card games while keeping the scanning and collection experience consistent.
```

Current items:

```text
Pokémon
Magic: The Gathering
More games planned
```

Treat “More games planned” visually differently from currently supported games.

Do not imply unimplemented games are already supported.

Do not use copyrighted game artwork or logos unless their use has separately been approved.

Text names are sufficient.

---

# 20. Section 7 — About

Anchor:

```text
#about
```

Eyebrow:

```text
ABOUT
```

Headline:

```text
A better way to maintain a collection.
```

Copy:

```text
CardScanner is an early-stage trading-card collection app being built to make scanning, organizing, and maintaining an accurate collection simpler and more trustworthy. The goal is straightforward: help collectors spend less time fighting their collection software and more time enjoying the collection itself.
```

Do not fabricate:

- founding story
- team size
- headquarters
- funding
- user metrics
- launch numbers
- partnerships

---

# 21. Section 8 — Final waitlist CTA

Anchor:

```text
#waitlist
```

This should be visually strong but restrained.

Headline:

```text
Be there when CardScanner launches.
```

Body:

```text
Join the waitlist for launch updates and early access information.
```

Form:

```text
[ Email address                         ]
[ Join the waitlist ]
```

Optional small reassurance text:

```text
Product updates only. Unsubscribe anytime.
```

No fake scarcity.

Do not write:

- “Only 100 spots”
- “Reserve your place before they're gone”
- fake countdown
- fake signup count

---

# 22. Waitlist behavior

The form must actually work.

Required behavior:

1. Validate email syntax client-side.
2. Validate again server-side or through the managed form provider.
3. Reject blank submissions.
4. Prevent obvious duplicate accidental submissions.
5. Provide clear loading state.
6. Provide clear success state.
7. Provide clear failure state.
8. Preserve accessibility during all states.

Success copy:

```text
You're on the list.
We'll let you know when there's something worth sharing.
```

Failure copy:

```text
Something went wrong. Please try again or email us directly.
```

Do not silently fail.

Do not accept an email and then discard it.

The destination/source of truth for submitted addresses must be documented in the repository README.

---

# 23. Footer

Use the same footer across every route.

Contents:

```text
CardScanner

© 2026 CardScanner. All rights reserved.

Privacy
Terms
Support
```

Also include:

```text
hello@[final-domain]
```

once the final domain exists.

Do not display placeholder email addresses in production.

---

# 24. Privacy page

Route:

```text
/privacy
```

The Privacy page must be a real completed page, not lorem ipsum or a copied generic template.

Visual layout:

- same header
- simple centered legal-content column
- page title
- effective date
- readable section headings
- same footer

Maximum readable width:

```text
720–800px
```

The final policy must accurately describe the actual website and application behavior.

At minimum, review whether disclosure is needed for:

- waitlist email collection
- contact submissions
- analytics
- cookies
- camera access
- card images
- collection data
- pricing/data providers
- data exports
- third-party infrastructure
- data retention
- deletion/contact requests

Do not have the coding model invent factual privacy practices.

If final legal copy has not been approved, treat Privacy copy as a deployment blocker rather than fabricating practices.

---

# 25. Terms page

Route:

```text
/terms
```

Use the same legal-page layout as Privacy.

The final Terms should correspond to the actual pre-launch website and CardScanner's current status.

Potential subjects include:

- website use
- pre-launch status
- informational pricing
- intellectual property
- prohibited use
- third-party data
- disclaimers
- limitation of liability
- changes to terms
- contact information

Do not have the coding model fabricate company entities, addresses, jurisdictions, or legal facts.

Missing approved Terms text is a production-deployment blocker.

---

# 26. Support page

Route:

```text
/support
```

Eyebrow:

```text
CONTACT
```

Headline:

```text
Questions about CardScanner?
```

Body:

```text
For product questions, launch information, or anything else related to CardScanner, get in touch.
```

Primary contact:

```text
hello@[final-domain]
```

Include a simple contact form only if it can be implemented reliably without adding meaningful maintenance burden.

If implemented, fields are exactly:

```text
Name
Email
Message
```

Button:

```text
Send message
```

No phone number is required.

No street address is required.

---

# 27. Responsive behavior

Test at minimum at:

```text
375px
390px
430px
768px
1024px
1280px
1440px
```

The design must work fluidly between those widths.

Requirements:

- zero horizontal overflow
- no clipped phone mockups
- no text collisions
- no awkward line wrapping in buttons
- no tiny legal text
- touch targets at least approximately 44px
- navigation usable by touch
- forms usable without zoom
- images retain sensible proportions

Do not build a desktop layout and merely stack everything at one breakpoint.

Mobile should feel intentionally designed.

---

# 28. Motion

Motion is optional and subordinate to usability.

Permitted:

- subtle opacity/translate reveal
- slight device parallax
- gentle hover state
- button microinteraction
- subtle header transition

Forbidden:

- scroll hijacking
- large 3D rotation
- constant floating animation
- animated gradients
- excessive blur animation
- cursor effects
- particle systems
- autoplay videos
- animation that delays reading content

Respect:

```text
prefers-reduced-motion
```

When reduced motion is enabled, decorative movement should disappear or become effectively instantaneous.

---

# 29. Accessibility

Minimum requirements:

- semantic HTML
- keyboard navigability
- visible focus states
- descriptive form labels
- meaningful button labels
- image alt text
- sufficient color contrast
- logical heading order
- no information conveyed solely by color
- accessible mobile navigation
- accessible form validation
- reduced-motion support

Aim for WCAG 2.2 AA behavior.

Do not sacrifice accessibility for an Apple-like visual treatment.

---

# 30. Performance

The site must feel effectively immediate on a modern connection.

Optimize:

- images
- screenshot dimensions
- image formats
- JavaScript bundle size
- font loading
- above-the-fold rendering

Prefer Next.js image optimization where appropriate.

Do not ship original multi-megabyte simulator screenshots directly to browsers.

Do not preload assets that are not important to the initial view.

Production Lighthouse targets on the homepage:

```text
Performance:      ≥ 90
Accessibility:    ≥ 95
Best Practices:   ≥ 95
SEO:              ≥ 95
```

Treat regressions below these targets as issues to investigate rather than automatically gaming the audit.

---

# 31. SEO and metadata

Every page requires a unique `<title>` and meta description.

Homepage title:

```text
CardScanner — Scan, Organize, and Understand Your Card Collection
```

Homepage meta description:

```text
CardScanner helps trading card collectors scan cards, organize what they own, and understand the value of their collection.
```

Privacy:

```text
Privacy Policy — CardScanner
```

Terms:

```text
Terms of Use — CardScanner
```

Support:

```text
Support — CardScanner
```

Implement:

- canonical metadata
- Open Graph title
- Open Graph description
- Open Graph image
- Twitter/social sharing metadata where supported
- favicon
- sitemap
- robots.txt

Do not stuff keywords.

---

# 32. Open Graph asset

Create one polished share image.

Recommended dimensions:

```text
1200 × 630
```

Contents:

```text
CardScanner
Your collection. Accurately cataloged.
```

plus one authentic CardScanner device/app composition.

Keep it legible when displayed small.

Do not fill the image with feature bullets.

---

# 33. Favicon

Create a restrained favicon derived from either:

- the approved future CardScanner brand mark, or
- a simple temporary monogram/mark

It must remain legible at:

```text
16×16
32×32
```

Do not use an entire trading card illustration as the favicon.

---

# 34. Analytics

Implement privacy-conscious basic analytics.

Use analytics only to answer basic questions such as:

- page views
- traffic source
- waitlist conversion
- device type

Do not add:

- session replay
- invasive fingerprinting
- unnecessary advertising trackers

Document the analytics provider in the README and ensure the Privacy Policy matches the implementation.

---

# 35. Error handling

Create a custom 404 page.

Copy:

```text
This card isn't in the collection.
```

Supporting line:

```text
The page you're looking for doesn't exist or may have moved.
```

Button:

```text
Back to CardScanner
```

Button navigates to `/`.

Keep the joke subtle.

Do not turn the 404 into an elaborate game or animation.

---

# 36. Loading behavior

The static marketing site should not need prominent loading screens.

Do not create:

- startup splash screen
- loading spinner before homepage display
- animated logo gate

The page should render immediately.

Lazy-load below-the-fold imagery where appropriate.

---

# 37. Content rules

The implementation must not invent any of the following:

- user counts
- waitlist counts
- launch date
- funding
- revenue
- accuracy percentages
- scan-speed statistics
- supported games
- customer quotes
- testimonials
- awards
- partnerships
- media coverage
- company address
- company legal entity
- team members
- App Store availability

If a factual statement is not included in this specification or supplied as an approved project asset, omit it.

---

# 38. Product claims

Permissible:

```text
Scan trading cards.
Organize your collection.
Understand what your collection is worth.
Fast, accurate identification.
Transparent pricing information.
Your collection data stays portable.
```

Avoid absolute claims.

Do not write:

```text
100% accurate
perfect identification
the fastest card scanner
the most accurate scanner
the best collection app
industry-leading
```

unless separately approved with evidence.

---

# 39. Product screenshot asset list

Before final production completion, obtain at least these screenshots from the real app:

### Screenshot A — Scanner

Shows:

- scanner interface
- a recognizable card
- successful identification or ready-to-scan state
- polished production UI

Use primarily in hero.

### Screenshot B — Collection

Shows:

- populated collection
- attractive but plausible data
- enough cards to make the product feel real
- no debug information

Use in product visual section.

### Screenshot C — Card detail

Shows:

- specific card
- collection information
- pricing/value information where appropriate

Use as secondary hero or supporting screenshot.

### Screenshot D — Optional organization view

If an existing screen clearly demonstrates physical collection organization, capture it.

Do not invent this screenshot if such an interface is not production-ready.

---

# 40. Screenshot QA

Every screenshot included in production must pass this checklist:

```text
[ ] From the real CardScanner application
[ ] Current UI
[ ] No debug overlays
[ ] No simulator controls
[ ] No personal data
[ ] No obviously fake values
[ ] No impossible product state
[ ] No UI defects
[ ] Correct device safe areas
[ ] Correct orientation
[ ] High enough source resolution
[ ] Optimized for web
```

---

# 41. Domain configuration

Once the final domain has been chosen:

1. Connect it to the production deployment.
2. Enable HTTPS.
3. Redirect the Vercel-generated production domain if appropriate.
4. Establish one canonical hostname.
5. Redirect alternate hostname appropriately.

For example:

```text
www.domain.com → domain.com
```

or the reverse.

Choose one.

Avoid duplicate public versions.

---

# 42. Business email

Before AWS submission, configure:

```text
hello@[domain]
```

and preferably:

```text
sean@[domain]
```

The public website should use:

```text
hello@[domain]
```

The AWS Activate profile/application should use the appropriate domain-matching business email.

Do not publish `sean@` unless there is a reason to.

---

# 43. Repository structure

Use a clean conventional structure.

Example:

```text
/app
  /page.tsx
  /privacy/page.tsx
  /terms/page.tsx
  /support/page.tsx
  /not-found.tsx

/components
  /Header.tsx
  /Footer.tsx
  /Hero.tsx
  /ProductVisual.tsx
  /Capabilities.tsx
  /BuiltDifferently.tsx
  /HowItWorks.tsx
  /SupportedCollections.tsx
  /About.tsx
  /Waitlist.tsx
  /DeviceMockup.tsx

/public
  /images
  /screenshots
  /icons

/lib

/styles
```

Exact organization may vary slightly where framework conventions make another structure cleaner.

Do not over-architect.

---

# 44. Component rules

Components should exist where there is genuine reuse or a meaningful conceptual boundary.

Do not create dozens of tiny one-line components merely for abstraction.

Avoid:

- complicated state-management libraries
- global stores
- dependency-heavy design systems
- unnecessary UI frameworks

This site does not require application-scale architecture.

---

# 45. Dependencies

Keep dependencies minimal.

Before adding a package, determine whether the task can reasonably be done with:

- React
- Next.js
- CSS/Tailwind
- browser APIs

Do not install large libraries solely for:

- one animation
- one icon
- one form interaction
- basic layout

A lightweight icon library is acceptable if useful.

---

# 46. Browser support

Support current mainstream releases of:

- Safari
- Chrome
- Edge
- Firefox

The site must work especially well in Safari on:

- iPhone
- iPad
- macOS

because the product itself is Apple-platform oriented.

---

# 47. QA requirements

Perform a complete manual QA pass after implementation.

Test:

### Navigation

```text
[ ] Logo
[ ] Every header link
[ ] Every CTA
[ ] Privacy
[ ] Terms
[ ] Support
[ ] Footer links
[ ] 404 return link
```

### Waitlist

```text
[ ] Valid email
[ ] Invalid email
[ ] Blank email
[ ] Duplicate submission
[ ] Loading state
[ ] Success state
[ ] Failure state
```

### Support

If contact form exists:

```text
[ ] Valid submission
[ ] Required fields
[ ] Invalid email
[ ] Loading
[ ] Success
[ ] Failure
```

### Responsive

```text
[ ] 375px
[ ] 390px
[ ] 430px
[ ] 768px
[ ] 1024px
[ ] 1280px
[ ] 1440px
```

### Browsers

```text
[ ] Safari
[ ] Chrome
[ ] Firefox or Edge
```

---

# 48. Visual QA

Manually inspect every route.

Reject the implementation if any of the following are visible:

- generic template appearance
- accidental horizontal scroll
- inconsistent spacing
- low-resolution screenshots
- fake content
- clipped device frames
- awkward mobile composition
- excessive gradients
- inconsistent border radii
- inconsistent shadows
- giant empty sections
- text walls
- misaligned cards
- excessive animation
- visible placeholder content
- broken links
- debug text
- developer-default form elements
- obvious accessibility failures

---

# 49. Acceptance criteria — homepage

Homepage passes only if:

```text
[ ] A new visitor can identify CardScanner as a trading-card scanning and collection-management application within approximately 5 seconds.

[ ] Scanning, collection organization, and collection value are all communicated above the fold or immediately adjacent to it.

[ ] Hero uses real CardScanner UI.

[ ] No fabricated product UI appears.

[ ] All eight required sections exist in the specified order.

[ ] No unapproved sections have been added.

[ ] Waitlist form actually stores submissions.

[ ] Every CTA works.

[ ] Desktop and mobile layouts both feel intentionally designed.

[ ] No placeholder copy remains.

[ ] No fake testimonials, statistics, customer counts, or launch dates appear.
```

---

# 50. Acceptance criteria — supporting pages

```text
[ ] /privacy exists and contains approved final copy.

[ ] /terms exists and contains approved final copy.

[ ] /support exists and provides a real working contact mechanism.

[ ] Header and footer remain consistent across all routes.

[ ] No supporting page feels unfinished.

[ ] Legal pages remain easily readable on mobile.
```

---

# 51. Acceptance criteria — technical

```text
[ ] Production build completes with no errors.

[ ] No material console errors.

[ ] No broken internal links.

[ ] HTTPS enabled.

[ ] Custom domain connected.

[ ] Canonical hostname configured.

[ ] sitemap.xml available.

[ ] robots.txt available.

[ ] Favicon works.

[ ] Open Graph image works.

[ ] Page metadata is correct.

[ ] Forms work in production, not merely locally.

[ ] Analytics work in production.

[ ] Lighthouse targets are met or any exceptions are documented and justified.
```

---

# 52. Acceptance criteria — AWS readiness

Before the AWS Activate application is submitted, verify:

```text
[ ] Final public domain is live.

[ ] Site is fully functional.

[ ] No construction/placeholder page appears.

[ ] Product is clearly described.

[ ] Authentic app screenshots demonstrate the product exists.

[ ] Contact information works.

[ ] hello@[domain] works.

[ ] Domain-matching business email for AWS application exists.

[ ] Privacy Policy is live.

[ ] Terms are live.

[ ] Waitlist works.

[ ] Product positioning on the website matches the wording intended for the AWS application.

[ ] Target market positioning matches the AWS application.

[ ] Company/funding information in the AWS application does not contradict the website.

[ ] AWS account meets the current Founders eligibility requirements before submission.
```

---

# 53. Explicit implementation sequence

Execute in this order.

## Phase 1 — Project foundation

1. Create Next.js TypeScript project.
2. Configure Tailwind.
3. Establish global typography.
4. Establish spacing/layout variables.
5. Build Header.
6. Build Footer.
7. Configure routing.
8. Configure metadata framework.

Do not begin embellishment yet.

---

## Phase 2 — Homepage skeleton

Implement all eight homepage sections in correct order using approved copy.

At this point:

- use correctly sized temporary screenshot containers if final screenshots have not yet been supplied
- do not substitute invented UI
- clearly isolate screenshot assets so real files can be dropped in later

Do not use generic stock images.

---

## Phase 3 — Product imagery

Insert authentic CardScanner screenshots.

Build:

- device presentation
- responsive screenshot scaling
- appropriate shadows
- cropping
- secondary screenshot composition

Then verify both desktop and mobile.

---

## Phase 4 — Supporting routes

Build:

```text
/privacy
/terms
/support
```

Apply the same design system.

Do not stylistically redesign each page independently.

---

## Phase 5 — Forms

Implement:

- waitlist
- contact form if approved

Test persistence and error states.

Verify production submissions.

---

## Phase 6 — Production polish

Add:

- subtle motion
- hover states
- focus states
- final responsive tuning
- Open Graph image
- favicon
- metadata
- sitemap
- robots.txt
- analytics
- custom 404

Do not add new sections during polish.

---

## Phase 7 — QA

Run:

- responsive review
- browser review
- accessibility review
- Lighthouse review
- link test
- form test
- screenshot review
- content review

Fix all material defects.

---

## Phase 8 — Production deployment

1. Deploy to Vercel.
2. Configure production environment variables.
3. Connect domain.
4. Verify HTTPS.
5. Verify canonical URL.
6. Verify forms from production.
7. Verify analytics from production.
8. Verify Open Graph preview.
9. Verify mobile Safari.
10. Conduct one final 30-second AWS-reviewer test.

---

# 54. Thirty-second reviewer test

Open the production site in a clean browser session.

Without relying on any prior knowledge, determine whether the page answers:

```text
What is being built?
→ A trading-card scanning and collection-management application.

Who is it for?
→ Trading-card collectors.

Is there a real product?
→ Yes. Authentic application screens are visible.

What does it do?
→ Scans cards, organizes a collection, and helps understand its value.

Does this appear to be an actual operating early-stage startup?
→ Yes.

Can someone contact the company?
→ Yes.

Does the website feel finished?
→ Yes.
```

If any answer is ambiguous, fix the page rather than explaining the ambiguity elsewhere.

---

# 55. Definition of done

This project is complete when CardScanner has:

- one genuinely excellent homepage
- three finished supporting pages
- authentic product screenshots
- real working waitlist
- real contact method
- domain email
- custom domain
- HTTPS
- privacy and terms
- analytics
- metadata
- sitemap
- robots.txt
- favicon
- social sharing image
- responsive mobile/desktop implementation
- no fake or placeholder content
- no broken interactions
- no obvious template feel
- production-level polish

Do not interpret “minimum scope” as permission to lower the quality bar.

The intended result is a small website that looks exceptionally complete, rather than a larger website that looks partially finished.
