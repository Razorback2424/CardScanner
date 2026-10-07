import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT))
SPEC = importlib.util.spec_from_file_location("magic_titles", SCRIPT / "build_magic_historical_title_vocabulary.py")
titles = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(titles)

class MagicHistoricalTitleVocabularyTests(unittest.TestCase):
    def test_vocabulary_spans_eras_and_faces_without_printing_authority(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            meta = {"date": "2026-10-06", "version": "test"}
            source = root / "AllPrintings.json"
            source.write_text(json.dumps({"meta": meta, "data": {
                "OLD": {"code": "OLD", "releaseDate": "1993-08-05", "cards": [
                    {"name": "Old Card", "layout": "normal"},
                    {"name": "Level Up Card", "layout": "leveler"},
                    {"name": "Digital Card", "layout": "normal", "isOnlineOnly": True},
                    {"name": "Token", "layout": "token"}]},
                "SPL": {"code": "SPL", "releaseDate": "2001-06-04", "cards": [
                    {"name": "Left // Right", "faceName": "Left", "layout": "split"},
                    {"name": "Left // Right", "faceName": "Right", "layout": "split"}]},
                "NEW": {"code": "NEW", "releaseDate": "2014-07-18", "cards": [
                    {"name": "Modern Card", "layout": "normal"}]}}}))
            pilot = root / "pilot.json"
            pilot.write_text(json.dumps({"meta": meta}))
            output = root / "words.json"
            self.assertEqual(titles.build(source, pilot, output), 5)
            first = output.read_bytes()
            artifact = json.loads(first)
            self.assertEqual(artifact["titles"], ["Left", "Left // Right", "Level Up Card", "Old Card", "Right"])
            self.assertNotIn("records", artifact)
            titles.build(source, pilot, output)
            self.assertEqual(output.read_bytes(), first)
