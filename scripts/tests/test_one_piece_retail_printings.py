import unittest
from pathlib import Path
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from reconcile_one_piece_retail_printings import (
    exact_artwork_match, listing_treatment, market_agrees, promotion_label, retailer_listings,
)
from normalize_one_piece_sources import Document
from one_piece_eb05_retail import cardboard_listings, rocket_listings


class OnePieceRetailPrintingsTests(unittest.TestCase):
    def test_image_match_requires_clear_agreement_in_every_region(self):
        scores = {"original": (0.013, 0.010, 0.014), "parallel": (0.170, 0.090, 0.013)}
        self.assertEqual(exact_artwork_match(scores), "original")
        scores["parallel"] = (0.012, 0.017, 0.015)
        self.assertIsNone(exact_artwork_match(scores))
        self.assertIsNone(exact_artwork_match({"wrong-footer": (0.002, 0.001, 0.025)}))

    def test_retailer_finish_is_english_and_bound_to_the_expected_group(self):
        row = '''<div class="productCard"><span class="small">OP09-020</span>
        <a class="small" href="/Products/100/68/24305/Event">Come On!! We'll Fight You!! (Manga)</a>
        <img class="productImage" src="https://product-images.tcgplayer.com/fit-in/600x600/123.jpg">
        <div class="small">English - Near Mint - Foil</div></div>'''
        [listing] = retailer_listings(Document(row.encode()).root, "24305")
        self.assertEqual((listing["sourceID"], listing["number"], listing["finish"]), ("24305:100", "OP09-020", "foil"))
        self.assertEqual(list(retailer_listings(Document(row.encode()).root, "24306")), [])
        japanese = row.replace("English -", "Japanese -")
        self.assertEqual(list(retailer_listings(Document(japanese.encode()).root, "24305")), [])
        ambiguous = row.replace("</div></div>", "</div><div class='small'>English - Near Mint - Normal</div></div>")
        self.assertEqual(list(retailer_listings(Document(ambiguous.encode()).root, "24305")), [])

    def test_retailer_title_keeps_unknown_stamps_and_revisions_held(self):
        self.assertEqual(listing_treatment("OP01-025", "Roronoa Zoro", "Roronoa Zoro (025) (Parallel)"),
                         ("Parallel", "Alternate artwork"))
        self.assertEqual(listing_treatment("ST30-014", "Mr.3(Galdino)", "Mr.3(Galdino)"), ("", "Standard artwork"))
        self.assertIsNone(listing_treatment("OP01-025", "Roronoa Zoro", "Roronoa Zoro (025) (Winner) (Parallel)"))

    def test_marketplace_conflicts_hold_exact_retailer_printing(self):
        listing = {"number": "OP09-042", "imageProductID": "596971", "finish": "normal"}
        title = ("Parallel", "Alternate artwork")
        products = {596971: {"name": "Buggy (042) (Parallel)",
                             "extendedData": [{"name": "Number", "value": "OP09-042"}]}}
        self.assertFalse(market_agrees(listing, title, "Buggy", products, {596971: {"foil"}}))
        self.assertFalse(market_agrees(listing, title, "Buggy", products, {596971: {"normal", "foil"}}))
        self.assertFalse(market_agrees(listing, title, "Buggy", products, {}))
        self.assertFalse(market_agrees(listing, ("Manga", "Manga artwork"), "Buggy", products, {596971: {"normal"}}))
        self.assertTrue(market_agrees(listing, title, "Buggy", products, {596971: {"normal"}}))

    def test_eb05_storefront_binds_english_finish_to_exact_product_image(self):
        url = ("https://www.cardboardcolosseumnj.com/onepiece/singles/extra-booster-one-piece-heroines-edition-vol-2/"
               "monet-eb05-007-p714391")
        html = f'''
        <link rel="canonical" href="{url}">
        <meta property="og:image" content="https://sortswift.nyc3.cdn.digitaloceanspaces.com/cards/714391.jpg">
        <h1>Monet</h1>
        <dl><dt>Set</dt><dd>Extra Booster: One Piece Heroines Edition Vol. 2</dd>
        <dt>Collector number</dt><dd>#EB05-007</dd></dl>
        <table><tr><th>Printing</th><th>Condition</th><th>Language</th></tr>
        <tr><td><span class="font-medium">Normal</span></td><td>NM</td><td>EN</td></tr></table>'''
        [listing] = cardboard_listings(url, html.encode())
        self.assertEqual((listing["provider"], listing["number"], listing["finish"], listing["imageProductID"]),
                         ("cardboard-colosseum", "EB05-007", "normal", "714391"))
        for document in (html.replace("<td>EN</td>", "<td>-</td>"),
                         html.replace("/cards/714391.jpg", "/cards/714392.jpg"),
                         html.replace("Edition Vol. 2</dd>", "Edition Vol. 1</dd>")):
            self.assertEqual(list(cardboard_listings(url, document.encode())), [])

    def test_promo_retailer_must_name_the_exact_official_distribution(self):
        labels = ["Winner Pack 2026 Vol. 2", "Included in Tournament Pack 2026 Vol. 2"]
        self.assertEqual(promotion_label("P-101", "Tony Tony.Chopper",
                                        "Tony Tony.Chopper (Winner Pack 2026 Vol.2)", labels), labels[0])
        self.assertEqual(promotion_label("P-101", "Tony Tony.Chopper",
                                        "Tony Tony.Chopper (Tournament Pack 2026 Vol. 2)", labels), labels[1])
        self.assertIsNone(promotion_label("P-101", "Tony Tony.Chopper", "Tony Tony.Chopper (Winner)", labels))
        self.assertIsNone(promotion_label("P-101", "Tony Tony.Chopper", "Tony Tony.Chopper (Winner Pack 2026 Vol.2)",
                                          [*labels, "Winner Pack 2026 Vol.2"]))
        self.assertIsNone(promotion_label("P-101", "Tony Tony.Chopper", "Nami (Winner Pack 2026 Vol.2)", labels))

    def test_shopify_eb05_requires_explicit_printing_option_matching_title(self):
        url = "https://www.rocketcitytoys.com/products/nico-robin-sp-eb05-eb05-016.js"
        record = {"handle": "nico-robin-sp-eb05-eb05-016", "type": "One Piece Card Game Singles",
                  "vendor": "Extra Booster: One Piece Heroines Edition Vol. 2",
                  "title": "Foil Nico Robin (SP) EB05-016 Near Mint Extra Booster: One Piece Heroines Edition Vol. 2",
                  "featured_image": "//cdn.shopify.com/s/files/1/0801/4423/6835/files/712885.jpg?v=1",
                  "options": [{"position": position, "name": name}
                              for position, name in enumerate(["Condition", "Language", "Printing"], 1)],
                  "variants": [{"id": 1, "option1": "Near Mint", "option2": "English", "option3": "Foil"}]}
        [listing] = rocket_listings(url, json.dumps(record).encode())
        self.assertEqual((listing["number"], listing["title"], listing["finish"], listing["imageProductID"]),
                         ("EB05-016", "Nico Robin (SP)", "foil", "712885"))
        record["variants"][0]["option3"] = "Normal"
        self.assertEqual(list(rocket_listings(url, json.dumps(record).encode())), [])
