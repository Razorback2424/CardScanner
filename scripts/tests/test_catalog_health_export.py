import csv
from datetime import date
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import catalog_health_export as health


class CatalogHealthTest(unittest.TestCase):
    def test_multiple_issues_and_unknown_mapping(self):
        row = health.classify(health.make(game='one-piece'), [
            ('PRINTING_NEEDS_REVIEW', 'Held', 'Review printing'),
            ('FINISH_UNVERIFIED', 'Unknown finish', 'Review finish')])
        self.assertEqual(row['issue_codes'], 'PRINTING_NEEDS_REVIEW|FINISH_UNVERIFIED')
        self.assertEqual(health.pricing(None, False), ('unknown', []))
        self.assertEqual(health.pricing(None, True)[1][0][0], 'PRICE_MAPPING_MISSING')
        self.assertEqual(health.pricing({'productID': 1}, True)[1][0][0], 'PRICE_NOT_CHECKED')

    def test_capture_validation_and_price_states(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            receipts = {}
            for kind, values in [('products', [dict(productId=n, categoryId=68, groupId=9, name='Card',
                                                    extendedData=[dict(name='Number', value='N')]) for n in (1, 2)]),
                                 ('prices', [dict(productId=1, subTypeName='Foil', marketPrice=0),
                                             dict(productId=2, subTypeName='Foil', marketPrice=None)])]:
                name = f'68-9-{kind}.json'
                raw = json.dumps(dict(success=True, errors=[], results=values, totalItems=len(values))).encode()
                (root / name).write_bytes(raw)
                receipts[name] = dict(sourceURL=f'https://tcgcsv.com/tcgplayer/68/9/{kind}', sha256=hashlib.sha256(raw).hexdigest())
            (root / 'capture.json').write_text(json.dumps(dict(upstreamBuild='2026-11-01T00:00:00+0000',
                mappedFeedsUpstreamBuild='2026-11-01T00:00:00+0000', captures=receipts)))
            captured, feeds = health.load_prices(root)
            def row(product):
                return health.classify(health.make(game='one-piece', record_type='physical_printing', market_provider='tcgplayer',
                    market_group_id=9, market_product_id=product, market_lane='Foil', market_product_name='Card',
                    market_product_number='N', price_status='not_checked'),
                    [('PRICE_NOT_CHECKED', 'Not checked', 'Check a dated provider snapshot')])
            rows = [row(1), row(2), row(3)]
            health.apply_prices(rows, captured, feeds, date(2026, 11, 2), 30)
            self.assertEqual([r['price_status'] for r in rows], ['quoted', 'no_quote', 'not_checked'])
            self.assertEqual(rows[0]['issue_codes'], '')
            self.assertEqual(rows[1]['issue_codes'], 'NO_MARKET_QUOTE')
            stale = [row(1)]
            health.apply_prices(stale, captured, feeds, date(2026, 12, 3), 30)
            self.assertEqual(stale[0]['issue_codes'], 'PRICE_STALE')
            with self.assertRaises(ValueError):
                health.apply_prices(stale, captured, feeds, date(2026, 10, 1), 30)
            (root / '68-9-prices.json').write_text('{}')
            with self.assertRaisesRegex(ValueError, 'Changed'):
                health.load_prices(root)

    def test_real_catalog_export_is_reproducible_and_consistent(self):
        repo = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as temp:
            one, two = Path(temp) / 'one', Path(temp) / 'two'
            health.export(repo, one)
            health.export(repo, two)
            for name in ('catalog-inventory.csv', 'catalog-exceptions.csv', 'catalog-summary.csv', 'catalog-metadata.json'):
                self.assertEqual(hashlib.sha256((one / name).read_bytes()).digest(),
                                 hashlib.sha256((two / name).read_bytes()).digest())
            def rows(name):
                with (one / name).open(encoding='utf-8', newline='') as file:
                    return list(csv.DictReader(file))
            inventory, exceptions, summary = (rows(name) for name in
                ('catalog-inventory.csv', 'catalog-exceptions.csv', 'catalog-summary.csv'))
            self.assertEqual({r['game'] for r in inventory}, {'pokemon', 'magic', 'one-piece', 'lorcana', 'yugioh'})
            self.assertEqual(exceptions, [r for r in inventory if r['issue_codes']])
            self.assertEqual(sum(int(r['count']) for r in summary),
                             sum(len(r['issue_codes'].split('|')) for r in exceptions))
            self.assertTrue(any(r['game'] == 'lorcana' and r['verification_status'] == 'discovery'
                                and not r['printing_id'] and not r['finish'] for r in inventory))
            self.assertTrue(any(r['game'] == 'one-piece' and r['record_type'] == 'market_discovery'
                                and not r['printing_id'] and not r['finish'] for r in inventory))


if __name__ == '__main__':
    unittest.main()
