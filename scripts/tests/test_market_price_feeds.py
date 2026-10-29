import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import market_price_feeds as feeds


class MarketPriceFeedTests(unittest.TestCase):
    marker = "2026-10-29T07:00:00Z"
    captured = "2026-10-29T08:00:00+00:00"

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.scope = {(71, 1): {123: {"Holofoil"}}}
        self.calls = []
        self.products = {"success": True, "errors": [], "totalItems": 2, "results": [
            {"productId": product, "categoryId": 71, "groupId": 1, "name": "Fixture " + str(product),
             "extendedData": [{"name": "Number", "value": str(product)}, {"name": "Text", "value": None}]}
            for product in (123, 456)]}
        self.prices = {"success": True, "errors": [], "results": [
            {"productId": 123, "subTypeName": "Holofoil", "marketPrice": 12.34},
            {"productId": 123, "subTypeName": "Normal", "marketPrice": 999},
            {"productId": 456, "subTypeName": "Holofoil", "marketPrice": 888}]}

    def tearDown(self):
        self.temp.cleanup()

    def fetch(self, url, maximum=feeds.MAX_FILE_BYTES, absent_ok=False):
        self.calls.append(url)
        if url.endswith("last-updated.txt"):
            return (self.marker + "\n").encode()
        return feeds.packed(self.products if url.endswith("products") else self.prices)

    def prepare(self, name="site", now=None):
        return feeds.prepare(self.scope, self.root / "cache", self.root / name,
                             fetch=self.fetch, now=lambda: now or self.captured, pause=lambda _: None)

    def test_scoped_snapshot_replays_without_new_group_requests_or_new_receipt_date(self):
        result = self.prepare()
        site = self.root / "site" / feeds.NAMESPACE
        index = (site / "index.json").read_bytes()
        product = json.loads((site / "tcgplayer/71/1/products").read_bytes())
        price = json.loads((site / "tcgplayer/71/1/prices").read_bytes())
        self.assertEqual([row["productId"] for row in product["results"]], [123])
        self.assertEqual(product["results"][0]["extendedData"], [{"name": "Number", "value": "123"}])
        self.assertEqual(price["results"], [{"productId": 123, "subTypeName": "Holofoil", "marketPrice": 12.34}])
        self.assertEqual(price["sourceFetchedAt"], self.captured)
        self.assertEqual(result["missingProducts"], [])
        self.calls.clear()
        self.prepare("replay", now="2026-10-29T09:00:00+00:00")
        self.assertEqual(self.calls, ["https://tcgcsv.com/last-updated.txt"] * 2)
        self.assertEqual((self.root / "replay" / feeds.NAMESPACE / "index.json").read_bytes(), index)

    def test_mixed_build_fails_before_writing_any_hosting_files(self):
        original = self.fetch
        markers = 0

        def changing(url, *args, **kwargs):
            nonlocal markers
            if url.endswith("last-updated.txt"):
                markers += 1
                if markers == 2:
                    return b"2026-10-30T07:00:00Z"
            return original(url, *args, **kwargs)
        self.fetch = changing
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertFalse((self.root / "site").exists())

    def test_same_job_yugioh_capture_is_reused_and_requires_both_build_markers(self):
        source = self.root / "yugioh"
        (source / "tcgcsv").mkdir(parents=True)
        for name in ("source-build-start.txt", "source-build-end.txt"):
            (source / name).write_text(self.marker)
        products = copy.deepcopy(self.products)
        for row in products["results"]:
            row["categoryId"] = 2
        for resource, doc in [("products", products), ("prices", self.prices)]:
            path = source / "tcgcsv" / f"1-{resource}.json"
            path.write_bytes(feeds.packed(doc))
            timestamp = feeds.instant(self.captured).timestamp()
            os.utime(path, (timestamp, timestamp))
        feeds.prepare({(2, 1): {123: {"Holofoil"}}}, self.root / "cache", self.root / "site",
                      fetch=self.fetch, now=lambda: self.captured, pause=lambda _: None, yugioh_source=source)
        self.assertEqual(self.calls, ["https://tcgcsv.com/last-updated.txt"] * 2)
        (source / "source-build-end.txt").write_text("2026-10-30T07:00:00Z")
        with self.assertRaises(ValueError):
            feeds.prepare({(2, 1): {123: {"Holofoil"}}}, self.root / "cache", self.root / "mixed",
                          fetch=self.fetch, now=lambda: self.captured, pause=lambda _: None, yugioh_source=source)

    def test_stale_receipts_and_corrupted_retained_bytes_cannot_be_republished(self):
        self.prepare()
        with self.assertRaises(ValueError):
            self.prepare("stale", now="2026-10-30T08:00:00+00:00")
        raw = next((self.root / "cache").glob("*/71-1-prices.json"))
        raw.write_bytes(b"changed")
        with self.assertRaises(ValueError):
            self.prepare("changed")

    def test_invalid_prices_duplicate_lanes_foreign_products_and_partial_exports_fail(self):
        original = self.prices["results"][0]
        for price in [-1, True, "12.34"]:
            invalid = copy.deepcopy(self.prices)
            invalid["results"][0]["marketPrice"] = price
            with self.assertRaises(ValueError):
                feeds.validate_response(feeds.packed(invalid), 71, 1, "prices")
        duplicate = self.prices | {"results": [original, original]}
        with self.assertRaises(ValueError):
            feeds.validate_response(feeds.packed(duplicate), 71, 1, "prices")
        for change in [{"categoryId": 68}, {"groupId": 2}]:
            invalid = copy.deepcopy(self.products)
            invalid["results"][0].update(change)
            with self.assertRaises(ValueError):
                feeds.validate_response(feeds.packed(invalid), 71, 1, "products")
        with self.assertRaises(ValueError):
            feeds.validate_response(feeds.packed(self.products | {"totalItems": 10}), 71, 1, "products")

    def test_missing_products_and_null_market_prices_do_not_borrow_other_rows(self):
        self.scope[(71, 1)][789] = {"Normal"}
        self.prices["results"][0]["marketPrice"] = None
        result = self.prepare()
        self.assertEqual(result["missingProducts"], [[71, 1, 789]])
        price = json.loads((self.root / "site" / feeds.NAMESPACE / "tcgplayer/71/1/prices").read_bytes())
        self.assertIsNone(price["results"][0]["marketPrice"])
        self.assertEqual(len(price["results"]), 1)

    def published(self):
        self.prepare()
        source = self.root / "site" / feeds.NAMESPACE

        def fetch(url, maximum=feeds.MAX_FILE_BYTES, absent_ok=False):
            self.assertTrue(url.startswith(feeds.ORIGIN + "/" + feeds.NAMESPACE + "/"))
            path = source / url.split("/" + feeds.NAMESPACE + "/", 1)[1]
            if not path.exists() and absent_ok:
                return None
            return path.read_bytes()
        return source, fetch

    def test_restore_preserves_published_namespace_and_reuses_a_valid_prepared_candidate(self):
        source, fetch = self.published()
        destination = self.root / "restored"
        self.assertTrue(feeds.restore(destination, fetch=fetch))
        for path in source.rglob("*"):
            if path.is_file():
                self.assertEqual(path.read_bytes(), (destination / feeds.NAMESPACE / path.relative_to(source)).read_bytes())
        self.assertTrue(feeds.restore(destination, fetch=lambda *args, **kwargs: self.fail("Prepared files require no network")))

    def test_absent_namespace_is_allowed_but_hash_failure_blocks_restore_without_partial_files(self):
        self.assertFalse(feeds.restore(self.root / "absent", fetch=lambda *args, **kwargs: None))
        source, fetch = self.published()
        (source / "tcgplayer/71/1/prices").write_bytes(b"changed")
        with self.assertRaises(ValueError):
            feeds.restore(self.root / "corrupt", fetch=fetch)
        self.assertFalse((self.root / "corrupt").exists())

    def test_restore_rejects_path_escape_duplicate_budget_and_missing_pair_before_publication(self):
        source, fetch = self.published()
        original = json.loads((source / "index.json").read_bytes())
        cases = []
        for path in ["../escaped", "/absolute", "tcgplayer/999/1/products"]:
            invalid = copy.deepcopy(original)
            invalid["files"][0]["path"] = path
            cases.append(invalid)
        invalid = copy.deepcopy(original)
        invalid["files"].append(invalid["files"][0])
        cases.append(invalid)
        invalid = copy.deepcopy(original)
        invalid["files"][0]["byteCount"] = feeds.MAX_FILE_BYTES + 1
        cases.append(invalid)
        cases.append(original | {"files": [entry for entry in original["files"] if not entry["path"].endswith("/prices")]})
        for index, invalid in enumerate(cases):
            (source / "index.json").write_bytes(feeds.packed(invalid))
            with self.assertRaises(ValueError):
                feeds.restore(self.root / str(index), fetch=fetch)
            self.assertFalse((self.root / str(index)).exists())


if __name__ == "__main__":
    unittest.main()
