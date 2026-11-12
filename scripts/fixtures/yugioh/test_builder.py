import copy
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
import build_yugioh_catalog as builder
import yugioh_edition_galleries as galleries

class BuilderTests(unittest.TestCase):
    def setUp(self):
        self.fixture = json.loads(pathlib.Path(__file__).with_name("catalog.json").read_text())

    def build(self, reviews=None, **options):
        f = self.fixture
        return builder.build(f["groups"], {1: f["products"]}, {1: f["prices"]}, f["cards"],
            {"12206212": ["Harpie's Brother"]}, reviews or {}, "2026-10-20T00:00:00Z", floor=1,
            price_provenance={1:{'h':'a'*64, 's':'2026-10-20T00:00:00Z', 'st':'capturedAt'}}, **options)

    def test_verified_metadata_keeps_the_original_printing_binding(self):
        f = self.fixture
        product = f["products"][0]
        product["name"] = "SkyScout (Ultra Rare)"
        product["extendedData"][1]["value"] = "Starfoil Rare"
        f["cards"][0]["name"] = "Sky★Scout"
        f["cards"][0]["card_sets"][0]["set_name"] = f["groups"][0]["name"]
        old = self.build()[0]
        corrections = {"1": {"groupID": 1, "code": "PSV-EN049", "productName": product["name"],
                             "providerRarity": "Starfoil Rare", "physicalRarity": "Ultra Rare"}}
        new = self.build(release_calendar=[{"name": f["groups"][0]["name"], "date": "2002-10-20"}],
                         rarity_corrections=corrections)[0]
        before = next(row for row in old["printings"] if row["p"] == 1)
        after = next(row for row in new["printings"] if row["p"] == 1)
        self.assertEqual(before["id"], after["id"])
        self.assertEqual(before["pn"], after["pn"])
        self.assertEqual(after["r"], "Starfoil Rare")
        self.assertEqual(after["vr"], "Ultra Rare")
        self.assertEqual(new["sets"][0]["d"], "2002-10-20")
        self.assertEqual(after["on"], "Sky★Scout")
        self.assertEqual(after["dn"], "Sky★Scout (Ultra Rare)")
        self.assertEqual(builder.catalog_regressions(new, old), {})

    def test_release_report_flags_an_expected_variant_missing_from_a_populated_parent(self):
        seed = self.build()[0]
        profile = {"groupID": 1, "url": "https://example.com/release", "count": 1,
                   "rows": [{"name": "Sky Scout", "rarities": ["Ultra Rare", "Starlight Rare"]}]}
        report = builder.release_coverage(seed, self.fixture["groups"], [], [profile], {"releases": []}, seed)
        expected = [{"name": "Sky Scout", "rarity": "Starlight Rare"}]
        self.assertEqual(report["checkedReleases"][0]["missingNameOrRarity"], expected)
        self.assertEqual(report["checkedReleases"][0]["parentMissingNameOrRarity"], expected)
        promo = {"id": "123", "date": "2026-10-19", "name": "Release event promo"}
        unmatched = builder.release_coverage(seed, self.fixture["groups"], [promo], [], {"releases": []}, seed)
        self.assertEqual(unmatched["unmatchedOfficialReleases"], [promo])
        self.assertEqual(unmatched["recentReleaseGaps"], [])

    def test_release_dates_are_scoped_to_original_reprint_and_regional_group(self):
        original = self.fixture["groups"][0]
        title = original["name"]
        reprint = {**original, "groupId": 2, "name": title + " (Reprint)"}
        self.fixture["groups"].append(reprint)
        releases = [{"id": "123", "name": title, "date": "2002-10-20"},
                    {"id": "456", "name": reprint["name"], "date": "1990-01-01"},
                    {"id": "789", "name": title + " 25th Anniversary", "date": "2023-04-21"}]
        name = self.fixture["cards"][0]["name"]
        regional = {"groupID": -1, "referenceID": "psv-eu", "code": "PSV", "name": title + " (European English)",
                    "rows": [["PSV-E049", self.fixture["cards"][0]["id"], name, "Ultra Rare"]]}
        reviews = {"2": {"name": reprint["name"], "abbreviation": "PSV", "date": "2023-04-21",
                         "source": "https://example.com/789", "officialReleaseID": "789"},
                   "-1": {"name": regional["name"], "abbreviation": "PSV-E", "date": "2003-12-12",
                          "source": "https://example.com/regional"}}
        f = self.fixture
        inventory = {"url": "https://example.com/regional", "sha256": "b" * 64, "releases": [regional]}
        seed = builder.build(f["groups"], {1: f["products"], 2: []}, {1: f["prices"], 2: []}, f["cards"],
            {"12206212": ["Harpie's Brother"]}, {}, "2026-10-20T00:00:00Z", floor=1,
            release_calendar=releases, reviewed_dates=reviews, reference_inventory=inventory,
            reference_editions={"sources": []})[0]
        self.assertEqual({s["g"]: s["d"] for s in seed["sets"]},
                         {1: "2002-10-20", 2: "2023-04-21", -1: "2003-12-12"})
        self.assertEqual(builder.matching_releases(f["groups"], releases, reviews), {1: releases[0], 2: releases[2]})
        reprint["abbreviation"] = "DIFFERENT"
        self.assertEqual(builder.matching_releases(f["groups"], releases, reviews), {1: releases[0]})

    def test_premiere_checklist_requires_the_exact_promo_inside_its_market_group(self):
        groups = self.fixture["groups"]
        group = groups[0]
        retail = {"id": "123", "date": "2026-10-19", "name": group["name"]}
        premiere = {"id": "456", "date": "2026-10-17", "name": group["name"] + " Premiere!"}
        code = "PSV-ENSP1"
        reviews = {"456": {"groupID": group["groupId"], "name": group["name"], "abbreviation": group["abbreviation"],
                           "printingCode": code, "source": "https://example.com/card"}}
        profile = {"groupID": group["groupId"], "url": "https://example.com/456", "count": 1, "printingCode": code,
                   "rows": [{"name": "Sky Scout", "rarities": ["Ultra Rare"]}]}
        seed = self.build(release_calendar=[retail, premiere])[0]
        self.assertEqual(seed["sets"][0]["d"], retail["date"])
        parent = copy.deepcopy(seed)
        row = next(p for p in seed["printings"] if p["p"] == 1)
        seed["printings"].append({**row, "id": "promo-printing", "c": code})
        report = builder.release_coverage(seed, groups, [retail, premiere], [profile], {"releases": []}, parent,
                                          supplemental_checklists=reviews)
        self.assertEqual(report["unmatchedOfficialReleases"], [])
        self.assertEqual(report["checkedReleases"][0]["missingNameOrRarity"], [])
        self.assertEqual(report["checkedReleases"][0]["parentMissingNameOrRarity"], [{"name": "Sky Scout", "rarity": "Ultra Rare"}])
        self.assertEqual(report["recentReleaseGaps"], [{**premiere, "printingCode": code, "groupID": group["groupId"],
                                                      "candidatePrintings": 1, "parentPrintings": 0}])

    def test_reviewed_unnumbered_display_card_is_discoverable_without_edition_authority(self):
        f = self.fixture
        product = copy.deepcopy(f["products"][0])
        product["productId"] = 100
        product["extendedData"] = [field for field in product["extendedData"] if field["name"] != "Number"]
        f["products"].append(product)
        correction = {"100": {"groupID": 1, "code": "", "productName": product["name"],
                              "providerRarity": "Ultra Rare", "physicalRarity": "Ultra Rare",
                              "unnumberedDisplayCardID": f["cards"][0]["id"]}}
        seed = self.build(rarity_corrections=correction)[0]
        row = seed["referencePrintings"][0]
        self.assertEqual((row["p"], row["c"], row["ir"]), (100, "", "unnumberedDisplay"))
        self.assertEqual((row["e"], row["pe"], row["m"]), ([], [], []))
        self.assertNotIn("", seed["autoEligibleCodes"])
        product["name"] += " different product"
        self.assertNotIn("referencePrintings", self.build(rarity_corrections=correction)[0])

    def test_reference_printing_keeps_id_when_an_exact_market_product_is_added(self):
        f = self.fixture
        title = f["groups"][0]["name"]
        name = f["cards"][0]["name"]
        inventory = {"url": "https://example.com/reference", "sha256": "b" * 64, "releases": [
            {"groupID": -1, "referenceID": "psv-eu", "code": "PSV",
             "name": title + " (European English)", "rows": [["PSV-E049", f["cards"][0]["id"], name, "Ultra Rare"]]},
        ]}
        editions = {"capturedAt": "2026-10-20T00:00:00Z", "sources": [
            {"url": "https://example.com/edition", "firstEditionCodes": ["PSV-E049"]},
        ]}
        options = dict(reference_inventory=inventory, reference_editions=editions)
        old = self.build(**options)[0]
        prior = old["referencePrintings"][0]
        self.assertNotIn("p", prior)
        self.assertEqual(prior["e"], ["yugioh1stEdition"])
        self.assertIsNone(prior["m"][0]["q"])

        product = copy.deepcopy(f["products"][0])
        product["productId"], product["name"] = 100, name
        product["extendedData"][0]["value"] = "PSV-E049"
        f["products"].append(product)
        f["cards"][0]["card_sets"].append({"set_code": "PSV-E049", "set_name": title, "set_rarity": "Ultra Rare"})
        f["prices"].append({"productId": 100, "subTypeName": "1st Edition", "marketPrice": 15})
        new = self.build(previous_references={prior["id"]: prior}, **options)[0]
        after = new["referencePrintings"][0]
        self.assertEqual(after["id"], prior["id"])
        self.assertEqual((after["p"], after["pg"], after["m"][0]["q"]), (100, 1, 15))
        self.assertFalse(any(row["p"] == 100 for row in new["printings"]))
        self.assertEqual(builder.catalog_regressions(new, old), {})

    def test_gallery_editions_use_exact_inventory_and_keep_market_authority_separate(self):
        name = self.fixture["cards"][0]["name"]
        title = self.fixture["groups"][0]["name"]
        codes = ["PSV-E049", "PSV-E050"]
        inventory = {"url": "https://example.com/reference", "sha256": "b" * 64, "releases": [
            {"groupID": 1, "referenceID": None, "code": "PSV", "name": title,
             "rows": [[code, self.fixture["cards"][0]["id"], name, "Ultra Rare"] for code in codes]},
        ]}
        date = "2026-10-20T00:00:00Z"
        contents = f"{{{{Set gallery|rarity=UR|\n{codes[0]}; {name}\n{codes[1]}; {name}; Rare\n}}}}"
        pages = [{"title": f"Set Card Galleries:{title} (TCG-EU-UE)", "revisions": [
            {"revid": 123, "slots": {"main": {"content": contents}}},
        ]}]
        projection = galleries.project(inventory, [(json.dumps({"query": {"pages": pages}}).encode(), date)])
        self.assertEqual(projection["sources"][0]["codes"], [codes[0]])
        product = self.fixture["products"][0]
        product["name"] = name
        product["extendedData"][0]["value"] = codes[0]
        self.fixture["cards"][0]["card_sets"].append({"set_code": codes[0], "set_name": title, "set_rarity": "Ultra Rare"})
        original = self.build()[0]
        editions = {"capturedAt": date, "sources": [], "galleryEvidence": projection}
        seed = self.build(reference_inventory=inventory, reference_editions=editions)[0]
        row = next(p for p in seed["printings"] if p["p"] == 1)
        self.assertEqual(row["e"], ["yugioh1stEdition", "yugiohUnlimited"])
        self.assertEqual(row["pe"], ["yugioh1stEdition"])
        self.assertEqual(row["m"][1]["t"], "independentlyReviewed")
        self.assertIsNone(row["m"][1]["q"])
        self.assertEqual(seed["referencePrintings"][0]["e"], [])
        self.assertEqual(builder.catalog_regressions(seed, original), {})
        inventory["releases"][0]["rows"][1][3] = "Rare"
        with self.assertRaisesRegex(AssertionError, "belongs to another inventory"):
            self.build(reference_inventory=inventory, reference_editions=editions)

    def test_same_title_regional_galleries_cannot_grant_each_others_editions(self):
        title = "Legend of Blue Eyes White Dragon"
        cards = [["LOB-E001", 89631139, "Blue-Eyes White Dragon", "Ultra Rare"],
                 ["LOB-A001", 89631139, "Blue-Eyes White Dragon", "Ultra Rare"]]
        inventory = {"releases": [
            {"groupID": -1, "name": title + " (European English)", "rows": [cards[0]]},
            {"groupID": -14, "name": title + " (Australian English)", "suffix": "A", "rows": [cards[1]]},
        ]}
        content = "{{Set gallery|rarity=UR|\nLOB-A001; Blue-Eyes White Dragon\nLOB-E001; Blue-Eyes White Dragon\n}}"
        pages = [{"title": f"Set Card Galleries:{title} (TCG-AU-1E)", "revisions": [
            {"revid": 123, "slots": {"main": {"content": content}}},
        ]}]
        projected = galleries.project(inventory, [(json.dumps({"query": {"pages": pages}}).encode(), "2026-10-20T00:00:00Z")])
        self.assertEqual([(s["groupID"], s["codes"]) for s in projected["sources"]], [(-14, ["LOB-A001"])])
        self.assertIsNotNone(builder.CODE.fullmatch("LOB-A001"))
        self.assertIsNone(builder.CODE.fullmatch("MRD-A001"))

    def test_market_gallery_requires_the_exact_finish_and_product_binding(self):
        f = self.fixture
        f["prices"] = []
        base = f["products"][0]
        alternate = copy.deepcopy(base)
        alternate["productId"] = 3
        alternate["name"] = "Harpie's Brother (Alternate Art)"
        common = copy.deepcopy(base)
        common["productId"] = 4
        common["extendedData"][1]["value"] = "Common"
        f["products"].extend([alternate, common])
        old = self.build()[0]
        title = f["groups"][0]["name"]
        body = (f"{{{{Card gallery|region=EN|\nPSV-EN049; {title}; UR; UE\n}}}}\n"
                f"{{{{Card gallery|region=JP|\nPSV-EN049; {title}; C; LE\n}}}}")
        pages = [{"title": "Card Gallery:Sky Scout", "revisions": [
            {"revid": 42, "slots": {"main": {"content": body}}},
        ]}]
        date = "2026-10-19T00:00:00Z"
        reviews = galleries.project_market(old, [(json.dumps({"query": {"pages": pages}}).encode(), date)])
        self.assertEqual(set(reviews), {"1"})
        candidate, _, _, _ = self.build(reviews)
        printing = next(p for p in candidate["printings"] if p["p"] == 1)
        self.assertEqual(printing["e"], ["yugiohUnlimited"])
        self.assertFalse(printing["ec"])
        self.assertEqual(printing["pe"], [])
        self.assertEqual(printing["m"][0]["s"], date)
        self.assertIsNone(printing["m"][0]["q"])
        self.assertEqual(candidate["autoEligibleCodes"], [])
        self.assertEqual(builder.catalog_regressions(candidate, old), {})
        base["name"] = "Harpie's Brother (Different Artwork)"
        drifted, _, exceptions, _ = self.build(reviews, previous={1: printing})
        self.assertEqual(exceptions["printingEditionEvidenceDrift"], [1])
        self.assertTrue(all(not p["e"] for p in drifted["printings"]))

    def test_bound_edition_correction_never_transfers_the_rejected_quote(self):
        prior = self.build()[0]
        before = next(p for p in prior["printings"] if p["p"] == 1)
        review = {
            "printing": {"groupID": before["g"], "code": before["c"], "productName": before["pn"], "rarity": before["r"]},
            "editions": ["yugiohUnlimited"],
            "rejectProviderEditions": ["yugioh1stEdition"],
            "evidence": {"yugiohUnlimited": {"url": "https://example.com/specimen"}},
        }
        candidate, _, _, _ = self.build({"1": review}, previous={1: before})
        after = next(p for p in candidate["printings"] if p["p"] == 1)
        self.assertEqual(after["id"], before["id"])
        self.assertEqual(after["e"], ["yugiohUnlimited"])
        self.assertEqual(after["pe"], before["pe"])
        self.assertFalse(after["ec"])
        self.assertIsNone(after["m"][0]["q"])
        self.assertEqual(after["historicalContradictions"], before["m"])
        self.assertEqual(builder.catalog_regressions(candidate, prior), {
            "withdrawnEditions": [{"id": before["id"], "code": before["c"], "editions": ["yugioh1stEdition"]}],
        })
        self.assertEqual(self.build({"1": review}, previous={1: after})[0], candidate)
        del review["printing"]
        with self.assertRaisesRegex(AssertionError, "unbound edition correction"):
            self.build({"1": review})

    def test_alias_matches_and_canonical_id_does_not_depend_on_printed_name(self):
        seed, _, exceptions, _ = self.build()
        row = next(x for x in seed["printings"] if x["p"] == 1)
        self.assertEqual(seed["cards"][row["k"]]["n"], "Sky Scout")
        self.assertEqual(seed["cards"][row["k"]]["id"], builder.stable("yugioh-card:", "ygoprodeck:12206212"))
        self.assertEqual(exceptions["aliasMatch"], [1])
        self.fixture["products"][0]["name"] = "Sky Scout (UR)"
        renamed = self.build()[0]
        self.assertEqual(seed["cards"], renamed["cards"])

    def test_reviewed_passcodes_replace_provider_ids_without_changing_identity(self):
        old = self.build()[0]
        before = next(c for c in old["cards"] if c["sourceID"] == 12206212)
        review = {"12206212": {"name": "Sky Scout", "passcodes": [12345678, 87654321], "evidence": "https://example.com/card"}}
        new = self.build(passcode_corrections=review)[0]
        after = next(c for c in new["cards"] if c["id"] == before["id"])
        self.assertEqual(after, {**before, "pc": [12345678, 87654321]})
        self.assertEqual(builder.catalog_regressions(new, old), {})
        review["12206212"]["name"] = "Different Card"
        unchanged, _, exceptions, _ = self.build(passcode_corrections=review)
        self.assertEqual(unchanged, old)
        self.assertEqual(exceptions["canonicalPasscodeEvidenceDrift"], [12206212])

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
            pointer = json.loads((root/'yugioh/v1/candidate.json').read_text())
            self.assertFalse((root/'yugioh/v1/current.json').exists())
            self.assertEqual(pointer['status'], 'candidate_not_deployed')
            self.assertEqual(pointer['schemaVersion'], 1)
            self.assertEqual(pointer['revision'], 1)
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
