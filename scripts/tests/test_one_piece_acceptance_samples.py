import importlib.util
import json
from pathlib import Path
import unittest

root = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("acceptance_samples", root / "scripts/prepare_one_piece_acceptance_samples.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AcceptanceSampleTests(unittest.TestCase):
    def test_real_samples_cover_all_multiple_printings_and_exact_prices(self):
        registry = json.loads((root / "OnePieceCatalogCore/ReviewCorpus/english-stress/registry.json").read_text())
        result = module.samples(registry)
        self.assertEqual(result, module.samples(registry))
        eligible = {p["id"] for p in registry["printings"] if p["status"] == "verified" and p["language"] == "en"}
        self.assertEqual(set(result["groupSamples"]), {p["id"] for p in registry["products"]})
        self.assertTrue(all(set(ids) <= eligible and len(ids) <= 10 for ids in result["groupSamples"].values()))
        expected = {}
        for p in registry["printings"]:
            if p["id"] in eligible:
                expected.setdefault(p["canonicalCardID"], []).append(p["id"])
        expected = {card: sorted(ids) for card, ids in expected.items() if len(ids) > 1}
        self.assertEqual(result["allMultipleVerifiedPrintings"], expected)
        self.assertEqual(len(result["exactPriceSamples"]), 50)
        self.assertTrue(all(m["status"] == "exact" and m["printingID"] in eligible for m in result["exactPriceSamples"]))
        self.assertEqual(len({p["printingID"] for p in result["deviceSamples"]}), 50)
        for family in ("ST", "OP", "EB", "P-"):
            self.assertTrue(any(p["printedNumber"].startswith(family) for p in result["deviceSamples"]))
        self.assertEqual(result["status"], "pending-owner-review")
