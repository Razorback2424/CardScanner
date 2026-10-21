import copy
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
import build_yugioh_catalog as builder

class BuilderTests(unittest.TestCase):
    def setUp(self):
        self.fixture = json.loads(pathlib.Path(__file__).with_name("catalog.json").read_text())

    def build(self, reviews=None):
        f = self.fixture
        return builder.build(f["groups"], {1: f["products"]}, {1: f["prices"]}, f["cards"],
            {"12206212": ["Harpie's Brother"]}, reviews or {}, "2026-10-20T00:00:00Z", floor=1)

    def test_alias_matches_and_canonical_id_does_not_depend_on_printed_name(self):
        seed, _, exceptions, _ = self.build()
        row = next(x for x in seed["printings"] if x["p"] == 1)
        self.assertEqual(seed["cards"][row["k"]]["n"], "Sky Scout")
        self.assertEqual(seed["cards"][row["k"]]["id"], builder.stable("yugioh-card:", "ygoprodeck:12206212"))
        self.assertEqual(exceptions["aliasMatch"], [1])
        self.fixture["products"][0]["name"] = "Sky Scout (UR)"
        renamed = self.build()[0]
        self.assertEqual(seed["cards"], renamed["cards"])

    def test_group_price_union_cannot_create_physical_editions(self):
        seed, stats, _, _ = self.build()
        self.assertTrue(all(x["e"] == [] and not x["ec"] for x in seed["printings"]))
        self.assertEqual(seed["autoEligibleCodes"], [])
        self.assertEqual(stats["verifiedPhysicalProducts"], 0)

    def test_supported_missing_lane_is_retained_without_price_whitelist(self):
        reviews = {"1": {"editions": ["yugioh1stEdition", "yugiohUnlimited"], "complete": True, "evidence": "synthetic:physical-review"}}
        seed, _, _, _ = self.build(reviews)
        first, second = seed["printings"]
        self.assertEqual(first["e"], ["yugioh1stEdition", "yugiohUnlimited"])
        self.assertNotIn("yugiohUnlimited", first["pe"])
        self.assertTrue(first["ec"])
        self.assertFalse(second["ec"])
        self.assertEqual(second["e"], [])

    def test_entire_group_missing_valid_edition_does_not_prove_completeness(self):
        self.fixture["prices"] = []
        seed = self.build()[0]
        self.assertTrue(all(not x["ec"] and not x["e"] for x in seed["printings"]))
        self.assertEqual(seed["autoEligibleCodes"], [])

    def test_skipped_rarity_product_poisoning(self):
        product = copy.deepcopy(self.fixture["products"][0])
        product["productId"] = 3
        product["extendedData"] = product["extendedData"][:1]
        self.fixture["products"].append(product)
        self.assertIn("PSV-EN049", self.build()[0]["incompleteCodes"])

    def test_same_rarity_missing_reprint_is_incomplete(self):
        self.fixture["cards"][0]["card_sets"].append({"set_code": "PSV-EN049", "set_name": "Reprint", "set_rarity": "Ultra Rare"})
        self.assertIn("printingShortfall", self.build()[3]["PSV-EN049"])

    def test_deterministic_input_order(self):
        first = self.build()[0]
        self.fixture["products"].reverse(); self.fixture["cards"].reverse(); self.fixture["prices"].reverse()
        self.assertEqual(first, self.build()[0])

    def test_unknown_subtype_and_duplicate_identity_fail_closed(self):
        self.fixture["prices"][0]["subTypeName"] = "Normal"
        self.assertIn("PSV-EN049", self.build()[0]["incompleteCodes"])
        self.fixture["products"].append(copy.deepcopy(self.fixture["products"][0]))
        with self.assertRaises(AssertionError): self.build()

    def test_review_cannot_contradict_observed_product_lane(self):
        with self.assertRaises(AssertionError):
            self.build({"1": {"editions": ["yugiohUnlimited"], "complete": True, "evidence": "synthetic:bad-review"}})

    def test_no_automatic_eligibility_for_alternate_art_or_unknown_coverage(self):
        self.fixture["cards"][0]["card_images"].append({"id": 1})
        reviews = {"1": {"editions": ["yugioh1stEdition"], "complete": True, "evidence": "synthetic:review"}}
        self.assertNotIn("PSV-EN049", self.build(reviews)[0]["autoEligibleCodes"])

    def test_failed_or_missing_input_preserves_existing_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            out, report = root / "catalog.json", root / "report.md"
            out.write_bytes(b"existing valid seed"); report.write_bytes(b"existing report")
            for invalid in [None, {"success": False, "errors": ["fixture failure"], "results": []},
                            {"success": True, "errors": [], "results": [], "totalItems": 10}]:
                if invalid is not None:
                    path = root / "cache" / "tcgcsv" / "categories.json"
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(json.dumps(invalid))
                result = subprocess.run([sys.executable, "-I", str(builder.ROOT / "build_yugioh_catalog.py"), "--offline",
                    "--cache-dir", str(root / "cache"), "--out", str(out), "--report", str(report)], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(out.read_bytes(), b"existing valid seed")
                self.assertEqual(report.read_bytes(), b"existing report")

if __name__ == "__main__": unittest.main()
