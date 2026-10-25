import importlib.util
import io
import json
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import urlencode

SPEC = importlib.util.spec_from_file_location('audit_set_pricing', Path(__file__).resolve().parents[1] / 'audit_set_pricing.py')
audit = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(audit)
MAGIC_SPEC = importlib.util.spec_from_file_location('audit_magic_set_products', SPEC.origin.replace('audit_set_pricing.py', 'audit_magic_set_products.py'))
magic = importlib.util.module_from_spec(MAGIC_SPEC)
with patch.dict(sys.modules, audit_set_pricing=audit):
    MAGIC_SPEC.loader.exec_module(magic)
POKEMON_SPEC = importlib.util.spec_from_file_location('verify_pokemon_subset_products', SPEC.origin.replace('audit_set_pricing.py', 'verify_pokemon_subset_products.py'))
pokemon = importlib.util.module_from_spec(POKEMON_SPEC)
with patch.dict(sys.modules, audit_set_pricing=audit):
    POKEMON_SPEC.loader.exec_module(pokemon)
YELLOW_SPEC = importlib.util.spec_from_file_location('verify_pokemon_yellow_a_products', SPEC.origin.replace('audit_set_pricing.py', 'verify_pokemon_yellow_a_products.py'))
yellow = importlib.util.module_from_spec(YELLOW_SPEC)
with patch.dict(sys.modules, audit_set_pricing=audit):
    YELLOW_SPEC.loader.exec_module(yellow)


