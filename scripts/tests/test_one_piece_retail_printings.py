import unittest
from pathlib import Path
import json
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from reconcile_one_piece_retail_printings import (
    PRB01_MANGA_SPEC, exact_artwork_match, exact_digital_artwork_match, listing_treatment, market_agrees,
    photographic_artwork_match, promotion_label, promotion_treatment, retailer_listings, reviewed_promo_artwork,
    treatment_matches_alias,
)
from normalize_one_piece_sources import Document
from one_piece_eb05_retail import cardboard_listings, rocket_listings, weirdwolf_listings


class OnePieceRetailPrintingsTests(unittest.TestCase):
    def test_image_match_requires_clear_agreement_in_every_region(self):
        scores = {"original": (0.013, 0.010, 0.014), "parallel": (0.170, 0.090, 0.013)}
        self.assertEqual(exact_artwork_match(scores), "original")
        scores["parallel"] = (0.012, 0.017, 0.015)
        self.assertIsNone(exact_artwork_match(scores))
        self.assertIsNone(exact_artwork_match({"wrong-footer": (0.002, 0.001, 0.025)}))

    def test_digital_comparison_distinguishes_a_center_stamp_and_rejects_ties(self):
        from PIL import Image

        ordinary = Image.new("RGB", (84, 117), (30, 50, 100))
        ordinary.paste((180, 180, 180), (8, 48, 76, 68))
        stamped = ordinary.copy()
        stamped.paste((230, 180, 10), (56, 53, 75, 66))
        finalist = ordinary.copy()
        finalist.paste((20, 20, 20), (56, 53, 75, 66))
        references = {"ordinary": ordinary, "stamped": stamped, "finalist": finalist}
        scores = {key: (0.006, 0.007, 0.006) for key in references}

        self.assertIsNone(exact_artwork_match(scores))
        for key, source in references.items():
            jpeg_like = source.point(lambda pixel: min(pixel + 3, 255))
            match = exact_digital_artwork_match(jpeg_like, references, scores)
            self.assertEqual(match[0], key)
            self.assertGreaterEqual(match[1], 20)

        self.assertIsNone(exact_digital_artwork_match(
            stamped, {**references, "same-image": stamped}, {**scores, "same-image": scores["stamped"]}))
        unknown = ordinary.copy()
        unknown.paste((90, 90, 90), (56, 53, 75, 66))
        self.assertIsNone(exact_digital_artwork_match(unknown, references, scores))
        scores["stamped"] = (0.006, 0.007, 0.025)
        self.assertIsNone(exact_digital_artwork_match(stamped, references, scores))

    def test_photo_comparison_requires_distinct_designs_and_matching_footer(self):
        from PIL import Image

        original = Image.linear_gradient("L").resize((84, 117)).convert("RGB")
        parallel = Image.linear_gradient("L").rotate(90).resize((84, 117)).convert("RGB")
        photo = original.point(lambda pixel: round(pixel * 0.65 + 30))
        references = {"original": original, "parallel": parallel}
        self.assertEqual(photographic_artwork_match(photo, references)[0], "original")

        stamped = original.copy()
        stamped.paste((230, 180, 10), (54, 51, 75, 65))
        self.assertIsNone(photographic_artwork_match(photo, {**references, "stamped": stamped}))
        photo.paste((100, 100, 100), (0, 106, 84, 117))
        self.assertIsNone(photographic_artwork_match(photo, references))

    def test_detailed_digital_comparison_can_resolve_a_thin_finish_mark(self):
        from PIL import Image

        ordinary = Image.new("RGB", (336, 468), (45, 45, 45))
        marked = ordinary.copy()
        marked.paste((150, 150, 150), (85, 30, 86, 410))
        references = {"ordinary": ordinary, "marked": marked}
        scores = {key: (0.006, 0.006, 0.006) for key in references}
        thumbnails = {key: image.resize((84, 117), Image.Resampling.BILINEAR) for key, image in references.items()}
        self.assertIsNone(exact_digital_artwork_match(thumbnails["marked"], thumbnails, scores))
        self.assertEqual(exact_digital_artwork_match(marked, references, scores, scale=4)[0], "marked")
        indistinct = Image.blend(ordinary, marked, 0.5)
        self.assertIsNone(exact_digital_artwork_match(indistinct, references, scores, scale=4))

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

    def test_prb01_manga_reprint_requires_explicit_finish_and_reprint_specification(self):
        product = {"groupId": 23496, "extendedData": [{"name": "Description", "value": PRB01_MANGA_SPEC}]}
        self.assertTrue(treatment_matches_alias("Manga", "OP01-120_r2", product, "foil"))
        self.assertFalse(treatment_matches_alias("Manga", "OP01-120_r2", product, "normal"))
        self.assertFalse(treatment_matches_alias("Manga", "OP01-120_r2", {**product, "groupId": 999}, "foil"))
        self.assertFalse(treatment_matches_alias("Manga", "OP01-120_r2", {**product, "extendedData": []}, "foil"))
        self.assertFalse(treatment_matches_alias("Parallel", "OP01-120_r2", product, "foil"))
        self.assertFalse(treatment_matches_alias("Reprint", "OP01-120_p1", product, "foil"))

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

    def test_reviewed_promo_photo_requires_both_exact_images_and_the_same_printing(self):
        listing = {"number": "OP01-029", "imageProductID": "546673", "imageURL": "retailer", "finish": "foil"}
        label = "Premium Card Collection -Best Selection-"
        reference = ("569801", "OP01-029_p4")
        references = {reference: "bandai"}
        artwork = {"retailer": {"payloadSHA256": "a"}, "bandai": {"payloadSHA256": "b"}}
        reviews = {"546673": {"number": "OP01-029", "series": reference[0], "alias": reference[1],
                             "distribution": label, "finish": "foil", "retailerImageSHA256": "a", "bandaiImageSHA256": "b"}}
        self.assertEqual(reviewed_promo_artwork(listing, label, references, artwork, reviews), reference)
        for provider in artwork:
            changed = {**artwork, provider: {"payloadSHA256": "c"}}
            self.assertIsNone(reviewed_promo_artwork(listing, label, references, changed, reviews))
        self.assertIsNone(reviewed_promo_artwork({**listing, "finish": "normal"}, label, references, artwork, reviews))
        self.assertIsNone(reviewed_promo_artwork(listing, "Best Selection Vol. 2", references, artwork, reviews))

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

    def test_reviewed_promo_title_alias_preserves_volume_and_alternate_artwork(self):
        official = "Premium Card Collection -Best Selection-"
        alias = "Premium Card Collection -Best Selection Vol. 1-"
        title = f"Nami ({alias}) (Alternate Art)"
        labels = [official, "Premium Card Collection -Best Selection Vol.2-"]
        self.assertEqual(promotion_treatment("OP01-016", "Nami", title, labels),
                         (official, "Alternate artwork"))
        self.assertIsNone(promotion_treatment("OP01-016", "Nami", title, [*labels, alias]))
        self.assertIsNone(promotion_treatment("OP01-016", "Nami", title.replace("Alternate Art", "Winner"), labels))
        listing = {"number": "OP01-016", "imageProductID": "123", "finish": "foil"}
        products = {123: {"name": f"Nami ({alias})",
                         "extendedData": [{"name": "Number", "value": "OP01-016"}]}}
        self.assertFalse(market_agrees(listing, (official, "Alternate artwork"), "Nami", products,
                                       {123: {"foil"}}, promotion=True))
        event = "ST15-20 Release Event"
        self.assertEqual(promotion_treatment("OP02-022", "Whitebeard Pirates",
                         "Whitebeard Pirates (ST15 - ST20 Release Event Pack)", [event]), (event, None))
        self.assertIsNone(promotion_treatment("OP02-022", "Whitebeard Pirates",
                          "Whitebeard Pirates (ST15 - ST20 Release Event Winner Pack)", [event]))
        uta = "ST-11 Uta Deck Battle Participation Pack"
        self.assertEqual(promotion_treatment("P-061", "Monkey.D.Luffy",
                         "Monkey.D.Luffy (Starter Deck 11: Uta Deck Battle)", [uta]), (uta, None))
        self.assertIsNone(promotion_treatment("P-061", "Monkey.D.Luffy",
                          "Monkey.D.Luffy (Starter Deck 11: Uta Deck Battle Winner)", [uta]))

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

    def test_weirdwolf_binds_explicit_english_finish_to_the_marketplace_sku(self):
        handle = "jewelry-bonney-extra-booster-one-piece-heroines-edition-vol-2-718686"
        url = f"https://www.weirdwolfgames.com/products/{handle}.js"
        record = {"handle": handle, "type": "Trading Card Game", "vendor": "Bandai",
                  "title": "Jewelry Bonney [EB05 - EB05-001]",
                  "tags": ["One Piece Card Game", "Extra Booster One Piece Heroines Edition Vol. 2"],
                  "featured_image": "//cdn.shopify.com/s/files/1/1032/2562/2862/files/"
                                    "718686-foil-disc-f651bac3-sf8d860ef7d-c7c81459e-u1000.jpg?v=1",
                  "options": [{"position": position, "name": name}
                              for position, name in enumerate(["Condition", "Language", "Printing"], 1)],
                  "variants": [{"id": 8, "option1": "Near Mint", "option2": "English", "option3": "Foil"}]}
        [listing] = weirdwolf_listings(url, json.dumps(record).encode())
        self.assertEqual((listing["number"], listing["imageProductID"], listing["finish"]), ("EB05-001", "718686", "foil"))
        self.assertEqual(list(weirdwolf_listings(url.replace("718686", "718687"), json.dumps(record).encode())), [])
        for option, value in (("option2", "Japanese"), ("option3", "Normal")):
            changed = {**record, "variants": [{**record["variants"][0], option: value}]}
            self.assertEqual(list(weirdwolf_listings(url, json.dumps(changed).encode())), [])
