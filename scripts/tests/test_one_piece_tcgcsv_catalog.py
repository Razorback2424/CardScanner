import argparse
import hashlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build_one_piece_catalog as builder
import one_piece_tcgcsv_capture as capture
import reconcile_one_piece_tcgcsv_sources as review


class CatalogTests(unittest.TestCase):
    def retained(self, root, group_products=None):
        marker = b"2026-10-04T20:00:00Z\n"
        docs = {"https://tcgcsv.com/last-updated.txt": ("last-updated-start.txt", marker),
                "https://tcgcsv.com/last-updated.txt#end": ("last-updated-end.txt", marker)}
        groups = {"success": True, "errors": [], "totalItems": 1,
                  "results": [{"groupId": 1, "categoryId": 68, "name": "Fixture OP01", "publishedOn": "2022-01-01"}]}
        products = {"success": True, "errors": [], "totalItems": 2, "results": group_products or [
            {"productId": 1, "categoryId": 68, "groupId": 1, "name": "Fixture Shanks", "extendedData": [{"name": "Number", "value": "OP01-120"}]},
            {"productId": 2, "categoryId": 68, "groupId": 1, "name": "Fixture Shanks (Manga)", "extendedData": [{"name": "Number", "value": "OP01-120"}]}]}
        products["totalItems"] = len(products["results"])
        docs["https://tcgcsv.com/tcgplayer/68/groups"] = ("68-groups.json", json.dumps(groups).encode())
        docs["https://tcgcsv.com/tcgplayer/68/1/products"] = ("68-1-products.json", json.dumps(products).encode())
        root.mkdir()
        manifest = {"schemaVersion": 1, "startedAt": "2026-10-04T20:00:00+00:00", "complete": True, "captures": {}}
        for url, (name, raw) in docs.items():
            (root / name).write_bytes(raw)
            manifest["captures"][url] = {"rawFile": name, "sourceURL": url.split("#")[0], "byteCount": len(raw),
                "payloadSHA256": hashlib.sha256(raw).hexdigest(), "observedAt": manifest["startedAt"]}
        (root / "captures.json").write_text(json.dumps(manifest))
        return manifest

    def args(self, root):
        return argparse.Namespace(base=builder.DEFAULT_BASE, output_dir=str(root / "output"),
            capture_dir=str(root / "source"), user_agent="Fixture/1.0", delay=0.12, offline=True, include_prices=False)

    def test_offline_replay_keeps_duplicate_numbers_as_separate_source_products(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); self.retained(root / "source")
            with patch.object(capture, "urlopen", side_effect=AssertionError("No HTTP in replay")), redirect_stdout(io.StringIO()):
                builder.build(self.args(root))
                output = root / "output" / "one_piece_catalog.json"
                initial = output.read_bytes(); modified = output.stat().st_mtime_ns
                capture_modified = (root / "source/captures.json").stat().st_mtime_ns
                builder.build(self.args(root))
            self.assertEqual(output.read_bytes(), initial)
            self.assertEqual(output.stat().st_mtime_ns, modified)
            self.assertEqual((root / "source/captures.json").stat().st_mtime_ns, capture_modified)
            rows = json.loads(initial)
            self.assertEqual(len(rows["cards"]), 2)
            self.assertEqual({row["printed_card_number"] for row in rows["cards"]}, {"OP01-120"})
            self.assertFalse(rows["meta"]["physical_coverage_complete"])
            self.assertFalse(rows["meta"]["price_lanes_requested"])
            self.assertNotIn("printing", rows["meta"]["identity_model"])

    def test_corrupt_or_missing_retained_bytes_never_refetch_silently(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); self.retained(root / "source")
            (root / "source" / "68-1-products.json").write_bytes(b"changed")
            with patch.object(capture, "urlopen", side_effect=AssertionError("No fallback HTTP")):
                with self.assertRaises(ValueError): builder.build(self.args(root))

    def test_failed_or_truncated_response_cannot_be_inventory(self):
        url = "https://tcgcsv.com/tcgplayer/68/groups"
        for doc in [{}, {"success": False, "errors": [], "results": []},
                    {"success": True, "errors": [], "results": [], "totalItems": 1},
                    {"success": True, "errors": [], "results": [], "totalItems": 0, "nextPage": "more"}]:
            with self.assertRaises(ValueError): capture.validate_document(doc, url)

    def test_mixed_daily_build_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "source"; manifest = self.retained(root)
            raw = b"2026-10-05T20:00:00Z"
            (root / "last-updated-end.txt").write_bytes(raw)
            record = manifest["captures"]["https://tcgcsv.com/last-updated.txt#end"]
            record.update(payloadSHA256=hashlib.sha256(raw).hexdigest(), byteCount=len(raw))
            (root / "captures.json").write_text(json.dumps(manifest))
            snapshot = capture.TCGCSVSnapshot(root, "Fixture/1.0", 0.12, offline=True)
            with self.assertRaises(ValueError): snapshot.finish()

    def test_empty_presale_group_is_retained_as_incomplete_inventory(self):
        doc = {"success": True, "errors": [], "results": []}
        result = capture.validate_document(doc, "https://tcgcsv.com/tcgplayer/68/1/products")
        self.assertFalse(result["sourceInventoryComplete"])
        self.assertEqual(result["sourceInventoryIssue"], "empty_export_without_totalItems")
        with self.assertRaises(ValueError): capture.validate_document(doc, "https://tcgcsv.com/tcgplayer/68/groups")

    def test_pacing_and_origin_are_enforced(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "source"; self.retained(root)
            for delay in [0.09, float("nan"), float("inf")]:
                with self.assertRaises(ValueError): capture.TCGCSVSnapshot(root, "Fixture/1.0", delay, offline=True)
            snapshot = capture.TCGCSVSnapshot(root, "Fixture/1.0", 0.12, offline=True)
            for url in ["http://tcgcsv.com/tcgplayer/68/groups", "https://tcgcsv.com/tcgplayer/3/groups"]:
                with self.assertRaises(ValueError): snapshot.fetch_json(url)

    def test_sealed_conflicts_and_unnumbered_rows_do_not_become_exact_cards(self):
        self.assertEqual(builder.card_status({"name": "Booster Box"}, "OP01", {"Number": "OP01-120"})[0], "metadata_conflict_candidate")
        self.assertEqual(builder.card_status({"name": "Mystery Card"}, "Promotion Cards", {})[0], "unnumbered_card_candidate")
        self.assertEqual(builder.card_status({"name": "Booster Box"}, "OP01", {})[0], "excluded_non_card_product")
        self.assertTrue(builder.is_don("DON!!", {}))
        with self.assertRaises(ValueError): builder.ext_map({"extendedData": [{"name": "Number", "value": "P-001"}, {"name": "Number", "value": "P-002"}]})

    def test_changed_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "review.json"; path.write_text("reviewed")
            with self.assertRaises(ValueError): builder.write_output(path, "replacement")
            self.assertEqual(path.read_text(), "reviewed")

    def test_crosswalk_preserves_market_candidates_without_one_to_one_artwork_join(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder); self.retained(root / "source")
            with redirect_stdout(io.StringIO()): builder.build(self.args(root))
            official = root / "official.json"
            official.write_text(json.dumps([{"alias": {"provider": "bandai", "sourceID": "OP01-120_p2"},
                "printedEvidence": {"number": "OP01-120"}}]))
            result = review.reconcile(root / "output/one_piece_catalog.json", root / "source", official)
            self.assertEqual(len(result["observations"]), 2)
            self.assertTrue(all(o["kind"] == "market" and o["language"] == "unknown" for o in result["observations"]))
            row = result["crosswalk"]["rows"][0]
            self.assertEqual(row["bandaiArtworkAliases"], ["OP01-120_p2"])
            self.assertEqual(row["reviewedPhysicalJoins"], [])
            self.assertEqual(len(row["candidateMarketProducts"]), 2)
            self.assertFalse(row["physicalCoverageComplete"])


if __name__ == "__main__": unittest.main()
