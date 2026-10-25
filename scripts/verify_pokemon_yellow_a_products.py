#!/usr/bin/env python3
"""Verify complete Yellow A source/number/finish reconciliation offline.

Generated source flags are retained as evidence, not used as physical authority.
Vendor product names, collector identifiers and unique finish lanes establish
the reviewed candidate projection. Native tests separately exercise app policy.
"""
import argparse
import json
from pathlib import Path
import re
import unicodedata

import audit_set_pricing as core


def text(value):
    value = unicodedata.normalize('NFKD', value.casefold())
    return ' '.join(re.sub('[^a-z0-9]+', ' ', value).split())


def local_number(value):
    match = re.fullmatch(r'(\d+)([a-z])', value.strip().casefold())
    return str(int(match[1])) + match[2] if match else value.strip().casefold()


def project_card(source, products, prices, group_name):
    details = source.get('variants_detailed', [])
    if len(details) != 1 or details[0] != dict(type='normal', size='standard', variantId='generated'):
        raise ValueError('Expected retained generated source metadata')
    candidates = []
    for product in products:
        numbers = [f['value'] for f in product.get('extendedData', []) if f['name'] == 'Number']
        if len(numbers) != 1 or '/' not in numbers[0]:
            continue
        if local_number(numbers[0].split('/')[0]) != local_number(source['localId']):
            continue
        if not text(product['name']).startswith(text(source['name']) + ' '):
            continue
        lanes = [p['subTypeName'] for p in prices if p['productId'] == product['productId']]
        if len(lanes) != 1 or lanes[0] not in ['Normal', 'Holofoil']:
            raise ValueError('Candidate physical finish is ambiguous')
        vendor = dict(id='tcgplayer-product-' + str(product['productId']), name=product['name'], number=numbers[0],
            game=dict(id='pokemon'), set=dict(id='1938', name=group_name), external_ids=dict(tcgplayer=str(product['productId'])))
        candidates.append(dict(finish='normal' if lanes[0] == 'Normal' else 'holo', printing=lanes[0], vendor=vendor))
    if not candidates or len({p['finish'] for p in candidates}) != len(candidates):
        raise ValueError('Source printing is not uniquely traceable per finish')
    candidates.sort(key=lambda p: (p['finish'] != 'normal', p['vendor']['external_ids']['tcgplayer']))
    projected = {k: source[k] for k in ['id', 'localId', 'name', 'variants']}
    projected['set'] = {k: source['set'][k] for k in ['id', 'name', 'cardCount']}
    projected['variants_detailed'] = details
    return dict(source=projected, products=candidates)


def verify(path, root):
    proof, manifest = core.read(path), core.read(root / 'capture.json')
    if proof['upstreamBuild'] != manifest['upstreamBuild']:
        raise ValueError('Yellow A proof and captures use different builds')
    for name, receipt in proof['receipts'].items():
        if receipt != manifest['captures'].get(name) or core.capture(receipt['sourceURL'], root / name, manifest, False) is None:
            raise ValueError('Missing or changed Yellow A receipt')
    def retained(name, url):
        if name not in proof['receipts']:
            raise ValueError('Missing required Yellow A receipt')
        raw = core.capture(url, root / name, manifest, False)
        if raw is None:
            raise ValueError('Missing Yellow A source capture')
        return raw
    catalog = json.loads(retained('tcgdex-xya.json', 'https://api.tcgdex.net/v2/en/sets/xya'))
    if catalog['id'] != 'xya' or len(catalog['cards']) != 6 or len({c['id'] for c in catalog['cards']}) != 6:
        raise ValueError('Yellow A source inventory changed')
    products = core.validate_feed(retained('3-1938-products.json', 'https://tcgcsv.com/tcgplayer/3/1938/products'), 3, 1938, 'products')
    prices = core.validate_feed(retained('3-1938-prices.json', 'https://tcgcsv.com/tcgplayer/3/1938/prices'), 3, 1938, 'prices')
    groups = json.loads(retained('groups-3.json', 'https://tcgcsv.com/tcgplayer/3/groups'))['results']
    group = next(g['name'] for g in groups if g['groupId'] == 1938)
    expected = []
    for brief in catalog['cards']:
        source = json.loads(retained('tcgdex-card-' + brief['id'] + '.json', 'https://api.tcgdex.net/v2/en/cards/' + brief['id']))
        if source['id'] != brief['id'] or source['set']['id'] != 'xya' or source['localId'] != brief['localId']:
            raise ValueError('Yellow A card identity changed')
        expected.append(project_card(source, products, prices, group))
    if proof['cases'] != expected or sum(len(e['products']) for e in expected) != 8:
        raise ValueError('Yellow A fixture omits or changes a card/finish product')
    return len(expected), sum(len(e['products']) for e in expected)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture-dir', type=Path, required=True)
    parser.add_argument('--proof', type=Path, required=True)
    args = parser.parse_args()
    print('Verified Yellow A cards/products:', *verify(args.proof, args.capture_dir))
