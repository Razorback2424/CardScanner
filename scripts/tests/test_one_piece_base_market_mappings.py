import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from review_one_piece_base_market_mappings import base_title_matches, reconcile


class BaseMarketMappingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source'; self.source.mkdir()
        self.prices = self.root / 'prices'; self.prices.mkdir()
        self.registry = {'canonicalCards': [{'id': 'card', 'printedNumber': 'OP01-120', 'name': 'Shanks'}],
            'printings': [{'id': 'permanent-uuid', 'canonicalCardID': 'card', 'releaseID': 'op01',
                'status': 'verified', 'treatment': 'Standard artwork', 'supportedVariantIDs': ['foil'], 'marketMappings': []}]}
        self.specs = {'products': [{'productID': 'op01', 'prefix': 'OP01', 'retailerGroupID': '3188'}]}
        self.products = [{'productId': 454664, 'categoryId': 68, 'groupId': 3188, 'name': 'Shanks',
            'extendedData': [{'name': 'Number', 'value': 'OP01-120'}]}]
        self.lanes = [{'productId': 454664, 'subTypeName': 'Foil', 'marketPrice': 8.16}]

    def run_review(self):
        for root, kind, rows in [(self.source, 'products', self.products), (self.prices, 'prices', self.lanes)]:
            data = json.dumps({'success': True, 'errors': [], 'results': rows}).encode()
            filename = f'68-3188-{kind}.json'; (root / filename).write_bytes(data)
            (root / 'captures.json').write_text(json.dumps({'captures': {
                f'https://tcgcsv.com/tcgplayer/68/3188/{kind}': {'rawFile': filename, 'byteCount': len(data),
                    'payloadSHA256': hashlib.sha256(data).hexdigest(), 'observedAt': '2026-10-04T00:00:00Z'}}}))
        return reconcile(self.registry, self.specs, self.source, self.prices)

    def test_exact_base_lane_retains_uuid_and_aggregate_condition(self):
        result, observations, _, _ = self.run_review()
        self.assertEqual(result['printings'][0]['id'], 'permanent-uuid')
        mapping = result['printings'][0]['marketMappings'][0]
        self.assertEqual(mapping['condition'], 'aggregate')
        self.assertEqual(mapping['providerVariantID'], 'Foil')
        self.assertEqual(observations[0]['printedEvidence']['marketProductID'], '454664')
        self.registry = result
        self.assertEqual(self.run_review()[0], result)

    def test_manga_and_duplicate_titles_cannot_join_base(self):
        original = copy.deepcopy(self.products)
        for products in [[dict(original[0], name='Shanks (Manga)')], original * 2]:
            self.products = products
            self.assertEqual(self.run_review()[1], [])

    def test_identifier_suffixes_map_systematically_without_treatment_fallback(self):
        for name in ['Shanks (120)', 'Shanks (OP01-120)', 'Shanks - OP01-120']:
            with self.subTest(name=name):
                self.products[0]['name'] = name
                result, _, _, review = self.run_review()
                self.assertEqual(review['decisions'][0]['status'], 'exact')
                self.assertEqual(result['printings'][0]['marketMappings'][0]['qualifiers']['productName'], name)
                self.assertEqual(result['printings'][0]['id'], 'permanent-uuid')

    def test_wrong_numbers_and_qualified_printings_stay_held(self):
        for name in ['Shanks (119)', 'Shanks (OP02-120)', 'Shanks (120) (Manga)',
                     'Shanks (OP01-120) (Alternate Art)', 'Shanks (120) (Winner)',
                     'Shanks (120) (120)', 'Shanks120', 'Shanks (1 20)',
                     'Shanks - OP02-120', 'Shanks - OP01-120 (Manga)']:
            with self.subTest(name=name):
                self.products[0]['name'] = name
                self.assertEqual(self.run_review()[1], [])

    def test_suffix_does_not_bypass_number_group_category_or_finish(self):
        self.products[0]['name'] = 'Shanks (120)'
        original = copy.deepcopy(self.products[0])
        for changes in [{'groupId': 999}, {'categoryId': 1},
                        {'extendedData': [{'name': 'Number', 'value': 'OP01-119'}]}]:
            self.products[0] = dict(original, **changes)
            self.assertEqual(self.run_review()[1], [])
        self.products[0] = original
        self.lanes[0]['subTypeName'] = 'Normal'
        self.assertEqual(self.run_review()[3]['decisions'][0]['reason'], 'missing-exact-finish-lane')

    def test_unsuffixed_and_suffixed_duplicates_are_ambiguous(self):
        self.products.append(dict(self.products[0], productId=999, name='Shanks (120)'))
        self.assertEqual(self.run_review()[3]['decisions'][0]['reason'], 'ambiguous-base-title')

    def test_character_parentheses_are_preserved_and_all_prefixes_are_supported(self):
        for number in ['OP16-056', 'ST13-007', 'EB03-010']:
            self.assertTrue(base_title_matches(f'Mr.3(Galdino) ({number})', 'Mr.3(Galdino)', number))
            self.assertFalse(base_title_matches(f'Mr.3 ({number})', 'Mr.3(Galdino)', number))
        self.assertFalse(base_title_matches('Shanks (120)', 'Shanks', 'OP01-120 (Manga)'))
        self.assertTrue(base_title_matches('Monkey.D.Luffy - OP14-34', 'Monkey.D.Luffy', 'OP14-034'))

    def test_suffix_review_is_idempotent_and_duplicate_finish_is_held(self):
        self.products[0]['name'] = 'Shanks (OP01-120)'
        result = self.run_review()[0]
        self.registry = result
        self.assertEqual(self.run_review()[0], result)
        self.lanes *= 2
        self.assertEqual(self.run_review()[3]['decisions'][0]['reason'], 'duplicate-exact-finish-lane')

    def test_wrong_finish_and_reprint_release_stay_unmapped(self):
        self.lanes[0]['subTypeName'] = 'Normal'
        self.assertEqual(self.run_review()[1], [])
        self.specs['products'][0]['prefix'] = 'ST01'
        self.assertEqual(self.run_review()[1], [])

    def test_changed_existing_mapping_requires_correction(self):
        self.registry['printings'][0]['marketMappings'] = [{'productID': 'another-physical-product'}]
        with self.assertRaisesRegex(ValueError, 'explicit correction'):
            self.run_review()


if __name__ == '__main__': unittest.main()
