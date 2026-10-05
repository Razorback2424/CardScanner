"""Bulk inventory fixtures; discovery must not allocate physical identities."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
import capture_one_piece_products as capture_driver
import discover_one_piece_products as discovery


class ProductDiscoveryTests(unittest.TestCase):
    def test_draft_keeps_previous_products_and_partitions_unreviewed_treatments(self):
        old = {'prefix': 'ST01', 'productID': 'permanent-old-product'}
        inventory = {'asOf': '2026-10-04', 'reviewedProducts': [old], 'productsWithoutSeries': [],
                     'series': [
                         {'prefixes': ['OP14', 'EB04'], 'reviewedProductID': None, 'seriesID': '14',
                          'captureID': 'bandai-op14', 'sourceURL': 'https://en.onepiece-cardgame.com/cardlist/?series=14',
                          'marketGroupCandidates': [{'groupId': 14, 'name': 'Combined release', 'abbreviation': 'OP14'}],
                          'officialProducts': [{'url': 'https://en.onepiece-cardgame.com/products/op14.html',
                                                'indexLabel': '[OP14-EB04] Release Date January 16, 2026'}],
                          'artworks': [{'printedNumber': 'OP14-001', 'artworkAlias': 'OP14-001'},
                                       {'printedNumber': 'OP14-001', 'artworkAlias': 'OP14-001_p1'},
                                       {'printedNumber': 'EB04-011', 'artworkAlias': 'EB04-011'},
                                       {'printedNumber': 'OP01-120', 'artworkAlias': 'OP01-120_p8'}]},
                         {'prefixes': ['PRB01'], 'reviewedProductID': None, 'seriesID': '301',
                          'marketGroupCandidates': [], 'officialProducts': []},
                     ]}
        products, scope = discovery.draft_manifest(inventory)
        self.assertEqual(products['products'][0], old)
        added = products['products'][1]
        self.assertEqual([c['printedNumber'] for c in added['cards']], ['EB04-011', 'OP14-001'])
        self.assertFalse(added['cards'][0]['isReprint'])
        self.assertEqual(added['heldArtworkReview'][0]['printedNumber'], 'OP01-120')
        self.assertEqual(scope['deferredSeries'][0]['prefix'], 'PRB01')
        self.assertFalse(added['physicalCoverageComplete'])

    def test_series_index_can_receive_a_catalog_capture_id_without_refetching(self):
        with tempfile.TemporaryDirectory() as directory:
            capture = capture_driver.ProductCapture(Path(directory), transport=lambda _: b'<p>Retained</p>')
            capture.capture(discovery.SERIES_INDEX, 'series-index.html')
            capture.offline = True
            record, raw = discovery.retained(capture, discovery.SERIES_INDEX, 'bandai-op17.html', 'bandai-op17')
            self.assertEqual(record['rawFile'], 'series-index.html')
            self.assertEqual(record['id'], 'bandai-op17')
            self.assertEqual(raw, b'<p>Retained</p>')
            self.assertEqual(len(capture.manifest['captures']), 1)

    def test_observed_pagination_combined_release_and_reprints_survive_discovery(self):
        responses = {
            discovery.INDEX: b'<a href="?page=2">Next</a><a href="/products/st99.html">DECK [ST-99]</a>',
            discovery.INDEX + '?page=2': b'<a href="?page=1">Previous</a><a href="/products/boosters/op98.php">BOOSTER [OP98-EB99]</a><a href="/products/op97.html">Upcoming [OP-97]</a>',
            'https://en.onepiece-cardgame.com/products/st99.html': b'<a href="/cardlist/?series=99">Cards</a>',
            'https://en.onepiece-cardgame.com/products/boosters/op98.php': b'<a href="/cardlist/?series=98">Cards</a>',
            'https://en.onepiece-cardgame.com/products/op97.html': b'<p>Not released</p>',
            discovery.SERIES_INDEX: b'<select><option value="99">DECK [ST-99]</option><option value="98">BOOSTER [OP98-EB99]</option><option value="97">PREMIUM [PRB-99]</option></select>',
            'https://en.onepiece-cardgame.com/cardlist/?series=99': b'<dl class="modalCol" id="ST99-001"></dl><dl class="modalCol" id="OP01-001_p8"></dl>',
            'https://en.onepiece-cardgame.com/cardlist/?series=98': b'<dl class="modalCol" id="OP98-001"></dl><dl class="modalCol" id="EB99-001"></dl>',
            'https://en.onepiece-cardgame.com/cardlist/?series=97': b'<dl class="modalCol" id="OP01-001_p9"></dl>',
        }
        reviewed = {'products': [{'prefix': 'ST99', 'productID': 'retained-deck'}]}
        groups = {'results': [{'name': 'Ordinary deck', 'abbreviation': 'ST-99', 'groupId': 99},
                              {'name': 'Combined booster', 'abbreviation': 'OP98-EB99', 'groupId': 98}]}
        with tempfile.TemporaryDirectory() as directory:
            capture = capture_driver.ProductCapture(Path(directory), transport=responses.__getitem__)
            result = discovery.discover(capture, reviewed, groups, '2026-10-04')
            self.assertEqual(len(result['officialIndexPages']), 2)
            self.assertEqual(len(result['series']), 3)
            self.assertEqual(result['series'][0]['reviewedProductID'], 'retained-deck')
            self.assertEqual(result['series'][1]['prefixes'], ['OP98', 'EB99'])
            self.assertIn('combined-release-number-families', result['series'][1]['reviewRequired'])
            self.assertIn('product-scoped-reprints-or-special-artwork', result['series'][2]['reviewRequired'])
            self.assertEqual(len(result['productsWithoutSeries']), 1)
            self.assertFalse(result['physicalCoverageComplete'])
            self.assertNotIn('printings', result)
            offline = capture_driver.ProductCapture(Path(directory), offline=True)
            self.assertEqual(result, discovery.discover(offline, reviewed, groups, '2026-10-04'))

    def test_missing_index_page_is_rejected(self):
        responses = {
            discovery.INDEX: b'<a href="?page=3">Last</a><a href="/products/st99.html">[ST-99]</a>',
            discovery.INDEX + '?page=3': b'<p>Last page</p>',
        }
        with tempfile.TemporaryDirectory() as directory:
            capture = capture_driver.ProductCapture(Path(directory), transport=responses.__getitem__)
            with self.assertRaisesRegex(ValueError, 'inventory gap'):
                discovery.discover(capture, {'products': []}, {'results': []}, '2026-10-04')


if __name__ == '__main__':
    unittest.main()
