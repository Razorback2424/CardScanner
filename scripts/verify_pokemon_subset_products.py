#!/usr/bin/env python3
"""Verify the reviewed Unown/Futsal graded product fixture offline.

Checks complete source membership, per-object product IDs and physical scope.
It neither changes app mappings nor establishes live graded availability.
"""
import argparse
import json
from pathlib import Path
from urllib.parse import quote

import audit_set_pricing as core


def project_case(source, products, group, group_name):
    details = source.get('variants_detailed', [])
    if (len(details) != 1 or details[0].get('type') != 'holo' or details[0].get('size') != 'standard'
            or details[0].get('stamp') or details[0].get('foil')
            or details[0].get('subtype') or details[0].get('languages') not in [None, ['en']]):
        raise ValueError('Subset source is not a single plain standard English holo')
    flags = source['variants']
    if flags.get('holo') is not True or any(flags.get(k) for k in ['normal', 'reverse', 'firstEdition', 'wPromo']):
        raise ValueError('Subset source has contradictory physical flags')
    product_id = details[0]['thirdParty']['tcgplayer']
    price_block = (details[0].get('pricing') or {}).get('tcgplayer') or {}
    ids = {p['productId'] for p in price_block.values() if isinstance(p, dict) and p.get('productId')}
    if type(product_id) is not int or product_id <= 0 or ids - {product_id}:
        raise ValueError('Subset product identity is conflicting')
    product = products[product_id]
    number = next(f['value'] for f in product['extendedData'] if f['name'] == 'Number')
    local, total = number.split('/')
    expected = '?' if source['id'] == 'exu-%3F' else source['localId']
    normalize = lambda value: str(int(value)) if value.isdigit() else value.casefold()
    if normalize(local) != normalize(expected) or int(total) != source['set']['cardCount']['official']:
        raise ValueError('Subset printed number disagrees with the source')
    projected = {k: source[k] for k in ['id', 'localId', 'name', 'variants']}
    projected['set'] = {k: source['set'][k] for k in ['id', 'name', 'cardCount']}
    projected['variants_detailed'] = [{k: v[k] for k in ['type', 'size', 'foil', 'stamp', 'languages', 'thirdParty', 'variantId'] if k in v}
        for v in details]
    vendor = dict(id='tcgplayer-product-' + str(product_id), name=product['name'], number=number,
        game=dict(id='pokemon'), set=dict(id=str(group), name=group_name), external_ids=dict(tcgplayer=str(product_id)))
    return dict(source=projected, vendor=vendor)


def verify(path, root):
    proof, manifest = core.read(path), core.read(root / 'capture.json')
    if proof['upstreamBuild'] != manifest['upstreamBuild']:
        raise ValueError('Subset proof and vendor capture use different builds')
    for name, receipt in proof['receipts'].items():
        if receipt != manifest['captures'].get(name) or core.capture(receipt['sourceURL'], root / name, manifest, False) is None:
            raise ValueError('Missing or changed subset source receipt')
    def retained(name, url):
        if name not in proof['receipts']:
            raise ValueError('Subset fixture omits a required source receipt')
        raw = core.capture(url, root / name, manifest, False)
        if raw is None:
            raise ValueError('Required subset source is missing')
        return raw
    groups = {g['groupId']: g['name'] for g in json.loads(retained('groups-3.json', 'https://tcgcsv.com/tcgplayer/3/groups'))['results']}
    expected = []
    for code, group, count in [('exu', 1398, 28), ('fut2020', 2374, 5)]:
        catalog = json.loads(retained(f'tcgdex-{code}.json', f'https://api.tcgdex.net/v2/en/sets/{code}'))
        if catalog['id'] != code or len(catalog['cards']) != count or len({c['id'] for c in catalog['cards']}) != count:
            raise ValueError('Subset source membership changed')
        products = {p['productId']: p for p in core.validate_feed(retained(f'3-{group}-products.json',
            f'https://tcgcsv.com/tcgplayer/3/{group}/products'), 3, group, 'products')}
        for brief in catalog['cards']:
            encoded = quote(brief['id'], safe='-')
            source = json.loads(retained('tcgdex-card-' + encoded + '.json', 'https://api.tcgdex.net/v2/en/cards/' + encoded))
            if source['id'] != brief['id'] or source['localId'] != brief['localId'] or source['set']['id'] != code:
                raise ValueError('Subset card identity changed')
            expected.append(project_case(source, products, group, groups[group]))
    if proof['cases'] != expected:
        raise ValueError('Subset fixture has missing, extra or changed records')
    return len(expected)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--capture-dir', type=Path, required=True)
    parser.add_argument('--proof', type=Path, required=True)
    args = parser.parse_args()
    print('Verified', verify(args.proof, args.capture_dir), 'complete reviewed subset identities')
