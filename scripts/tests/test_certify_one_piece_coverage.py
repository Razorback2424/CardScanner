import copy
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from audit_one_piece_coverage import BROWSE_DISCOVERY, apply_coverage_certifications
from certify_one_piece_coverage import compare_cards, resolved, status


def observation(oid, provider, source, number, **fields):
    return {"id": oid, "kind": "catalog", "language": "en", "alias": {"provider": provider, "sourceID": source},
            "sourceURL": "https://en.onepiece-cardgame.com/cardlist/?series=569101", "productEvidence": ["product:op01"],
            "printedEvidence": dict(fields, number=number)}


def fixture():
    base = {"id": "AAAA", "canonicalCardID": "one-piece:en:OP01-001", "language": "en", "status": "verified",
            "releaseID": "product:op01", "treatment": None, "supportedVariantIDs": ["normal"],
            "sourceAliases": [{"provider": "bandai", "sourceID": "OP01-001"}],
            "marketMappings": [{"provider": "tcgplayer", "productID": "100", "qualifiers": {"groupID": "3188"}}],
            "review": {"evidence": [{"kind": "finish", "observationID": "retail"}]}}
    release = {
        "registry": {"canonicalCards": [{"id": "one-piece:en:OP01-001", "printedNumber": "OP01-001", "language": "en",
                                         "name": "Roronoa Zoro", "printingCoverageComplete": False}],
                     "printings": [base]},
        "observations": [observation("list", "bandai", "OP01-001", "OP01-001"),
                         observation("retail", "coretcg", "/Products/1/68/3188/Zoro", "OP01-001",
                                     sourceRole="retailer-standard-printing-specification")],
    }
    coverage = {"series": [{"seriesID": "569101", "rows": [
        {"number": "OP01-001", "artworkAlias": "OP01-001", "status": "verified", "printingIDs": ["AAAA"]}]}]}
    market = {"OP01-001": [{"productId": 100, "groupId": 3188, "name": "Roronoa Zoro (001)", "groupName": "Romance Dawn"}]}
    return release, coverage, market


