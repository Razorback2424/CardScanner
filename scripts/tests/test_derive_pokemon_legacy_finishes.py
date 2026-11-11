import sys
from pathlib import Path
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from certify_pokemon_finish_coverage import ROOT, SNAPSHOT, read_json, write_json
from derive_pokemon_legacy_finishes import ascended_reverse_aggregate, cosmos_holo_aggregate, derive, match_cards
from market_price_feeds import digest


class PokemonFinishProjectionTests(unittest.TestCase):
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
