"""Offline tests for the backup checks in iphone_releaselocal_install.py."""
import base64
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import iphone_releaselocal_install as tool  # noqa: E402

SUPPORT = tool.APP_SUPPORT


def make_wal_store(path: Path, cards: int) -> None:
    """A SwiftData-like store whose newest rows live only in the WAL."""
    path.parent.mkdir(parents=True, exist_ok=True)
    keeper = sqlite3.connect(str(path))
    keeper.execute("PRAGMA journal_mode=WAL")
    keeper.execute("PRAGMA wal_autocheckpoint=0")
    keeper.execute("CREATE TABLE ZCOLLECTEDCARD (Z_PK INTEGER PRIMARY KEY, ZNAME TEXT)")
    keeper.execute("CREATE TABLE ZCOLLECTIONACTIVITY (Z_PK INTEGER PRIMARY KEY)")
    keeper.execute("CREATE TABLE Z_METADATA (Z_VERSION INTEGER)")
    keeper.commit()
    keeper.executemany("INSERT INTO ZCOLLECTEDCARD (ZNAME) VALUES (?)", [(f"card {i}",) for i in range(cards)])
    keeper.commit()
    # Copy the three files while the connection is still open, like an app
    # that was stopped without a checkpoint.
    snapshot = {suffix: path.with_name(path.name + suffix).read_bytes() for suffix in ("", "-wal", "-shm")}
    keeper.close()
    for suffix, data in snapshot.items():
        path.with_name(path.name + suffix).write_bytes(data)


def listing_for(root: Path) -> dict:
    return {"result": {"files": [{"relativePath": str(p.relative_to(root)), "fileSize": p.stat().st_size,
                                  "type": "file"} for p in root.rglob("*") if p.is_file()]
                       + [{"relativePath": "Library", "type": "directory"}]}}


class ListingTests(unittest.TestCase):
    def test_reads_files_and_skips_directories(self):
        files = tool.file_listing({"result": {"files": [
            {"relativePath": "/Library/a.json", "fileSize": 3, "type": "file"},
            {"relativePath": "Library", "type": "directory"},
            {"path": "./Documents/b", "size": 0},
        ]}})
        self.assertEqual(files, {"Library/a.json": 3, "Documents/b": 0})

    def test_reads_devicectl_metadata_shape(self):
        listing = {"result": {"files": [
            {"metadata": {"size": 160}, "name": "Documents", "relativePath": "Documents",
             "resources": {"isDirectory": True, "isSymbolicLink": False}},
            {"metadata": {"size": 257, "extendedAttributes": {}}, "name": "Documents/a.json",
             "relativePath": "Documents/a.json", "resources": {"isDirectory": False, "isSymbolicLink": False}},
        ]}}
        self.assertEqual(tool.file_listing(listing), {"Documents/a.json": 257})
        listing["result"]["files"].append({"metadata": {"size": 3}, "relativePath": "Library/l",
                                           "resources": {"isDirectory": False, "isSymbolicLink": True}})
        with self.assertRaises(tool.Refused):
            tool.file_listing(listing)

    def test_refuses_files_without_sizes_and_empty_listings(self):
        with self.assertRaises(tool.Refused):
            tool.file_listing({"result": {"files": [{"relativePath": "x", "type": "file"}]}})
        with self.assertRaises(tool.Refused):
            tool.file_listing({"result": {"files": []}})

    def test_mismatches_are_refused(self):
        with self.assertRaises(tool.Refused):
            tool.compare_listing({"Library/a": 3, "Library/b": 1}, {"Library/a": 3})
        with self.assertRaises(tool.Refused):
            tool.compare_listing({"Library/a": 3}, {"Library/a": 2})
        tool.compare_listing({"Library/a": 3, "tmp/x": 9}, {"Library/a": 3})

    def test_finds_app_and_processes(self):
        apps = {"result": {"apps": [{"bundleIdentifier": tool.BUNDLE_ID, "version": "1.0"}]}}
        self.assertEqual(tool.installed_app(apps)["version"], "1.0")
        self.assertIsNone(tool.installed_app({"result": {"apps": []}}))
        processes = {"result": {"runningProcesses": [
            {"processIdentifier": 10, "executable": "file:///private/var/containers/Bundle/Application/X/TradingCardScanner.app/TradingCardScanner"},
            {"processIdentifier": 11, "executable": "file:///usr/libexec/other"}]}}
        self.assertEqual(tool.app_process_ids(processes), [10])
        with self.assertRaises(tool.Refused):
            tool.app_process_ids({"result": {}})


class BackupTreeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.container = self.root / "container"
        make_wal_store(self.container / SUPPORT / "default.store", cards=7)
        manifest = self.container / SUPPORT / "CardScanner/CollectionStorage/manifest.json"
        manifest.parent.mkdir(parents=True)
        manifest.write_text('{"storeID": "x"}')

    def tearDown(self):
        for path in self.root.rglob("*"):
            path.chmod(0o755 if path.is_dir() else 0o644)
        self.temp.cleanup()

    def test_wal_rows_count_and_backup_bytes_untouched(self):
        store = self.container / SUPPORT / "default.store"
        before = {p.name: p.read_bytes() for p in store.parent.glob("default.store*")}
        self.assertGreater(len(before["default.store-wal"]), 0)
        summary = tool.verify_backup_tree(self.container, tool.file_listing(listing_for(self.container)))
        self.assertEqual(summary["stores"][0]["rowCounts"]["ZCOLLECTEDCARD"], 7)
        self.assertTrue(summary["collectionManifest"])
        after = {p.name: p.read_bytes() for p in store.parent.glob("default.store*")}
        self.assertEqual(before, after)

    def test_missing_wal_is_caught_by_the_listing(self):
        listing = tool.file_listing(listing_for(self.container))
        (self.container / SUPPORT / "default.store-wal").unlink()
        with self.assertRaises(tool.Refused):
            tool.verify_backup_tree(self.container, listing)

    def test_missing_store_or_tables_refused(self):
        (self.container / SUPPORT / "default.store").unlink()
        with self.assertRaises(tool.Refused):
            tool.verify_backup_tree(self.container, tool.file_listing(listing_for(self.container)))

    def test_store_without_collection_tables_refused(self):
        other = self.root / "x" / "default.store"
        other.parent.mkdir()
        sqlite3.connect(str(other)).execute("CREATE TABLE T (a)").connection.close()
        with self.assertRaises(tool.Refused):
            tool.check_store(other, required_tables=tool.COLLECTION_TABLES)

    def test_corrupt_store_refused(self):
        bad = self.root / "bad.store"
        bad.write_bytes(b"SQLite format 3\x00" + b"\x00" * 200)
        with self.assertRaises(Exception):
            tool.check_store(bad)

    def test_restore_set_holds_all_rows_with_empty_wal(self):
        store = self.container / SUPPORT / "default.store"
        target = self.root / "restore" / "default.store"
        tool.prepare_restore_store(store, target)
        self.assertEqual(target.with_name("default.store-wal").stat().st_size, 0)
        self.assertEqual(target.with_name("default.store-shm").stat().st_size, 0)
        only_main = self.root / "only" / "default.store"
        only_main.parent.mkdir()
        only_main.write_bytes(target.read_bytes())
        connection = sqlite3.connect(str(only_main))
        self.assertEqual(connection.execute("SELECT COUNT(*) FROM ZCOLLECTEDCARD").fetchone()[0], 7)
        connection.close()

    def test_checksums_cover_everything_and_detect_changes(self):
        tool.write_checksums(self.container)
        self.assertGreater(tool.verify_checksums(self.container), 0)
        (self.container / SUPPORT / "CardScanner/CollectionStorage/manifest.json").write_text("{}")
        with self.assertRaises(tool.Refused):
            tool.verify_checksums(self.container)

    def test_read_only(self):
        tool.make_read_only(self.container)
        with self.assertRaises(PermissionError):
            (self.container / SUPPORT / "default.store").write_bytes(b"")


class NormalizeCopyTests(unittest.TestCase):
    def test_flattens_only_the_nested_shape(self):
        with tempfile.TemporaryDirectory() as temp:
            nested = Path(temp) / "Library" / "Library" / "Preferences"
            nested.mkdir(parents=True)
            (nested / "a.plist").write_text("x")
            tool.normalize_copy(Path(temp) / "Library")
            self.assertTrue((Path(temp) / "Library/Preferences/a.plist").is_file())
            tool.normalize_copy(Path(temp) / "Library")  # already flat: unchanged
            self.assertTrue((Path(temp) / "Library/Preferences/a.plist").is_file())


class CatalogReportTests(unittest.TestCase):
    def test_reports_packaged_and_persisted_revisions(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            app = root / "App.app"

            def envelope(path: Path, payload: dict, key: str = "k"):
                path.parent.mkdir(parents=True, exist_ok=True)
                encoded = base64.urlsafe_b64encode(json.dumps(payload).encode()).decode().rstrip("=")
                path.write_text(json.dumps({"keyID": key, "payload": encoded, "signature": "s"}))

            envelope(app / "PokemonCatalogRelease/catalog-release.json", {"revision": 24, "sets": [{}, {}]})
            envelope(app / "OnePieceOwnerCatalog/one-piece-owner-catalog.json",
                     {"revision": 10, "registry": {"canonicalCards": [1], "printings": [1, 2]}}, "owner-r10")
            (app / "MagicCatalogSeed").mkdir()
            (app / "MagicCatalogSeed/catalog.json").write_text(json.dumps({"revision": 1, "sets": [1]}))
            (app / "YuGiOhCatalogSeed").mkdir()
            (app / "YuGiOhCatalogSeed/catalog.json").write_text(json.dumps({"generation": "g", "cards": [], "printings": []}))
            (app / "LorcanaCatalogSeed").mkdir()
            (app / "LorcanaCatalogSeed/discovery.json").write_text(json.dumps({"generatedOn": "d", "cards": [], "sealed": []}))
            container = root / "c"
            envelope(container / SUPPORT / "BrowseCatalogCache/CatalogReleases/catalog-release-current.json",
                     {"revision": 22})
            rows = {r["game"]: r for r in tool.catalog_report(container, app)}
            self.assertEqual(rows["Pokémon"]["persistedCurrent"], 22)
            self.assertEqual(rows["Pokémon"]["active"], 24)
            self.assertEqual(rows["Pokémon"]["source"], "bundled signed release")
            self.assertEqual(rows["One Piece"]["active"], 10)
            self.assertEqual(rows["Magic"]["active"], 1)


if __name__ == "__main__":
    unittest.main()
