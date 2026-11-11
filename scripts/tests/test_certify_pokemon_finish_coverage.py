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
        self.capture = coverage.capture_directory(self.root, "sample", coverage.FIRST_REVISION)
        self.evidence = self.capture / "report.json"
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
        self.historical_path = self.snapshot / "legacy-finish-evidence.json"
        self.historical = {"schemaVersion": 1, "cards": {}, "holoAggregates": {}, "reverseAggregates": {}}
        coverage.write_json(self.historical_path, self.historical)
        self.enterContext(patch.object(coverage, "ledger", side_effect=lambda: self.ledger))
        self.enterContext(patch.object(coverage, "stamp", return_value="2026-11-10T20:00:00Z"))

    def fetch(self, url, limit=None):
        if url == coverage.MARKER:
            return b"2026-11-10T20:00:00Z"
        return json.dumps(self.fixture[url.rsplit("/", 1)[-1]]).encode()

    def report(self, revision=None):
        return coverage.report(self.root, "sample", 55, self.fetch, revision=revision)

    def reviewed(self, revision=None):
        result = self.report(revision)
        citation = "https://example.com/retail-evidence"
        result["resolutions"] = {
            "sample-002": {"finishes": ["holo"], "normalReview": "exclude", "citation": citation,
                           "reason": "Retail evidence confirms the holo print."},
            "sample-003": {"finishes": ["holo"], "citation": citation, "reason": "Retail evidence confirms the unmatched number."},
            "market:99": {"exclude": True, "citation": citation, "reason": "This is a numbered product from another set."},
        }
        return result

    def set_signed(self, card_id, **evidence):
        card = next(slot for slot in self.fixture["snapshot"] if slot["providerID"] == card_id)
        coverage.write_json(self.publisher, {"sets": [{"providerSetID": "sample", "additionalVariants": [
            {"providerCardID": card_id, "canonicalName": card["name"], **evidence},
        ]}]})

    def historical_holo(self):
        self.historical["cards"]["sample-001"] = {
            "setID": "sample", "number": "001", "minimum": ["holo"], "normalNeedsReview": True,
        }
        coverage.write_json(self.historical_path, self.historical)

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
        before = self.evidence.read_bytes()
        comparison = coverage.replay(self.root, self.root / coverage.EVIDENCE)["sets"]["sample@initial"]
        self.assertEqual(comparison["cardRows"]["sample-001"]["replay"], original["cards"]["sample-001"])
        self.assertEqual(self.evidence.read_bytes(), before)
        (self.capture / "prices.json").write_bytes(b"{}")
        with self.assertRaisesRegex(ValueError, "Market prices bytes differ"):
            coverage.replay(self.root, self.capture)

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
        self.set_signed("sample-003", variantID="jumbo")
        coverage.write_json(self.evidence, self.reviewed())
        path = self.snapshot / "finish-coverage.json"
        self.assertEqual(coverage.certify(self.root, "sample"), 4)
        first = path.read_bytes()
        self.assertEqual(coverage.certify(self.root, "sample"), 4)
        self.assertEqual(first, path.read_bytes())
        result = json.loads(first)["sets"]["sample"]
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
        (self.capture / "receipt.json").unlink()
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
        self.set_signed("sample-003", canonicalName="Éxample-Three", variantID="cosmos")
        evidence = self.reviewed()
        self.assertEqual(evidence["cards"]["sample-003"]["signedStandardFinishes"], ["cosmos"])
        coverage.write_json(self.evidence, evidence)
        with self.assertRaisesRegex(ValueError, "sample-003 omits signed standard finishes: cosmos"):
            coverage.certify(self.root, "sample")

        evidence["resolutions"]["sample-003"]["finishes"].append("cosmos")
        coverage.write_json(self.evidence, evidence)
        self.assertEqual(coverage.certify(self.root, "sample"), 4)
        result = coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"]
        self.assertEqual(result["cards"]["sample-003"], ["cosmos", "holo"])

    def test_mismatched_signed_name_blocks_capture_and_certification(self):
        mismatch = "Signed name 'Different Card' differs from checklist name 'Example Three' for sample-003"
        self.set_signed("sample-003", canonicalName="Different Card", normalNeedsReview=True)
        with self.assertRaisesRegex(ValueError, mismatch):
            self.report()
        self.assertFalse(self.capture.exists())

        self.set_signed("sample-003", variantID="cosmos")
        coverage.write_json(self.evidence, self.reviewed())
        self.set_signed("sample-003", canonicalName="Different Card", variantID="cosmos")
        with self.assertRaisesRegex(ValueError, mismatch):
            coverage.certify(self.root, "sample")
        self.assertEqual(coverage.read_json(self.snapshot / "finish-coverage.json")["sets"], {})

    def test_refuses_report_for_changed_snapshot(self):
        coverage.write_json(self.evidence, self.reviewed())
        self.slots.write_bytes(self.slots.read_bytes() + b"\n")
        with self.assertRaisesRegex(ValueError, "checklist bytes"):
            coverage.certify(self.root, "sample")

    def test_certification_checks_retained_market_bytes(self):
        coverage.write_json(self.evidence, self.reviewed())
        prices = self.capture / "prices.json"
        prices.write_bytes(prices.read_bytes() + b"\n")
        with self.assertRaisesRegex(ValueError, "Market prices bytes differ"):
            coverage.certify(self.root, "sample")

    def test_certificate_cannot_override_an_unaudited_runtime_minimum(self):
        coverage.write_json(self.evidence, self.reviewed())
        path = self.snapshot / "finish-minimums.json"
        projection = coverage.read_json(path)
        projection["sample-002"]["minimum"].append("reverse")
        coverage.write_json(path, projection)
        with self.assertRaisesRegex(ValueError, "Bundled finish minimums differ from the audited source"):
            coverage.certify(self.root, "sample")

    def test_signed_normal_review_must_be_cleared_before_capture(self):
        self.set_signed("sample-001", normalNeedsReview=True)
        with self.assertRaisesRegex(ValueError, "Publisher input still marks Normal for review: sample-001"):
            self.report()
        self.assertFalse(self.capture.exists())

        self.set_signed("sample-001", normalNeedsReview=False)
        coverage.write_json(self.evidence, self.reviewed())
        self.set_signed("sample-001", normalNeedsReview=True)
        with self.assertRaisesRegex(ValueError, "Finish evidence changed"):
            coverage.certify(self.root, "sample")

    def test_ledger_only_membership_requires_specific_supersession_to_omit(self):
        self.historical_holo()
        reviewed = self.reviewed()
        row = reviewed["cards"]["sample-001"]
        self.assertEqual(row["legacyMinimum"], ["holo"])
        self.assertEqual(row["required"], ["holo", "reverse"])
        self.assertEqual(row["status"], "conflict")
        decision = {"finishes": ["normal", "reverse"], "normalReview": "include",
                    "citation": "https://example.com/retail-evidence", "reason": "Confirmed the two listed products."}
        reviewed["resolutions"]["sample-001"] = decision
        coverage.write_json(self.evidence, reviewed)
        with self.assertRaisesRegex(ValueError, "omits reviewed ledger finishes.*legacy-finish-evidence/holo"):
            coverage.certify(self.root, "sample")

        decision["supersedes"] = [
            {"source": "finish-minimums", "finish": "holo", "citation": decision["citation"], "reason": "Duplicate listing."},
        ]
        coverage.write_json(self.evidence, reviewed)
        with self.assertRaisesRegex(ValueError, "without matching omitted evidence"):
            coverage.certify(self.root, "sample")
        decision["supersedes"][0]["source"] = "legacy-finish-evidence"
        coverage.write_json(self.evidence, reviewed)
        self.assertEqual(coverage.certify(self.root, "sample"), 4)

    def test_historical_normal_needs_an_explicit_decision_and_can_certify(self):
        self.historical_holo()
        self.set_signed("sample-003", variantID="cosmos")
        reviewed = self.reviewed()
        decision = {"finishes": ["holo", "normal", "reverse"],
                    "citation": "https://example.com/retail-evidence", "reason": "Physical copies confirm all three finishes."}
        reviewed["resolutions"]["sample-001"] = decision
        reviewed["resolutions"]["sample-003"]["finishes"].append("cosmos")
        coverage.write_json(self.evidence, reviewed)
        with self.assertRaisesRegex(ValueError, "sample-001 needs a cited Normal review decision of include"):
            coverage.certify(self.root, "sample")
        decision["normalReview"] = "include"
        coverage.write_json(self.evidence, reviewed)
        self.assertEqual(coverage.certify(self.root, "sample"), 4)
        self.assertEqual(coverage.read_json(self.snapshot / "finish-coverage.json"), self.fixture["certificate"])

    def test_historical_normal_review_blocks_automatic_acceptance_on_market_agreement(self):
        self.historical_holo()
        self.fixture["prices"]["results"][0]["subTypeName"] = "Holofoil"
        reviewed = self.reviewed()
        row = reviewed["cards"]["sample-001"]
        self.assertEqual(row["market"], row["required"])
        self.assertEqual(row["status"], "conflict")
        coverage.write_json(self.evidence, reviewed)
        with self.assertRaisesRegex(ValueError, "1 unresolved cards: sample-001"):
            coverage.certify(self.root, "sample")

    def test_every_bound_finish_input_invalidates_receipt_independently(self):
        coverage.write_json(self.evidence, self.reviewed())
        output = self.snapshot / "finish-coverage.json"
        self.assertEqual(coverage.certify(self.root, "sample"), 4)
        certified = output.read_bytes()
        vocabulary = self.snapshot / "finish-coverage-variants.json"
        for path, mutate in [
            (self.historical_path, self.historical_holo),
            (self.publisher, lambda: self.set_signed("sample-003", variantID="cosmos")),
            (vocabulary, lambda: coverage.write_json(vocabulary, ["holo", "normal", "reverse"])),
        ]:
            with self.subTest(path=path.name):
                before = path.read_bytes()
                mutate()
                with self.assertRaisesRegex(ValueError, "Finish evidence changed"):
                    coverage.certify(self.root, "sample")
                self.assertEqual(output.read_bytes(), certified)
                path.write_bytes(before)
        self.ledger[0]["required_minimum_finishes"] = "holo; reverse"
        with self.assertRaisesRegex(ValueError, "Finish evidence changed"):
            coverage.certify(self.root, "sample")
        self.assertEqual(output.read_bytes(), certified)

    def test_recapture_preserves_review_and_replays_after_evidence_and_checklist_change(self):
        coverage.write_json(self.evidence, self.reviewed())
        self.assertEqual(coverage.certify(self.root, "sample"), 4)
        before = {path: path.read_bytes() for path in self.capture.rglob("*") if path.is_file()}
        self.historical_holo()
        self.slots.write_bytes(self.slots.read_bytes() + b"\n")
        with self.assertRaisesRegex(ValueError, "choose a new --revision"):
            self.report()
        second = self.reviewed("recheck")
        self.assertNotEqual(second["finishEvidenceSHA256"], coverage.read_json(self.evidence)["finishEvidenceSHA256"])
        second["resolutions"]["sample-001"] = {
            "finishes": ["holo", "reverse"], "normalReview": "exclude",
            "citation": "https://example.com/retail-evidence", "reason": "Physical copies confirm both foil finishes.",
        }
        second_path = coverage.capture_directory(self.root, "sample", "recheck") / "report.json"
        coverage.write_json(second_path, second)
        with self.assertRaisesRegex(ValueError, "choose a new --revision"):
            self.report("recheck")
        self.assertEqual(coverage.certify(self.root, "sample", revision="recheck"), 4)
        replayed = coverage.replay(self.root, self.root / coverage.EVIDENCE)["sets"]
        self.assertEqual(set(replayed), {"sample@initial", "sample@recheck"})
        first_row = replayed["sample@initial"]["cardRows"]["sample-001"]
        self.assertEqual(first_row["baseline"], "agree")
        self.assertEqual(first_row["replay"]["status"], "conflict")
        for path, raw in before.items():
            self.assertEqual(path.read_bytes(), raw)

    def test_legacy_reports_still_replay_with_retained_market_bytes(self):
        original = self.report()
        legacy = self.root / "legacy"
        original["schemaVersion"] = 1
        del original["captureRevision"]
        del original["finishEvidenceSHA256"]
        coverage.write_json(legacy / "sample.json", original)
        for kind in ("products", "prices"):
            (legacy / f"55-{kind}.json").write_bytes((self.capture / f"{kind}.json").read_bytes())
        # Replay takes the directory of reports separately from the old market cache.
        reports = legacy / "reports"
        reports.mkdir()
        (legacy / "sample.json").rename(reports / "sample.json")
        self.historical_holo()
        self.slots.write_bytes(self.slots.read_bytes() + b"\n")
        with self.assertRaisesRegex(ValueError, "Bundled checklist bytes differ"):
            coverage.replay(self.root, reports, legacy)
        replay = coverage.replay(self.root, reports, legacy, legacy_snapshot=self.capture / "checklist")
        row = replay["sets"]["sample"]["cardRows"]["sample-001"]
        self.assertEqual(row["baseline"], "agree")
        self.assertEqual(row["replay"]["legacyMinimum"], ["holo"])

    def test_aggregate_projection_requires_path_and_matching_resource_bytes(self):
        for index, finish in [(2, "cosmos"), (0, "energy"), (0, "pokeBall")]:
            row = deepcopy(self.fixture["snapshot"][index])
            row["masterSetVariant"]["id"] = finish
            self.fixture["snapshot"].append(row)
        coverage.write_json(self.slots, self.fixture["snapshot"])
        self.historical["holoAggregates"] = {"sample-002": ["cosmos"]}
        self.historical["reverseAggregates"] = {"sample-001": ["energy", "pokeBall"]}
        sha256 = coverage.digest(self.slots.read_bytes())
        self.historical["aggregateChecklistSources"] = {"sets/another.json": sha256}
        coverage.write_json(self.historical_path, self.historical)
        wrong_path = self.report()["cards"]["sample-002"]["checklist"]
        self.assertEqual(wrong_path, ["cosmos", "holo", "normal"])

        self.historical["aggregateChecklistSources"] = {"sets/opaque.json": sha256}
        coverage.write_json(self.historical_path, self.historical)
        pinned = self.report("pinned")["cards"]
        self.assertEqual(pinned["sample-002"]["checklist"], ["cosmos", "normal"])
        self.assertEqual(pinned["sample-001"]["checklist"], ["energy", "normal", "pokeBall"])

        self.slots.write_bytes(self.slots.read_bytes() + b"\n")
        changed = self.report("changed")["cards"]
        self.assertEqual(changed["sample-002"]["checklist"], ["cosmos", "holo", "normal"])
        self.assertEqual(changed["sample-001"]["checklist"], ["energy", "normal", "pokeBall", "reverse"])


if __name__ == "__main__":
    unittest.main()
