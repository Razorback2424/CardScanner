import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path
from types import SimpleNamespace

SCRIPT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT))
SPEC = importlib.util.spec_from_file_location("magic_reconciliation", SCRIPT / "reconcile_magic_historical_pilot.py")
reconcile = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reconcile)


class MagicHistoricalReconciliationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.card = {"object": "card", "id": "00000000-0000-4000-8000-000000000001",
            "oracle_id": "00000000-0000-4000-8000-000000000002",
            "set_id": "00000000-0000-4000-8000-000000000003", "name": "Allay", "set": "exo",
            "collector_number": "1", "lang": "en", "games": ["paper"], "digital": False,
            "oversized": False, "layout": "normal", "finishes": ["nonfoil"],
            "released_at": "1998-06-15", "image_uris": {"large": "https://example.org/front.jpg"}}
        self.record = {"printingID": self.card["id"], "name": "Allay", "setCode": "exo",
            "collectorNumber": "1", "language": "en", "layout": "normal", "finishes": ["nonfoil"],
            "releaseDate": "1998-06-15", "reconciled": True}
        (self.root / "Allay.jpg").write_bytes(b"reviewed-image")
        review = {"reviewKind": "provider_front_visible_number", "reviewedOn": "2026-10-06", "records": [
            {"printingID": self.card["id"], "name": "Allay", "collectorNumber": "1", "layout": "normal",
             "denominator": 143, "imageSHA256": hashlib.sha256(b"reviewed-image").hexdigest()}]}
        (self.root / "review.json").write_text(json.dumps(review))
        self.args = SimpleNamespace(index=self.root / "index.json", review=self.root / "review.json",
            captures=self.root, output=self.root / "output", observed_on=date(2026, 10, 6))
        self.write_index()
        for name in ["Allay", "Cataclysm", "Monstrous Hound", "Angelic Blessing", "Charging Paladin"]:
            rows = [self.card] if name == "Allay" else []
            self.write_page(name, rows)

    def write_index(self):
        self.args.index.write_text(json.dumps({"records": [self.record], "sources": [],
            "catalog": {"sets": [{"code": "exo", "scryfallSetID": self.card["set_id"]}]}}))

    def write_page(self, name, rows, **changes):
        page = {"object": "list", "has_more": False, "total_cards": len(rows), "data": rows} | changes
        (self.root / (name.replace(" ", "-") + "-search.json")).write_text(json.dumps(page))

    def test_review_receipt_is_exact_dated_and_reproducible(self):
        first = reconcile.build(self.args)
        second = reconcile.build(self.args)
        self.assertEqual(first["artifactSHA256"], second["artifactSHA256"])
        self.assertEqual(first["completeKeyCount"], 1)
        artifact = json.loads((self.args.output / "pilot-index.json").read_text())
        self.assertEqual(artifact["coverage"]["validUntil"], "2026-10-07T00:00:00.000Z")
        self.assertTrue(artifact["records"][0]["visibleCollectorNumber"])
        self.assertFalse(first["productionEnabled"])

    def test_refresh_replaces_previous_cross_era_source(self):
        first = reconcile.build(self.args)
        self.args.index = self.args.output / "pilot-index.json"
        second = reconcile.build(self.args)
        self.assertEqual(first["artifactSHA256"], second["artifactSHA256"])
        artifact = json.loads(self.args.index.read_text())
        self.assertEqual(sum(source["kind"] == "scryfallCrossEra" for source in artifact["sources"]), 1)

    def test_new_same_number_printing_invalidates_complete_key(self):
        self.write_page("Allay", [self.card, self.card | {"id": "00000000-0000-4000-8000-000000000004"}])
        report = reconcile.build(self.args)
        self.assertEqual(report["completeKeyCount"], 0)
        artifact = json.loads((self.args.output / "pilot-index.json").read_text())
        self.assertIsNone(artifact["coverage"]["validUntil"])
        self.assertEqual(report["discrepancies"][0]["kind"], "incomplete_current_key")

    def test_provider_date_is_per_printing_and_language_names_normalize(self):
        self.record["language"] = "English"
        self.write_index()
        self.write_page("Allay", [self.card | {"released_at": "1998-06-01"}])
        report = reconcile.build(self.args)
        artifact = json.loads((self.args.output / "pilot-index.json").read_text())
        self.assertEqual(artifact["records"][0]["language"], "en")
        self.assertEqual(artifact["records"][0]["route"], "legacyNoCollectorNumber")
        self.assertEqual(report["discrepancies"][0]["kind"], "printing_date_correction")

    def test_partial_warned_duplicate_and_foreign_scope_pages_reject(self):
        for changes in [{"has_more": True}, {"warnings": ["partial"]}, {"total_cards": 2}]:
            self.write_page("Allay", [self.card], **changes)
            with self.assertRaises(ValueError): reconcile.build(self.args)
        for rows in [[self.card, self.card], [self.card | {"lang": "fr"}], [self.card | {"games": ["mtgo"]}]]:
            self.write_page("Allay", rows)
            with self.assertRaises(ValueError): reconcile.build(self.args)

    def test_changed_front_and_unsupported_provider_identity_reject(self):
        (self.root / "Allay.jpg").write_bytes(b"changed")
        with self.assertRaises(ValueError): reconcile.build(self.args)
        (self.root / "Allay.jpg").write_bytes(b"reviewed-image")
        for key, value in [("oversized", True), ("digital", True), ("layout", "split"), ("set", "v14")]:
            self.write_page("Allay", [self.card | {key: value}])
            with self.assertRaises(ValueError): reconcile.build(self.args)

    def test_photographic_review_preserves_source_and_rejects_path_escape(self):
        review = json.loads(self.args.review.read_text())
        review["reviewKind"] = "printed_front_visible_number"
        front = review["records"][0]
        front.update(imageKind="photographic_front", imageFilename="corpus-photo.jpg",
                     imageURL="https://example.org/photo.jpg")
        (self.root / "corpus-photo.jpg").write_bytes(b"reviewed-image")
        self.args.review.write_text(json.dumps(review))
        report = reconcile.build(self.args)
        self.assertEqual(report["reviewedFronts"][0]["imageURL"], front["imageURL"])
        self.assertEqual(report["completeKeyCount"], 1)
        for filename in ["../corpus-photo.jpg", "/corpus-photo.jpg"]:
            front["imageFilename"] = filename
            self.args.review.write_text(json.dumps(review))
            with self.assertRaises(ValueError): reconcile.build(self.args)

    def test_duplicate_unknown_and_wrong_template_reviews_reject(self):
        original = json.loads(self.args.review.read_text())
        for change in ["duplicate", "unknown", "denominator", "kind", "name"]:
            review = json.loads(json.dumps(original))
            if change == "duplicate": review["records"].append(review["records"][0])
            if change == "unknown": review["records"][0]["printingID"] = "missing"
            if change == "denominator": review["records"][0]["denominator"] = 144
            if change == "kind": review["records"][0]["imageKind"] = "generated"
            if change == "name": review["records"][0]["name"] = "Different card"
            self.args.review.write_text(json.dumps(review))
            with self.assertRaises(ValueError): reconcile.build(self.args)


if __name__ == "__main__":
    unittest.main()
