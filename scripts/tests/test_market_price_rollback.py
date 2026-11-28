from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from urllib.error import HTTPError
from urllib.parse import urlsplit

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import market_price_rollback as rollback
import market_price_v2 as v2
from market_price_feeds import NAMESPACE, ORIGIN, packed
from r2_catalog_publish import HostingRules
import test_r2_catalog_publish as publisher_tests


class FirebaseRollbackTests(unittest.TestCase):
    def setUp(self):
        work = tempfile.TemporaryDirectory()
        self.addCleanup(work.cleanup)
        self.root = Path(work.name)
        self.enterContext(redirect_stdout(StringIO()))
        self.remote = {ORIGIN: {}, rollback.R2: {}}

    def fetch(self, url, limit, *, absent_ok=False):
        parsed = urlsplit(url)
        raw = self.remote[f"{parsed.scheme}://{parsed.netloc}"].get(parsed.path.lstrip("/"))
        if raw is None and not absent_ok:
            raise HTTPError(url, 404, "missing fixture", {}, None)
        if raw is not None and len(raw) > limit:
            raise ValueError("fixture exceeded read budget")
        return raw

    def fixture(self, name, **kwargs):
        return publisher_tests.AtomicPriceV2Tests.fixture(self, name, **kwargs)

    def host_v2(self, origin, site):
        for path in (site / v2.V2).rglob("*"):
            if path.is_file():
                self.remote[origin][path.relative_to(site).as_posix()] = path.read_bytes()

    def test_bootstrap_retains_all_r2_builds_and_later_deploys_keep_them(self):
        old, old_pointer = self.fixture("older-r2", price=10)
        active, active_pointer = self.fixture("active-r2", price=20)
        self.host_v2(rollback.R2, old)
        self.host_v2(rollback.R2, active)
        candidate_site, candidate = self.fixture("candidate", price=30)
        shutil.rmtree(candidate_site / v2.V2)
        inventory = self.root / "inventory.json"
        inventory.write_bytes(packed([f"{rollback.BUILDS}{pointer['build']}/"
                                      for pointer in (old_pointer, active_pointer)]))
        self.assertEqual(rollback.prepare(candidate_site, rollback.inventory_ids(inventory), self.fetch), candidate)
        all_builds = {pointer["build"] for pointer in (old_pointer, active_pointer, candidate)}
        inventory_bytes = (candidate_site / rollback.HISTORY).read_bytes()
        self.assertEqual(rollback.history(inventory_bytes), all_builds)
        self.host_v2(ORIGIN, candidate_site)
        rollback.verify(candidate_site, self.fetch)
        rollback.confirm_pointer(packed(candidate), self.fetch)

        # A new full-site catalog checkout has no staged prices of its own.
        catalog = self.root / "catalog-only"
        rollback.restore(catalog, self.fetch)
        self.assertEqual((catalog / rollback.HISTORY).read_bytes(), inventory_bytes)
        self.assertEqual((catalog / v2.LATEST).read_bytes(), packed(candidate))
        self.assertEqual({path.relative_to(catalog): path.read_bytes() for path in catalog.rglob("*") if path.is_file()},
                         {path.relative_to(candidate_site): path.read_bytes()
                          for path in (candidate_site / v2.V2).rglob("*") if path.is_file()})

        next_site, next_pointer = self.fixture("next", price=40)
        shutil.rmtree(next_site / v2.V2)
        rollback.restore(next_site, self.fetch)
        self.remote[rollback.R2].clear()
        self.assertEqual(rollback.prepare(next_site, None, self.fetch), next_pointer)
        self.assertEqual(rollback.history((next_site / rollback.HISTORY).read_bytes()), all_builds | {next_pointer["build"]})
        self.assertEqual((next_site / NAMESPACE / "index.json").read_bytes(),
                         (next_site / rollback.BUILDS / next_pointer["build"] / "index.json").read_bytes())

    def test_missing_or_corrupt_retained_build_blocks_full_site_restore(self):
        site, pointer = self.fixture("firebase")
        (site / rollback.HISTORY).write_bytes(rollback.history_bytes({pointer["build"]}))
        self.host_v2(ORIGIN, site)
        key = f"{rollback.BUILDS}{pointer['build']}/tcgplayer/3/1/prices"
        raw = self.remote[ORIGIN].pop(key)
        destination = self.root / "catalog"
        with self.assertRaises(HTTPError):
            rollback.restore(destination, self.fetch)
        self.remote[ORIGIN][key] = b" " + raw[1:]
        with self.assertRaisesRegex(ValueError, "hash/size mismatch"):
            rollback.restore(destination, self.fetch)
        with self.assertRaisesRegex(ValueError, "hash/size mismatch"):
            rollback.verify(site, self.fetch)
        self.assertFalse((destination / v2.LATEST).exists())

    def test_superseded_candidate_and_incomplete_inventory_fail_closed(self):
        active, pointer = self.fixture("r2", marker="2026-11-27T20:05:59+00:00")
        self.host_v2(rollback.R2, active)
        old, _ = self.fixture("old")
        shutil.rmtree(old / v2.V2)
        with self.assertRaisesRegex(ValueError, "older Firebase v2"):
            rollback.prepare(old, {pointer["build"]}, self.fetch)
        with self.assertRaisesRegex(ValueError, "history disappeared"):
            rollback.prepare(old, None, self.fetch)
        self.remote[ORIGIN][v2.LATEST] = packed(pointer)
        with self.assertRaisesRegex(ValueError, "pointer and history are incomplete"):
            rollback.restore(old, self.fetch)

    def test_r2_requires_byte_identical_firebase_pointer(self):
        first, pointer = self.fixture("old")
        second, _ = self.fixture("correction", price=25)
        self.host_v2(ORIGIN, first)
        rollback.confirm_pointer(packed(pointer), self.fetch)
        self.host_v2(ORIGIN, second)
        with self.assertRaisesRegex(ValueError, "pointer differs"):
            rollback.confirm_pointer(packed(pointer), self.fetch)

    def test_firebase_header_rules_do_not_overlap_for_v2(self):
        rules = HostingRules.load(Path(__file__).resolve().parents[2] / "firebase.json")
        immutable = "public,max-age=31536000,immutable"
        json_type = "application/json; charset=utf-8"
        expected = {
            v2.LATEST: (json_type, "no-cache"),
            rollback.HISTORY: (json_type, "no-cache"),
            "market-prices/v2/builds/hash/index.json": (json_type, immutable),
            "market-prices/v2/builds/hash/scopes/yugioh.json": (json_type, immutable),
            "market-prices/v2/builds/hash/tcgplayer/3/1/products": (json_type, immutable),
            "market-prices/v2/builds/hash/last-updated.txt": ("text/plain; charset=utf-8", immutable),
        }
        for path, headers in expected.items():
            with self.subTest(path=path):
                self.assertEqual(sum(rule.match(path) is not None for rule, _ in rules.rules), 1)
                self.assertEqual(rules.headers(path), headers)


if __name__ == "__main__":
    unittest.main()
