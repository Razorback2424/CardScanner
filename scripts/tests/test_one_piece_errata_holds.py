import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from audit_one_piece_coverage import apply_errata_resolutions
from resolve_one_piece_errata_holds import release_group


def held():
    return {"id": "AAAA", "canonicalCardID": "one-piece:en:OP01-042", "status": "provisional",
            "releaseID": "product:op01", "supportedVariantIDs": ["normal"], "sourceAliases": [],
            "review": {"reference": "r", "evidence": []}}


def listing(**fields):
    return {"id": "obs", "alias": {"provider": "tcgplayer", "sourceID": "454600"}, "productEvidence": ["product:op01"],
            "printedEvidence": dict({"sourceRole": "marketplace-single-release-product"}, **fields)}


class ErrataHoldTests(unittest.TestCase):
    def test_release_group_ignores_super_pre_release_editions(self):
        groups = [{"groupId": 1, "name": "ST-02: Starter Deck 2 Worst Generation"},
                  {"groupId": 2, "name": "ST-02: Starter Deck 2 Worst Generation (Super Pre-Release Edition)"},
                  {"groupId": 3, "name": "Romance Dawn"}]
        self.assertEqual(release_group("Romance Dawn · OP-01", groups)["groupId"], 3)
        self.assertIsNone(release_group("Unknown Set · XX-01", groups))

    def test_resolution_verifies_only_a_matching_held_printing(self):
        registry = {"printings": [held()]}
        resolution = [{"printingID": "AAAA", "observationID": "obs", "detail": "One product."}]
        printing = apply_errata_resolutions(registry, [listing()], resolution)["printings"][0]
        self.assertEqual(printing["status"], "verified")
        self.assertIn({"provider": "tcgplayer", "sourceID": "454600"}, printing["sourceAliases"])
        for bad_registry, bad_observation in [
                ({"printings": [dict(held(), supportedVariantIDs=[])]}, listing()),
                ({"printings": [dict(held(), status="verified")]}, listing()),
                (registry, dict(listing(), productEvidence=["product:other"])),
                (registry, listing(sourceRole="marketplace-promo-listing"))]:
            with self.assertRaises(ValueError):
                apply_errata_resolutions(bad_registry, [bad_observation], resolution)


class ReprintAppearanceAdditionTests(unittest.TestCase):
    def test_reviewed_additions_merge_appearances_without_replacing_one(self):
        from audit_one_piece_coverage import applying_reviewed_additions
        release = {"registry": {"artworks": [], "printings": [], "products": [], "appearances": [
                       {"printingID": "AAAA", "productID": "product:st15", "observationIDs": ["a"]}]},
                   "observations": [], "inventories": []}
        additions = {"artworks": [], "printings": [], "observations": [], "inventories": [], "appearances": [
            {"printingID": "AAAA", "productID": "product:prb01", "observationIDs": ["b"]}]}
        merged = applying_reviewed_additions(release, additions)["registry"]["appearances"]
        self.assertEqual({row["productID"] for row in merged}, {"product:st15", "product:prb01"})
        additions["appearances"] = [{"printingID": "aaaa", "productID": "product:st15", "observationIDs": ["c"]}]
        with self.assertRaises(ValueError):
            applying_reviewed_additions(release, additions)


if __name__ == "__main__":
    unittest.main()
