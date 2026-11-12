import json
import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from certify_pokemon_finish_coverage import ROOT, SNAPSHOT, read_json, write_json
from derive_pokemon_legacy_finishes import (
    alternate_market_products, apply_unnumbered_energy, ascended_reverse_aggregate, cosmos_holo_aggregate,
    derive, linked_market_products, match_cards,
)
from market_price_feeds import digest


class PokemonFinishProjectionTests(unittest.TestCase):
    def test_alternate_market_capture_requires_a_unique_full_footer_and_retained_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            group = 1938
            marker = "2026-11-11T20:05:27+0000"
            for name in ("start", "end"):
                (root / f"{name}.txt").write_text(marker)
            products = [{"productId": product_id, "categoryId": 3, "groupId": group,
                         "name": f"Trainers' Mail - {number}",
                         "extendedData": [{"name": "Number", "value": number}]}
                        for product_id, number in ((1, "092a/108"), (2, "092a/124"), (3, "092b/108"), (4, "092/108"))]
            prices = [{"productId": row["productId"], "subTypeName": "Holofoil"} for row in products]
            sources = {}
            for kind, rows in (("products", products), ("prices", prices)):
                path = root / f"{group}-{kind}.json"
                write_json(path, {"success": True, "errors": [], "results": rows})
                sources[kind] = {"url": f"https://tcgcsv.com/tcgplayer/3/{group}/{kind}",
                                 "sha256": digest(path.read_bytes())}
            write_json(root / "verified-alternates.json", {
                "marketGroup": group, "marketBuild": marker, "marketSources": sources,
            })
            entries = [{"providerID": "xy6", "officialCount": 108}]
            slots = {"xy6": [{"providerID": "xy6-92a", "collectorNumber": "92a"}]}
            result, receipt = alternate_market_products(root, entries, slots)
            self.assertEqual({k: [p["productId"] for p in v] for k, v in result.items()}, {"xy6-92a": [1]})
            self.assertEqual(receipt["marketSources"], sources)

            entries.append({"providerID": "other", "officialCount": 108})
            slots["other"] = [{"providerID": "other-092a", "collectorNumber": "092a"}]
            self.assertEqual(alternate_market_products(root, entries, slots)[0], {})

            with (root / f"{group}-prices.json").open("ab") as file:
                file.write(b"\n")
            with self.assertRaisesRegex(ValueError, "differs from the retained receipt"):
                alternate_market_products(root, entries, slots)

    def test_unnumbered_energy_requires_matching_basic_energy_and_market_identity(self):
        card_id = "sm1-164"
        cards = {card_id: {"name": "Grass Energy", "number": "164"}}
        primary = {card_id: {"name": "Grass Energy", "localId": "164"}}
        independent = {card_id: {"name": "Grass Energy", "number": "164", "supertype": "Energy", "subtypes": ["Basic"]}}
        group = 1863
        product = {"productId": 1, "categoryId": 3, "groupId": group,
                   "name": "Grass Energy (2017 Unnumbered)",
                   "extendedData": [{"name": "Card Type", "value": "Basic Grass Energy"}]}

        def raw(rows):
            return json.dumps({"success": True, "errors": [], "results": rows}).encode()

        prices = raw([{"productId": 1, "subTypeName": lane} for lane in ("Normal", "Reverse Holofoil")])
        matches = match_cards(cards, primary, independent, {})
        apply_unnumbered_energy(matches, cards, primary, independent, raw([product]), prices, group)
        self.assertEqual(matches[card_id]["minimum"], ["normal", "reverse"])
        self.assertEqual(matches[card_id]["productIDs"], [1])
        self.assertTrue(matches[card_id]["isUnnumbered"])

        numbered = dict(product, extendedData=product["extendedData"] + [{"name": "Number", "value": "164/149"}])
        for wrong in (numbered, dict(product, name="Grass Energy (2020 Unnumbered)")):
            apply_unnumbered_energy(matches, cards, primary, independent, raw([wrong]), prices, group)
            self.assertEqual(matches[card_id]["minimum"], [])

        independent[card_id]["subtypes"] = ["Special"]
        matches = match_cards(cards, primary, independent, {})
        apply_unnumbered_energy(matches, cards, primary, independent, raw([product]), prices, group)
        self.assertNotIn("isUnnumbered", matches[card_id])

    def test_linked_price_lane_requires_the_same_empty_market_product_and_footer(self):
        card = {"name": "Empoleon", "number": "117"}
        detail = {"id": "bw9-117", "name": "Empoleon", "localId": "117", "set": {"id": "bw9"},
                  "pricing": {"tcgplayer": {"holofoil": {"productId": 85203}, "normal": {"productId": 1}}}}
        product = {"name": "Empoleon (117 Secret Rare)", "number": "117/116", "productId": 85203, "subtypes": []}
        variants = [product, dict(product, productId=2), dict(product, number="117/118"),
                    dict(product, number="117/116/118"), dict(product, subtypes=["Normal"])]
        exact = linked_market_products("bw9-117", card, detail, "bw9", 116, variants)
        self.assertEqual(exact, [dict(product, subtypes=["Holofoil"])])
        with self.assertRaisesRegex(ValueError, "detail identity differs"):
            linked_market_products("bw9-117", card, dict(detail, localId="118"), "bw9", 116, variants)

    def test_bundled_aggregate_sources_match_every_pinned_checklist(self):
        snapshot = ROOT / SNAPSHOT
        sources = read_json(snapshot / "legacy-finish-evidence.json")["aggregateChecklistSources"]
        manifest_resources = {entry["resource"] for entry in read_json(snapshot / "manifest.json")["entries"]}
        self.assertTrue(sources)
        for resource, expected in sources.items():
            with self.subTest(resource=resource):
                self.assertIn(resource, manifest_resources)
                self.assertEqual(digest((snapshot / resource).read_bytes()), expected)

    def test_derive_binds_repairs_to_the_explicit_baseline_without_git(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            baseline = root / "archived-checklist"
            historical = root / "historical-evidence"
            foil = root / "foil-evidence"
            reverse = root / "reverse-evidence"
            set_id, card_id, number = "me02.5", "me02.5-001", "001"
            resource = "sets/ascended.json"
            manifest = {"entries": [{"providerID": set_id, "resource": resource, "set": {"name": "Ascended Heroes"}}]}
            base_slot = {"providerID": card_id, "name": "Oddish", "collectorNumber": number, "setID": {"providerID": set_id}}
            slots = [dict(base_slot, masterSetVariant={"id": variant})
                     for variant in ("holo", "reverse", "cosmos", "energy", "pokeBall")]
            write_json(baseline / "manifest.json", manifest)
            write_json(baseline / resource, slots)
            write_json(root / SNAPSHOT / "manifest.json", manifest)
            write_json(root / SNAPSHOT / resource, slots[2:])
            sources = {resource: digest((baseline / resource).read_bytes())}

            card = {"id": card_id, "name": "Oddish", "localId": number, "set": {"id": set_id},
                    "variants": {"holo": True, "reverse": True}, "variants_detailed": [
                        {"type": "holo", "foil": "cosmos"}, {"type": "reverse", "foil": "energy"},
                        {"type": "reverse", "foil": "pokeball"},
                    ]}
            for evidence in (foil, reverse):
                path = evidence / f"{card_id}.json"
                write_json(path, card)
                write_json(evidence / "receipts.json", {"files": [
                    {"id": card_id, "url": f"https://api.tcgdex.net/v2/en/cards/{card_id}", "sha256": digest(path.read_bytes())},
                ]})
            products = [{"productId": index, "categoryId": 3, "groupId": 55, "name": f"Oddish ({pattern} Pattern)",
                         "extendedData": [{"name": "Number", "value": number}]}
                        for index, pattern in enumerate(("Energy Symbol", "Poke Ball"), 1)]
            prices = [{"productId": row["productId"], "subTypeName": "Reverse Holofoil"} for row in products]
            market_sources = {}
            for kind, rows in (("products", products), ("prices", prices)):
                path = reverse / f"market-{kind}.json"
                write_json(path, {"success": True, "errors": [], "results": rows})
                market_sources[kind] = {"url": f"https://tcgcsv.com/tcgplayer/3/55/{kind}", "sha256": digest(path.read_bytes())}
            write_json(reverse / "market-report.json", {"setID": set_id, "tcgplayerGroupID": 55,
                       "checklistSources": sources, "marketSources": market_sources})

            write_json(historical / "group-map.json", {})
            write_json(historical / "receipts.json", {"marketBuild": "fixture", "files": []})
            write_json(historical / "secondary-receipts.json", {"commit": "fixture", "files": []})
            write_json(historical / "pokemon-groups.json", {"results": []})
            for marker in ("start", "end"):
                (historical / f"market-build-{marker}.txt").write_bytes(b"fixture\n")

            output, report = derive(root, historical, foil, reverse, aggregate_baseline=baseline)
            self.assertEqual(output["holoAggregates"], {card_id: ["cosmos"]})
            self.assertEqual(output["reverseAggregates"], {card_id: ["energy", "pokeBall"]})
            self.assertEqual(output["aggregateChecklistSources"], sources)
            self.assertEqual(report["aggregateChecklistSources"], sources)
            self.assertNotEqual(sources[resource], digest((root / SNAPSHOT / resource).read_bytes()))
            with self.assertRaisesRegex(ValueError, "Ascended Heroes market report differs from the checklist"):
                derive(root, historical, foil, reverse, aggregate_baseline=root / SNAPSHOT)

            write_json(root / SNAPSHOT / resource, slots)
            previous = root / SNAPSHOT / "legacy-finish-evidence.json"
            write_json(previous, output)
            bundled, _ = derive(root, historical, foil, reverse)
            self.assertEqual(bundled, output)
            write_json(previous, {"aggregateChecklistSources": {resource: "different-hash"}})
            with self.assertRaisesRegex(ValueError, r"--aggregate-baseline TradingCardScanner/PokemonChecklistSnapshot\."):
                derive(root, historical, foil, reverse)

    def test_matches_exact_number_name_and_independently_identified_trait(self):
        cards = {"xy5-9": {"name": "Sceptile", "number": "9"}}
        primary = {"xy5-9": {"name": "Sceptile", "localId": "9"}}
        secondary = {"xy5-9": {"name": "Sceptile", "number": "9", "ancientTrait": {"name": "Ω Barrier"}}}
        products = {"9": [
            {"productId": 41, "name": "Sceptile (Omega)", "number": "9/160", "subtypes": ["Holofoil"]},
            {"productId": 42, "name": "Sceptile (Alpha)", "number": "9/160", "subtypes": ["Normal"]},
            {"productId": 43, "name": "Sceptile (Omega)", "number": "8/160", "subtypes": ["Normal"]},
        ]}
        row = match_cards(cards, primary, secondary, products)["xy5-9"]
        self.assertEqual(row["minimum"], ["holo"])
        self.assertEqual(row["productIDs"], [41])
        self.assertEqual(row["otherProductsAtNumber"], [42, 43])

        secondary["xy5-9"]["number"] = "10"
        row = match_cards(cards, primary, secondary, products)["xy5-9"]
        self.assertEqual(row["minimum"], [])
        self.assertEqual(row["status"], "independent catalog identity unavailable or differs")

    def test_mega_charizard_market_labels_match_only_the_corroborated_form_and_number(self):
        name = "M Charizard-EX"
        for number, form, attack, rarity in (("13", "Y", "Crimson Dive", "Rare Holo EX"),
                                              ("108", "X", "Wild Blaze", "Rare Secret")):
            with self.subTest(form=form):
                card_id = "xy2-" + number
                qualifier = " (Secret)" if rarity == "Rare Secret" else ""
                other_form = "X" if form == "Y" else "Y"
                other_qualifier = " (Secret)" if not qualifier else ""
                cards = {card_id: {"name": name, "number": number}}
                primary = {card_id: {"name": name, "localId": number}}
                secondary = {card_id: {"name": name, "number": number, "subtypes": ["MEGA", "EX"],
                                       "attacks": [{"name": attack}], "rarity": rarity}}
                products = {number: [
                    {"productId": 1, "name": f"M Charizard EX ({form}){qualifier}", "number": number + "/106",
                     "subtypes": ["Holofoil"]},
                    {"productId": 2, "name": f"M Charizard EX ({other_form}){qualifier}", "number": number + "/106",
                     "subtypes": ["Normal"]},
                    {"productId": 3, "name": f"M Charizard EX ({form}){other_qualifier}", "number": number + "/106",
                     "subtypes": ["Normal"]},
                    {"productId": 4, "name": f"M Charizard EX ({form}){qualifier}", "number": "99/106",
                     "subtypes": ["Normal"]},
                ]}
                row = match_cards(cards, primary, secondary, products)[card_id]
                self.assertEqual(row["minimum"], ["holo"])
                self.assertEqual(row["productIDs"], [1])
                self.assertEqual(row["otherProductsAtNumber"], [2, 3, 4])

    def test_reviewed_market_title_aliases_preserve_number_and_type(self):
        cases = [
            ("Giratina ◇", ["Prism Star"], "Giratina Prism Star", "Giratina V", "Holofoil", "holo"),
            ("N", ["Supporter"], "N (Supporter)", "N (Staff)", "Reverse Holofoil", "reverse"),
            ("Nidoran♀", ["Basic"], "Nidoran (F)", "Nidoran (M)", "Normal", "normal"),
            ("Head Ringer Team Flare Hyper Gear", ["Pokémon Tool F"], "Head Ringer", "Head Ringer (Staff)", "Holofoil", "holo"),
            ("Fairy Charm Dragon", ["Pokémon Tool"], "Fairy Charm O", "Fairy Charm F", "Reverse Holofoil", "reverse"),
        ]
        for name, subtypes, alias, other, lane, finish in cases:
            with self.subTest(name=name):
                cards = {"set-1": {"name": name, "number": "1"}}
                primary = {"set-1": {"name": name, "localId": "1"}}
                secondary = {"set-1": {"name": name, "number": "1", "subtypes": subtypes}}
                products = {"1": [
                    {"productId": 1, "name": alias, "number": "1/10", "subtypes": [lane]},
                    {"productId": 2, "name": other, "number": "1/10", "subtypes": ["Normal"]},
                    {"productId": 3, "name": alias, "number": "2/10", "subtypes": ["Normal"]},
                ]}
                row = match_cards(cards, primary, secondary, products)["set-1"]
                self.assertEqual(row["minimum"], [finish])
                self.assertEqual(row["productIDs"], [1])
                self.assertEqual(row["otherProductsAtNumber"], [2, 3])

                if "Prism Star" in subtypes or "Supporter" in subtypes:
                    secondary["set-1"]["subtypes"] = []
                    row = match_cards(cards, primary, secondary, products)["set-1"]
                    self.assertEqual(row["minimum"], [])

    def test_special_energy_abbreviations_require_exact_independent_type_order(self):
        cards = {"bw6-117": {"name": "Blend Energy Grass Fire Psychic Darkness", "number": "117"}}
        primary = {"bw6-117": {"name": cards["bw6-117"]["name"], "localId": "117"}}
        secondary = {"bw6-117": {"name": "Blend Energy GrassFirePsychicDarkness", "number": "117",
                                 "supertype": "Energy", "subtypes": ["Special"]}}
        products = {"117": [
            {"productId": 1, "name": "Blend Energy GFPD", "number": "117/124", "subtypes": ["Normal", "Reverse Holofoil"]},
            {"productId": 2, "name": "Blend Energy GFDP", "number": "117/124", "subtypes": ["Holofoil"]},
            {"productId": 3, "name": "Blend Energy GFPD", "number": "118/124", "subtypes": ["Holofoil"]},
        ]}
        row = match_cards(cards, primary, secondary, products)["bw6-117"]
        self.assertEqual(row["minimum"], ["normal", "reverse"])
        self.assertEqual(row["productIDs"], [1])
        secondary["bw6-117"]["name"] = "Blend Energy GrassFireDarknessPsychic"
        row = match_cards(cards, primary, secondary, products)["bw6-117"]
        self.assertEqual(row["minimum"], [])

    def test_cosmos_aggregate_requires_existing_pattern_and_preserves_plain_holo(self):
        cosmos = {"type": "holo", "foil": "cosmos", "size": "standard"}
        card = {"variants": {"holo": True}, "variants_detailed": [cosmos]}
        self.assertEqual(cosmos_holo_aggregate(card, {"normal", "holo", "cosmos"}), ["cosmos"])
        self.assertEqual(cosmos_holo_aggregate(card, {"normal", "holo"}), [])

        card["variants_detailed"].append({"type": "holo", "languages": ["ja"]})
        self.assertEqual(cosmos_holo_aggregate(card, {"holo", "cosmos"}), ["cosmos"])
        card["variants_detailed"].append({"type": "holo", "languages": ["en"]})
        self.assertEqual(cosmos_holo_aggregate(card, {"holo", "cosmos"}), [])

        card["variants_detailed"] = [cosmos]
        card["pricing"] = {"tcgplayer": {"holofoil": {"productId": 12}}}
        self.assertEqual(cosmos_holo_aggregate(card, {"holo", "cosmos"}), [])

    def test_ascended_reverse_aggregate_needs_both_named_market_products(self):
        patterns = {"energy", "pokeBall"}
        slots = patterns | {"reverse", "normal"}
        card = {"set": {"id": "me02.5"}, "variants": {"reverse": True}, "variants_detailed": [
            {"type": "reverse", "foil": "energy"}, {"type": "reverse", "foil": "pokeball"},
        ]}
        self.assertEqual(ascended_reverse_aggregate(card, slots, patterns), ["energy", "pokeBall"])
        self.assertEqual(ascended_reverse_aggregate(card, slots, {"energy"}), [])
        self.assertEqual(ascended_reverse_aggregate(card, slots, patterns | {"reverse"}), [])
        card["variants_detailed"].append({"type": "reverse"})
        self.assertEqual(ascended_reverse_aggregate(card, slots, patterns), [])
