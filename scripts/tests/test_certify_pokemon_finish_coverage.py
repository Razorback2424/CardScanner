from copy import deepcopy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import catalog_exceptions
import certify_pokemon_finish_coverage as coverage


class PokemonNameKeyTests(unittest.TestCase):
    def test_nidoran_marketplace_abbreviations_match_checklist_symbols(self):
        self.assertEqual(coverage.name_key("Nidoran M"), coverage.name_key("Nidoran♂"))
        self.assertEqual(coverage.name_key("Nidoran F"), coverage.name_key("Nidoran♀"))
        self.assertEqual(coverage.name_key("Nidoran M (Delta Species)"), coverage.name_key("Nidoran♂ (Delta Species)"))
        self.assertNotEqual(coverage.name_key("Nidoran M"), coverage.name_key("Nidoran F"))

    def test_nidoran_normalization_leaves_other_names_alone(self):
        self.assertEqual(coverage.name_key("Nidoran Max"), "nidoran max")
        self.assertEqual(coverage.name_key("Nidorino M"), "nidorino m")
        self.assertEqual(coverage.name_key("Mew M"), "mew m")


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

    def test_alternate_collector_padding_and_finish_labels_preserve_exact_membership(self):
        card = {"name": "Trainers' Mail", "number": "92a", "checklist": ["holo", "normal"]}
        holo = {"productId": 1, "name": "Trainers' Mail - 92a/108 (Holo)",
                "number": "092A/108", "subtypes": ["Holofoil"]}
        normal = {"productId": 2, "name": "Trainers' Mail - 92a/108 (Non-Holo)",
                  "number": "092a/108", "subtypes": ["Normal"]}
        self.assertEqual(coverage.local_number(holo["number"]), "92a")
        self.assertEqual(coverage.product_finishes(card, holo), {"holo"})
        self.assertEqual(coverage.product_finishes(card, normal), {"normal"})
        self.assertIsNone(coverage.product_finishes(card, dict(holo, number="092b/108")))
        self.assertIsNone(coverage.product_finishes(card, dict(holo, subtypes=["Normal"])))
        self.assertIsNone(coverage.product_finishes(card, dict(holo, name="Trainers' Mail - 92a/122 (Holo)")))

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

    def test_edition_union_can_be_reviewed_but_cannot_become_an_exact_certificate(self):
        manifest_path = self.snapshot / "manifest.json"
        manifest = coverage.read_json(manifest_path)
        first_edition = manifest["entries"][0]
        first_edition["set"]["catalogID"] = {"providerID": "sample", "pokemonPrintRun": "firstEdition"}
        unlimited = deepcopy(first_edition)
        unlimited["set"]["catalogID"]["pokemonPrintRun"] = "unlimited"
        unlimited["resource"] = "sets/unlimited.json"
        unlimited_slots = [slot for slot in self.fixture["snapshot"] if slot["providerID"] != "sample-002"]
        coverage.write_json(self.snapshot / unlimited["resource"], unlimited_slots)
        manifest["entries"].append(unlimited)
        coverage.write_json(manifest_path, manifest)

        evidence = self.reviewed()
        self.assertIn("holo", evidence["cards"]["sample-002"]["checklist"])
        coverage.write_json(self.evidence, evidence)
        minimums = self.snapshot / "finish-minimums.json"
        before = minimums.read_bytes()

        with self.assertRaisesRegex(ValueError, "multiple print runs"):
            coverage.certify(self.root, "sample")

        self.assertEqual(coverage.read_json(self.snapshot / "finish-coverage.json")["sets"], {})
        self.assertEqual(minimums.read_bytes(), before)

    def test_exact_certificate_cannot_skip_a_separately_reviewed_artwork_printing(self):
        coverage.write_json(self.evidence, self.reviewed())
        coverage.write_json(self.snapshot / "reviewed-artwork-printings.json", {
            "schemaVersion": 1, "families": [{"providerSetID": "sample"}],
        })
        with self.assertRaisesRegex(ValueError, "reviewed artwork printings outside the captured checklist"):
            coverage.certify(self.root, "sample")
        self.assertEqual(coverage.read_json(self.snapshot / "finish-coverage.json")["sets"], {})

    def test_reviewed_unnumbered_energy_stays_outside_and_no_longer_blocks_the_set(self):
        coverage.write_json(self.evidence, self.reviewed())
        energy = self.snapshot / "reviewed-unnumbered-energy.json"
        coverage.write_json(energy, {"schemaVersion": 1, "families": [{"providerSetID": "sample", "cards": [
            {"providerID": "tcgplayer:900", "name": "Grass Energy", "finishProducts": {"normal": 900}}]}]})
        self.assertEqual(coverage.certify(self.root, "sample"), 4)
        cards = coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"]["cards"]
        self.assertNotIn("tcgplayer:900", cards)

    def test_certificate_refuses_a_card_that_is_also_reviewed_unnumbered_energy(self):
        coverage.write_json(self.evidence, self.reviewed())
        coverage.write_json(self.snapshot / "reviewed-unnumbered-energy.json", {"schemaVersion": 1, "families": [
            {"providerSetID": "sample", "cards": [{"providerID": "tcgplayer:14", "name": "Energy"}]}]})
        with self.assertRaisesRegex(ValueError, "would include reviewed unnumbered Energy"):
            coverage.certify(self.root, "sample")
        self.assertEqual(coverage.read_json(self.snapshot / "finish-coverage.json")["sets"], {})

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


