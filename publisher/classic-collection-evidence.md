# Classic Collection membership review

Reviewed 2026-09-30 against the working tree based on `7db2e18`, following the
review of `82d0611`. This records public catalog evidence for the proposed
revision 10 input; it does not establish that revision 10 was signed or deployed.

All 30 printed number/denominator pairs below agree with the rendered English
TCGplayer Classic Collection listings. All 30 provider IDs and canonical names
agree with the [TCGdex set response](https://api.tcgdex.net/v2/en/sets/30th-c),
using the publisher's punctuation, case, and ampersand normalization. Marketplace
qualifiers such as “Delta Species,” “Team Plasma,” “Prime,” and “Top/Bottom” are
not part of the corresponding TCGdex names. Raikou's `050` normalizes to `50`.

| Provider ID suffix (`30th-c-`) | Canonical name | Printed number | TCGplayer product |
| --- | --- | --- | --- |
| 001 | charizard | 4/102 | 714372 |
| 002 | delcatty | 5/109 | 716156 |
| 003 | metagross | 11/113 | 716157 |
| 004 | genesect ex | 11/101 | 716158 |
| 005 | misty | 18/132 | 716159 |
| 006 | dark tyranitar | 19/109 | 716160 |
| 007 | sneasel | 25/111 | 716161 |
| 008 | pikachu and zekrom gx | 33/181 | 714373 |
| 009 | greninja break | 41/122 | 716162 |
| 010 | uxie | 43/146 | 716163 |
| 011 | crobat g | 47/127 | 716191 |
| 012 | raikou | 50/185 | 716192 |
| 013 | buzzwole gx | 57/111 | 716193 |
| 014 | pikachu | 58/102 | 716194 |
| 015 | erika s jigglypuff | 69/132 | 716195 |
| 016 | rayquaza ex | 85/124 | 716196 |
| 017 | solgaleo gx | 89/149 | 716197 |
| 018 | gengar | 94/102 | 716198 |
| 019 | darkrai and cresselia legend | 99/102 | 716199 |
| 020 | darkrai and cresselia legend | 100/102 | 716200 |
| 021 | n | 101/101 | 716202 |
| 022 | palkia | 106/106 | 716203 |
| 023 | m gardevoir ex | 106/160 | 716204 |
| 024 | shining celebi | 106/105 | 716205 |
| 025 | scizor ex | 108/115 | 716206 |
| 026 | mew vmax | 114/264 | 716207 |
| 027 | arceus vstar | 123/172 | 716208 |
| 028 | zacian v | 138/202 | 716209 |
| 029 | lugia | 149/147 | 714386 |
| 030 | magikarp | 203/193 | 716210 |

The renamed rows have direct supporting listings:
[Darkrai & Cresselia LEGEND Top](https://www.tcgplayer.com/product/716199/pokemon-me-30th-celebration-classic-collection-darkrai-and-cresselia-legend-top)
and [Bottom](https://www.tcgplayer.com/product/716200/pokemon-me-30th-celebration-classic-collection-darkrai-and-cresselia-legend-bottom)
retain `99/102` and `100/102` and include LEGEND. The
[Palkia LV.X listing](https://www.tcgplayer.com/product/716203/pokemon-me-30th-celebration-classic-collection-palkia-lvx)
retains `106/106`; its
[TCGdex card response](https://api.tcgdex.net/v2/en/cards/30th-c-022) names it
“Palkia.” The membership name therefore stays `palkia` to satisfy the strict
provider identity gate. These checks used public listings and API responses;
no additional physical cards were inspected.

## Correction and offline boundaries

An explicit complete `membershipRecognition` list replaces the existing list
in a higher revision. A regression test builds revision 10 with a wrong printed
number, supplies the corrected list in revision 11, validates the candidate,
and checks that the change is classified as protected authority. Omitting the
field preserves the old signed membership. Deleting one member from the input
is not a supported withdrawal: the builder requires complete provider-card
coverage, and there is no explicit membership-withdrawal input today.

The bundled registry supplies Classic membership choices and main-set
`30C`/128 recognition. It does not bundle a Classic checklist. First-launch
offline selection fails closed; a downloaded checklist or live card response
is still required to materialize the selected Classic card. With checklist or
provider data, Classic results display the parent's `30C` code without claiming
the parent's scanner namespace.

The historical stale-cache branch now evicts one key. In this checkout,
historical scan identifiers already return no persistent cache key, so that
branch is currently defensive rather than an active historical cache path.
Set-wide invalidation remains available for catalog activation.
