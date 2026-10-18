#!/usr/bin/env python3
"""Build exact read-only Browse joins; never allocate physical UUIDs or prices."""
import argparse
import collections
import hashlib
import json
from pathlib import Path

from build_lorcana_discovery_catalog import name_key


def build(discovery_bytes, physical, source, groups, captures):
    discovery = json.loads(discovery_bytes)
    reviewed = {a['id'] for p in physical['physicalPrintings'] for a in p.get('sourceAliases', [])}
    raw = {f"lorcanajson:en:{c['id']}": c for c in source['cards']}
    products = []
    lanes = collections.defaultdict(list)
    receipts = []
    group_names = collections.defaultdict(list)
    for group in groups['results']:
        gid = group['groupId']
        group_names[name_key(group['name'])].append(gid)
        bodies = []
        for resource in ['products', 'prices']:
            body = (captures / f'71-{gid}-{resource}.json').read_bytes()
            batch = json.loads(body)
            if not batch['success'] or batch['errors'] or batch.get('totalItems', len(batch['results'])) != len(batch['results']):
                raise ValueError('Incomplete marketplace response')
            bodies.append(hashlib.sha256(body).hexdigest())
            if resource == 'products':
                if any(p['categoryId'] != 71 or p['groupId'] != gid for p in batch['results']):
                    raise ValueError('Wrong product group/category')
                products.extend(batch['results'])
            else:
                for row in batch['results']:
                    lanes[(gid, row['productId'])].append(row)
        receipts.append(dict(groupID=gid, productsSHA256=bodies[0], pricesSHA256=bodies[1]))
    by_id = collections.defaultdict(list)
    for p in products:
        by_id[p['productId']].append(p)
    entries, held = [], []
    counts = collections.defaultdict(collections.Counter)
    for card in discovery['cards']:
        if card['id'] in reviewed:
            continue
        original = raw.get(card['id'])
        if original and (original['fullIdentifier'] != card['printedIdentifier'] or original['fullName'] != card['name']
                         or original['foilTypes'] != card['foilTypes']):
            raise ValueError('Source identity/finish changed since discovery capture')
        product_id = (original or {}).get('externalLinks', {}).get('tcgPlayerId')
        if card['id'].startswith('tcgcsv:71:'):
            product_id = int(card['id'].split(':')[-1])
        candidates = by_id.get(int(product_id), []) if product_id else [p for p in products
            if p['groupId'] in group_names[name_key(card['setName'])]]
        footer = card['footer']
        numbers = {footer['collectorNumber'], footer['collectorNumber'] + '/' + footer['denominator']} if footer else {None}
        expected_names = {name_key(card['name']), name_key(card['name'] + ' (' + card['rarity'] + ')')}
        matches = []
        for p in candidates:
            number = [f['value'] for f in p['extendedData'] if f['name'] == 'Number']
            if name_key(p['name']) not in expected_names or len(number) > 1:
                continue
            if (number[0] if number else None) not in numbers:
                continue
            if not footer and not card.get('unnumberedSetMarker'):
                continue
            matches.append(p)
        if len(matches) != 1:
            held.append(dict(sourceID=card['id'], set=card['setCode'], reason='No unique exact product/title/number'))
            continue
        p = matches[0]
        rows = lanes[(p['groupId'], p['productId'])]
        if len({r['subTypeName'] for r in rows}) != len(rows):
            raise ValueError('Duplicate product finish lanes')
        available = {r['subTypeName']: r for r in rows}
        finishes = []
        if 'None' in card['foilTypes'] and 'Normal' in available:
            finishes.append(('normal', 'Normal'))
        foils = [f for f in card['foilTypes'] if f != 'None']
        foil_lanes = [lane for lane in ['Cold Foil', 'Holofoil'] if lane in available]
        if len(foils) == 1 and len(foil_lanes) == 1:
            finishes.append(('foil', foil_lanes[0]))
        for finish, lane in finishes:
            mapping = dict(finish=finish, groupID=p['groupId'], productID=p['productId'], productName=p['name'],
                productNumber=next((f['value'] for f in p['extendedData'] if f['name'] == 'Number'), ''),
                providerVariantID=lane, market='us', currency='USD', condition='aggregate',
                evidenceReferences=[card['imageURL'], f"https://tcgcsv.com/tcgplayer/71/{p['groupId']}/products"])
            entries.append(dict(sourceID=card['id'], mapping=mapping))
            counts[card['setCode']]['lanes'] += 1
            counts[card['setCode']]['withMarketPrice' if available[lane].get('marketPrice') is not None else 'noMarketPrice'] += 1
    output = dict(schemaVersion=1, discoverySHA256=hashlib.sha256(discovery_bytes).hexdigest(), entries=entries)
    report = dict(schemaVersion=1, sources=receipts, bySet={k: dict(v) for k,v in sorted(counts.items())}, held=held,
                  sourceSHA256=hashlib.sha256(json.dumps(source, sort_keys=True).encode()).hexdigest())
    return output, report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['discovery', 'physical', 'source', 'groups', 'captures', 'output', 'report']:
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    output, report = build(args.discovery.read_bytes(), json.loads(args.physical.read_bytes()),
        json.loads(args.source.read_bytes()), json.loads(args.groups.read_bytes()), args.captures)
    args.output.write_text(json.dumps(output, sort_keys=True, separators=(',', ':')) + '\n')
    args.report.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(json.dumps(report['bySet'], indent=2))


if __name__ == '__main__':
    main()
