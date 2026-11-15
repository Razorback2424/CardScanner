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
            missing_group = row(1)
            missing_group['market_group_id'] = ''
            mismatch = row(1)
            mismatch['market_product_name'] = 'Other'
            health.apply_prices([missing_group, mismatch], captured, feeds, date(2026, 11, 2), 30)
            self.assertEqual([missing_group['price_status'], mismatch['price_status']], ['mapping_incomplete', 'mapping_mismatch'])
            self.assertEqual(missing_group['issue_codes'], 'MARKET_MAPPING_INCOMPLETE')
            self.assertEqual(mismatch['issue_codes'], 'MARKET_MAPPING_MISMATCH')
            self.assertIn('expected Other / N', mismatch['issue_details'])
            stale = [row(1)]
            health.apply_prices(stale, captured, feeds, date(2026, 12, 3), 30)
            self.assertEqual(stale[0]['issue_codes'], 'PRICE_SNAPSHOT_STALE')
            self.assertEqual(stale[0]['price_status'], 'snapshot_stale')
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
            for name in ('catalog-inventory.csv', 'catalog-exceptions.csv', 'catalog-summary.csv', 'catalog-census-findings.csv', 'catalog-metadata.json'):
                self.assertEqual(hashlib.sha256((one / name).read_bytes()).digest(),
                                 hashlib.sha256((two / name).read_bytes()).digest())
            def rows(name):
                with (one / name).open(encoding='utf-8', newline='') as file:
                    return list(csv.DictReader(file))
            inventory, exceptions, summary, census = (rows(name) for name in
                ('catalog-inventory.csv', 'catalog-exceptions.csv', 'catalog-summary.csv', 'catalog-census-findings.csv'))
            self.assertEqual({r['game'] for r in inventory}, {'pokemon', 'magic', 'one-piece', 'lorcana', 'yugioh'})
            self.assertEqual(exceptions, [r for r in inventory if r['assessment'] == 'actionable'])
            self.assertTrue(census)
            self.assertTrue({r['game'] for r in census} <= {'pokemon', 'magic', 'one-piece', 'lorcana', 'yugioh'})
            self.assertTrue(all(r['disposition'] and r['code'] for r in census))
            self.assertTrue(all(r['source_scope'] for r in inventory))
            self.assertTrue(all(r['source_scope'] for r in summary))
            self.assertFalse(any(r['game'] == 'pokemon' and r['issue_codes'] == 'FINISH_UNVERIFIED' for r in inventory))
            self.assertTrue(any(r['game'] == 'pokemon' and r['issue_codes'] == 'RAW_FINISH_COVERAGE_UNEVALUATED' and r['assessment'] == 'coverage_not_evaluated' for r in inventory))
            self.assertEqual(sum(int(r['count']) for r in summary),
                             sum(len(r['issue_codes'].split('|')) for r in inventory if r['issue_codes']))
            self.assertTrue(any(r['game'] == 'lorcana' and r['verification_status'] == 'discovery'
                                and not r['printing_id'] and not r['finish'] for r in inventory))
            self.assertTrue(any(r['game'] == 'one-piece' and r['record_type'] == 'market_discovery'
                                and not r['printing_id'] and not r['finish'] for r in inventory))
            envelope = health.read(repo / 'TradingCardScanner/OnePieceOwnerCatalog/one-piece-owner-catalog.json')
            import base64
            payload = envelope['payload']
            release = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))
            for code in ('EB05', 'OP18'):
                source = release if code == 'EB05' else health.read(repo / 'publisher/one-piece/production/revision-4/candidate.json')
                products = {p['id']: p for p in source['registry']['products']}
                expected = {o['id'] for o in source['observations'] if o['printedEvidence'].get('sourceRole') == health.BROWSE_DISCOVERY
                            and o.get('productEvidence') and code in health.prefixes(products[o['productEvidence'][0]]['label'])}
                actual = {identity for r in inventory if r['record_type'] in ('browse_discovery', 'candidate_discovery') and r['product_set_code'] == code
                          for identity in r['source_id'].split('|')}
                self.assertTrue(expected, code)
                self.assertEqual(actual, expected)
            self.assertTrue(any(r['product_set_code'] == 'EB05' and r['printed_set_marker'] == 'EB03' for r in inventory))
            for kind in ('browse_discovery', 'candidate_discovery'):
                keys = [(r['source_scope'], r['product_set_code'], r['card_number']) for r in inventory if r['record_type'] == kind]
                self.assertEqual(len(keys), len(set(keys)), kind)
            self.assertEqual({r['source_scope'] for r in inventory if r['record_type'] == 'candidate_discovery'}, {'candidate'})

    def test_spreadsheet_formula_protection(self):
        for value in ('=1+1', '+1', '-1', '@x', '  =cmd', '\ttext', '\rtext'):
            self.assertEqual(health.spreadsheet_safe(value), "'" + value)
        self.assertEqual(health.spreadsheet_safe('EB05-001'), 'EB05-001')


if __name__ == '__main__':
    unittest.main()
