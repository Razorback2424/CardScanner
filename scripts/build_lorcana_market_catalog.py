#!/usr/bin/env python3
"""Promote bounded English ordinary printings using explicit offline source joins.

No fuzzy/provider fallback or price-column finish inference. UUID assignments are
retained independently in a ledger; ambiguous families and market siblings stay
discovery-only. Existing reviewed Hades identities are retained exactly.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import re
import uuid

from build_lorcana_discovery_catalog import name_key

REVIEW = 'docs/research/lorcana-normal-pricing-rollout.md'
FINISH = 'https://disneyparksblog.com/products/getting-started-with-disney-lorcana-trading-card-game/'


def build(discovery, sources, baseline, assignments):
    source_bytes = discovery.read_bytes()
    payload = json.loads(source_bytes)
    base = json.loads(baseline.read_bytes())
    ledger = dict(assignments)
    def allocate(key):
        if key not in ledger:
            ledger[key] = str(uuid.uuid4())
        return ledger[key]
    rows = payload['cards']
    by_footer = collections.defaultdict(list)
    def footer_key(f):
        return ':'.join(f[k] for k in ['language', 'printedSetMarker', 'collectorNumber', 'denominator'])
    for row in rows:
        if row['footer']:
            by_footer[footer_key(row['footer'])].append(row)
    catalogs = {}
    receipts = []
    for group in json.loads((sources / 'groups-selected.json').read_bytes()):
        product_bytes = (sources / f"{group['groupID']}-products.json").read_bytes()
        price_bytes = (sources / f"{group['groupID']}-prices.json").read_bytes()
        products, prices = json.loads(product_bytes), json.loads(price_bytes)
        for batch in [products, prices]:
            if not batch['success'] or batch['errors'] or batch.get('totalItems', len(batch['results'])) != len(batch['results']):
                raise ValueError('Incomplete or failed feed')
        for p in products['results']:
            if p['categoryId'] != 71 or p['groupId'] != group['groupID']:
                raise ValueError('Cross-category/group product')
        catalogs[group['code']] = (group, products['results'], prices['results'], hashlib.sha256(product_bytes).hexdigest())
        receipts.append(dict(**group, productsSHA256=hashlib.sha256(product_bytes).hexdigest(), pricesSHA256=hashlib.sha256(price_bytes).hexdigest()))
    manifest = dict(base)
    manifest['discoverySHA256'] = hashlib.sha256(source_bytes).hexdigest()
    manifest['canonicalCards'] = list(base['canonicalCards'])
    manifest['physicalPrintings'] = list(base['physicalPrintings'])
    manifest['printFamilies'] = list(base['printFamilies'])
    manifest['universes'] = list(base['universes'])
    existing = {footer_key(f['footer']) for f in base['printFamilies']}
    decisions = []
    for row in sorted(rows, key=lambda r: r['id']):
        f = row['footer']
        if not f or row['setCode'] not in catalogs or not row['id'].startswith('lorcanajson:'):
            continue
        key = footer_key(f)
        if key in existing:
            continue
        if not re.fullmatch(r'[0-9]+', f['collectorNumber']) or f['denominator'] != '204' or not 1 <= int(f['collectorNumber']) <= 204:
            continue
        reason = None
        if len(by_footer[key]) != 1:
            reason = 'Multiple source physical candidates'
        elif set(row['foilTypes']) != {'None', 'Silver'}:
            reason = 'Outside reviewed ordinary normal/silver-foil policy'
        group, products, prices, product_hash = catalogs[row['setCode']]
        numbers = {f['collectorNumber'], f['collectorNumber'] + '/204'}
        matches = []
        siblings = []
        for p in products:
            fields = [field['value'] for field in p['extendedData'] if field['name'] == 'Number']
            if len(fields) != 1 or fields[0] not in numbers or re.search(r'\((?:JP|CS) Exclusive\)', p['name']):
                continue
            if name_key(re.sub(r' \([^)]*\)$', '', p['name'])) == name_key(row['name']):
                siblings.append(p)
            if name_key(p['name']) == name_key(row['name']):
                matches.append(p)
        if len(matches) != 1 or len(siblings) != 1:
            reason = reason or 'Missing/ambiguous exact title-number join or qualified sibling'
        if reason:
            decisions.append(dict(sourceID=row['id'], status='held', reason=reason));continue
        product = matches[0]
        lanes = [p['subTypeName'] for p in prices if p['productId'] == product['productId']]
        if sorted(lanes) != ['Cold Foil', 'Normal']:
            decisions.append(dict(sourceID=row['id'], status='held', reason='Missing/duplicate/unexpected market lanes'));continue
        canonical, artwork, printing = [allocate(key + ':' + kind) for kind in ['canonical', 'artwork', 'printing']]
        aliases = [dict(provider='lorcanajson', id=row['id']), dict(provider='tcgcsv', id=f"tcgcsv:71:{product['productId']}")]
        image = row['imageURL']
        refs = [REVIEW, image]
        manifest['printFamilies'].append(dict(footer=f, providerSetCode=row['sourceSetCode'], name=row['name'], version=None,
            rarity=row['rarity'], layout=row['layout'], sourceAliases=aliases, footerEvidenceReference=image))
        manifest['canonicalCards'].append(dict(id=canonical, name=row['name'], version=None, relationshipEvidenceReferences=refs))
        manifest['physicalPrintings'].append(dict(id=printing, identity=dict(canonicalCardID=canonical, footer=f, artworkID=artwork,
            distributionID='ordinary-expansion-' + row['setCode'], size='standard', layout=row['layout']),
            providerSetCode=row['sourceSetCode'], setName=row['setName'], artworkLabel='Original artwork',
            distributionLabel='Ordinary expansion', imageURL=image, status='verified',
            identityEvidence=[dict(kind=k, reference=image if k in ['printedFooter','artwork','stamp'] else REVIEW) for k in ['printedFooter','artwork','stamp','size','distribution']],
            finishes=[dict(finish=k, evidenceReferences=[REVIEW, FINISH]) for k in ['normal','foil']], finishUniverseEvidenceReference=REVIEW,
            sourceAliases=aliases, marketMappings=[dict(finish=k, groupID=group['groupID'], productID=product['productId'],
                productName=product['name'], productNumber=next(x['value'] for x in product['extendedData'] if x['name']=='Number'),
                providerVariantID=lane, market='us', currency='USD', condition='aggregate',
                evidenceReferences=[REVIEW, f"https://tcgcsv.com/tcgplayer/71/{group['groupID']}/products", 'sha256:'+product_hash])
                for k,lane in [('normal','Normal'),('foil','Cold Foil')]]))
        manifest['universes'].append(dict(footer=f, printingIDs=[printing], isComplete=True, evidenceReference=REVIEW))
        decisions.append(dict(sourceID=row['id'], printingID=printing, productID=product['productId'], groupID=group['groupID'], status='mapped'))
    report = dict(schemaVersion=1, discoverySHA256=hashlib.sha256(source_bytes).hexdigest(), groups=receipts,
        mappedPrintingCount=sum(bool(p.get('marketMappings')) for p in manifest['physicalPrintings']),
        mappingCount=sum(len(p.get('marketMappings',[])) for p in manifest['physicalPrintings']), decisions=decisions)
    return manifest, ledger, report


def validate_previous(current, previous):
    old = {p['id']: p for p in previous['physicalPrintings']}
    new = {p['id']: p for p in current['physicalPrintings']}
    if not old.keys() <= new.keys():
        raise ValueError('Existing physical IDs cannot disappear; explicit withdrawal/held transition required')
    for key, p in old.items():
        if p['identity'] != new[key]['identity'] or p['imageURL'] != new[key]['imageURL']:
            raise ValueError('Physical identity/artwork changed; explicit supersession review required')
    if len(set(p['id'] for p in current['physicalPrintings'])) != len(new):
        raise ValueError('Duplicate allocated physical UUID')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for name in ['discovery','sources','baseline','assignments','output','report']:
        parser.add_argument('--'+name, required=True, type=Path)
    args=parser.parse_args()
    assignments=json.loads(args.assignments.read_bytes()) if args.assignments.exists() else {}
    manifest, ledger, report=build(args.discovery,args.sources,args.baseline,assignments)
    if args.output.exists():
        validate_previous(manifest, json.loads(args.output.read_bytes()))
    for path,value in [(args.output,manifest),(args.assignments,ledger),(args.report,report)]:
        path.write_text(json.dumps(value,sort_keys=True,separators=(',',':'))+'\n')
    print(report['mappedPrintingCount'], 'mapped printings;',report['mappingCount'],'finish mappings')


if __name__ == '__main__':
    main()
