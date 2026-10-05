"""Authored retained-byte fixtures; no live requests or licensed card assets."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
import reconcile_one_piece_launch_products as pipeline
import capture_one_piece_products as driver


class ProductPipelineTests(unittest.TestCase):
    def test_name_annotation_normalization_keeps_physical_treatment_distinctions(self):
        self.assertTrue(pipeline.names_agree("ST20-001", "Charlotte Katakuri", "Charlotte Katakuri (ST20-001)"))
        self.assertTrue(pipeline.names_agree("PRB02-002", "Trafalgar Law", "Trafalgar Law - PRB02-002"))
        self.assertFalse(pipeline.names_agree("PRB02-002", "Trafalgar Law", "Trafalgar Law - PRB02-003"))
        self.assertFalse(pipeline.names_agree("P-044", "Sabo", "Sabo - P-044 (Pirate Foil)"))
        self.assertFalse(pipeline.names_agree("P-044", "Sabo", "Sabo - P-044 (Reprint)"))

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.spec = {
            "productID": "product:st99-review", "label": "Reviewed deck", "releaseDate": "2026-10-04",
            "prefix": "ST99", "manufacturerCaptureID": "bandai-st99",
            "manufacturerListURL": "https://en.onepiece-cardgame.com/cardlist/?series=review",
            "retailerGroupID": "123", "retailerStartURL": "https://coretcg.com/Products/0/68/123/review",
            "retailerCaptureFiles": ["retailer.html"],
            "cards": [{"printedNumber": "ST99-001", "artworkAlias": "ST99-001", "isReprint": False}],
        }
        self.registry = {"variants": [{"id": "foil", "label": "Foil"}], "products": [],
                         "canonicalCards": [], "artworks": [], "printings": []}

    def capture(self, filename, payload, url, identity=None):
        path = self.root / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        value = {"rawFile": filename, "sourceURL": url, "observedAt": "2026-10-04T00:00:00Z",
                 "byteCount": len(payload), "payloadSHA256": hashlib.sha256(payload).hexdigest()}
        if identity:
            value["id"] = identity
        return value

    def fixtures(self, finishes=("Foil",), reprint=False, manufacturer=False):
        if reprint:
            self.spec["cards"] = [{"printedNumber": "OP01-001", "artworkAlias": "OP01-001_p3", "isReprint": True}]
        else:
            self.spec["cards"] = [{"printedNumber": "ST99-001", "artworkAlias": "ST99-001", "isReprint": False}]
        card = self.spec["cards"][0]
        number, alias = card["printedNumber"], card["artworkAlias"]
        page = f'<dl class="modalCol" id="{alias}"><div class="cardName">Example</div></dl>'.encode()
        official = self.capture("official.html", page, self.spec["manufacturerListURL"], "bandai-st99")
        retailer = ''.join(f'<div class="productCard"><a class="small" href="/printing/{i}">Example</a>'
                           f'{number}<div class="small">English - Near Mint - {finish}</div></div>'
                           for i, finish in enumerate(finishes)).encode()
        captures = [self.capture("retailer.html", retailer, self.spec["retailerStartURL"]),
                    self.capture("images/" + alias + ".png", b"authored-image-fingerprint", "https://en.onepiece-cardgame.com/image.png")]
        if manufacturer:
            self.spec["manufacturerFinish"] = {
                "captureFile": "finish.html", "sourceURL": "https://en.onepiece-cardgame.com/product.php",
                "exactText": "All cards are holographic.", "variantID": "foil",
                "appliesToPrintedNumbers": [number], "evidenceDetail": "Explicit reviewed manufacturer specification."}
            captures.append(self.capture("finish.html", b"<p>All cards are holographic.</p>", self.spec["manufacturerFinish"]["sourceURL"]))
        return {"captures": [official]}, {"captures": captures}

    def run_reconcile(self, official, captures, registry=None, allocate=True):
        return pipeline.reconcile(registry or self.registry, official, captures, self.root, self.root,
                                  allocate, [self.spec])

    def load_manifest(self, products=None):
        path = self.root / "products.json"
        path.write_text(json.dumps({"schemaVersion": 1, "reviewDate": "2026-10-04",
                                    "products": products or [self.spec]}))
        return pipeline.load_products(path)

    def test_allocation_is_explicit_and_replay_retains_every_identity(self):
        official, captures = self.fixtures()
        with self.assertRaisesRegex(ValueError, "explicit UUID"):
            self.run_reconcile(official, captures, allocate=False)
        result = self.run_reconcile(official, captures)
        self.assertEqual(result, self.run_reconcile(official, captures, result[0], allocate=False))
        printing = result[0]["printings"][0]
        self.assertEqual(printing["status"], "verified")
        self.assertEqual(printing["supportedVariantIDs"], ["foil"])
        self.assertFalse(result[0]["canonicalCards"][0]["printingCoverageComplete"])
        self.assertEqual(result[1][0]["id"], "launch-products:product:st99-review:ST99-001:catalog")

    def test_whole_batch_source_audit_reports_other_products_without_allocating(self):
        official, captures = self.fixtures()
        original = deepcopy(self.registry)
        missing = {**self.spec, "productID": "missing-product", "prefix": "ST98",
                   "manufacturerCaptureID": "missing-source"}
        audit = pipeline.audit_product_sources(self.registry, official, captures, self.root, self.root,
                                               [self.spec, missing])
        self.assertEqual(self.registry, original)
        self.assertEqual(len(audit["products"]), 2)
        self.assertTrue(audit["products"][0]["sourceEvidenceReady"])
        self.assertFalse(audit["products"][1]["sourceEvidenceReady"])
        self.assertFalse(audit["sourceEvidenceReady"])
        self.assertFalse(audit["physicalCoverageComplete"])
        self.assertNotIn("registry", audit)
        self.assertNotIn("printingID", audit["products"][0])

    def test_exact_retailer_title_review_cannot_follow_another_listing_or_changed_title(self):
        review = {"listingPath": "/Products/123/68/123/reprint", "printedNumber": "ST99-001",
                  "retailerTitle": "Example (Reprint)", "manufacturerName": "Example",
                  "evidenceDetail": "Reviewed exact product-scoped ordinary reprint."}
        self.spec["reviewedRetailerTitles"] = [review]
        self.load_manifest()
        self.assertTrue(pipeline.reviewed_name_agrees(self.spec, "ST99-001", "Example",
                        ("Example (Reprint)", "English - Near Mint - Foil", review["listingPath"], {})))
        self.assertFalse(pipeline.reviewed_name_agrees(self.spec, "ST99-001", "Example",
                         ("Example (Reprint)", "English - Near Mint - Foil", "/another-listing", {})))
        with self.assertRaisesRegex(ValueError, "reviewed retailer title changed"):
            pipeline.reviewed_name_agrees(self.spec, "ST99-001", "Example",
                         ("Example (Pirate Foil)", "English - Near Mint - Foil", review["listingPath"], {}))

    def test_duplicate_finish_assertions_are_retained_and_disagreement_is_conflicted(self):
        official, captures = self.fixtures(finishes=("Foil", "Normal"))
        registry, observations, _, _ = self.run_reconcile(official, captures)
        self.assertEqual(registry["printings"][0]["status"], "conflicted")
        self.assertEqual(registry["printings"][0]["supportedVariantIDs"], [])
        self.assertEqual(len([o for o in observations if o["alias"]["provider"] == "coretcg"]), 2)

    def test_reprint_without_retailer_requires_explicit_manufacturer_finish(self):
        official, captures = self.fixtures(finishes=(), reprint=True, manufacturer=True)
        self.load_manifest()
        registry, observations, _, _ = self.run_reconcile(official, captures)
        printing = registry["printings"][0]
        self.assertEqual(printing["status"], "verified")
        self.assertEqual(printing["supportedVariantIDs"], ["foil"])
        self.assertIn("no matching retailer", next(e["detail"] for e in printing["review"]["evidence"] if e["kind"] == "language"))
        self.assertEqual(observations[-1]["printedEvidence"]["sourceRole"], "manufacturer-product-finish-specification")
        self.spec["manufacturerFinish"]["exactText"] = "Changed specification"
        with self.assertRaisesRegex(ValueError, "specification changed"):
            self.run_reconcile(official, captures)

    def test_missing_finish_stays_provisional_with_an_explicit_review_gap(self):
        official, captures = self.fixtures(finishes=(), reprint=True)
        registry, _, _, decisions = self.run_reconcile(official, captures)
        self.assertEqual(registry["printings"][0]["status"], "provisional")
        self.assertEqual(registry["printings"][0]["supportedVariantIDs"], [])
        self.assertEqual(pipeline.discrepancy_ledger(registry, decisions)["discrepancies"][0]["reasonCode"], "missing-finish")
        official, captures = self.fixtures(finishes=())
        with self.assertRaisesRegex(ValueError, "retailer standard scope changed"):
            self.run_reconcile(official, captures)
        self.spec["retailerEvidenceMissing"] = ["ST99-001"]
        self.load_manifest()
        registry, _, _, _ = self.run_reconcile(official, captures)
        self.assertEqual(registry["printings"][0]["status"], "provisional")

    def test_changed_bytes_and_existing_review_changes_are_rejected(self):
        official, captures = self.fixtures()
        result = self.run_reconcile(official, captures)
        changed = deepcopy(result[0])
        changed["printings"][0]["supportedVariantIDs"] = ["normal"]
        with self.assertRaisesRegex(ValueError, "reviewed correction"):
            self.run_reconcile(official, captures, changed, False)
        (self.root / "retailer.html").write_bytes(b"different bytes")
        with self.assertRaisesRegex(ValueError, "bytes changed"):
            self.run_reconcile(official, captures)

    def test_multiple_retained_pages_preserve_finish_evidence_in_order(self):
        official, captures = self.fixtures()
        payload = (b'<div class="productCard"><a class="small" href="/printing/other">Example</a>'
                   b'ST99-001<div class="small">English - Near Mint - Normal</div></div>')
        captures["captures"].append(self.capture("page2.html", payload, "https://coretcg.com/Products/GetProducts?p=2"))
        self.spec["retailerCaptureFiles"].append("page2.html")
        registry, observations, _, _ = self.run_reconcile(official, captures)
        self.assertEqual(registry["printings"][0]["status"], "conflicted")
        self.assertEqual([o["alias"]["sourceID"] for o in observations if o["alias"]["provider"] == "coretcg"],
                         ["/printing/0", "/printing/other"])

    def test_played_condition_retains_exact_finish_without_creating_price_evidence(self):
        official, captures = self.fixtures()
        payload = (self.root / "retailer.html").read_bytes().replace(b"Near Mint", b"Lightly Played")
        captures["captures"][0] = self.capture("retailer.html", payload, self.spec["retailerStartURL"])
        registry, observations, _, _ = self.run_reconcile(official, captures)
        self.assertEqual(registry["printings"][0]["supportedVariantIDs"], ["foil"])
        self.assertEqual(observations[-1]["printedEvidence"]["sourceCondition"], "Lightly Played")
        self.assertEqual(observations[-1]["kind"], "catalog")
        self.assertEqual(registry["printings"][0]["marketMappings"], [])

    def test_discrepancy_history_is_stable_and_cannot_resolve_a_held_printing(self):
        official, captures = self.fixtures(finishes=("Foil", "Normal"))
        registry, _, _, decisions = self.run_reconcile(official, captures)
        ledger = pipeline.discrepancy_ledger(registry, decisions)
        self.assertEqual(ledger["discrepancies"][0]["reasonCode"], "source-conflict")
        self.assertEqual(ledger, pipeline.discrepancy_ledger(registry, decisions, ledger))
        ledger["discrepancies"][0]["requiredEvidence"] = "Retained reviewer instruction"
        self.assertEqual(ledger, pipeline.discrepancy_ledger(registry, decisions, ledger))
        ledger["discrepancies"][0].update(status="resolved", resolutionReferences=["review:approved"])
        with self.assertRaisesRegex(ValueError, "held printing"):
            pipeline.discrepancy_ledger(registry, decisions, ledger)
        registry["printings"][0]["status"] = "verified"
        self.assertEqual(ledger, pipeline.discrepancy_ledger(registry, decisions, ledger))

    def test_manifest_rejects_duplicate_inventory_and_observation_keys(self):
        duplicate = deepcopy(self.spec)
        duplicate["cards"].append(deepcopy(duplicate["cards"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate inventory"):
            self.load_manifest([duplicate])
        self.spec["cards"][0]["observationKey"] = "launch-products:fixed"
        duplicate = deepcopy(self.spec)
        duplicate["productID"] = "product:other"
        with self.assertRaisesRegex(ValueError, "observation identity"):
            self.load_manifest([self.spec, duplicate])

    def test_exact_reviewed_treatment_exclusion_does_not_supply_base_finish(self):
        official, captures = self.fixtures()
        extra = (b'<div class="productCard"><a class="small" href="/Products/999/68/123/Special">Example (SP)</a>'
                 b'ST99-001<div class="small">English - Near Mint - Normal</div></div>')
        payload = (self.root / "retailer.html").read_bytes() + extra
        captures["captures"][0] = self.capture("retailer.html", payload, self.spec["retailerStartURL"])
        with self.assertRaisesRegex(ValueError, "name disagreement"):
            self.run_reconcile(official, captures)
        self.spec["excludedRetailerListingPaths"] = ["/Products/999/68/123/Special"]
        self.load_manifest()
        registry, observations, _, _ = self.run_reconcile(official, captures)
        self.assertEqual(registry["printings"][0]["supportedVariantIDs"], ["foil"])
        self.assertFalse(any(o["alias"]["sourceID"].endswith("Special") for o in observations))

    def test_path_escape_duplicate_capture_and_missing_artwork_are_rejected(self):
        official, captures = self.fixtures()
        changed = deepcopy(captures)
        changed["captures"][0]["rawFile"] = "../retailer.html"
        with self.assertRaisesRegex(ValueError, "unsafe capture path"):
            pipeline.checked_capture(self.root, changed["captures"][0])
        changed = deepcopy(captures)
        changed["captures"].append(deepcopy(changed["captures"][0]))
        with self.assertRaisesRegex(ValueError, "duplicate capture"):
            self.run_reconcile(official, changed)
        self.spec["cards"][0]["artworkAlias"] = "ST99-001_p2"
        with self.assertRaisesRegex(ValueError, "reviewed standard artwork"):
            self.run_reconcile(official, captures)


class ProductCaptureTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.list_url = "https://en.onepiece-cardgame.com/cardlist/?series=review"
        self.retailer_url = "https://coretcg.com/Products/0/68/123/review"
        self.image_url = "https://en.onepiece-cardgame.com/images/cardlist/card/ST99-001.png?v=1"
        self.page2_url = "https://coretcg.com/Products/GetProducts?p=2&mastergroupid=123&mastercategoryid=68"
        self.manifest = {"schemaVersion": 1, "reviewDate": "2026-10-04", "products": [{
            "productID": "product:st99", "prefix": "ST99", "manufacturerCaptureID": "bandai-st99",
            "manufacturerListURL": self.list_url, "retailerGroupID": "123",
            "retailerStartURL": self.retailer_url, "retailerCaptureFiles": ["st99-retailer-all.html"],
            "cards": [{"printedNumber": "ST99-001", "artworkAlias": "ST99-001", "isReprint": False}],
        }]}
        self.responses = {
            self.list_url: b'<dl class="modalCol" id="ST99-001"><img data-src="../images/cardlist/card/ST99-001.png?v=1"></dl>',
            self.retailer_url: (b'<div class="productCard">Example</div><ul class="pagination"><a rel="next" href="/Products/GetProducts?p=2&amp;mastergroupid=123&amp;mastercategoryid=68">2</a></ul>'),
            self.page2_url: b'<div class="productCard">Example</div><ul class="pagination"><a rel="prev" href="/Products/GetProducts?p=1&amp;mastergroupid=123&amp;mastercategoryid=68">1</a></ul>',
            self.image_url: b"authored image",
        }

    def test_capture_discovers_pages_and_offline_replay_preserves_records(self):
        calls = []
        def transport(url):
            calls.append(url)
            return self.responses[url]
        capture = driver.ProductCapture(self.root, transport=transport)
        result = driver.capture_products(capture, self.manifest)
        self.assertEqual(len(calls), 4)
        self.assertEqual(result[0]["products"][0]["retailerCaptureFiles"],
                         ["st99-retailer-all.html", "st99-retailer-page2.html"])
        self.assertTrue(result[1][0]["scopedPaginationComplete"])
        self.assertFalse(result[1][0]["physicalCoverageComplete"])
        before = (self.root / "capture-manifest.json").read_bytes()
        def never_fetch(url):
            self.fail("offline mode fetched " + url)
        replay = driver.ProductCapture(self.root, offline=True, transport=never_fetch)
        self.assertEqual(result, driver.capture_products(replay, self.manifest))
        self.assertEqual(before, (self.root / "capture-manifest.json").read_bytes())

    def test_offline_missing_changed_bytes_and_orphan_are_rejected(self):
        capture = driver.ProductCapture(self.root, offline=True)
        with self.assertRaisesRegex(ValueError, "offline capture missing"):
            capture.capture(self.list_url, "list.html")
        (self.root / "list.html").write_bytes(b"orphan")
        with self.assertRaisesRegex(ValueError, "orphan capture"):
            capture.capture(self.list_url, "list.html")
        capture = driver.ProductCapture(self.root, transport=lambda url: b"retained")
        capture.capture(self.list_url, "other.html")
        (self.root / "other.html").write_bytes(b"changed")
        with self.assertRaisesRegex(ValueError, "bytes changed"):
            capture.capture(self.list_url, "other.html")

    def test_pagination_rejects_cycle_gap_foreign_origin_and_foreign_product(self):
        for href, reason in ((self.page2_url.replace("p=2", "p=1"), "cycle"),
                             (self.page2_url.replace("p=2", "p=3"), "gap"),
                             (self.page2_url.replace("coretcg.com", "foreign.invalid"), "origin"),
                             (self.page2_url.replace("123", "999"), "scope")):
            with self.subTest(href=href):
                document = driver.Document(f'<ul class="pagination"><a rel="next" href="{href}">Next</a></ul>'.encode()).root
                with self.assertRaisesRegex(ValueError, reason):
                    driver.next_retailer_page(document, self.retailer_url, "123", 1)

    def test_capture_rejects_paths_and_foreign_urls_before_transport(self):
        capture = driver.ProductCapture(self.root, transport=lambda url: self.fail("unexpected transport"))
        for filename in ("../escape", "/absolute"):
            with self.assertRaisesRegex(ValueError, "unsafe capture path"):
                capture.capture(self.list_url, filename)
        (self.root / "link").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "symlink capture path"):
            capture.capture(self.list_url, "link/escape")
        for url in ("http://coretcg.com/page", "https://coretcg.com@foreign.invalid/page", "https://coretcg.com:444/page"):
            with self.assertRaisesRegex(ValueError, "origin"):
                capture.capture(url, "page")

    def test_reprint_image_capture_uses_reviewed_alias_and_oversize_stops(self):
        product = self.manifest["products"][0]
        product["cards"][0].update(printedNumber="OP01-016", artworkAlias="OP01-016_p3", isReprint=True)
        self.responses[self.list_url] = b'<dl class="modalCol" id="OP01-016_p3"><img data-src="/images/OP01-016_p3.png"></dl>'
        self.responses["https://en.onepiece-cardgame.com/images/OP01-016_p3.png"] = b"reprint"
        capture = driver.ProductCapture(self.root, transport=self.responses.__getitem__)
        driver.capture_products(capture, self.manifest)
        self.assertTrue((self.root / "images/OP01-016_p3.png").exists())
        self.assertFalse((self.root / "images/OP01-016.png").exists())
        with self.assertRaisesRegex(ValueError, "byte limit"):
            driver.ProductCapture(self.root, transport=lambda url: b"x" * (driver.MAX_BYTES + 1)).capture(self.list_url, "oversize.html")
        self.assertFalse((self.root / "oversize.html").exists())

    def test_redirect_and_manifest_write_interruption_are_explicit(self):
        with self.assertRaisesRegex(ValueError, "origin"):
            driver.RejectRedirect().redirect_request(None, None, 302, "redirect", {}, "https://foreign.invalid/page")
        with self.assertRaisesRegex(ValueError, "redirect"):
            driver.RejectRedirect().redirect_request(None, None, 302, "redirect", {}, self.list_url)
        path = self.root / "output.json"
        path.with_suffix(".json.tmp").write_text("interrupted")
        with self.assertRaisesRegex(ValueError, "requires repair"):
            driver.atomic_json(path, {})
        self.assertFalse(path.exists())

    def test_non_catalog_response_cannot_mark_pagination_complete(self):
        self.responses[self.retailer_url] = b"<html>Temporary service error</html>"
        capture = driver.ProductCapture(self.root, transport=self.responses.__getitem__)
        with self.assertRaisesRegex(ValueError, "inventory remains incomplete"):
            driver.capture_products(capture, self.manifest)


if __name__ == "__main__":
    unittest.main()