class FakeMarket:
    """An offline stand-in for SnapshotMarket keyed by group."""

    def __init__(self, groups, documents):
        self.build = "2026-11-10T20:00:00Z"
        self.directory = Path("fake-capture")
        self.groups = groups
        self.documents = documents

    def fetch(self, url, limit=None):
        if url == coverage.MARKER:
            return self.build.encode()
        group, resource = url.rsplit("/", 2)[-2:]
        return json.dumps(self.documents[int(group)][resource]).encode()

    def products(self, group_id):
        return coverage.numbered_products(self.fetch(f"{coverage.BASE}/{group_id}/products"),
                                          self.fetch(f"{coverage.BASE}/{group_id}/prices"), group_id)


class PokemonFinishCoverageBatchTests(unittest.TestCase):
    setUp = PokemonFinishCoverageTests.setUp
    fetch = PokemonFinishCoverageTests.fetch

    def market(self, extra=None):
        extra = extra or {}
        documents = {55: {"products": self.fixture["products"], "prices": self.fixture["prices"]}, **extra}
        groups = [{"groupId": 55, "name": "Sample Set", "categoryId": 3}]
        groups += [{"groupId": gid, "name": names["name"], "categoryId": 3}
                   for gid, names in extra.items()]
        return FakeMarket(groups, {gid: {k: v for k, v in docs.items() if k != "name"} for gid, docs in documents.items()})

    def batch(self, market=None, revision=None):
        path = self.root / "ledger.json"
        result = coverage.batch(self.root, None, path, certify_revision=revision, fetch_market=market or self.market())
        return result, catalog_exceptions.read_ledger(path)

    def keep_only(self, *card_ids, products=(11, 14)):
        self.fixture["snapshot"] = [slot for slot in self.fixture["snapshot"] if slot["providerID"] in card_ids]
        coverage.write_json(self.slots, self.fixture["snapshot"])
        self.fixture["products"]["results"] = [row for row in self.fixture["products"]["results"]
                                               if row["productId"] in products]
        self.fixture["prices"]["results"] = [row for row in self.fixture["prices"]["results"]
                                             if row["productId"] in products]

    def test_report_all_ledgers_each_pending_card_with_one_reason_and_writes_nothing(self):
        coverage_path = self.snapshot / "finish-coverage.json"
        before = coverage_path.read_bytes()
        result, rows = self.batch()
        self.assertEqual(result["statuses"], {"sample": "pending"})
        self.assertEqual({row["identity"]: row["reason"] for row in rows}, {
            "sample-002": "normalNeedsReview", "sample-003": "unmatchedMarket",
            "sample/market:99": "unmatchedMarketProduct",
        })
        self.assertTrue(all(row["game"] == "pokemon" and row["set"] == "sample" for row in rows))
        self.assertEqual(coverage_path.read_bytes(), before)
        self.assertFalse(self.capture.parent.exists())

    def test_certify_all_uses_unchanged_single_set_certification_for_fully_agreeing_sets(self):
        self.keep_only("sample-001", "tcgplayer:14")
        result, rows = self.batch(revision="batch")
        self.assertEqual(rows, [])
        self.assertEqual(result["newlyCertified"], ["sample"])
        certificate = coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"]
        self.assertEqual(certificate["cards"], {"sample-001": ["normal", "reverse"], "tcgplayer:14": ["pokeBall"]})
        self.assertEqual(certificate["tcgplayerGroupID"], 55)
        capture = coverage.capture_directory(self.root, "sample", "batch")
        self.assertEqual(coverage.read_json(capture / "report.json")["resolutions"], {})
        # The certificate replays through the ordinary single-set path, and a rerun is a no-op.
        self.assertEqual(coverage.certify(self.root, "sample", revision="batch"), 2)
        again, _ = self.batch(revision="batch")
        self.assertEqual(again["statuses"], {"sample": "certified"})
        self.assertEqual(again["newlyCertified"], [])

    def test_agreement_beyond_the_bundled_checklist_slots_is_certified_and_recorded(self):
        self.keep_only("sample-001", "tcgplayer:14")
        self.fixture["snapshot"] = [slot for slot in self.fixture["snapshot"]
                                    if slot["masterSetVariant"]["id"] != "reverse"]
        coverage.write_json(self.slots, self.fixture["snapshot"])
        self.ledger.append({"provider_id": "sample-001", "set_id": "sample", "collector_number": "001",
                            "required_minimum_finishes": "reverse", "extra_observed_finishes_requiring_review": ""})
        coverage.write_json(self.snapshot / "finish-minimums.json", coverage.minimum_table(self.ledger, set()))
        result, rows = self.batch(revision="batch")
        self.assertEqual(rows, [])
        certificate = coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"]
        self.assertEqual(certificate["cards"]["sample-001"], ["normal", "reverse"])
        # The app's consistency test checks this difference against the evidence report.
        self.assertEqual(certificate["slotChanges"], {"sample-001": {"added": ["reverse"]}})

    def test_certificates_matching_their_slots_record_no_changes(self):
        self.keep_only("sample-001", "tcgplayer:14")
        self.batch(revision="batch")
        self.assertNotIn("slotChanges", coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"])

    def test_finish_differences_split_into_targetable_reasons(self):
        row = {"name": "A", "number": "1", "products": [{"productId": 1}], "normalNeedsReview": False,
               "status": "conflict"}
        cases = [(["normal"], ["normal", "reverse"], "marketExtraLane"),
                 (["normal", "reverse"], ["normal"], "standardFinishNotListed"),
                 (["cosmos", "holo"], ["holo"], "parallelFinishNotListed"),
                 (["normal"], ["holo"], "finishConflict"),
                 (["holo"], ["holo"], None)]
        for required, market, reason in cases:
            with self.subTest(required=required, market=market):
                self.assertEqual(coverage.card_reason("a-1", dict(row, required=required, market=market))[0], reason)
        self.assertEqual(coverage.card_reason("a-1", dict(row, required=["holo"], market=["holo"], products=[]))[0],
                         "unmatchedMarket")

    def test_set_level_blockers_replace_the_comparison(self):
        coverage.write_json(self.snapshot / "manifest.json", {"entries": [
            {"providerID": "sample", "resource": "sets/opaque.json",
             "set": {"name": "Sample Set", "catalogID": {"pokemonPrintRun": "firstEdition"}}},
            {"providerID": "sample", "resource": "sets/opaque.json",
             "set": {"name": "Sample Set", "catalogID": {"pokemonPrintRun": "unlimited"}}},
        ]})
        _, rows = self.batch()
        self.assertEqual({row["reason"] for row in rows}, {"multiplePrintRuns"})
        self.assertIn("set:sample", {row["identity"] for row in rows})
        self.assertNotIn("sample/market:99", {row["identity"] for row in rows})

        unlinked = FakeMarket([{"groupId": 55, "name": "Another Set", "categoryId": 3}], {})
        _, rows = self.batch(unlinked)
        self.assertEqual({row["reason"] for row in rows}, {"noMarketGroup", "multiplePrintRuns"})

    def test_reviewed_group_links_replace_automatic_links_and_pin_the_group_name(self):
        entries = [{"providerID": "sample", "set": {"name": "Sample Set", "code": "SMP"}}]
        groups = [{"groupId": 55, "name": "Sample Set"}, {"groupId": 56, "name": "SMP Trainer Kit", "abbreviation": "SMP"},
                  {"groupId": 57, "name": "Prefixed - Sample"}]
        self.assertEqual(coverage.group_links(groups, entries)["sample"], {55, 56})
        reviewed = {"links": [{"setID": "sample", "groupID": 55, "groupName": "Sample Set", "reason": "Exact name."}]}
        self.assertEqual(coverage.group_links(groups, entries, reviewed)["sample"], {55})
        with self.assertRaisesRegex(ValueError, "no longer named"):
            coverage.group_links(groups, entries, {"links": [dict(reviewed["links"][0], groupName="Renamed")]})
        with self.assertRaisesRegex(ValueError, "duplicate"):
            coverage.group_links(groups, entries, {"links": reviewed["links"] * 2})
        with self.assertRaisesRegex(ValueError, "Invalid"):
            coverage.group_links(groups, entries, {"links": [dict(reviewed["links"][0], reason="")]})

    def conventions(self, **conventions):
        coverage.write_json(self.root / coverage.Conventions.PATH, {"schemaVersion": 1, **conventions})

    def convention(self, **fields):
        return {"id": "test", "decision": "Test convention.", "sources": ["https://example.com"], **fields}

    def lane_prices(self, product_id, lanes):
        self.fixture["prices"]["results"] = [row for row in self.fixture["prices"]["results"]
                                             if row["productId"] != product_id]
        self.fixture["prices"]["results"] += [{"productId": product_id, "subTypeName": lane, "marketPrice": price}
                                              for lane, price in lanes.items()]

    def test_reverse_lane_convention_needs_a_sold_reverse_on_the_cards_own_product(self):
        self.keep_only("sample-001", "tcgplayer:14")
        self.fixture["snapshot"] = [slot for slot in self.fixture["snapshot"]
                                    if slot["masterSetVariant"]["id"] != "reverse"]
        coverage.write_json(self.slots, self.fixture["snapshot"])
        for price, certified in ((None, False), (0, False), (0.25, True)):
            with self.subTest(price=price):
                self.setUp()
                self.keep_only("sample-001", "tcgplayer:14")
                self.fixture["snapshot"] = [slot for slot in self.fixture["snapshot"]
                                            if slot["masterSetVariant"]["id"] != "reverse"]
                coverage.write_json(self.slots, self.fixture["snapshot"])
                self.lane_prices(11, {"Normal": 0.5, "Reverse Holofoil": price})
                self.conventions(reverseLane=self.convention(excludeSetIDs=[]))
                result, rows = self.batch(revision="batch")
                if not certified:
                    self.assertEqual([(row["identity"], row["reason"]) for row in rows],
                                     [("sample-001", "marketExtraLane")])
                    continue
                self.assertEqual(rows, [])
                certificate = coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"]
                self.assertEqual(certificate["cards"]["sample-001"], ["normal", "reverse"])
                self.assertEqual(certificate["slotChanges"]["sample-001"], {"added": ["reverse"]})
        self.setUp()
        self.keep_only("sample-001", "tcgplayer:14")
        self.fixture["snapshot"] = [slot for slot in self.fixture["snapshot"]
                                    if slot["masterSetVariant"]["id"] != "reverse"]
        coverage.write_json(self.slots, self.fixture["snapshot"])
        self.conventions(reverseLane=self.convention(excludeSetIDs=["sample"]))
        _, rows = self.batch()
        self.assertEqual([row["reason"] for row in rows], ["marketExtraLane"], "An excluded set keeps the row open")

    def test_normal_placeholder_convention_excludes_an_unsold_historical_normal(self):
        self.keep_only("sample-001", "tcgplayer:14")
        self.historical["cards"] = {"sample-001": {"setID": "sample", "number": "001", "minimum": ["reverse"],
                                                   "normalNeedsReview": True}}
        coverage.write_json(self.historical_path, self.historical)
        self.lane_prices(11, {"Reverse Holofoil": 1.0})
        _, rows = self.batch()
        self.assertEqual([row["reason"] for row in rows], ["normalNeedsReview"], "No convention, no decision")
        self.conventions(historicalNormalPlaceholder=self.convention(setIDs=["sample"]))
        result, rows = self.batch(revision="batch")
        self.assertEqual(rows, [])
        certificate = coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"]
        self.assertEqual(certificate["cards"]["sample-001"], ["reverse"])
        self.assertEqual(certificate["slotChanges"]["sample-001"], {"removed": ["normal"]})
        report_value = coverage.read_json(coverage.capture_directory(self.root, "sample", "batch") / "report.json")
        self.assertEqual(report_value["resolutions"]["sample-001"]["normalReview"], "exclude")

    def test_normal_placeholder_convention_keeps_a_sold_normal_open(self):
        self.keep_only("sample-001", "tcgplayer:14")
        self.historical["cards"] = {"sample-001": {"setID": "sample", "number": "001", "minimum": ["reverse"],
                                                   "normalNeedsReview": True}}
        coverage.write_json(self.historical_path, self.historical)
        self.conventions(historicalNormalPlaceholder=self.convention(setIDs=["sample"]))
        _, rows = self.batch()
        self.assertEqual([(row["identity"], row["reason"]) for row in rows], [("sample-001", "normalNeedsReview")])

    def test_treatment_alias_convention_keeps_only_the_priced_holo_printing(self):
        self.keep_only("sample-001", "tcgplayer:14")
        holo = dict(self.fixture["snapshot"][0], providerID="sample-005", collectorNumber="005", name="Example Five",
                    masterSetVariant={"id": "holo"})
        self.fixture["snapshot"] += [holo, dict(holo, masterSetVariant={"id": "rainbow"})]
        coverage.write_json(self.slots, self.fixture["snapshot"])
        self.fixture["products"]["results"].append({"productId": 50, "categoryId": 3, "groupId": 55,
            "name": "Example Five (Secret)", "extendedData": [{"name": "Number", "value": "005/004"}]})
        self.lane_prices(50, {"Holofoil": 9.0})
        _, rows = self.batch()
        self.assertEqual([(row["identity"], row["reason"]) for row in rows], [("sample-005", "parallelFinishNotListed")])
        self.conventions(treatmentAliases=self.convention(finishes=["gold", "rainbow"], setIDs=["sample"],
                                                          exceptCardIDs=["sample-005"]))
        _, rows = self.batch()
        self.assertEqual([row["identity"] for row in rows], ["sample-005"], "An excepted card stays open")
        self.conventions(treatmentAliases=self.convention(finishes=["gold", "rainbow"], setIDs=["sample"],
                                                          exceptCardIDs=[]))
        _, rows = self.batch(revision="batch")
        self.assertEqual(rows, [])
        certificate = coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"]
        self.assertEqual(certificate["cards"]["sample-005"], ["holo"])
        self.assertEqual(certificate["slotChanges"]["sample-005"], {"removed": ["rainbow"]})

    def test_ex_set_logo_reverse_convention_reads_the_reverse_lane_as_the_stamped_reverse(self):
        self.keep_only("sample-001", "tcgplayer:14")
        stamp = "pokemonStamp|normal|set-logo|"
        self.fixture["snapshot"] = [dict(slot, masterSetVariant={"id": stamp})
                                    if slot["masterSetVariant"]["id"] == "reverse" else slot
                                    for slot in self.fixture["snapshot"]]
        coverage.write_json(self.slots, self.fixture["snapshot"])
        _, rows = self.batch()
        self.assertEqual([row["reason"] for row in rows], ["finishConflict"])
        self.conventions(setLogoReverseHolo=self.convention(setIDs=["sample"]),
                         reverseLane=self.convention(excludeSetIDs=[]))
        _, rows = self.batch(revision="batch")
        self.assertEqual(rows, [])
        certificate = coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"]
        self.assertEqual(certificate["cards"]["sample-001"], ["normal", stamp])
        self.assertNotIn("slotChanges", certificate)

    def test_ex_energy_reverse_convention_reads_the_one_reverse_lane_as_the_energy_pattern(self):
        self.keep_only("sample-001", "tcgplayer:14")
        self.fixture["snapshot"] += [dict(slot, masterSetVariant={"id": "energy"})
                                     for slot in self.fixture["snapshot"]
                                     if slot["masterSetVariant"]["id"] == "reverse"]
        coverage.write_json(self.slots, self.fixture["snapshot"])
        _, rows = self.batch()
        self.assertEqual([row["reason"] for row in rows], ["parallelFinishNotListed"])
        self.conventions(energyReverseHolo=self.convention(setIDs=["sample"]),
                         reverseLane=self.convention(excludeSetIDs=[]))
        _, rows = self.batch(revision="batch")
        self.assertEqual(rows, [])
        certificate = coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"]
        self.assertEqual(certificate["cards"]["sample-001"], ["energy", "normal"])

    def test_ex_energy_reverse_convention_only_applies_to_its_sets(self):
        self.keep_only("sample-001", "tcgplayer:14")
        self.fixture["snapshot"] += [dict(slot, masterSetVariant={"id": "energy"})
                                     for slot in self.fixture["snapshot"]
                                     if slot["masterSetVariant"]["id"] == "reverse"]
        coverage.write_json(self.slots, self.fixture["snapshot"])
        self.conventions(energyReverseHolo=self.convention(setIDs=["ex6"]),
                         reverseLane=self.convention(excludeSetIDs=[]))
        _, rows = self.batch(revision="batch")
        self.assertEqual([row["reason"] for row in rows], ["parallelFinishNotListed"])

    def test_conventions_need_a_decision_and_sources(self):
        self.conventions(reverseLane={"id": "x", "excludeSetIDs": []})
        with self.assertRaisesRegex(ValueError, "decision and sources"):
            self.batch()

    def cosmos_setup(self, title="Example One - 1/4 (Cosmos Holo)", lane="Holofoil", number="001/004"):
        self.keep_only("sample-001", "tcgplayer:14")
        self.fixture["snapshot"].append(dict(self.fixture["snapshot"][0], masterSetVariant={"id": "cosmos"}))
        coverage.write_json(self.slots, self.fixture["snapshot"])
        coverage.write_json(self.snapshot / "manifest.json", {"entries": [
            {"providerID": "sample", "resource": "sets/opaque.json", "officialCount": 4, "set": {"name": "Sample Set"}},
        ]})
        self.conventions(appearances=[{
            "id": "cosmos-test", "finishes": {"cosmos": ["Holofoil"]}, "titleQualifiers": ["Cosmos Holo"],
            "groups": [{"groupID": 77, "groupName": "Deck Exclusives"}], "decision": "Test rule.",
            "sources": ["https://example.com"]}])
        product = {"productId": 70, "categoryId": 3, "groupId": 77, "name": title,
                   "extendedData": [{"name": "Number", "value": number}]}
        return self.market({
            77: {"name": "Deck Exclusives", "products": {"success": True, "errors": [], "results": [product]},
                 "prices": {"success": True, "errors": [], "results": [{"productId": 70, "subTypeName": lane}]}}})

    def test_cosmos_appearance_rule_certifies_with_a_cited_resolution(self):
        market = self.cosmos_setup()
        result, rows = self.batch(market, revision="batch")
        self.assertEqual(rows, [])
        self.assertEqual(result["reconciledCards"], 1)
        certificate = coverage.read_json(self.snapshot / "finish-coverage.json")["sets"]["sample"]
        self.assertEqual(certificate["cards"]["sample-001"], ["cosmos", "normal", "reverse"])
        report_value = coverage.read_json(coverage.capture_directory(self.root, "sample", "batch") / "report.json")
        resolution = report_value["resolutions"]["sample-001"]
        self.assertEqual(resolution["citation"], "publisher/pokemon-finish-conventions.json")
        self.assertIn("[70]", resolution["reason"])
        self.assertEqual(report_value["cards"]["sample-001"]["status"], "conflict")

    def test_cosmos_appearance_rule_rejects_inexact_evidence(self):
        cases = {
            "wrong lane": dict(lane="Normal"),
            "wrong denominator": dict(title="Example One - 1/5 (Cosmos Holo)", number="001/005"),
            "extra qualifier": dict(title="Example One - 1/4 (Cosmos Holo) (Stamped)"),
            "other name": dict(title="Example Two - 1/4 (Cosmos Holo)"),
            "no denominator": dict(title="Example One (Cosmos Holo)", number="001"),
        }
        for label, overrides in cases.items():
            with self.subTest(label):
                self.setUp()
                _, rows = self.batch(self.cosmos_setup(**overrides))
                self.assertEqual([(row["identity"], row["reason"]) for row in rows],
                                 [("sample-001", "parallelFinishNotListed")])
        self.setUp()
        market = self.cosmos_setup(title="Example One (Cosmos Holo)")
        _, rows = self.batch(market)
        self.assertEqual(rows, [], "A title without a number still matches on the number field")

    def test_cosmos_appearance_rule_refuses_a_name_number_shared_with_another_set(self):
        market = self.cosmos_setup()
        other = self.snapshot / "sets/other.json"
        coverage.write_json(other, [dict(self.fixture["snapshot"][0], providerID="other-001",
                                         setID={"providerID": "other"})])
        manifest = coverage.read_json(self.snapshot / "manifest.json")
        manifest["entries"].append({"providerID": "other", "resource": "sets/other.json", "officialCount": 4,
                                    "set": {"name": "Other Set"}})
        coverage.write_json(self.snapshot / "manifest.json", manifest)
        _, rows = self.batch(market)
        self.assertIn(("sample-001", "parallelFinishNotListed"), [(row["identity"], row["reason"]) for row in rows])


    def number_remap_setup(self):
        self.keep_only("sample-001", "tcgplayer:14")
        self.fixture["snapshot"] = [
            {"providerID": "sample-001", "collectorNumber": "CC1", "name": "Example One",
             "setID": {"providerID": "sample"}, "masterSetVariant": {"id": "holo"}},
        ]
        coverage.write_json(self.slots, self.fixture["snapshot"])
        self.fixture["products"]["results"] = []
        self.fixture["prices"]["results"] = []
        remap_group = {
            "name": "Remap Group",
            "products": {"success": True, "errors": [], "results": [
                {"productId": 70, "categoryId": 3, "groupId": 88,
                 "name": "Example One", "extendedData": [{"name": "Number", "value": "1/4"}]},
            ]},
            "prices": {"success": True, "errors": [], "results": [
                {"productId": 70, "subTypeName": "Holofoil", "marketPrice": 5.0},
            ]},
        }
        self.conventions(numberRemaps=[{
            "id": "test-remap", "setID": "sample", "groupID": 88,
            "mapping": {"CC1": {"marketNumber": "1/4", "productId": 70}},
            "decision": "Test remap.", "sources": ["https://example.com"],
        }])
        return self.market({88: remap_group})

    def test_number_remap_convention_resolves_mismatched_numbers_and_certifies(self):
        market = self.number_remap_setup()
        _, rows = self.batch(market)
        self.assertEqual(rows, [], "Remap should resolve the CC-numbered card and the market product")

    def test_number_remap_convention_refuses_when_product_missing(self):
        market = self.number_remap_setup()
        self.conventions(numberRemaps=[{
            "id": "test-remap", "setID": "sample", "groupID": 88,
            "mapping": {"CC1": {"marketNumber": "1/4", "productId": 999}},
            "decision": "Test remap.", "sources": ["https://example.com"],
        }])
        _, rows = self.batch(market)
        self.assertEqual([(row["identity"], row["reason"]) for row in rows],
                         [("sample-001", "unmatchedMarket")],
                         "A wrong product ID should leave the card unmatched")

    def test_ecard_holo_title_accepts_only_the_same_number_and_holo_lane(self):
        card = {"name": "Ampharos", "number": "H01", "checklist": ["holo"]}
        market = {"productId": 83537, "name": "Ampharos (H1)", "number": "H01/H32",
                  "subtypes": ["Holofoil"]}
        for product in (
            dict(market, name="Ampharos (H2)"),
            dict(market, name="Ampharos (H001)"),
            dict(market, number="H01/H31"),
            dict(market, number="H02/H32"),
            dict(market, subtypes=[]),
            dict(market, subtypes=["Normal", "Holofoil"]),
        ):
            with self.subTest(product=product):
                self.assertIsNone(coverage.product_finishes(card, product, ecard_holo=True))
        self.assertIsNone(coverage.product_finishes(card, market))
        self.assertIsNone(coverage.product_finishes(dict(card, number="1"), market, ecard_holo=True))
        self.assertEqual(coverage.product_finishes(card, market, ecard_holo=True), {"holo"})
        duplicate = coverage.compare({"a": card}, {}, {"h01": [market, dict(market, productId=90000)]},
                                     ecard_holo=True)
        self.assertFalse(duplicate["a"]["products"])
        conflict = coverage.compare({"a": dict(card, checklist=["holo", "reverse"])}, {}, {"h01": [market]},
                                    ecard_holo=True)
        self.assertEqual(conflict["a"]["market"], ["holo"])
        self.assertEqual(conflict["a"]["status"], "conflict")

    def test_ecard_holo_title_is_bound_to_the_reviewed_group_and_report(self):
        self.keep_only("sample-001", products=(11,))
        slot = self.fixture["snapshot"][0]
        slot["collectorNumber"] = "H01"
        slot["masterSetVariant"]["id"] = "holo"
        coverage.write_json(self.slots, [slot])
        product = self.fixture["products"]["results"][0]
        product["name"] = "Example One (H1)"
        product["extendedData"][0]["value"] = "H01/H32"
        self.fixture["prices"]["results"] = [{"productId": 11, "subTypeName": "Holofoil", "marketPrice": 1}]
        self.fixture["groups"] = {"success": True, "errors": [],
                                  "results": [{"groupId": 55, "name": "Sample Set"}]}
        self.conventions(ecardHoloTitles=self.convention(sets={
            "sample": {"groupID": 55, "groupName": "Sample Set"},
        }))
        self.assertIsNone(coverage.ecard_holo_title_scope(self.root, "sample", "Sample Set", 56))
        self.assertEqual(self.batch()[1], [])
        captured = coverage.report(self.root, "sample", 55, self.fetch, revision="ecard-holo")
        self.assertEqual(captured["cards"]["sample-001"]["status"], "agree")
        archived = coverage.capture_directory(self.root, "sample", "ecard-holo")
        replayed = coverage.replay(self.root, archived)["sets"]["sample@ecard-holo"]
        self.assertEqual(replayed["cardRows"]["sample-001"]["replay"], captured["cards"]["sample-001"])
        self.assertEqual(coverage.certify(self.root, "sample", revision="ecard-holo"), 1)

        self.fixture["groups"]["results"][0]["name"] = "Renamed"
        with self.assertRaisesRegex(ValueError, "no longer uniquely named"):
            coverage.report(self.root, "sample", 55, self.fetch, revision="renamed-holos")


if __name__ == "__main__":
    unittest.main()
