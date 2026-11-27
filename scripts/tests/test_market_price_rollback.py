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

    def test_backup_bootstraps_and_catches_up_on_builds_missed_during_an_outage(self):
        old, old_pointer = self.fixture("older-r2", price=10)
        active, active_pointer = self.fixture("active-r2", price=20)
        self.host_v2(rollback.R2, old)
        self.host_v2(rollback.R2, active)
        candidate_site, candidate = self.fixture("candidate", price=30)
        self.host_v2(rollback.R2, candidate_site)
        shutil.rmtree(candidate_site / v2.V2)
        inventory = self.root / "inventory.json"
        inventory.write_bytes(packed([f"{rollback.BUILDS}{pointer['build']}/"
                                      for pointer in (old_pointer, active_pointer, candidate)]))
        self.assertEqual(rollback.prepare(candidate_site, rollback.inventory_ids(inventory),
                                          packed(candidate), self.fetch), candidate)
        all_builds = {pointer["build"] for pointer in (old_pointer, active_pointer, candidate)}
        inventory_bytes = (candidate_site / rollback.HISTORY).read_bytes()
        self.assertEqual(rollback.history(inventory_bytes), all_builds)
        self.host_v2(ORIGIN, candidate_site)
        rollback.verify(candidate_site, self.fetch)
        rollback.confirm_primary_pointer(packed(candidate), self.fetch)

        # A new full-site catalog checkout has no staged prices of its own.
        catalog = self.root / "catalog-only"
        rollback.restore(catalog, self.fetch)
        self.assertEqual((catalog / rollback.HISTORY).read_bytes(), inventory_bytes)
        self.assertEqual((catalog / v2.LATEST).read_bytes(), packed(candidate))
        self.assertEqual({path.relative_to(catalog): path.read_bytes() for path in catalog.rglob("*") if path.is_file()},
                         {path.relative_to(candidate_site): path.read_bytes()
                          for path in (candidate_site / v2.V2).rglob("*") if path.is_file()})

        missed_site, missed = self.fixture("firebase-outage", price=35)
        self.host_v2(rollback.R2, missed_site)
        next_site, next_pointer = self.fixture("next", price=40)
        self.host_v2(rollback.R2, next_site)
        shutil.rmtree(next_site / v2.V2)
        rollback.restore(next_site, self.fetch, prefer_r2=True)
        inventory.write_bytes(packed([f"{rollback.VERIFIED}{pointer['build']}.json"
                                      for pointer in (missed, next_pointer)]))
        self.assertEqual(rollback.prepare(next_site, rollback.inventory_ids(inventory),
                                          packed(next_pointer), self.fetch), next_pointer)
        self.assertEqual(rollback.history((next_site / rollback.HISTORY).read_bytes()),
                         all_builds | {missed["build"], next_pointer["build"]})
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
        old, older = self.fixture("old")
        shutil.rmtree(old / v2.V2)
        with self.assertRaisesRegex(ValueError, "pointer differs"):
            rollback.prepare(old, {older["build"]}, packed(older), self.fetch)
        with self.assertRaisesRegex(ValueError, "missing its active"):
            rollback.prepare(old, set(), packed(pointer), self.fetch)
        with self.assertRaisesRegex(ValueError, "does not reproduce"):
            rollback.prepare(old, {pointer["build"]}, packed(pointer), self.fetch)
        (old / v2.LATEST).unlink()
        self.remote[ORIGIN][v2.LATEST] = packed(pointer)
        with self.assertRaisesRegex(ValueError, "pointer and history are incomplete"):
            rollback.restore(old, self.fetch)

    def test_firebase_backup_requires_byte_identical_r2_pointer(self):
        first, pointer = self.fixture("old")
        second, _ = self.fixture("correction", price=25)
        self.host_v2(rollback.R2, first)
        rollback.confirm_primary_pointer(packed(pointer), self.fetch)
        self.host_v2(rollback.R2, second)
        with self.assertRaisesRegex(ValueError, "pointer differs"):
            rollback.confirm_primary_pointer(packed(pointer), self.fetch)

    def test_sync_r2_catches_up_missed_builds_even_when_catalog_scope_advanced(self):
        first_site, first = self.fixture("first", price=10)
        self.host_v2(rollback.R2, first_site)
        (first_site / rollback.HISTORY).write_bytes(rollback.history_bytes({first["build"]}))
        self.host_v2(ORIGIN, first_site)

        # Two price builds land on R2 while Firebase is out.
        missed_site, missed = self.fixture("missed", price=15)
        self.host_v2(rollback.R2, missed_site)
        latest_site, latest = self.fixture("latest", price=20)
        self.host_v2(rollback.R2, latest_site)

        # Now a catalog publish advances One Piece's scope on R2 ahead of the last price build.
        backup_site = self.root / "catalog-backup-site"
        shutil.copytree(latest_site / NAMESPACE, backup_site / NAMESPACE)
        advanced_scope = backup_site / "one-piece/v1/market-price-scope.json"
        advanced_scope.parent.mkdir(parents=True, exist_ok=True)
        advanced_scope.write_bytes(packed({
            "schemaVersion": 1, "game": "one-piece", "revision": 9,
            "catalogSHA256": "c" * 64, "pointerSHA256": "d" * 64,
            "groups": [[99, [[456, ["Normal"]]]]],
        }))
        rollback.restore(backup_site, self.fetch, prefer_r2=True)
        synced = rollback.sync_r2(backup_site, {first["build"], missed["build"], latest["build"]}, self.fetch)
        self.assertEqual(synced, latest)
        self.assertEqual(rollback.history((backup_site / rollback.HISTORY).read_bytes()),
                         {first["build"], missed["build"], latest["build"]})
        self.assertEqual((backup_site / v2.LATEST).read_bytes(), packed(latest))

        # Verify against Firebase once deployed.
        self.host_v2(ORIGIN, backup_site)
        rollback.verify(backup_site, self.fetch)
        rollback.confirm_primary_pointer(packed(latest), self.fetch)

        # Reject if R2 legacy v1 index disagrees with R2 active v2 build.
        (backup_site / NAMESPACE / "index.json").write_bytes(b'{"schemaVersion":1}\n')
        with self.assertRaisesRegex(ValueError, "legacy v1 prices do not match"):
            rollback.sync_r2(backup_site, {first["build"], missed["build"], latest["build"]}, self.fetch)

    def test_sync_r2_accepts_already_retained_pre_receipt_build_and_rejects_unrecorded_new_build(self):
        legacy_site, legacy = self.fixture("legacy-retained", price=10)
        self.host_v2(rollback.R2, legacy_site)
        (legacy_site / rollback.HISTORY).write_bytes(rollback.history_bytes({legacy["build"]}))
        self.host_v2(ORIGIN, legacy_site)
        backup_site = self.root / "pre-receipt-backup"
        shutil.copytree(legacy_site / NAMESPACE, backup_site / NAMESPACE)
        rollback.restore(backup_site, self.fetch, prefer_r2=True)
        # Empty verified-builds inventory is valid when the active R2 build is already retained on Firebase.
        self.assertEqual(rollback.sync_r2(backup_site, set(), self.fetch), legacy)
        # A brand-new R2 build absent from both verified-builds and retained history still fails closed.
        unrecorded_site, _ = self.fixture("unrecorded-new", price=15)
        self.host_v2(rollback.R2, unrecorded_site)
        with self.assertRaisesRegex(ValueError, "missing its active price build"):
            rollback.sync_r2(backup_site, set(), self.fetch)

    def test_sync_r2_rejects_older_r2_build_or_concurrent_firebase_change(self):
        newer_site, newer = self.fixture("newer", marker="2026-11-28T20:05:59+00:00", price=30)
        (newer_site / rollback.HISTORY).write_bytes(rollback.history_bytes({newer["build"]}))
        self.host_v2(ORIGIN, newer_site)
        older_site, older = self.fixture("older", marker="2026-11-27T20:05:59+00:00", price=20)
        self.host_v2(rollback.R2, older_site)
        backup_site = self.root / "older-sync"
        shutil.copytree(older_site / NAMESPACE, backup_site / NAMESPACE)
        rollback.restore(backup_site, self.fetch)
        with self.assertRaisesRegex(ValueError, "older Firebase v2"):
            rollback.sync_r2(backup_site, {older["build"]}, self.fetch)

        # Concurrent Firebase mutation during sync is rejected too.
        fresh_site, fresh = self.fixture("fresh", marker="2026-11-29T20:05:59+00:00", price=40)
        self.host_v2(rollback.R2, fresh_site)
        backup_site2 = self.root / "concurrent-sync"
        shutil.copytree(fresh_site / NAMESPACE, backup_site2 / NAMESPACE)
        rollback.restore(backup_site2, self.fetch)
        # Mutate Firebase while backup_site2 was staged.
        (fresh_site / rollback.HISTORY).write_bytes(rollback.history_bytes({newer["build"], fresh["build"]}))
        self.host_v2(ORIGIN, fresh_site)
        with self.assertRaisesRegex(ValueError, "changed before the catalog deploy"):
            rollback.sync_r2(backup_site2, {fresh["build"]}, self.fetch)

    def test_workflow_can_publish_primary_prices_without_any_firebase_job(self):
        workflow_file = Path(__file__).resolve().parents[2] / ".github/workflows/yugioh-catalog.yml"
        workflow = workflow_file.read_text()
        primary, remaining = workflow.split("\n  publish-prices-to-r2:\n", 1)[1].split("\n  inventory-r2-price-builds:\n", 1)
        self.assertNotIn("needs:", primary)
        self.assertNotIn("FIREBASE_", primary)
        self.assertNotIn("web.app", primary)
        self.assertIn("--primary-prices", primary)
        self.assertIn("needs: publish-prices-to-r2", remaining)
        self.assertIn("needs: [publish-prices-to-r2, inventory-r2-price-builds]", remaining)
        self.assertIn("The verified R2 price publication remains active.", remaining)
        # Catalog synchronization must no longer originate from Firebase.
        self.assertNotIn("mirror-catalogs-to-r2:", workflow)
        self.assertIn("--origin \"$R2_READ_ORIGIN\"", remaining)

    def test_all_catalog_workflows_are_r2_first_with_independent_firebase_backup(self):
        workflows = Path(__file__).resolve().parents[2] / ".github/workflows"
        cases = (
            ("pokemon-catalog.yml", "publish-production", "v1"),
            ("one-piece-catalog.yml", "publish-reviewed-artifact", "one-piece/v1"),
            ("magic-catalog.yml", "publish-production", "magic/v1"),
        )
        for filename, stage_job, namespace in cases:
            with self.subTest(workflow=filename):
                text = (workflows / filename).read_text()
                stage_body = text.split(f"\n  {stage_job}:\n", 1)[1].split("\n  publish-r2-catalog:\n", 1)[0]
                r2_body = text.split("\n  publish-r2-catalog:\n", 1)[1].split("\n  backup-firebase-catalog:\n", 1)[0]
                backup_body = text.split("\n  backup-firebase-catalog:\n", 1)[1]
                # Staging and R2 primary publication must not depend on Firebase.
                self.assertNotIn("FIREBASE_", stage_body)
                self.assertNotIn("web.app", stage_body)
                self.assertIn("--write-catalog-metadata", stage_body)
                self.assertNotIn("FIREBASE_", r2_body)
                self.assertNotIn("web.app", r2_body)
                self.assertIn("environment: r2-catalog-production", r2_body)
                self.assertIn("group: scanstash-catalog-r2-hosting", r2_body)
                self.assertIn(f"--primary-catalog {namespace}", r2_body)
                # Firebase backup runs strictly downstream of R2 publication and restores from R2.
                self.assertIn(f"needs: [{stage_job}, publish-r2-catalog]", backup_body)
                self.assertIn("group: scanstash-catalog-production-hosting", backup_body)
                self.assertIn("scripts/restore_catalog_hosting_site.sh", backup_body)
                self.assertIn("market_price_rollback.py sync-r2", backup_body)
                self.assertIn("verify-firebase-catalogs", backup_body)
                self.assertIn("The verified R2 catalog publication remains active.", backup_body)

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
