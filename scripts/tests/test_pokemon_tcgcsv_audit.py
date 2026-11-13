import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import audit_pokemon_tcgcsv as audit
import capture_pokemon_tcgcsv as capture
from one_piece_tcgcsv_capture import BUILD_MARKER_URL


class PokemonTCGCSVAuditTests(unittest.TestCase):
    def test_category_capture_reuses_the_same_build_and_preserves_title_only_candidates(self):
        def document(results, **other):
            return json.dumps(dict(results=results, success=True, errors=[], **other)).encode()

        group = {"categoryId": 3, "groupId": 24451, "name": "ME: Mega Evolution Promo"}
        marker = b"2026-11-12T20:06:19+0000\n"
        rows = [
            {"productId": 1, "categoryId": 3, "groupId": 24451, "name": "Kyogre - 117 (Pokemon Center Exclusive)"},
            {"productId": 2, "categoryId": 3, "groupId": 24451, "name": "Booster Pack"},
        ]
        responses = {BUILD_MARKER_URL: marker, f"{capture.BASE}/groups": document([group], totalItems=1),
                     f"{capture.BASE}/24451/products": document(rows, totalItems=2),
                     f"{capture.BASE}/24451/prices": document([])}

        def fetch(url, user_agent, delay):
            self.assertEqual(user_agent, capture.USER_AGENT)
            self.assertGreaterEqual(delay, 0.1)
            return responses[url]

        with tempfile.TemporaryDirectory() as temp:
            with patch.object(capture, "fetch_response", side_effect=fetch), \
                 patch("one_piece_tcgcsv_capture.fetch_response", side_effect=fetch) as downloads:
                directory = capture.capture(Path(temp))
                self.assertEqual(downloads.call_count, 5)
                self.assertEqual(capture.capture(Path(temp)), directory)
                self.assertEqual(downloads.call_count, 5)
                build, groups, products, incomplete = audit.read_source(directory)
            self.assertEqual(build, marker.decode().strip())
            self.assertEqual(groups, [group])
            self.assertEqual(incomplete, [])
            self.assertEqual(products[1]["number"], "117")
            self.assertEqual(products[1]["numberSource"], "marketTitle")
            self.assertTrue(products[1]["singleCardCandidate"])
            self.assertFalse(products[2]["singleCardCandidate"])

    def test_deck_reprints_do_not_inherit_a_base_cards_market_id_or_finish(self):
        inventory = {"sets": [{"id": "me06", "name": "Delta Reign", "code": "DLR", "officialCount": 103, "cards": [
            {"id": "me06-021", "name": "Magmortar", "number": "021", "scanResult": "resolved",
             "scanFinishes": ["holo", "reverse"], "browseFinishes": ["holo", "reverse"],
             "market": [{"variant": "holo", "productID": 100, "scanProductID": 100,
                         "url": "https://www.tcgplayer.com/product/100?Printing=Holofoil"}]},
        ]}]}
        groups = [{"groupId": 1840, "name": "Deck Exclusives"}]
        base = {"groupID": 1840, "name": "Magmortar - 021/103", "number": "021/103",
                "numberSource": "marketField", "singleCardCandidate": True}
        products = {
            100: dict(base, productID=100, lanes={"Holofoil": 0.22, "Normal": 0.08}),
            200: dict(base, productID=200, lanes={"Normal": 0.10}),
            300: dict(base, productID=300, number="021/102", lanes={"Normal": 0.10}),
        }
        quote_scope = {(3, 1840): {100: {"Holofoil", "Normal"}}}
        exact, deck, wrong = audit.compare(products, groups, inventory, quote_scope,
                                           {(1840, 100, "Holofoil"): (0.22, True),
                                            (1840, 200, "Normal"): (0.10, True)})
        self.assertEqual(exact["match"], "exactProduct")
        self.assertEqual(exact["unverifiedAppLanes"], ["Normal"])
        self.assertTrue(exact["exactAppMatches"][0]["scanExactProduct"])
        self.assertEqual(exact["hostedPrice"], "Holofoil=hostedQuoteAvailable | Normal=missingFromHostedFeed")
        self.assertEqual(deck["match"], "possibleBaseIdentity")
        self.assertEqual(deck["appCandidates"][0]["id"], "me06-021")
        self.assertTrue(deck["possibleMissingStandardFinish"])
        self.assertEqual(deck["exactAppMatches"], [])
        self.assertEqual(deck["hostedPrice"], "outsideReviewedMirror")
        self.assertEqual(wrong["match"], "unmatched")

    def test_mapped_promo_set_uses_printed_identity_and_ignores_other_releases(self):
        card = {"id": "other-1", "name": "Pikachu", "number": "001", "scanResult": "resolved",
                "scanFinishes": ["holo"], "browseFinishes": ["holo"], "market": []}
        inventory = {"sets": [{"id": "other", "name": "Other Set", "code": "OTH", "officialCount": 15,
                               "cards": [card]}]}
        groups = [{"groupId": 24938, "name": "McDonald's Promos 2026"}]
        product = {"productID": 730419, "groupID": 24938, "name": "Pikachu", "number": "001/015",
                   "numberSource": "marketField", "singleCardCandidate": True, "lanes": {"Holofoil": 0.9}}
        row = audit.compare({730419: product}, groups, inventory, {}, {})[0]
        self.assertEqual(row["match"], "mappedSetAbsent")
        self.assertEqual(row["appCandidates"], [])

    def test_daily_diff_uses_finishes_and_availability_and_ignores_price_amounts(self):
        product = {"groupID": 1840, "name": "Magmortar", "number": "021/103", "numberSource": "marketField",
                   "lanes": {"Normal": 0.09}}
        prior = {1: product, 2: product, 3: product, 4: dict(product, groupID=99)}
        current = {1: dict(product, lanes={"Normal": 0.11}), 2: dict(product, lanes={"Normal": None}),
                   3: dict(product, lanes={"Reverse Holofoil": 1.10}), 5: product}
        self.assertEqual(audit.catalog_changes(prior, current, {99}), {"added": [5], "removed": [], "changed": [2, 3]})

    def test_bundled_printing_tables_invalidate_the_inventory_cache(self):
        with tempfile.TemporaryDirectory() as temp:
            repo = Path(temp)
            subprocess.run(["git", "init", "--quiet", str(repo)], check=True)
            (repo / "publisher").mkdir()
            for filename in ("pokemon-battle-deck-finishes.json", "pokemon-deck-exclusive-normals.json",
                             "pokemon-delta-reign-printings.json", "pokemon-mcdonalds-2026.json"):
                with self.subTest(filename=filename):
                    path = repo / "publisher" / filename
                    path.write_text("{}")
                    previous = audit.app_fingerprint(repo)
                    path.write_text('{"schemaVersion":1}')
                    self.assertNotEqual(audit.app_fingerprint(repo), previous)


if __name__ == "__main__":
    unittest.main()
