import copy
import contextlib
from hashlib import sha256
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import catalog_parity as parity
from market_price_feeds import packed

ROOT = Path(__file__).resolve().parents[2]


def catalog():
    return {"schemaVersion": 1, "generation": "fixture", "capturedAt": "2026-11-24",
            "autoEligibleCodes": ["SET-EN001"], "incompleteCodes": [], "sets": [{"g": 42}],
            "cards": [{"id": "card-A"}, {"id": "card-B"}], "referencePrintings": [],
            "printings": [{"id": "printing-A", "g": 42, "k": 0, "c": "SET-EN001", "e": ["Limited"],
                           "ec": True, "p": 1000, "pn": "One", "pe": ["Limited"],
                           "m": [{"e": "Limited", "t": "reviewed", "q": 3}]}]}


class CatalogParityTests(unittest.TestCase):
    def test_one_piece_envelope_and_payload_preserve_all_records(self):
        seed = ROOT / "TradingCardScanner/OnePieceCatalogSeed/one-piece-catalog-release.json"
        baseline = parity.one_piece(seed)
        candidate = parity.release_payload(seed)
        candidate["revision"] += 1
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "candidate.json"
            path.write_bytes(packed(candidate))
            self.assertEqual(parity.compare(baseline, parity.one_piece(path)), [])
            printing = next(row for row in candidate["registry"]["printings"] if row["marketMappings"])
            printing["marketMappings"] = []
            path.write_bytes(packed(candidate))
            self.assertEqual([(change["section"], change["identity"]) for change in
                              parity.compare(baseline, parity.one_piece(path))],
                             [("marketplaceMappings", printing["id"].lower())])

    def test_lorcana_requires_discovery_binding_and_checks_finish_evidence(self):
        seed = ROOT / "TradingCardScanner/LorcanaCatalogSeed"
        baseline = parity.lorcana(seed)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            market = parity.read_json(seed / "market.json")
            (path / "market.json").write_bytes(packed(market))
            (path / "discovery.json").write_bytes((seed / "discovery.json").read_bytes() + b"\n")
            with self.assertRaisesRegex(ValueError, "different discovery bytes"):
                parity.lorcana(path)
            (path / "discovery.json").write_bytes((seed / "discovery.json").read_bytes())
            row = market["physicalPrintings"][0]
            row["finishes"][0]["evidenceReferences"].append("reviewed-change")
            (path / "market.json").write_bytes(packed(market))
            self.assertEqual([(change["section"], change["identity"]) for change in
                              parity.compare(baseline, parity.lorcana(path))], [("finishes", row["id"].lower())])

    def test_magic_ignores_prices_changing_amount_but_detects_lost_lane(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            set_id = "a2f58272-bba6-439d-871e-7a46686ac018"
            card = {"object": "card", "id": "c0079e57-1afe-4447-b68a-6a9444e2c915", "lang": "en",
                    "digital": False, "games": ["paper"], "set_id": set_id, "set": "abc", "collector_number": "100",
                    "finishes": ["foil"], "prices": {"usd_foil": "1.20"}, "tcgplayer_id": 12}
            (path / "sets.json").write_bytes(packed({"object": "list", "has_more": False,
                                                    "data": [{"id": set_id, "code": "abc"}]}))
            bulk = path / "default-cards.jsonl"
            bulk.write_bytes(packed(card) + packed({**card, "lang": "fr"}))
            original = parity.magic(path)
            card["prices"]["usd_foil"] = "1.30"
            bulk.write_bytes(packed(card))
            self.assertEqual(parity.compare(original, parity.magic(path)), [])
            card["prices"]["usd_foil"] = None
            bulk.write_bytes(packed(card))
            self.assertEqual([change["section"] for change in parity.compare(original, parity.magic(path))],
                             ["pricedProducts"])

    def test_mirror_coverage_checks_products_lanes_and_integrity(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            group = path / "tcgplayer/68/1"
            group.mkdir(parents=True)
            marker = "2026-10-29T07:00:00Z"
            metadata = {"sourceBuild": marker, "sourceFetchedAt": marker, "success": True, "errors": []}
            files = {"last-updated.txt": (marker + "\n").encode(),
                     "tcgplayer/68/1/products": packed({**metadata, "results": [
                         {"productId": 7, "categoryId": 68, "groupId": 1, "name": "Card", "extendedData": []}]}),
                     "tcgplayer/68/1/prices": packed({**metadata, "results": [
                         {"productId": 7, "subTypeName": "Foil", "marketPrice": 0},
                         {"productId": 7, "subTypeName": "Normal", "marketPrice": None}]})}
            for name, data in files.items():
                (path / name).write_bytes(data)
            (path / "index.json").write_bytes(packed({"schemaVersion": 1, "sourceBuild": marker, "files": [
                {"path": name, "byteCount": len(data), "sha256": sha256(data).hexdigest()} for name, data in files.items()]}))
            self.assertEqual(parity.mirror_priced_products(path, 68), {parity.canonical(["1", 7, "Foil"]): True})
            with self.assertRaisesRegex(ValueError, "no groups for category 71"):
                parity.mirror_priced_products(path, 71)
            (group / "prices").write_bytes(b"corrupt")
            with self.assertRaisesRegex(ValueError, "hash/size mismatch"):
                parity.mirror_priced_products(path, 68)

    def test_record_order_and_new_receipts_do_not_change_identity_or_coverage(self):
        old, new = catalog(), catalog()
        new["cards"].reverse()
        new["printings"][0]["k"] = 1
        new["printings"][0]["m"][0]["q"] = 8
        new["capturedAt"] = "2026-11-25"
        self.assertEqual(parity.compare(parity.yugioh(old), parity.yugioh(new)), [])

    def test_reports_all_identity_finish_mapping_and_priced_product_changes(self):
        old, new = catalog(), catalog()
        new["sets"].append({"g": 43})
        new["printings"][0].update(id="printing-B", ec=False, p=1001, pe=[])
        new["printings"][0]["m"][0].pop("q")
        changes = parity.compare(parity.yugioh(old), parity.yugioh(new))
        self.assertEqual({change["section"] for change in changes},
                         {"sets", "printings", "finishes", "marketplaceMappings", "pricedProducts"})
        for section in ("printings", "finishes", "marketplaceMappings", "pricedProducts"):
            self.assertEqual({change["identity"] for change in changes if change["section"] == section},
                             {"printing-a", "printing-b"})

    def test_normal_and_reference_records_cannot_repeat_a_printing_id(self):
        document = catalog()
        document["referencePrintings"].append(copy.deepcopy(document["printings"][0]))
        with self.assertRaisesRegex(ValueError, "Duplicate printing"):
            parity.yugioh(document)

    def test_allowlist_requires_exact_digests_and_rejects_unused_approval(self):
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            first, second, allow = (Path(folder) / (name + ".json") for name in ("old", "new", "allow"))
            old, new = catalog(), catalog()
            new["printings"][0]["p"] = 3333
            first.write_text(json.dumps(old))
            second.write_text(json.dumps(new))
            args = ["yugioh", "--before", str(first), "--after", str(second)]
            self.assertEqual(parity.main(args), 1)
            changes = parity.compare(parity.yugioh(old), parity.yugioh(new))
            allow.write_text(json.dumps([{**change, "reason": "Reviewed product repair"} for change in changes]))
            self.assertEqual(parity.main(args + ["--allowlist", str(allow)]), 0)
            second.write_text(json.dumps(old))
            self.assertEqual(parity.main(args + ["--allowlist", str(allow)]), 1)


if __name__ == "__main__":
    unittest.main()
