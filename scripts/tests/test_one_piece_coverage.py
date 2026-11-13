import json
import unittest
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from audit_one_piece_coverage import applying_reviewed_additions, compare, discovery_inputs, parse_cardlist, series_options
from normalize_one_piece_sources import Document


class OnePieceCoverageTests(unittest.TestCase):
    def test_directory_includes_promo_and_other_products(self):
        raw = b'''<select name="series"><option value="">ALL</option>
        <option value="1">[EB-05]</option><option value="2">Promotion card</option>
        <option value="3">Other Product Card</option></select>'''
        self.assertEqual(series_options(Document(raw).root),
                         {"1": "[EB-05]", "2": "Promotion card", "3": "Other Product Card"})

    def test_card_list_requires_all_rows_and_the_requested_product(self):
        raw = b'''<select name="series"><option value="1" selected>[EB-05]</option></select>
        <div class="countCol">1 result</div><dl class="modalCol" id="EB05-001_p1">
        <div class="cardName">Jewelry Bonney</div><div class="infoCol"><span>EB05-001</span></div>
        <div class="getInfo"><h3>Card Set(s)</h3>EB-05</div></dl>'''
        self.assertEqual(parse_cardlist(raw, "1"), [{"number": "EB05-001", "name": "Jewelry Bonney",
                                                    "artworkAlias": "EB05-001_p1", "productLabels": ["EB-05"]}])
        with self.assertRaisesRegex(ValueError, "different series"):
            parse_cardlist(raw, "2")
        with self.assertRaisesRegex(ValueError, "Incomplete"):
            parse_cardlist(raw.replace(b"1 result", b"2 results"), "1")

    def test_canonical_match_never_covers_a_different_artwork_or_product(self):
        number = "OP09-020"
        card_id = "one-piece:en:" + number
        printing = {"id": "base-uuid", "canonicalCardID": card_id, "releaseID": "original", "status": "verified",
                    "supportedVariantIDs": ["foil"], "review": {"evidence": [
                        {"kind": "printedIdentity", "observationID": "base"}]}}
        release = {"registry": {"canonicalCards": [{"id": card_id, "language": "en", "name": "Example",
                                                   "printedNumber": number}], "printings": [printing], "appearances": []},
                   "observations": [{"id": "base", "sourceURL": "https://en.onepiece-cardgame.com/cardlist/?series=1",
                                     "alias": {"provider": "bandai", "sourceID": "reviewed-base"},
                                     "productEvidence": ["original"],
                                     "printedEvidence": {"number": number, "sourceArtworkAlias": number}}]}
        base = {"number": number, "name": "Example", "artworkAlias": number, "productLabels": ["Original"]}
        report = compare([{"seriesID": "1", "rows": [base, {**base, "artworkAlias": number + "_p1"}]},
                          {"seriesID": "2", "rows": [base, {**base, "number": "EB05-001"}]}], release)
        self.assertEqual([r["status"] for r in report[0]["rows"]], ["verified", "missing-printing-or-appearance"])
        self.assertEqual(report[0]["rows"][0]["verifiedFinishIDs"], ["foil"])
        self.assertEqual([r["status"] for r in report[1]["rows"]], ["missing-printing-or-appearance", "missing-number"])

    def test_discovery_preserves_ownership_and_retires_only_the_reviewed_presentation(self):
        number = "OP09-020"
        card_id = "one-piece:en:" + number
        card = {"id": card_id, "printedNumber": number, "language": "en", "name": "Example",
                "printingCoverageComplete": True, "coverageReviewReference": "old-scope"}
        baseline = {"registry": {"canonicalCards": [card], "products": [], "artworks": [],
                                "printings": [], "appearances": []},
                    "observations": [], "inventories": []}
        alias = number + "_p2"
        source = {"sourceURL": "https://en.onepiece-cardgame.com/cardlist/?series=1",
                  "observedAt": "2026-11-11T23:00:00Z", "payloadSHA256": "a" * 64}
        inventory = [{"seriesID": "1", "label": "[PRB-02]", "source": source, "rows": [
            {"number": number, "name": "Example", "artworkAlias": alias, "productLabels": ["Winner Pack Vol. 2"]},
            {"number": "EB05-001", "name": "Jewelry Bonney", "artworkAlias": "EB05-001", "productLabels": []},
        ]}]
        initial = discovery_inputs(baseline, compare(inventory, baseline))
        registry = initial["registry"]
        self.assertEqual(registry["printings"], [])
        self.assertFalse(registry["canonicalCards"][0]["printingCoverageComplete"])
        self.assertNotIn("coverageReviewReference", registry["canonicalCards"][0])
        self.assertEqual(registry["canonicalCards"][1]["printedNumber"], "EB05-001")
        self.assertEqual(len(initial["observations"]), 2)
        self.assertEqual(initial["observations"][0]["printedEvidence"]["productLabel"], "Winner Pack Vol. 2")
        report = compare(inventory, initial)
        self.assertTrue(all(row["browseDiscovery"] for row in report[0]["rows"]))
        self.assertEqual(discovery_inputs(initial, report), initial)
        older = dict(initial, observations=[dict(row, printedEvidence={
            key: value for key, value in row["printedEvidence"].items() if key != "productLabel"
        }) for row in initial["observations"]])
        self.assertEqual(discovery_inputs(older, report), initial)
        different_receipt = [dict(report[0], source=dict(source, payloadSHA256="b" * 64))]
        self.assertEqual(discovery_inputs(older, different_receipt), older)

        product = registry["products"][0]["id"]
        printing = {"id": "physical-id", "canonicalCardID": card_id, "releaseID": product,
                    "status": "verified", "supportedVariantIDs": ["foil"],
                    "review": {"evidence": [{"kind": "printedIdentity", "observationID": "reviewed"}]}}
        observation = {**source, "id": "reviewed", "alias": {"provider": "bandai", "sourceID": alias},
                       "productEvidence": [product], "printedEvidence": {"number": number}}
        additions = {"printings": [printing], "artworks": [], "observations": [observation], "inventories": []}
        reviewed = applying_reviewed_additions(initial, additions)
        self.assertEqual(applying_reviewed_additions(reviewed, additions), reviewed)
        with self.assertRaisesRegex(ValueError, "replace a retained record"):
            applying_reviewed_additions(reviewed, {**additions, "printings": [{**printing, "status": "held"}]})
        next_release = discovery_inputs(reviewed, compare(inventory, reviewed))
        self.assertEqual(next_release["registry"]["printings"], [printing])
        self.assertEqual({row["id"] for row in next_release["observations"]}, {"bandai-browse:1:EB05-001", "reviewed"})
        self.assertEqual(next_release["inventories"][0]["observationIDs"], ["bandai-browse:1:EB05-001"])

    def test_product_update_names_and_dates_a_discovered_release_in_place(self):
        product_id = "product:bandai-series:569205"
        printing = {"id": "physical-id", "releaseID": product_id}
        baseline = {"registry": {"products": [{"id": product_id, "label": "EXTRA BOOSTER [EB-05]"}],
                                 "artworks": [], "printings": [printing]},
                    "observations": [], "inventories": []}
        update = {"id": product_id, "label": "Extra Booster: One Piece Heroines Edition Vol. 2 · EB05",
                  "releaseDate": "2026-10-30", "sourceURL": "https://en.onepiece-cardgame.com/products/eb05.html"}
        additions = {"artworks": [], "printings": [], "observations": [], "inventories": [],
                     "productUpdates": [update]}
        updated = applying_reviewed_additions(baseline, additions)
        self.assertEqual(applying_reviewed_additions(updated, additions), updated)
        self.assertEqual(updated["registry"]["products"],
                         [{"id": product_id, "label": update["label"], "releaseDate": "2026-10-30"}])
        self.assertEqual(updated["registry"]["printings"], [printing])
        self.assertEqual(baseline["registry"]["products"][0]["label"], "EXTRA BOOSTER [EB-05]")
        for invalid in ({**update, "id": "product:unknown"}, {**update, "sourceURL": "https://example.com/products/eb05"},
                        {**update, "releaseDate": "October 30, 2026"}, {**update, "label": " "}):
            with self.assertRaises(ValueError):
                applying_reviewed_additions(baseline, {**additions, "productUpdates": [invalid]})

        retained = json.loads((Path(__file__).resolve().parents[2] / "publisher/one-piece/product-updates.json").read_bytes())
        self.assertEqual(retained["productUpdates"][0]["id"], product_id)

    def test_verified_finish_promotes_the_same_provisional_printing(self):
        printing = {"id": "existing", "artworkID": "art", "language": "en", "releaseID": "product",
                    "canonicalCardID": "one-piece:en:ST31-001", "treatment": "Standard artwork",
                    "status": "provisional", "supportedVariantIDs": [], "sourceAliases": [],
                    "review": {"reference": "retained", "evidence": []}}
        baseline = {"registry": {"canonicalCards": [{"id": "one-piece:en:ST31-001", "printedNumber": "ST31-001"}],
                                 "products": [], "artworks": [{"id": "art", "imageSHA256": "a" * 64}],
                                 "variants": [{"id": "foil"}], "printings": [printing]},
                    "observations": [], "inventories": []}
        fields = {"number": "ST31-001", "treatment": "Standard artwork", "finishVariantID": "foil",
                  "sourceRole": "retailer-exact-printing-specification", "matchedBandaiImageSHA256": "a" * 64}
        evidence = {"id": "finish", "kind": "catalog", "language": "en", "productEvidence": ["product"],
                    "sourceURL": "https://coretcg.com/Products/0/68/24749/Example",
                    "alias": {"provider": "coretcg", "sourceID": "24749:100"}, "printedEvidence": fields}
        additions = {"artworks": [], "printings": [], "observations": [evidence], "inventories": [],
                     "finishUpdates": [{"printingID": "existing", "observationID": "finish"}]}
        updated = applying_reviewed_additions(baseline, additions)
        self.assertEqual(applying_reviewed_additions(updated, additions), updated)
        [new] = updated["registry"]["printings"]
        self.assertEqual((new["id"], new["artworkID"], new["status"]), ("existing", "art", "verified"))
        self.assertEqual(new["supportedVariantIDs"], ["foil"])
        self.assertEqual(printing["status"], "provisional")
        wrong = {**evidence, "printedEvidence": {**fields, "matchedBandaiImageSHA256": "b" * 64}}
        with self.assertRaisesRegex(ValueError, "does not match"):
            applying_reviewed_additions(baseline, {**additions, "observations": [wrong]})
