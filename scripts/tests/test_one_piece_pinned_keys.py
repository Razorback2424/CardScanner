import base64
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("pinned_keys", Path(__file__).parents[1] / "one_piece_pinned_keys.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PinnedKeysTests(unittest.TestCase):
    def test_exports_app_pins(self):
        key = base64.b64encode(bytes(range(32))).decode()
        config = f"// comment\nONE_PIECE_CATALOG_PINNED_KEYS = one-piece-production:{key}\n"
        self.assertEqual(module.pinned_keys(config), {"one-piece-production": key})

    def test_rejects_missing_invalid_and_duplicate_pins(self):
        key = base64.b64encode(bytes(range(32))).decode()
        for value in ["", "pokemon-key:" + key, "one-piece-key:invalid",
                      f"one-piece-key:{key},one-piece-key:{key}"]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                module.pinned_keys("ONE_PIECE_CATALOG_PINNED_KEYS = " + value)
