import sys
from pathlib import Path
import unittest

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from audit_one_piece_live_artwork import match_products, region_errors


class LiveArtworkAuditTests(unittest.TestCase):
    def test_parallel_artwork_uses_independent_market_product_identity(self):
        base = Image.new("RGB", (84, 117), (25, 55, 90))
        alt = Image.new("RGB", (84, 117), (230, 100, 25))
        rows = [
            {"artworkAlias": "EB05-016", "number": "EB05-016"},
            {"artworkAlias": "EB05-016_p1", "number": "EB05-016"},
        ]
        products = [
            {"productId": 718684, "name": "Nico Robin", "imageUrl": "base"},
            {"productId": 723248, "name": "Nico Robin (Super Rare Alternate Art)", "imageUrl": "alt"},
        ]

        def load(provider, value):
            if provider == "bandai":
                return {"EB05-016": base, "EB05-016_p1": alt}[value], None
            return {"base": base, "alt": alt}[value["imageUrl"]], None

        matches, gaps = match_products("EB05-016", rows, products, load)
        self.assertEqual(gaps, {})
        self.assertEqual([(m["productID"], m["matchedAlias"]) for m in matches],
                         [(718684, "EB05-016"), (723248, "EB05-016_p1")])
        self.assertTrue(all(m["decision"] == "unique-artwork-candidate" for m in matches))

    def test_missing_sibling_blocks_artwork_authority_for_all_market_products(self):
        image = Image.new("RGB", (84, 117), "green")
        rows = [
            {"artworkAlias": "EB05-006", "number": "EB05-006"},
            {"artworkAlias": "EB05-006_p1", "number": "EB05-006"},
        ]
        product = [{"productId": 718679, "name": "Miss Buckingham Stussy",
                    "imageUrl": "base"}]

        def load(provider, value):
            if provider == "bandai" and value == "EB05-006_p1":
                return None, "not-captured"
            return image, None

        matches, gaps = match_products("EB05-006", rows, product, load)
        self.assertEqual(gaps, {"EB05-006_p1": "not-captured"})
        self.assertEqual(matches[0]["decision"], "official-sibling-image-unavailable")
        self.assertNotIn("matchedAlias", matches[0])

    def test_absent_market_art_does_not_grant_identity(self):
        rows = [{"artworkAlias": "EB05-014_p2", "number": "EB05-014"}]
        product = [{"productId": 718677, "name": "Shirahoshi (Manga)", "imageUrl": ""}]

        def load(provider, value):
            if provider == "market":
                return None, "no-recorded-image-url"
            return Image.new("RGB", (84, 117), "blue"), None

        matches, _ = match_products("EB05-014", rows, product, load)
        self.assertEqual(matches[0]["decision"], "market-image-unavailable")
        self.assertNotIn("matchedAlias", matches[0])

    def test_region_errors_are_zero_for_equal_references(self):
        image = Image.new("RGB", (84, 117), "navy")
        self.assertEqual(region_errors(image, image), (0, 0, 0))


if __name__ == "__main__":
    unittest.main()
