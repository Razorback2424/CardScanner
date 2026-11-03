Target screen: collection and price-check sharing
- Route name: `CardShareReview`
- Expected device: iPhone 17 Pro; compact iPhone and iPad follow-up captures

Status — 2026-11-02: implementation updated. All post-change testing, builds and
simulator captures were skipped at the owner's explicit request. Items below
are future acceptance checks, not claims of completed verification.

Visual checklist:
1. [ ] Export is 1080 × 1920 (9:16); the artwork keeps its proportions.
2. [ ] Rarity has a distinct symbol and full readable name; finish is secondary.
3. [ ] Common, Uncommon, Rare, Double Rare, Ultra Rare, Illustration Rare,
   Special Illustration Rare and Hyper Rare are visually distinguishable.
4. [ ] Names remain sufficient in grayscale; no information depends on hue.
5. [ ] Long rarity names, set names, grades and printing details do not overlap.
6. [ ] ScanStash uses natural text proportions and a restrained foil mark.
7. [ ] Price, source and history retain their labels and adequate spacing.
8. [ ] Missing artwork retains an intentional, usable composition.

Behavior checklist:
1. [ ] Collection and price-check adapters retain catalog rarity separately
   from finish, edition and grade; unknown rarity is never inferred.
2. [ ] Plain-text and accessibility summaries include the same facts.
3. [ ] Price/asking controls, Close and Share remain visible at large text sizes.
4. [ ] Existing loading, failure, retry and personal-photo export tests pass.

Native share targets, spoken VoiceOver and physical-device acceptance remain
manual checks; simulator captures do not establish them.
