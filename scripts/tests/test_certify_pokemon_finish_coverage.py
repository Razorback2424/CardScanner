from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import certify_pokemon_finish_coverage as coverage


class PokemonFinishCoverageTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.snapshot = self.root / coverage.SNAPSHOT
        self.evidence = self.root / coverage.EVIDENCE / "sample.json"
        self.slots = self.snapshot / "sets/opaque.json"
        self.fixture = coverage.read_json(SCRIPTS / "fixtures/pokemon_finish_coverage.json")
        coverage.write_json(self.slots, self.fixture["snapshot"])
        coverage.write_json(self.snapshot / "manifest.json", {"entries": [
            {"providerID": "sample", "resource": "sets/opaque.json", "set": {"name": "Sample Set"}},
        ]})
        coverage.write_json(self.snapshot / "finish-coverage.json", {"schemaVersion": 1, "sets": {}})
        vocabulary = coverage.read_json(coverage.ROOT / coverage.SNAPSHOT / "finish-coverage-variants.json")
        coverage.write_json(self.snapshot / "finish-coverage-variants.json", vocabulary)
        self.publisher = self.root / "publisher/catalog-input.json"
        coverage.write_json(self.publisher, {"sets": []})
        self.ledger = [
            {"provider_id": "sample-002", "set_id": "sample", "collector_number": "002",
             "required_minimum_finishes": "holo", "extra_observed_finishes_requiring_review": "normal"},
            {"provider_id": "other-1", "set_id": "other", "collector_number": "1",
             "required_minimum_finishes": "reverse", "extra_observed_finishes_requiring_review": ""},
        ]
        coverage.write_json(self.snapshot / "finish-minimums.json", coverage.minimum_table(self.ledger, set()))

    def fetch(self, url, limit=None):
        if url == coverage.MARKER:
            return b"2026-11-10T20:00:00Z"
        return json.dumps(self.fixture[url.rsplit("/", 1)[-1]]).encode()

    def report(self):
        return coverage.report(self.root, "sample", 55, self.fetch)

    def reviewed(self):
        result = self.report()
        citation = "https://example.com/retail-evidence"
        result["resolutions"] = {
            "sample-002": {"finishes": ["holo"], "citation": citation, "reason": "Retail evidence confirms the holo print."},
            "sample-003": {"finishes": ["holo"], "citation": citation, "reason": "Retail evidence confirms the unmatched number."},
            "market:99": {"exclude": True, "citation": citation, "reason": "This is a numbered product from another set."},
        }
        return result

    def test_report_matches_numbers_and_preserves_named_parallels(self):
        result = self.report()
        self.assertEqual(result["resolutions"], {})
        self.assertEqual({key: card["status"] for key, card in result["cards"].items()}, {
            "sample-001": "agree", "sample-002": "conflict", "sample-003": "unmatched",
            "tcgplayer:14": "agree", "market:99": "unmatched",
        })
        self.assertEqual(result["cards"]["tcgplayer:14"]["market"], ["pokeBall"])
        self.assertEqual(result["cards"]["sample-002"]["market"], ["holo"])
        self.assertTrue(result["cards"]["sample-002"]["normalNeedsReview"])
        self.assertEqual(coverage.read_json(self.evidence), result)

    def test_normal_review_conflicts_even_when_market_matches_checklist(self):
        self.fixture["prices"]["results"].append({"productId": 12, "subTypeName": "Normal", "marketPrice": 1})
        card = self.report()["cards"]["sample-002"]
        self.assertEqual(card["market"], card["checklist"])
        self.assertEqual(card["status"], "conflict")

    def test_wrong_market_identity_conflicts(self):
        self.fixture["products"]["results"][0]["name"] = "Different Card - 1/4"
        comparison = self.report()["cards"]
        self.assertEqual(comparison["sample-001"]["status"], "conflict")
        self.assertEqual(comparison["market:product:11"]["status"], "unmatched")

    def test_shared_collector_number_matches_exact_identities_and_retains_foreign_product(self):
        cards = {
            "sample-1": {"name": "Snivy", "number": "001", "checklist": ["normal"]},
            "sample-1-energy": {"name": "Grass Energy", "number": "1", "checklist": ["holo"]},
        }
        products = {"1": [
            {"productId": 11, "name": "Snivy", "number": "1/4", "subtypes": ["Normal"]},
            {"productId": 12, "name": "Grass Energy", "number": "1/8", "subtypes": ["Holofoil"]},
            {"productId": 13, "name": "Unidentified", "number": "1/7", "subtypes": ["Normal"]},
        ]}
        comparison = coverage.compare(cards, {}, products)
        self.assertEqual(comparison["sample-1"]["status"], "agree")
        self.assertEqual(comparison["sample-1-energy"]["status"], "agree")
        self.assertEqual(comparison["sample-1-energy"]["market"], ["holo"])
        self.assertEqual(comparison["market:product:13"]["products"], [products["1"][2]])
        self.assertEqual(comparison["market:product:13"]["status"], "unmatched")

        cards["other-1"] = dict(cards["sample-1"])
        comparison = coverage.compare(cards, {}, products)
        self.assertEqual(comparison["sample-1"]["status"], "conflict")
        self.assertEqual(comparison["other-1"]["status"], "conflict")
        self.assertEqual(comparison["market:product:11"]["status"], "unmatched")

    def test_offline_replay_uses_exact_source_bytes_without_mutating_evidence(self):
        original = self.report()
        market = self.root / "market"
        market.mkdir()
        for kind in ("products", "prices"):
            (market / f"55-{kind}.json").write_bytes(self.fetch(f"https://tcgcsv.com/tcgplayer/3/55/{kind}"))
        before = self.evidence.read_bytes()
        comparison = coverage.replay(self.root, self.evidence.parent, market)["sets"]["sample"]
        self.assertEqual(comparison["cardRows"]["sample-001"]["replay"], original["cards"]["sample-001"])
        self.assertEqual(self.evidence.read_bytes(), before)
        (market / "55-prices.json").write_bytes(b"{}")
        with self.assertRaisesRegex(ValueError, "Market prices bytes differ"):
            coverage.replay(self.root, self.evidence.parent, market)

    def test_recognizes_pattern_products_with_a_number_or_trainer_character_qualifier(self):
        cases = [
            ("Amarys", "Amarys - 093/131 (Poke Ball Pattern)", "Holofoil", {"pokeBall"}),
            ("Amarys", "Amarys (Poke Ball Pattern) - 093/131", "Holofoil", {"pokeBall"}),
            ("Amarys", "Amarys - 093/132 (Poke Ball Pattern)", "Holofoil", None),
            ("Professor's Research", "Professor's Research [Professor Oak] (Poke Ball Pattern)", "Holofoil", {"pokeBall"}),
            ("Professor's Research", "Professor's Research [Jumbo] (Poke Ball Pattern)", "Holofoil", None),
            ("Erika's Oddish", "Erika's Oddish (Energy Symbol Pattern)", "Reverse Holofoil", {"energy"}),
            ("Team Rocket's Zubat", "Team Rocket's Zubat (Team Rocket)", "Reverse Holofoil", {"team-rocket"}),
            ("Snivy", "Snivy (93)", "Normal", {"normal"}),
            ("Snivy", "Snivy (94)", "Normal", None),
            ("Serperior", "Serperior (93 Secret Rare)", "Holofoil", {"holo"}),
            ("Serperior", "Serperior (93 Full Art Secret Rare)", "Holofoil", {"holo"}),
            ("Serperior", "Serperior (Full Art)", "Holofoil", {"holo"}),
            ("Serperior", "Serperior (Stamped Full Art)", "Holofoil", None),
            ("Nidoran♂", "Nidoran♀ (93)", "Normal", None),
            ("Legendary Pyroduct", "Legendary Pyroduct - 093/131 (Left)", "Holofoil", {"holo"}),
            ("Legendary Pyroduct", "Legendary Pyroduct - 094/131 (Left)", "Holofoil", None),
            ("Bubbly Water Energy", "Bubbly W Energy", "Holofoil", {"holo"}),
            ("Bubbly Water Energy", "Bubbly G Energy", "Holofoil", None),
        ]
        for card, title, lane, expected in cases:
            with self.subTest(title=title):
                self.assertEqual(coverage.product_finishes(
                    {"name": card, "number": "093"},
                    {"name": title, "number": "93/131", "subtypes": [lane]},
                ), expected)

    def test_refuses_unresolved_or_uncited_rows_without_mutating_tables(self):
        evidence = self.reviewed()
        del evidence["resolutions"]["sample-003"]["citation"]
        del evidence["resolutions"]["market:99"]
        coverage.write_json(self.evidence, evidence)
        path = self.snapshot / "finish-minimums.json"
        before = path.read_bytes()
        with self.assertRaisesRegex(ValueError, "2 unresolved cards: sample-003, market:99"):
            coverage.certify(self.root, "sample")
        self.assertEqual(coverage.read_json(self.snapshot / "finish-coverage.json")["sets"], {})
        self.assertEqual(path.read_bytes(), before)

    def test_cited_resolutions_certify_whole_set_and_retire_only_its_minimums(self):
        coverage.write_json(self.publisher, {"sets": [{"additionalVariants": [
            {"providerCardID": "sample-003", "variantID": "jumbo"},
        ]}]})
        coverage.write_json(self.evidence, self.reviewed())
        with patch.object(coverage, "ledger", return_value=self.ledger):
            self.assertEqual(coverage.certify(self.root, "sample"), 4)
            self.assertEqual(coverage.certify(self.root, "sample"), 4)
        result = coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"]
        self.assertEqual(result["evidence"], self.evidence.relative_to(self.root).as_posix())
        self.assertEqual(result["cards"], {"sample-001": ["normal", "reverse"], "sample-002": ["holo"],
                                          "sample-003": ["holo"], "tcgplayer:14": ["pokeBall"]})
        self.assertEqual(set(coverage.read_json(self.snapshot / "finish-minimums.json")), {"other-1"})

    def test_report_edits_cannot_remove_an_unmatched_product_or_clear_a_conflict(self):
        evidence = self.reviewed()
        removed = deepcopy(evidence)
        del removed["cards"]["market:99"]
        del removed["resolutions"]["market:99"]
        relabeled = deepcopy(evidence)
        relabeled["cards"]["sample-002"]["status"] = "agree"
        del relabeled["resolutions"]["sample-002"]
        for edited in (removed, relabeled):
            coverage.write_json(self.evidence, edited)
            with self.assertRaisesRegex(ValueError, "Report differs from the captured comparison"):
                coverage.certify(self.root, "sample")
        self.assertEqual(coverage.read_json(self.snapshot / "finish-coverage.json")["sets"], {})

    def test_certification_requires_a_retained_comparison_receipt(self):
        coverage.write_json(self.evidence, self.reviewed())
        (self.root / coverage.CAPTURES / "sample.json").unlink()
        with self.assertRaisesRegex(ValueError, "Missing captured comparison receipt"):
            coverage.certify(self.root, "sample")

    def test_cited_resolution_rejects_unknown_and_nonstandard_finish_ids(self):
        evidence = self.reviewed()
        for finish in ("holoo", "jumbo", "firstEdition", "foil", "pokemonStamp|holo|set-loog|"):
            with self.subTest(finish=finish):
                evidence["resolutions"]["sample-003"]["finishes"] = [finish]
                coverage.write_json(self.evidence, evidence)
                with self.assertRaisesRegex(ValueError, "sample-003 has unsupported standard Pokémon finishes"):
                    coverage.certify(self.root, "sample")
        self.assertEqual(coverage.read_json(self.snapshot / "finish-coverage.json")["sets"], {})

    def test_signed_standard_membership_must_be_in_the_certificate(self):
        coverage.write_json(self.publisher, {"sets": [{"additionalVariants": [
            {"providerCardID": "sample-003", "variantID": "cosmos"},
        ]}]})
        evidence = self.reviewed()
        self.assertEqual(evidence["cards"]["sample-003"]["signedStandardFinishes"], ["cosmos"])
        coverage.write_json(self.evidence, evidence)
        with self.assertRaisesRegex(ValueError, "sample-003 omits signed standard finishes: cosmos"):
            coverage.certify(self.root, "sample")

        evidence["resolutions"]["sample-003"]["finishes"].append("cosmos")
        coverage.write_json(self.evidence, evidence)
        with patch.object(coverage, "ledger", return_value=self.ledger):
            self.assertEqual(coverage.certify(self.root, "sample"), 4)
        result = coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"]
        self.assertEqual(result["cards"]["sample-003"], ["cosmos", "holo"])

    def test_refuses_report_for_changed_snapshot(self):
        coverage.write_json(self.evidence, self.reviewed())
        self.slots.write_bytes(self.slots.read_bytes() + b"\n")
        with self.assertRaisesRegex(ValueError, "checklist bytes"):
            coverage.certify(self.root, "sample")

    def test_signed_normal_review_must_be_cleared_before_certifying(self):
        coverage.write_json(self.publisher, {"sets": [{"additionalVariants": [
            {"providerCardID": "sample-001", "normalNeedsReview": True},
        ]}]})
        evidence = self.reviewed()
        self.assertEqual(evidence["cards"]["sample-001"]["status"], "conflict")
        self.assertTrue(evidence["cards"]["sample-001"]["signedNormalNeedsReview"])
        coverage.write_json(self.evidence, evidence)
        with self.assertRaisesRegex(ValueError, "Publisher input still marks Normal for review: sample-001"):
            coverage.certify(self.root, "sample")


if __name__ == "__main__":
    unittest.main()