class CertifyOnePieceCoverageTests(unittest.TestCase):
    def test_complete_family_is_certifiable_and_attaches_its_retailer_evidence(self):
        release, coverage, market = fixture()
        card = compare_cards(release, coverage, market)["one-piece:en:OP01-001"]
        self.assertEqual(status(card), "certifiable")
        self.assertEqual(card["accountedMarketProducts"], {"100": "AAAA"})
        self.assertEqual(card["aliasAttachments"], [{"printingID": "AAAA", "alias": {
            "provider": "coretcg", "sourceID": "/Products/1/68/3188/Zoro"}}])

    def test_title_match_accounts_only_a_unique_product_in_the_printings_group(self):
        release, coverage, market = fixture()
        printing = release["registry"]["printings"][0]
        printing["marketMappings"] = []
        printing["sourceAliases"].append({"provider": "coretcg", "sourceID": "3188:5"})
        card = compare_cards(release, coverage, market)["one-piece:en:OP01-001"]
        self.assertEqual(card["accountedMarketProducts"], {"100": "AAAA"})
        market["OP01-001"].append({"productId": 101, "groupId": 3188, "name": "Roronoa Zoro (001)",
                                   "groupName": "Romance Dawn"})
        card = compare_cards(release, coverage, market)["one-piece:en:OP01-001"]
        self.assertEqual(card["accountedMarketProducts"], {})
        self.assertEqual([row["productID"] for row in card["unaccountedMarketProducts"]], ["100", "101"])
        # A product already mapped to the printing leaves no room for a title-only claim.
        printing["marketMappings"] = [{"provider": "tcgplayer", "productID": "100", "qualifiers": {}}]
        card = compare_cards(release, coverage, market)["one-piece:en:OP01-001"]
        self.assertEqual(card["accountedMarketProducts"], {"100": "AAAA"})
        self.assertEqual([row["productID"] for row in card["unaccountedMarketProducts"]], ["101"])

    def test_unexplained_marketplace_product_needs_a_cited_resolution(self):
        release, coverage, market = fixture()
        market["OP01-001"].append({"productId": 200, "groupId": 9999, "name": "Roronoa Zoro (Pre-Release)",
                                   "groupName": "Romance Dawn Pre-Release Cards"})
        card = compare_cards(release, coverage, market)["one-piece:en:OP01-001"]
        self.assertEqual(status(card), "needs-resolution")
        cited = {"decision": "exclude", "reason": "Not an English card.", "citation": "https://example.com/x"}
        self.assertEqual(status(card, {"200": cited}), "certifiable")
        for bad in ({**cited, "citation": "http://example.com"}, {**cited, "reason": " "},
                    {**cited, "decision": "same-printing", "printingID": "BBBB"}, {**cited, "printingID": "AAAA"}):
            with self.assertRaises(ValueError):
                resolved(card, {"200": bad})
        with self.assertRaises(ValueError):
            resolved(card, {"100": cited})

    def test_discovery_held_printing_and_missing_bandai_row_block(self):
        release, coverage, market = fixture()
        held = copy.deepcopy(release)
        held["registry"]["printings"][0]["status"] = "provisional"
        self.assertTrue(compare_cards(held, coverage, market)["one-piece:en:OP01-001"]["blockers"])
        discovered = copy.deepcopy(release)
        discovered["observations"].append(observation("browse", "bandai", "browse", "OP01-001", sourceRole=BROWSE_DISCOVERY))
        self.assertIn("browse-discovery:browse",
                      compare_cards(discovered, coverage, market)["one-piece:en:OP01-001"]["blockers"])
        missing = copy.deepcopy(coverage)
        missing["series"][0]["rows"][0]["status"] = "missing-printing-or-appearance"
        self.assertEqual(status(compare_cards(release, missing, market)["one-piece:en:OP01-001"]), "blocked")
        orphan = copy.deepcopy(release)
        orphan["observations"].append(observation("orphan", "coretcg", "/elsewhere", "OP01-001"))
        self.assertIn("unreconciled-source-observation:orphan",
                      compare_cards(orphan, coverage, market)["one-piece:en:OP01-001"]["blockers"])

    def test_known_unpriced_printing_does_not_hold_the_family_open(self):
        release, coverage, market = fixture()
        release["observations"].append(observation("unpriced", "tcgplayer", "900", "OP01-001",
                                                   marketplaceFinishLanes="none", retailerReferenceProductID="900"))
        release["registry"]["printings"].append({
            "id": "BBBB", "canonicalCardID": "one-piece:en:OP01-001", "language": "en", "status": "provisional",
            "releaseID": "product:promo", "supportedVariantIDs": [], "marketMappings": [],
            "sourceAliases": [{"provider": "tcgplayer", "sourceID": "900"}],
            "review": {"evidence": [{"kind": "printedIdentity", "observationID": "unpriced"}]}})
        market["OP01-001"].append({"productId": 900, "groupId": 17675, "name": "Roronoa Zoro (Judge)",
                                   "groupName": "One Piece Promotion Cards"})
        card = compare_cards(release, coverage, market)["one-piece:en:OP01-001"]
        self.assertEqual(status(card), "certifiable")
        self.assertEqual(card["knownUnpricedPrintingIDs"], ["BBBB"])
        # An unresolved provisional printing, such as an errata hold, still blocks.
        release["registry"]["printings"][1]["review"]["evidence"] = []
        self.assertEqual(status(compare_cards(release, coverage, market)["one-piece:en:OP01-001"]), "blocked")

    def test_audit_applies_certification_only_while_its_gates_still_hold(self):
        release, coverage, market = fixture()
        card = compare_cards(release, coverage, market)["one-piece:en:OP01-001"]
        certification = [{"canonicalCardID": "one-piece:en:OP01-001", "reference": "one-piece-coverage-certification:x"}]
        registry = apply_coverage_certifications(release["registry"], release["observations"],
                                                 card["aliasAttachments"], certification)
        self.assertTrue(registry["canonicalCards"][0]["printingCoverageComplete"])
        self.assertEqual(len(registry["printings"][0]["sourceAliases"]), 2)
        with self.assertRaises(ValueError):  # the retailer alias is not attached
            apply_coverage_certifications(release["registry"], release["observations"], [], certification)
        later = release["observations"] + [observation("new", "bandai", "new", "OP01-001", sourceRole=BROWSE_DISCOVERY)]
        with self.assertRaises(ValueError):
            apply_coverage_certifications(release["registry"], later, card["aliasAttachments"], certification)


if __name__ == "__main__":
    unittest.main()
