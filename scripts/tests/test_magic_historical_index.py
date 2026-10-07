import importlib.util
import json
import tempfile
import unittest
from datetime import date
from pathlib import Path
from types import SimpleNamespace

MODULE = Path(__file__).resolve().parents[1] / "build_magic_historical_index.py"
SPEC = importlib.util.spec_from_file_location("magic_index", MODULE)
index = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(index)


class MagicHistoricalIndexImporterTests(unittest.TestCase):
    def setUp(self):
        self.meta = {"date": "2026-10-06", "version": "fixture"}
        self.printing_id = "00000000-0000-4000-8000-000000000001"
        self.source_id = "00000000-0000-4000-8000-000000000002"
        self.set_id = "00000000-0000-4000-8000-000000000003"
        self.card = {"uuid": self.source_id, "name": "Example", "number": "1a", "language": "English",
            "availability": ["paper"], "finishes": ["nonfoil", "foil"], "layout": "normal",
            "identifiers": {"scryfallId": self.printing_id},
            "skuIds": {"nonfoil": "00000000-0000-4000-8000-000000000004",
                       "foil": "00000000-0000-4000-8000-000000000005"}}
        self.set_data = {"code": "EXO", "name": "Exodus", "releaseDate": "1998-06-15", "type": "expansion"}
        self.provider = {"object": "card", "id": self.printing_id, "set_id": self.set_id, "set": "exo",
            "name": "Example", "collector_number": "1a", "lang": "en", "games": ["paper"],
            "finishes": ["nonfoil", "foil"], "layout": "normal", "released_at": "1998-06-15", "oversized": False}
        self.page = {"object": "list", "data": [self.provider], "total_cards": 1, "has_more": False}
        self.descriptors = {"exo": {"scryfallSetID": self.set_id}}

    def record(self, group=None, provider=None):
        return index.record_for_group(group or [(self.card, self.set_data)],
            {self.printing_id: provider or self.provider}, self.descriptors, date(2026, 10, 6))

    def test_finish_references_belong_to_one_printing(self):
        record = self.record()
        self.assertEqual(record["printingID"], self.printing_id)
        self.assertEqual(record["finishes"], ["foil", "nonfoil"])
        self.assertEqual(set(record["sourceFinishReferences"]), {"foil", "nonfoil"})
        self.assertIsNone(record["visibleCollectorNumber"])
        self.assertEqual(record["unresolvedDistinctions"], ["physical_review_pending"])

    def test_name_number_match_cannot_allocate_crosswalk(self):
        with self.assertRaises(ValueError):
            self.record(provider=self.provider | {"name": "Different"})
        with self.assertRaises(ValueError):
            self.record(provider=self.provider | {"collector_number": "1"})
        with self.assertRaises(ValueError):
            self.record(provider=self.provider | {"set_id": self.source_id})
        with self.assertRaises(ValueError):
            self.record(provider=self.provider | {"lang": "fr"})
        with self.assertRaises(ValueError):
            self.record(provider=self.provider | {"games": ["mtgo"]})

    def test_linked_faces_consolidate_only_with_reciprocal_ids(self):
        other_id = "00000000-0000-4000-8000-000000000006"
        first = self.card | {"layout": "transform", "faceName": "Front", "otherFaceIds": [other_id]}
        second = self.card | {"uuid": other_id, "layout": "transform", "faceName": "Back", "otherFaceIds": [self.source_id]}
        group = [(first, self.set_data), (second, self.set_data)]
        record = self.record(group=group, provider=self.provider | {"layout": "transform"})
        self.assertEqual(len(record["sourceIDs"]), 2)
        self.assertEqual(record["aliases"], ["Back", "Front"])
        with self.assertRaises(ValueError):
            self.record(group=[(first, self.set_data)], provider=self.provider | {"layout": "transform"})
        with self.assertRaises(ValueError):
            self.record(group=[(self.card, self.set_data), (self.card | {"uuid": other_id}, self.set_data)])

    def test_partial_warned_or_duplicate_pages_reject(self):
        for mutation in [{"has_more": True}, {"next_page": "https://api.scryfall.com/next"},
                         {"total_cards": 2}, {"warnings": ["partial query"]},
                         {"data": [self.provider, self.provider], "total_cards": 2}]:
            with self.assertRaises(ValueError):
                index.validate_page(self.page | mutation)

    def test_stream_rejects_truncation_trailing_data_and_duplicate_keys(self):
        valid = json.dumps({"meta": self.meta, "data": {"EXO": self.set_data}})
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "all.json"
            path.write_text(valid)
            self.assertEqual(list(index.all_printings(path, self.meta)), [self.set_data])
            for malformed in [valid[:-1], valid + "x", valid.replace('"EXO":', '"EXO": {}, "EXO":')]:
                path.write_text(malformed)
                with self.assertRaises(ValueError):
                    list(index.all_printings(path, self.meta))
            path.write_text(valid)
            with self.assertRaises(ValueError):
                list(index.all_printings(path, self.meta | {"date": "2026-10-05"}))

    def test_exact_keys_preserve_suffixes_punctuation_and_zeros(self):
        self.assertEqual(index.evidence_keys(self.card), {("example", "1a")})
        self.assertNotEqual(index.evidence_keys(self.card), index.evidence_keys(self.card | {"number": "01a"}))
        self.assertNotEqual(index.evidence_keys(self.card), index.evidence_keys(self.card | {"number": "1★"}))
        self.assertEqual(index.evidence_keys(self.card | {"name": " EXAMPLE\n"}), {("example", "1a")})

    def test_ineligible_rows_keep_explicit_dispositions(self):
        for mutation, expected in [({"language": "French"}, "non_english_or_unknown"),
                                   ({"availability": []}, "paper_unproven"),
                                   ({"layout": "split"}, "unsupported_layout_or_product")]:
            self.assertEqual(index.disposition(self.card | mutation, self.set_data, date(2026, 10, 6)), expected)
        self.assertEqual(index.disposition(self.card, self.set_data | {"type": "memorabilia"}, date(2026, 10, 6)),
                         "unsupported_layout_or_product")

    def test_pipeline_preserves_cross_era_and_missing_crosswalk_without_completeness(self):
        pilot = self.set_data | {"cards": [self.card]}
        collision = self.card | {"uuid": "00000000-0000-4000-8000-000000000006", "skuIds": {},
            "identifiers": {"scryfallId": "00000000-0000-4000-8000-000000000007"}}
        missing = self.card | {"uuid": "00000000-0000-4000-8000-000000000008", "identifiers": {}}
        modern = self.set_data | {"code": "M15", "releaseDate": "2014-07-18", "cards": [collision, missing]}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            files = {"pilot": {"meta": self.meta, "data": pilot},
                     "all": {"meta": self.meta, "data": {"EXO": pilot, "M15": modern}},
                     "scryfall": self.page,
                     "catalog": {"schemaVersion": 1, "catalogKind": "magic",
                                 "sets": [{"code": "EXO", "scryfallSetID": self.set_id}]}}
            for name, value in files.items():
                (root / (name + ".json")).write_text(json.dumps(value))
            args = SimpleNamespace(pilot=root / "pilot.json", all_printings=root / "all.json",
                scryfall=root / "scryfall.json", catalog=root / "catalog.json",
                output=root / "output", observed_on=date(2026, 10, 6))
            report = index.build(args)
            self.assertEqual(report["sourceRows"], 3)
            self.assertEqual(report["projectionPrintings"], 2)
            self.assertEqual(report["unverifiedCollisionPrintings"], 1)
            self.assertEqual(report["unresolvedKeys"], 1)
            artifact = json.loads((args.output / "pilot-index.json").read_text())
            self.assertEqual(artifact["coverage"]["completeKeys"], [])
            self.assertEqual(artifact["coverage"]["keyReceipts"], [])
            args.output = root / "repeat"
            self.assertEqual(index.build(args), report)


if __name__ == "__main__":
    unittest.main()
