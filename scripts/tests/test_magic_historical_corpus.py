import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT))
SPEC = importlib.util.spec_from_file_location("magic_corpus", SCRIPT / "stage_magic_historical_corpus.py")
corpus = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(corpus)


class MagicHistoricalCorpusStagingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle = self.root / "Tests.xctest"
        self.bundle.mkdir()
        (self.root / "front.jpg").write_bytes(b"original-image")
        self.manifest = self.root / "evaluation.json"
        self.row = {"index": 6, "filename": "front.jpg",
                    "sha256": hashlib.sha256(b"original-image").hexdigest()}
        self.page = self.root / "provider.json"
        self.page.write_text(json.dumps({"object": "list", "has_more": False, "total_cards": 0, "data": []}))
        self.write_manifest([self.row])

    def write_manifest(self, rows):
        self.manifest.write_text(json.dumps({"schemaVersion": 1, "records": rows,
            "providerSearchSHA256": hashlib.sha256(self.page.read_bytes()).hexdigest()}))

    def stage(self):
        return corpus.stage(self.manifest, self.root, self.bundle, self.page)

    def test_hash_pinned_stage_preserves_original_bytes(self):
        self.assertEqual(self.stage(), 1)
        self.assertEqual((self.bundle / "MagicHistoricalCorpus/front.jpg").read_bytes(), b"original-image")
        self.assertEqual((self.root / "front.jpg").read_bytes(), b"original-image")

    def test_changed_duplicate_and_escaping_sources_reject_before_writes(self):
        for rows in [[self.row | {"sha256": "changed"}], [self.row, self.row],
                     [self.row | {"filename": "../front.jpg"}]]:
            self.write_manifest(rows)
            with self.assertRaises(ValueError): self.stage()
            self.assertFalse((self.bundle / "MagicHistoricalCorpus").exists())

    def test_partial_warned_and_malformed_provider_captures_reject(self):
        original = json.loads(self.page.read_text())
        for changes in [{"has_more": True}, {"total_cards": 1}, {"warnings": ["partial"]}]:
            self.page.write_text(json.dumps(original | changes))
            self.write_manifest([self.row])
            with self.assertRaises(ValueError): self.stage()
            self.assertFalse((self.bundle / "MagicHistoricalCorpus").exists())

    def test_changed_provider_capture_rejects_before_writes(self):
        self.page.write_text(self.page.read_text() + "\n")
        with self.assertRaises(ValueError): self.stage()
        self.assertFalse((self.bundle / "MagicHistoricalCorpus").exists())

    def test_general_provider_capture_is_pinned_before_staging(self):
        general = self.root / "general.json"
        general.write_text("{}")
        data = json.loads(self.manifest.read_text())
        data["generalProviderCaptureSHA256"] = hashlib.sha256(general.read_bytes()).hexdigest()
        self.manifest.write_text(json.dumps(data))
        self.assertEqual(corpus.stage(self.manifest, self.root, self.bundle, self.page, general), 1)
        self.assertEqual((self.bundle / "MagicHistoricalCorpus/general-provider-captures.json").read_text(), "{}")
        general.write_text("{\"changed\":true}")
        with self.assertRaises(ValueError): corpus.stage(self.manifest, self.root, self.bundle, self.page, general)
