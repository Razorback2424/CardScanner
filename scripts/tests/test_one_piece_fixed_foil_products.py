import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from reconcile_one_piece_fixed_foil_products import PNG_SIGNATURE, reconcile


class OnePieceFixedFoilProductsTests(unittest.TestCase):
    cardlist_url = "https://en.onepiece-cardgame.com/cardlist/?series=7"
    specification_url = "https://en.onepiece-cardgame.com/products/other/fixture.php"
    image_url = "https://en.onepiece-cardgame.com/images/cardlist/card/OP01-004_p1.png"

    def fixture(self, root, contents="・Card x 1 (Holo＋Textured Foil)", image_path=None):
        image_path = image_path or self.image_url
        cardlist = f'''<select name="series"><option value="7" selected>Other</option></select>
        <div class="countCol">1 result</div><dl class="modalCol" id="OP01-004_p1">
        <div class="cardName">Usopp</div><div class="infoCol"><span>OP01-004</span></div>
        <div class="getInfo"><h3>Card Set(s)</h3>Fixed Product</div><img data-src="{image_path}"></dl>'''
        specification = f'''<div class="prodStatusBox"><div class="prodStatusTit">Product Name</div>
        <div class="prodStatusContents">Official Fixed Product</div></div>
        <div class="prodStatusBox"><div class="prodStatusTit">Contents</div>
        <ul class="prodStatusContents"><li>{contents}</li></ul></div>'''
        records = []
        for filename, url, data in (("list.html", self.cardlist_url, cardlist.encode()),
                                    ("spec.html", self.specification_url, specification.encode()),
                                    ("render.png", self.image_url, PNG_SIGNATURE + b"fixture")):
            (root / filename).write_bytes(data)
            records.append({"sourceURL": url, "rawFile": filename, "byteCount": len(data),
                            "payloadSHA256": hashlib.sha256(data).hexdigest(), "observedAt": "2026-11-12T00:00:00Z"})
        (root / "capture-manifest.json").write_text(json.dumps({"captures": records}))
        return {"schemaVersion": 1, "cardList": records[0],
                "products": [{"id": "product:fixture", "label": "Fixed Product", "specificationURL": self.specification_url,
                              "specificationTitle": "Official Fixed Product", "specificationContents": contents,
                              "specificationSHA256": records[1]["payloadSHA256"]}]}

    def test_exact_product_finish_and_render_create_stable_evidence(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rules = self.fixture(root)
            additions = reconcile(rules, root, root)
            self.assertEqual(additions, reconcile(rules, root, root))
            [printing] = additions["printings"]
            self.assertEqual(printing["canonicalCardID"], "one-piece:en:OP01-004")
            self.assertEqual(printing["supportedVariantIDs"], ["foil"])
            self.assertEqual(printing["status"], "verified")
            observation_ids = {row["id"] for row in additions["observations"]}
            self.assertEqual(set(additions["inventories"][0]["observationIDs"]), observation_ids)
            finish_id = next(e["observationID"] for e in printing["review"]["evidence"] if e["kind"] == "finish")
            finish = next(row for row in additions["observations"] if row["id"] == finish_id)
            self.assertEqual(finish["sourceURL"], self.specification_url)
            self.assertEqual(finish["printedEvidence"]["sourceArtworkAlias"], "OP01-004_p1")

    def test_rejects_partial_product_and_wrong_artwork(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rules = self.fixture(root, contents="・Card x 2 (Holo＋Textured Foil)")
            with self.assertRaisesRegex(ValueError, "fixed foil quantity"):
                reconcile(rules, root, root)
            rules = self.fixture(root, image_path=self.image_url.replace("_p1", "_p2"))
            with self.assertRaisesRegex(ValueError, "does not match the card-list alias"):
                reconcile(rules, root, root)

    def test_rejects_unreviewed_or_nonfoil_product_contents(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rules = self.fixture(root)
            rules["products"][0]["specificationContents"] = "・Card x 1"
            with self.assertRaisesRegex(ValueError, "contents changed"):
                reconcile(rules, root, root)
            rules = self.fixture(root, contents="・Card x 1")
            with self.assertRaisesRegex(ValueError, "fixed foil quantity"):
                reconcile(rules, root, root)

    def test_event_finish_requires_the_exact_featured_artwork_and_finish_note(self):
        from PIL import Image

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            rules = self.fixture(root)
            manifest = root / "capture-manifest.json"
            records = json.loads(manifest.read_text())["captures"]
            event_url = "https://en.onepiece-cardgame.com/events/finalist.php"
            featured_url = "https://en.onepiece-cardgame.com/images/prize/finalist/01.png"
            event = f'''<section id="finalist"><h5 class="smallTit">Finalist Pack</h5>
            <ul class="cardPopupWrap"><li><a class="js_modalOpenImage" href="{featured_url}"></a></li></ul>
            <ul class="commonNoticeList"><li>*Holo+Textured foil</li></ul></section>'''

            def record(filename, url):
                raw = (root / filename).read_bytes()
                entry = {"sourceURL": url, "rawFile": filename, "byteCount": len(raw),
                         "payloadSHA256": hashlib.sha256(raw).hexdigest(), "observedAt": "2026-11-12T00:00:00Z"}
                records[:] = [r for r in records if r["rawFile"] != filename] + [entry]
                manifest.write_text(json.dumps({"captures": records}))
                return entry["payloadSHA256"]

            (root / "spec.html").write_text(event)
            artwork = Image.new("RGB", (6, 8), (30, 60, 90))
            artwork.save(root / "render.png", compress_level=0)
            artwork.save(root / "featured.png", compress_level=9)
            record("render.png", self.image_url)
            record("featured.png", featured_url)
            rule = rules["products"][0]
            rule.update(eventSectionID="finalist", artworkAliases=["OP01-004_p1"], specificationURL=event_url,
                        specificationTitle="Finalist Pack", specificationSHA256=record("spec.html", event_url))
            output = reconcile(rules, root, root)
            [printing] = output["printings"]
            self.assertEqual(printing["distributionLabel"], "Fixed Product")
            self.assertEqual(printing["supportedVariantIDs"], ["foil"])
            self.assertFalse(output["inventories"][0]["paginationComplete"])

            artwork.putpixel((3, 4), (31, 60, 90))
            artwork.save(root / "featured.png")
            record("featured.png", featured_url)
            with self.assertRaisesRegex(ValueError, "exact Bandai event artwork"):
                reconcile(rules, root, root)

            (root / "spec.html").write_text(event.replace("*Holo+Textured foil", "*Legal Date"))
            rule["specificationSHA256"] = record("spec.html", event_url)
            with self.assertRaisesRegex(ValueError, "does not specify holo and textured foil"):
                reconcile(rules, root, root)
