import copy
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
import build_yugioh_catalog as builder

class BuilderTests(unittest.TestCase):
    def setUp(self):
        self.fixture = json.loads(pathlib.Path(__file__).with_name("catalog.json").read_text())

    def build(self, reviews=None):
        f = self.fixture
        return builder.build(f["groups"], {1: f["products"]}, {1: f["prices"]}, f["cards"],
            {"12206212": ["Harpie's Brother"]}, reviews or {}, "2026-10-20T00:00:00Z", floor=1,
            price_provenance={1:{'h':'a'*64, 's':'2026-10-20T00:00:00Z', 'st':'capturedAt'}})

    def test_alias_matches_and_canonical_id_does_not_depend_on_printed_name(self):
        seed, _, exceptions, _ = self.build()
        row = next(x for x in seed["printings"] if x["p"] == 1)
        self.assertEqual(seed["cards"][row["k"]]["n"], "Sky Scout")
        self.assertEqual(seed["cards"][row["k"]]["id"], builder.stable("yugioh-card:", "ygoprodeck:12206212"))
        self.assertEqual(exceptions["aliasMatch"], [1])
        self.fixture["products"][0]["name"] = "Sky Scout (UR)"
        renamed = self.build()[0]
        self.assertEqual(seed["cards"], renamed["cards"])

    def test_group_price_union_cannot_create_physical_editions(self):
        seed, stats, _, _ = self.build()
        self.assertTrue(all(not x["ec"] for x in seed["printings"]))
        self.assertEqual(seed["printings"][0]["e"], ["yugioh1stEdition"])
        self.assertEqual(seed["printings"][1]["e"], ["yugiohLimited"])
        self.assertEqual(seed["autoEligibleCodes"], [])
        self.assertEqual(stats["verifiedPhysicalProducts"], 0)

    def test_supported_missing_lane_is_retained_without_price_whitelist(self):
        reviews = {"1": {"editions": ["yugioh1stEdition", "yugiohUnlimited"], "complete": True, "evidence": "synthetic:physical-review"}}
        seed, _, _, _ = self.build(reviews)
        first, second = seed["printings"]
        self.assertEqual(first["e"], ["yugioh1stEdition", "yugiohUnlimited"])
        self.assertNotIn("yugiohUnlimited", first["pe"])
        self.assertTrue(first["ec"])
        self.assertFalse(second["ec"])
        self.assertEqual(second["e"], ["yugiohLimited"])

    def test_entire_group_missing_valid_edition_does_not_prove_completeness(self):
        self.fixture["prices"] = []
        seed = self.build()[0]
        self.assertTrue(all(not x["ec"] and not x["e"] for x in seed["printings"]))
        self.assertEqual(seed["autoEligibleCodes"], [])

    def test_skipped_rarity_product_poisoning(self):
        product = copy.deepcopy(self.fixture["products"][0])
        product["productId"] = 3
        product["extendedData"] = product["extendedData"][:1]
        self.fixture["products"].append(product)
        self.assertIn("PSV-EN049", self.build()[0]["incompleteCodes"])

    def test_same_rarity_missing_reprint_is_incomplete(self):
        self.fixture["cards"][0]["card_sets"].append({"set_code": "PSV-EN049", "set_name": "Reprint", "set_rarity": "Ultra Rare"})
        self.assertIn("printingShortfall", self.build()[3]["PSV-EN049"])

    def test_deterministic_input_order(self):
        first = self.build()[0]
        self.fixture["products"].reverse(); self.fixture["cards"].reverse(); self.fixture["prices"].reverse()
        self.assertEqual(first, self.build()[0])

    def test_equal_rarity_counts_do_not_prove_correspondence(self):
        self.fixture["cards"][0]["card_sets"].append({"set_code": "PSV-EN049", "set_name": "Synthetic set", "set_rarity": "Secret Rare"})
        product = copy.deepcopy(self.fixture["products"][0])
        product["productId"] = 3
        product["extendedData"][1]["value"] = "Common"
        self.fixture["products"].append(product)
        reviews = {str(pid): {"editions": ["yugioh1stEdition"], "complete": True, "evidence": "synthetic:edition"} for pid in [1, 3]}
        seed, stats, _, reasons = self.build(reviews)
        self.assertIn("printingCorrespondenceGap", reasons["PSV-EN049"])
        self.assertIn("unreviewedCorrespondence", reasons["PSV-EN049"])
        self.assertIn("PSV-EN049", seed["incompleteCodes"])
        self.assertEqual(stats["manualEligibleProducts"], 3)

    def test_listing_only_supports_membership_without_market_valuation(self):
        self.fixture["prices"][0].update(marketPrice=None, lowPrice=10)
        p = self.build()[0]["printings"][0]
        self.assertEqual(p["e"], ["yugioh1stEdition"])
        self.assertEqual(p["m"][0]["t"], "providerListing")
        self.assertIsNone(p["m"][0]["q"])
        self.fixture['prices'][0]['marketPrice'] = 0
        m = self.build()[0]['printings'][0]['m'][0]
        self.assertEqual(m['t'], 'providerListing'); self.assertEqual(m['q'], 0)

    def test_null_zero_invalid_unknown_are_not_membership(self):
        for values in [{"marketPrice": None}, {"marketPrice": 0}, {"marketPrice": -1},
                       {"marketPrice": float('nan')}, {"marketPrice": True},
                       {"marketPrice": 1, "lowPrice": -1}]:
            rows = [{"productId": 1, "subTypeName": "Unlimited", **values}]
            self.assertEqual(builder.grade_prices(rows)[0], [])
        self.assertEqual(builder.grade_prices([{"productId": 1, "subTypeName": "Unknown", "marketPrice": 1}])[0], [])

    def test_identical_duplicates_only_and_conflict_local_to_edition(self):
        row = {"productId": 1, "subTypeName": "Unlimited", "marketPrice": 1}
        self.assertEqual(len(builder.grade_prices([row, dict(row)])[0]), 1)
        good = {"productId": 1, "subTypeName": "Limited", "marketPrice": 2}
        graded, reasons = builder.grade_prices([row, {**row, "marketPrice": 9}, good])
        self.assertEqual([x["e"] for x in graded], ["yugiohLimited"])
        self.assertIn("conflictingDuplicate:yugiohUnlimited", reasons)
        row = self.fixture['prices'][0]
        self.fixture['prices'].append({**row, 'marketPrice':9})
        review = {'1': {'editions':['yugioh1stEdition'], 'complete':True, 'evidence':'synthetic:review'}}
        p = self.build(review)[0]['printings'][0]
        self.assertEqual(p['e'], []); self.assertFalse(p['ec'])

    def test_passcodes_do_not_union_image_ids_or_long_provider_ids(self):
        self.fixture["cards"][0]["card_images"].append({"id": 12345678})
        self.assertEqual(next(x for x in self.build()[0]["cards"] if x['n']=='Sky Scout')["pc"], [12206212])
        self.fixture["cards"][0]["id"] = 10012206212
        p = self.build()[0]
        self.assertTrue(all(12345678 not in x['pc'] and 10012206212 not in x['pc'] for x in p['cards']))

    def test_group_creation_is_not_release_date(self):
        self.assertEqual(self.build()[0]["sets"][0]["d"], "")
        self.assertEqual(self.build()[0]["sets"][0]["created"], "2002-01-01")

    def test_taxonomy_is_scoped_and_code_exceptions_are_bounded(self):
        self.assertEqual(builder.corresponding_rarity(23416, "RA02-EN001", "Prismatic Ultimate Rare"), "Ultimate Rare")
        self.assertEqual(builder.corresponding_rarity(1, "RA02-EN001", "Prismatic Ultimate Rare"), "Prismatic Ultimate Rare")
        self.assertEqual(builder.corresponding_rarity(23416, "LOB-001", "Prismatic Ultimate Rare"), "Prismatic Ultimate Rare")
        for code in ['IOC-SE1', 'IOC-SE2', 'IOC-SE3', 'IOC-SE4']: self.assertRegex(code, builder.CODE)
        for code in ['IOC-SE5', 'LOB-SE1', 'LOB-JP001']: self.assertIsNone(builder.CODE.fullmatch(code))

    def test_bad_ygo_rarity_is_not_physical_evidence(self):
        self.fixture["cards"][0]["card_sets"].append({"set_code": "PSV-EN049", "set_name": "Synthetic set", "set_rarity": "New artwork"})
        _, _, _, incomplete = self.build()
        self.assertNotIn("rarityShortfall", incomplete["PSV-EN049"])
        self.fixture['cards'][0]['card_sets'][0]['set_rarity'] = 'New'
        seed = self.build()[0]
        row = next(x for x in seed['printings'] if x['p'] == 1)
        self.assertEqual(seed['cards'][row['k']]['id'], builder.stable('yugioh-card:', 'ygoprodeck:12206212'))

    def test_independent_non_exhaustive_review_can_support_missing_price(self):
        self.fixture['prices'] = []
        review = {'1': {'editions':['yugiohUnlimited'], 'complete':False, 'evidence':'synthetic:independent-association'}}
        p = self.build(review)[0]['printings'][0]
        self.assertEqual(p['e'], ['yugiohUnlimited']); self.assertFalse(p['ec'])
        self.assertEqual(p['m'][0]['t'], 'independentlyReviewed')

    def test_hosting_candidate_is_isolated_immutable_and_hashed(self):
        seed = self.build()[0]
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            builder.stage_hosting(seed, root)
            pointer = json.loads((root/'yugioh/v1/current.json').read_text())
            self.assertEqual(pointer['status'], 'candidate_not_deployed')
            self.assertEqual(pointer['schemaVersion'], 1)
            self.assertEqual(pointer['revision'], 1792454400)
            self.assertEqual(pointer['sha256'], builder.hashlib.sha256(builder.packed(seed)).hexdigest())
            self.assertEqual((root/pointer['path']).read_bytes(), builder.packed(seed))
            builder.stage_hosting(seed, root)
            changed = copy.deepcopy(seed); changed['capturedAt'] = '2027-01-01T00:00:00Z'
            with self.assertRaises(ValueError): builder.stage_hosting(changed, root)

    def test_staging_rejects_missing_provenance_before_creating_artifacts(self):
        seed = self.build()[0]
        seed['printings'][0]['m'][0].pop('h')
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory) / 'site'
            with self.assertRaises(AssertionError): builder.stage_hosting(seed, root)
            self.assertFalse(root.exists())

    def test_membership_survives_withdrawal_but_conflicting_revision_retracts_lane(self):
        f = self.fixture
        original = builder.build(f['groups'], {1:f['products']}, {1:f['prices']}, f['cards'],
            {}, {}, '2026-10-20T00:00:00Z', floor=1,
            price_provenance={1:{'h':'a'*64,'s':'2026-10-20T00:00:00Z'}})[0]
        previous = {x['p']:x for x in original['printings']}
        def rebuild(prices):
            return builder.build(f['groups'], {1:f['products']}, {1:prices}, f['cards'], {}, {},
                '2026-10-21T00:00:00Z', floor=1, previous=previous)[0]['printings'][0]
        p = rebuild([])
        self.assertEqual(p['e'], ['yugioh1stEdition']); self.assertIsNone(p['m'][0]['q'])
        row = f['prices'][0]
        self.assertEqual(rebuild([row,{**row,'marketPrice':9}])['e'], [])

    def test_bad_sibling_does_not_poison_exact_product(self):
        product = copy.deepcopy(self.fixture['products'][0])
        product['productId'] = 3; product['name'] += ' (Alternate Art)'
        self.fixture['products'].append(product)
        seed, stats, _, _ = self.build()
        self.assertEqual(stats['manualEligibleProducts'], 2)
        self.assertEqual(next(x for x in seed['printings'] if x['p']==3)['e'], [])

    def test_exact_association_and_conflicting_product_metadata_are_required(self):
        self.fixture['products'][0]['categoryId'] = 3
        seed, stats, _, _ = self.build()
        self.assertEqual(seed['printings'][0]['ir'], 'invalidProductAssociation')
        self.assertEqual(stats['manualEligibleProducts'], 1)
        self.fixture['products'][0]['categoryId'] = 2
        self.fixture['products'][0]['extendedData'].append({'name':'Number', 'value':'LOB-001'})
        self.assertTrue(any(x['ir']=='contradictoryProductFields' for x in self.build()[0]['printings']))

    def test_singleton_mismatch_requires_reviewed_correspondence(self):
        self.fixture["products"][0]["extendedData"][1]["value"] = "Provider-specific rarity"
        review = {"editions": ["yugioh1stEdition"], "complete": True, "evidence": "synthetic:edition"}
        self.assertNotIn("PSV-EN049", self.build({"1": review})[0]["autoEligibleCodes"])
        review["sourcePrintings"] = [{"cardID": 12206212, "setName": "Synthetic set", "rarity": "Ultra Rare"}]
        with self.assertRaises(AssertionError): self.build({"1": review})
        review["correspondenceEvidence"] = "synthetic:independent-product-correspondence"
        self.assertIn("PSV-EN049", self.build({"1": review})[0]["autoEligibleCodes"])
        review["sourcePrintings"][0]["rarity"] = "Secret Rare"
        seed, _, _, reasons = self.build({"1": review})
        self.assertIn("invalidCorrespondence", reasons["PSV-EN049"])
        self.assertNotIn("PSV-EN049", seed["autoEligibleCodes"])

    def test_matching_rarity_in_wrong_set_cannot_authorize_acquisition(self):
        self.fixture["groups"][0]["name"] = "Different set"
        reviews = {"1": {"editions": ["yugioh1stEdition"], "complete": True, "evidence": "synthetic:edition"}}
        self.assertIn("PSV-EN049", self.build(reviews)[0]["incompleteCodes"])

    def test_unknown_subtype_and_duplicate_identity_fail_closed(self):
        self.fixture["prices"][0]["subTypeName"] = "Normal"
        self.assertIn("PSV-EN049", self.build()[0]["incompleteCodes"])
        self.fixture["products"].append(copy.deepcopy(self.fixture["products"][0]))
        with self.assertRaises(AssertionError): self.build()

    def test_review_cannot_contradict_observed_product_lane(self):
        with self.assertRaises(AssertionError):
            self.build({"1": {"editions": ["yugiohUnlimited"], "complete": True, "evidence": "synthetic:bad-review"}})

    def test_complete_review_retracts_historical_lane_but_keeps_provenance(self):
        f = self.fixture
        prior = self.build({'1': {'editions':['yugiohUnlimited'], 'evidence':'synthetic:prior'}})[0]
        # Give the historical review a durable provenance stamp (builder supplies it).
        previous = {x['p']:x for x in prior['printings']}
        f['prices'] = []
        seed = builder.build(f['groups'], {1:f['products']}, {1:[]}, f['cards'], {},
            {'1': {'editions':['yugioh1stEdition'], 'complete':True, 'evidence':'synthetic:new-complete'}},
            '2026-10-21T00:00:00Z', floor=1, previous=previous)[0]
        row = next(x for x in seed['printings'] if x['p'] == 1)
        self.assertEqual(row['e'], ['yugioh1stEdition'])
        self.assertEqual([m['e'] for m in row['historicalContradictions']], ['yugiohUnlimited'])
        self.assertTrue(row['ec'])

    def test_invalid_association_reviewed_singleton_stays_quarantined(self):
        self.fixture['products'][0]['categoryId'] = 99
        seed = self.build({'1': {'editions':['yugioh1stEdition'], 'complete':True, 'evidence':'synthetic:review'}})[0]
        row = next(x for x in seed['printings'] if x['p'] == 1)
        self.assertEqual(row['ir'], 'invalidProductAssociation')
        self.assertNotIn(row['c'], seed['autoEligibleCodes'])
        self.assertTrue(any(x['p'] == 2 and x['e'] and not x['ir'] for x in seed['printings']))
        builder.validate_output(seed)
        seed['autoEligibleCodes'] = [row['c']]
        with self.assertRaises(AssertionError): builder.validate_output(seed)

    def test_no_automatic_eligibility_for_alternate_art_or_unknown_coverage(self):
        self.fixture["cards"][0]["card_images"].append({"id": 1})
        reviews = {"1": {"editions": ["yugioh1stEdition"], "complete": True, "evidence": "synthetic:review"}}
        self.assertNotIn("PSV-EN049", self.build(reviews)[0]["autoEligibleCodes"])

    def test_failed_or_missing_input_preserves_existing_outputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            out, report = root / "catalog.json", root / "report.md"
            out.write_bytes(b"existing valid seed"); report.write_bytes(b"existing report")
            for invalid in [None, {"success": False, "errors": ["fixture failure"], "results": []},
                            {"success": True, "errors": [], "results": [], "totalItems": 10}]:
                if invalid is not None:
                    path = root / "cache" / "tcgcsv" / "categories.json"
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(json.dumps(invalid))
                result = subprocess.run([sys.executable, "-I", str(builder.ROOT / "build_yugioh_catalog.py"), "--offline",
                    "--cache-dir", str(root / "cache"), "--out", str(out), "--report", str(report)], capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(out.read_bytes(), b"existing valid seed")
                self.assertEqual(report.read_bytes(), b"existing report")

if __name__ == "__main__": unittest.main()
