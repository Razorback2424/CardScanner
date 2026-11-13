import copy
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import market_price_feeds as feeds


class MarketPriceFeedTests(unittest.TestCase):
    def test_m26_market_scope_contains_only_the_verified_product_finishes(self):
        repo = Path(__file__).resolve().parents[2]
        scope = feeds.scope_from_repo(repo)
        normal = {730416, 730422, 730424, 730426, 730427, 730430, 730431, 730432}
        holofoil = {730417, 730418, 730419, 730420, 730421, 730423, 730429}
        self.assertEqual(scope[(3, 24938)],
                         {product: {"Normal"} for product in normal} | {product: {"Holofoil"} for product in holofoil})

    def test_battle_deck_products_enter_scope_with_their_exact_lanes(self):
        repo = Path(__file__).resolve().parents[2]
        scope = feeds.scope_from_repo(repo)
        manifest = json.loads((repo / "publisher/pokemon-battle-deck-finishes.json").read_bytes())
        entries = manifest["entries"]
        self.assertEqual(len(entries), 34)
        self.assertEqual(len({entry["cardID"] for entry in entries}), 34)
        self.assertEqual(len({entry["productID"] for entry in entries}), 34)
        self.assertEqual(sum(lanes == {"Reverse Holofoil"} for lanes in scope[(3, 1840)].values()), 30)
        self.assertEqual(scope[(3, 1840)][729924], {"Reverse Holofoil"})
        self.assertEqual(scope[(3, 1840)][729923], {"Reverse Holofoil"})
        self.assertEqual({entry["productID"] for entry in entries if entry["groupID"] == 24461},
                         {729815, 729816, 729817, 729818})
        for entry in entries:
            self.assertEqual(scope[(3, entry["groupID"])][entry["productID"]], {entry["printing"]})

    def test_delta_reign_uses_exact_normal_and_holofoil_products(self):
        scope = feeds.scope_from_repo(Path(__file__).resolve().parents[2])
        for product in (732417, 732418):
            self.assertEqual(scope[(3, 1840)][product], {"Normal"})
        self.assertEqual(scope[(3, 24451)], {pid: {"Holofoil"} for pid in
                         (730455, 730456, 730453, 730454, 730451, 730452, 730130, 732591, 731807, 731799, 732872)})

    def test_deck_exclusives_scope_only_the_verified_normal_products(self):
        scope = feeds.scope_from_repo(Path(__file__).resolve().parents[2])
        normal = {
            494096, 494950, 494952, 494955, 494956, 494957, 497055, 498187, 501480, 505053, 505059,
            505065, 505070, 505071, 528306, 528307, 528308, 528309, 528428, 528430, 543958, 546428,
            547649, 547650, 547651, 547652, 583519, 583730, 583734, 591109, 598050, 604895, 604896,
            604897, 685652, 725079, 725080, 725081, 725082, 725084, 725085,
        }
        expected = normal | {732417, 732418}
        group = scope[(3, 1840)]
        self.assertEqual({product for product, lanes in group.items() if "Normal" in lanes}, expected)
        self.assertTrue(all(group[product] == {"Normal"} for product in expected))

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

    def test_upstream_product_without_metadata_keeps_an_empty_staged_number_list(self):
        del self.products["results"][0]["extendedData"]
        self.prices["results"] = []
        self.prepare()
        site = self.root / "site" / feeds.NAMESPACE
        product = json.loads((site / "tcgplayer/71/1/products").read_bytes())["results"][0]
        self.assertEqual(product["extendedData"], [])
        self.assertEqual(json.loads((site / "tcgplayer/71/1/prices").read_bytes())["results"], [])

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

    def test_old_yugioh_job_capture_is_refetched_even_when_upstream_build_is_unchanged(self):
        source = self.root / "yugioh"
        (source / "tcgcsv").mkdir(parents=True)
        for name in ("source-build-start.txt", "source-build-end.txt"):
            (source / name).write_text(self.marker)
        self.products["results"][0]["categoryId"] = 2
        self.products["results"][1]["categoryId"] = 2
        for resource, doc in [("products", self.products), ("prices", self.prices)]:
            path = source / "tcgcsv" / f"1-{resource}.json"
            path.write_bytes(feeds.packed(doc))
            timestamp = feeds.instant(self.captured).timestamp()
            os.utime(path, (timestamp, timestamp))
        feeds.prepare({(2, 1): {123: {"Holofoil"}}}, self.root / "cache", self.root / "site",
                      fetch=self.fetch, now=lambda: "2026-10-30T08:00:00+00:00", pause=lambda _: None,
                      yugioh_source=source)
        self.assertIn("https://tcgcsv.com/tcgplayer/2/1/products", self.calls)
        self.assertIn("https://tcgcsv.com/tcgplayer/2/1/prices", self.calls)
        prices = json.loads((self.root / "site" / feeds.NAMESPACE / "tcgplayer/2/1/prices").read_bytes())
        self.assertEqual(prices["sourceFetchedAt"], "2026-10-30T08:00:00+00:00")

    def test_aging_captures_are_refetched_without_relabeling_cached_bytes(self):
        self.prepare()
        self.calls.clear()
        self.prepare("renewed", now="2026-10-29T20:00:00+00:00")
        self.assertEqual(self.calls, ["https://tcgcsv.com/last-updated.txt",
            "https://tcgcsv.com/tcgplayer/71/1/products", "https://tcgcsv.com/tcgplayer/71/1/prices",
            "https://tcgcsv.com/last-updated.txt"])
        doc = json.loads((self.root / "renewed" / feeds.NAMESPACE / "tcgplayer/71/1/prices").read_bytes())
        self.assertEqual(doc["sourceFetchedAt"], "2026-10-29T20:00:00+00:00")
        self.assertEqual(doc["sourceBuild"], self.marker)

    def test_failed_renewal_never_stamps_old_captures_as_new(self):
        self.prepare()
        receipts = next((self.root / "cache").glob("*/captures.json"))
        original = receipts.read_bytes()
        fetch = self.fetch
        def unavailable(url, *args, **kwargs):
            if not url.endswith("last-updated.txt"):
                raise TimeoutError("upstream unavailable")
            return fetch(url, *args, **kwargs)
        self.fetch = unavailable
        with self.assertRaises(TimeoutError):
            self.prepare("failed", now="2026-10-30T08:00:00+00:00")
        self.assertEqual(receipts.read_bytes(), original)
        self.assertFalse((self.root / "failed").exists())

    def test_corrupted_retained_bytes_cannot_be_republished(self):
        self.prepare()
        raw = next((self.root / "cache").glob("*/71-1-prices.json"))
        raw.write_bytes(b"changed")
        with self.assertRaises(ValueError):
            self.prepare("changed")

    def test_http_reads_retry_transient_timeouts_and_server_errors(self):
        with patch.object(feeds, "build_opener") as opener, patch.object(feeds.time, "sleep") as pause:
            opener.return_value.open.side_effect = [URLError(TimeoutError()),
                HTTPError("https://feed.test", 503, "temporary", {}, None), io.BytesIO(b"valid")]
            self.assertEqual(feeds.read_http("https://feed.test"), b"valid")
            self.assertEqual(opener.return_value.open.call_count, 3)
            self.assertEqual([call.args[0] for call in pause.call_args_list], [1, 2])

    def test_http_retry_budget_is_bounded_and_permanent_errors_are_not_retried(self):
        with patch.object(feeds, "build_opener") as opener, patch.object(feeds.time, "sleep"):
            opener.return_value.open.side_effect = TimeoutError()
            with self.assertRaises(TimeoutError):
                feeds.read_http("https://feed.test")
            self.assertEqual(opener.return_value.open.call_count, 3)
        for status in (301, 403, 404):
            with patch.object(feeds, "build_opener") as opener, patch.object(feeds.time, "sleep") as pause:
                opener.return_value.open.side_effect = HTTPError("https://feed.test", status, "permanent", {}, None)
                with self.assertRaises(HTTPError):
                    feeds.read_http("https://feed.test")
                self.assertEqual(opener.return_value.open.call_count, 1)
                pause.assert_not_called()

    def test_absent_namespace_and_byte_limit_remain_fail_closed_without_retries(self):
        with patch.object(feeds, "build_opener") as opener, patch.object(feeds.time, "sleep") as pause:
            opener.return_value.open.side_effect = HTTPError("https://feed.test", 404, "absent", {}, None)
            self.assertIsNone(feeds.read_http("https://feed.test", absent_ok=True))
            pause.assert_not_called()
        with patch.object(feeds, "build_opener") as opener, patch.object(feeds.time, "sleep") as pause:
            opener.return_value.open.return_value = io.BytesIO(b"too large")
            with self.assertRaises(ValueError):
                feeds.read_http("https://feed.test", maximum=2)
            pause.assert_not_called()

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

    def test_publication_rejects_stale_or_future_captures_before_writing_site(self):
        source, fetch = self.published()
        self.assertTrue(feeds.restore(self.root / "fresh", fetch=fetch, require_fresh=True,
                                     now=lambda: "2026-10-29T09:00:00+00:00"))
        for name, now in [("expired", "2026-10-30T02:00:00+00:00"),
                          ("future", "2026-10-29T07:59:59+00:00")]:
            with self.assertRaises(ValueError):
                feeds.restore(self.root / name, fetch=fetch, require_fresh=True, now=lambda: now)
            self.assertFalse((self.root / name).exists())
        # Catalog-only publications must still preserve a valid older namespace.
        self.assertTrue(feeds.restore(self.root / "preserved", fetch=fetch))

    def test_absent_namespace_is_allowed_but_hash_failure_blocks_restore_without_partial_files(self):
        self.assertFalse(feeds.restore(self.root / "absent", fetch=lambda *args, **kwargs: None))
        source, fetch = self.published()
        (source / "tcgplayer/71/1/prices").write_bytes(b"changed")
        with self.assertRaises(ValueError):
            feeds.restore(self.root / "corrupt", fetch=fetch)
        self.assertFalse((self.root / "corrupt").exists())

    def test_required_published_feed_can_use_a_validated_replacement(self):
        with self.assertRaisesRegex(ValueError, "Published market-prices/v1/index.json is missing"):
            feeds.restore(self.root / "absent", fetch=lambda *args, **kwargs: None, require_present=True)
        source, _ = self.published()
        self.assertTrue(feeds.restore(source.parent.parent, require_present=True,
                                     fetch=lambda *args, **kwargs: self.fail("Prepared files require no network")))

    def test_marker_only_feed_cannot_satisfy_publication_checks(self):
        source, fetch = self.published()
        index_path = source / "index.json"
        index = json.loads(index_path.read_bytes())
        index["files"] = [entry for entry in index["files"] if entry["path"] == "last-updated.txt"]
        index_path.write_bytes(feeds.packed(index))

        destination = self.root / "restored"
        for site in (destination, source.parent.parent):
            with self.subTest(site=site.name):
                with self.assertRaisesRegex(ValueError, "at least one product/price pair"):
                    feeds.restore(site, fetch=fetch, require_present=True, require_fresh=True,
                                  now=lambda: "2026-10-29T09:00:00+00:00")
        self.assertFalse(destination.exists())

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