class SetPricingAuditTests(unittest.TestCase):
    def feed(self, rows):
        return json.dumps(dict(success=True, errors=[], results=rows)).encode()

    def test_product_group_and_duplicate_identity_are_checked(self):
        row = dict(productId=1, categoryId=68, groupId=10)
        self.assertEqual(audit.validate_feed(self.feed([row]), 68, 10, 'products'), [row])
        for rows, category, group in [([row, row], 68, 10), ([row], 71, 10), ([row], 68, 11)]:
            with self.assertRaises(ValueError):
                audit.validate_feed(self.feed(rows), category, group, 'products')

    def test_null_and_zero_quotes_are_valid_and_distinct(self):
        rows = [dict(productId=1, subTypeName='Normal', marketPrice=None),
                dict(productId=1, subTypeName='Foil', marketPrice=0)]
        self.assertEqual(audit.validate_feed(self.feed(rows), 68, 10, 'prices'), rows)

    def test_duplicate_lanes_and_invalid_amounts_are_not_coverage_misses(self):
        row = dict(productId=1, subTypeName='Normal', marketPrice=1)
        with self.assertRaises(ValueError):
            audit.validate_feed(self.feed([row, row]), 68, 10, 'prices')
        for amount in [-1, float('nan'), float('inf'), True]:
            with self.assertRaises(ValueError):
                audit.validate_feed(self.feed([dict(row, marketPrice=amount)]), 68, 10, 'prices')

    def test_incomplete_export_is_rejected(self):
        with self.assertRaises(ValueError):
            audit.validate_feed(b'{"success":true,"errors":[],"totalItems":2,"results":[]}', 68, 10, 'products')

    def test_offline_capture_requires_hash_bound_bytes_and_never_fetches(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'products.json'
            path.write_bytes(b'public capture')
            manifest = dict(captures={path.name: dict(sourceURL='https://tcgcsv.com/test', sha256=audit.digest(path))})
            with patch.object(audit, 'urlopen', side_effect=AssertionError('offline replay accessed network')):
                self.assertEqual(audit.capture('https://tcgcsv.com/test', path, manifest, False), b'public capture')
                path.write_bytes(b'changed')
                with self.assertRaises(ValueError):
                    audit.capture('https://tcgcsv.com/test', path, manifest, False)

    def test_untracked_capture_cannot_be_adopted(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'products.json'
            path.write_bytes(b'untracked')
            with self.assertRaises(ValueError):
                audit.capture('https://tcgcsv.com/test', path, dict(captures={}), False)

    def test_empty_search_404_is_retained_but_rate_limit_is_not(self):
        url = 'https://api.scryfall.com/cards/search?q=empty'
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'cards.json'
            manifest = dict(captures={})
            error = HTTPError(url, 404, 'No cards', {}, io.BytesIO(b'{"object":"error","status":404}'))
            with patch.object(audit, 'urlopen', side_effect=error), patch.object(audit.time, 'sleep') as sleep:
                raw = audit.capture(url, path, manifest, True, allow_not_found=True, delay=.75)
                sleep.assert_called_once_with(.75)
            self.assertEqual(manifest['captures'][path.name]['httpStatus'], 404)
            self.assertEqual(audit.capture(url, path, manifest, False, allow_not_found=True), raw)
            other = Path(root) / 'rate-limited.json'
            with patch.object(audit, 'urlopen', side_effect=HTTPError(url, 429, 'Slow down', {}, io.BytesIO())), patch.object(audit.time, 'sleep'):
                with self.assertRaises(HTTPError):
                    audit.capture(url, other, manifest, True, allow_not_found=True)
            self.assertFalse(other.exists())
            self.assertNotIn(other.name, manifest['captures'])

    def test_capture_rejects_invalid_pacing_before_network(self):
        with tempfile.TemporaryDirectory() as root, patch.object(audit, 'urlopen', side_effect=AssertionError('invalid request reached network')):
            for delay in [.1, -1, float('nan'), float('inf')]:
                with self.assertRaises(ValueError):
                    audit.capture('https://tcgcsv.com/test', Path(root) / 'feed.json', dict(captures={}), True, delay=delay)

    def test_card_pagination_requires_complete_unique_same_set_inventory(self):
        card = dict(id='a', set='tst', lang='en', games=['paper'])
        next_url = 'https://api.scryfall.com/cards/search?' + urlencode(dict(q='set:tst lang:en game:paper', unique='prints', order='set', page=2))
        first = dict(object='list', total_cards=2, has_more=True, next_page=next_url, data=[card])
        last = dict(object='list', total_cards=2, has_more=False, data=[dict(card, id='b')])
        def run(documents):
            with patch.object(audit, 'capture', side_effect=[json.dumps(d).encode() for d in documents]):
                return magic.cards_for('TST', Path('/tmp'), dict(captures={}), False)
        self.assertEqual(len(run([first, last])), 2)
        for invalid in [dict(last, data=[card]), dict(last, total_cards=3),
                        dict(last, data=[dict(card, id='b', lang='ja')]),
                        dict(last, data=[dict(card, id='b', set='other')]),
                        dict(last, data=[dict(card, id='b', games=['arena'])]),
                        dict(last, data=[])]:
            with self.assertRaises(ValueError):
                run([first, invalid])

    def test_card_pagination_cannot_change_host_query_or_printing_scope(self):
        query = dict(q='set:tst lang:en game:paper', unique='prints', order='set', page=2)
        urls = ['https://example.com/cards/search?' + urlencode(query),
                'https://api.scryfall.com/cards/search?' + urlencode(dict(query, q='set:other')),
                'https://api.scryfall.com/cards/search?' + urlencode(dict(query, unique='cards')),
                'https://api.scryfall.com/cards/search?' + urlencode(dict(query, page=1))]
        for url in urls:
            document = dict(object='list', total_cards=2, has_more=True, next_page=url,
                data=[dict(id='a', set='tst', lang='en', games=['paper'])])
            with patch.object(audit, 'capture', return_value=json.dumps(document).encode()):
                with self.assertRaises(ValueError):
                    magic.cards_for('TST', Path('/tmp'), {}, False)

    def test_card_number_diagnostics_preserve_suffixes_and_denominators(self):
        for left, right in [('001', '1'), ('1/100', '1'), ('1/100', '01/0100')]:
            self.assertTrue(magic.numbers_agree(left, right))
        for left, right in [('14★', '14'), ('86a', '65'), ('MM2-48', '48'), ('1/100', '1/101'), ('', '')]:
            self.assertFalse(magic.numbers_agree(left, right))

    def test_native_proof_cannot_omit_numberless_products_or_change_source_product_id(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            products = [dict(productId=1, categoryId=1, groupId=10, name='Card', extendedData=[dict(name='Number', value='1')]),
                        dict(productId=2, categoryId=1, groupId=10, name='Sealed pack', extendedData=[])]
            product_path = root / '1-10-products.json'
            product_path.write_bytes(self.feed(products))
            receipt = dict(sourceURL='https://tcgcsv.com/tcgplayer/1/10/products', sha256=audit.digest(product_path))
            (root / 'capture.json').write_text(json.dumps(dict(upstreamBuild='test', captures={product_path.name: receipt})))
            entry = dict(code='TST', groupID='10', cards=[dict(name='Card', number='1', productID='1')],
                products=[dict(name='Card', number='1', productID='1'), dict(name='Sealed pack', number='', productID='2')])
            proof = dict(upstreamBuild='test', receipts={product_path.name: receipt}, cases=[entry])
            path = root / 'proof.json'
            with patch.object(magic, 'cards_for', return_value=[dict(name='Card', collector_number='1', tcgplayer_id=1)]):
                path.write_text(json.dumps(proof))
                magic.verify_pinned_proof(path, root)
                entry['products'].pop()
                path.write_text(json.dumps(proof))
                with self.assertRaisesRegex(ValueError, 'projection'):
                    magic.verify_pinned_proof(path, root)
                entry['products'].append(dict(name='Sealed pack', number='', productID='2'))
                entry['cards'][0]['productID'] = '999'
                path.write_text(json.dumps(proof))
                with self.assertRaisesRegex(ValueError, 'projection'):
                    magic.verify_pinned_proof(path, root)

    def test_direct_proof_preserves_separate_etched_product_and_all_source_facts(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            captures = {}
            for name, url, raw in [
                ('groups-1.json', 'https://tcgcsv.com/tcgplayer/1/groups', self.feed([dict(groupId=10, name='Vendor')])),
                ('1-10-products.json', 'https://tcgcsv.com/tcgplayer/1/10/products', self.feed([
                    dict(productId=n, categoryId=1, groupId=10, name='Card' if n == 1 else 'Card (Etched)',
                        extendedData=[dict(name='Number', value='1')]) for n in [1, 2]]))]:
                p = root / name; p.write_bytes(raw)
                captures[name] = dict(sourceURL=url, sha256=audit.digest(p))
            (root / 'capture.json').write_text(json.dumps(dict(upstreamBuild='test', captures=captures)))
            source = dict(id='source', object='card', name='Card', set='tst', set_name='Source', collector_number='1',
                lang='en', digital=False, games=['paper'], oversized=False, layout='normal', released_at='2020-01-01',
                finishes=['foil', 'etched'], tcgplayer_id=1, tcgplayer_etched_id=2)
            def vendor(n):
                return dict(id=f'tcgplayer-product-{n}', name='Card' if n == 1 else 'Card (Etched)', number='1',
                    game=dict(id='magic-the-gathering'), set=dict(id='10', name='Vendor'), external_ids=dict(tcgplayer=str(n)))
            entry = dict(code='TST', source=dict(source), vendor=vendor(1), etchedVendor=vendor(2))
            proof = dict(upstreamBuild='test', receipts=captures, cases=[entry])
            path = root / 'proof.json'
            with patch.object(magic, 'cards_for', return_value=[source]):
                path.write_text(json.dumps(proof)); magic.verify_direct_product_proof(path, root)
                entry['source'].pop('tcgplayer_etched_id')
                path.write_text(json.dumps(proof))
                with self.assertRaisesRegex(ValueError, 'source projection'):
                    magic.verify_direct_product_proof(path, root)
                entry['source']['tcgplayer_etched_id'] = 2
                entry['etchedVendor']['external_ids']['tcgplayer'] = '1'
                path.write_text(json.dumps(proof))
                with self.assertRaisesRegex(ValueError, 'vendor projection'):
                    magic.verify_direct_product_proof(path, root)

    def test_pokemon_subset_projection_requires_plain_holo_and_consistent_product(self):
        source = dict(id='exu-A', localId='A', name='Unown', set=dict(id='exu', name='Unown Collection', cardCount=dict(official=28)),
            variants=dict(holo=True, normal=False, reverse=False, firstEdition=False, wPromo=False),
            variants_detailed=[dict(type='holo', size='standard', thirdParty=dict(tcgplayer=1))])
        products = {1: dict(name='Unown (A)', extendedData=[dict(name='Number', value='A/28')])}
        projected = pokemon.project_case(source, products, 10, 'Vendor')
        self.assertEqual(projected['vendor']['external_ids'], dict(tcgplayer='1'))
        for key, value in [('stamp', ['winner']), ('foil', 'cosmos'), ('size', 'jumbo'), ('languages', ['ja'])]:
            changed = json.loads(json.dumps(source)); changed['variants_detailed'][0][key] = value
            with self.assertRaises(ValueError):
                pokemon.project_case(changed, products, 10, 'Vendor')
        changed = json.loads(json.dumps(source))
        changed['variants_detailed'][0]['pricing'] = dict(tcgplayer=dict(holofoil=dict(productId=2)))
        with self.assertRaisesRegex(ValueError, 'conflicting'):
            pokemon.project_case(changed, products, 10, 'Vendor')
        products[1]['extendedData'][0]['value'] = 'A/29'
        with self.assertRaisesRegex(ValueError, 'printed number'):
            pokemon.project_case(source, products, 10, 'Vendor')

    def test_yellow_a_projection_distinguishes_finish_products_and_preserves_letter_suffix(self):
        source = dict(id='xya-92a', localId='92a', name='Trainers’ Mail',
            variants=dict(normal=True, holo=False), set=dict(id='xya', name='Yellow A Alternate', cardCount=dict(official=6)),
            variants_detailed=[dict(type='normal', size='standard', variantId='generated')])
        products = [dict(productId=1, name="Trainers' Mail - 92a/108 (Non-Holo)", extendedData=[dict(name='Number', value='092a/108')]),
                    dict(productId=2, name="Trainers' Mail - 92a/108 (Holofoil)", extendedData=[dict(name='Number', value='92a/108')]),
                    dict(productId=3, name="Trainers' Mail - 92/108", extendedData=[dict(name='Number', value='92/108')])]
        prices = [dict(productId=1, subTypeName='Normal'), dict(productId=2, subTypeName='Holofoil'), dict(productId=3, subTypeName='Normal')]
        result = yellow.project_card(source, products, prices, 'Vendor')
        self.assertEqual([p['vendor']['external_ids']['tcgplayer'] for p in result['products']], ['1', '2'])
        self.assertEqual([p['finish'] for p in result['products']], ['normal', 'holo'])
        self.assertEqual(result['source']['variants']['holo'], False, 'Retain the upstream discrepancy')
        prices[1]['subTypeName'] = 'Normal'
        with self.assertRaisesRegex(ValueError, 'uniquely traceable'):
            yellow.project_card(source, products, prices, 'Vendor')


if __name__ == '__main__':
    unittest.main()
