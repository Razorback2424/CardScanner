#!/usr/bin/env python3
"""Attach reviewed original-release base market lanes; never allocate printings.

Scope is deliberately narrower than the catalog: original numbered OP/ST/EB
cards, exact ordinary release group, exact base product title, and one
supported physical finish. Reprints, alternate art, stamps and missing lanes
are held. TCGCSV prices are product-level aggregate USD, not condition SKUs.
All network bytes must already be retained with hash/size provenance.
"""
import argparse
from collections import Counter
import copy
import hashlib
import json
from pathlib import Path
import re
import unicodedata


def title(value):
    return ''.join(c for c in unicodedata.normalize('NFKD', value).casefold() if c.isalnum())


def base_title_matches(product_name, card_name, number):
    """Only the exact printed identifier may qualify an ordinary base title.

    Vendors disambiguate repeated character names with either (120) or
    (OP01-120). Never remove arbitrary parentheses: those distinguish artwork,
    distribution and other physical products, or belong to the character name.
    The caller independently validates the product's Number, category and group.
    """
    if not re.fullmatch(r'(OP|ST|EB)\d{2}-\d{3}', number):
        return False
    if title(product_name) == title(card_name):
        return True
    suffix = re.fullmatch(r'(.+?)\s+\(([^()]*)\)\s*', product_name)
    if suffix and suffix[2].upper() in {number, number.split('-')[1]}:
        return title(suffix[1]) == title(card_name)
    # Some vendor titles use " - OP14-34" instead of parentheses/padded digits.
    suffix = re.fullmatch(r'(.+?)\s+-\s+((?:OP|ST|EB)\d{2})-(\d{1,3})\s*', product_name, re.IGNORECASE)
    return bool(suffix and f'{suffix[2].upper()}-{int(suffix[3]):03d}' == number
                and title(suffix[1]) == title(card_name))


def reconcile(registry, products, source_root, price_root):
    result = copy.deepcopy(registry)
    cards = {c['id']: c for c in registry['canonicalCards']}
    specs = {p['productID']: p for p in products['products']}
    source_manifest = json.loads((source_root / 'captures.json').read_bytes())['captures']
    price_manifest = json.loads((price_root / 'captures.json').read_bytes())['captures']
    observations, decisions, groups = [], [], {}

    def retained(root, manifest, url):
        record = manifest[url]
        filename = record['rawFile']
        if Path(filename).name != filename: raise ValueError('Unsafe retained capture path')
        data = (root / filename).read_bytes()
        if len(data) != record['byteCount'] or hashlib.sha256(data).hexdigest() != record['payloadSHA256']:
            raise ValueError('Retained market bytes changed')
        document = json.loads(data)
        if document.get('success') is not True or document.get('errors'):
            raise ValueError('Failed source response')
        if document.get('totalItems', len(document['results'])) != len(document['results']):
            raise ValueError('Incomplete source response')
        return document['results'], record

    for printing in result['printings']:
        spec = specs.get(printing.get('releaseID'))
        if not spec: continue
        card = cards[printing['canonicalCardID']]
        number = card['printedNumber']
        if printing['status'] != 'verified' or printing.get('treatment') != 'Standard artwork' \
            or printing.get('stamp') or printing.get('distributionLabel') \
            or len(printing['supportedVariantIDs']) != 1 \
            or not re.fullmatch(r'(OP|ST|EB)\d{2}', spec['prefix']) \
            or not number.startswith(spec['prefix'] + '-'):
            continue
        group = int(spec['retailerGroupID'])
        product_url = f'https://tcgcsv.com/tcgplayer/68/{group}/products'
        price_url = f'https://tcgcsv.com/tcgplayer/68/{group}/prices'
        if price_url not in price_manifest: raise ValueError('Missing reviewed group price capture')
        if group not in groups:
            source, source_capture = retained(source_root, source_manifest, product_url)
            prices, price_capture = retained(price_root, price_manifest, price_url)
            groups[group] = source, source_capture, prices, price_capture
        source, source_capture, prices, price_capture = groups[group]
        matches = [p for p in source if p['categoryId'] == 68 and p['groupId'] == group
                   and [f['value'] for f in p.get('extendedData', []) if f['name'] == 'Number'] == [number]
                   and base_title_matches(p['name'], card['name'], number)]
        if len(matches) != 1:
            decisions.append({'printingID': printing['id'], 'number': number, 'status': 'held',
                              'reason': 'ambiguous-base-title' if matches else 'no-exact-base-title'})
            continue
        product = matches[0]
        variant = printing['supportedVariantIDs'][0]
        lane = {'normal': 'Normal', 'foil': 'Foil'}.get(variant)
        lanes = [p for p in prices if p['productId'] == product['productId'] and p['subTypeName'] == lane]
        if lane is None or len(lanes) != 1:
            decisions.append({'printingID': printing['id'], 'number': number, 'status': 'held',
                              'reason': 'duplicate-exact-finish-lane' if len(lanes) > 1 else 'missing-exact-finish-lane'})
            continue
        pid = str(product['productId'])
        oid = f'base-market:{printing["id"]}:{pid}:{variant}'
        qualifiers = {'groupID': str(group), 'productName': product['name'], 'finish': lane}
        fields = {'number': number, 'marketProductID': pid, 'marketVariantID': lane,
                  'finishVariantID': variant, 'market': 'us', 'currency': 'USD', 'condition': 'aggregate',
                  'treatment': printing['treatment'], 'sourcePricePayloadSHA256': price_capture['payloadSHA256'],
                  **{'qualifier:' + k: v for k, v in qualifiers.items()}}
        observations.append({'id': oid, 'kind': 'market', 'alias': {'provider': 'tcgplayer', 'sourceID': pid},
            'sourceURL': product_url, 'observedAt': source_capture['observedAt'], 'language': 'en',
            'payloadSHA256': source_capture['payloadSHA256'], 'productEvidence': [printing['releaseID']],
            'printedEvidence': fields})
        mapping = {'printingID': printing['id'], 'provider': 'tcgplayer', 'productID': pid,
            'providerVariantID': lane, 'variantID': variant, 'market': 'us', 'currency': 'USD',
            'condition': 'aggregate', 'qualifiers': qualifiers, 'status': 'exact',
            'review': {'reference': 'english-stress/base-market-review.json#' + printing['id'],
                      'evidence': [{'kind': k, 'observationID': oid, 'detail':
                          'Reviewed original standard-art release and unqualified TCGplayer title/number/group; exact supported finish lane. Aggregate market only, no condition SKU.'}
                          for k in ['printedIdentity', 'marketIdentity']]}}
        if printing['marketMappings'] and printing['marketMappings'] != [mapping]:
            raise ValueError('Existing market mapping changed; explicit correction required')
        printing['marketMappings'] = [mapping]
        decisions.append({'printingID': printing['id'], 'number': number, 'productID': pid,
                          'groupID': group, 'lane': lane, 'status': 'exact'})
    inventories = [{'provider': 'tcgplayer', 'snapshotID': 'base-market-review-2026-10-04',
                    'paginationComplete': False, 'observationIDs': sorted(o['id'] for o in observations)}]
    printing_by_id = {p['id']: p for p in result['printings']}
    summaries = {}
    for decision in decisions:
        release = printing_by_id[decision['printingID']]['releaseID']
        summary = summaries.setdefault(release, {'exact': 0, 'held': 0, 'reasons': Counter()})
        summary[decision['status']] += 1
        if decision['status'] == 'held':
            summary['reasons'][decision['reason']] += 1
    return result, observations, inventories, {'schemaVersion': 1,
        'scope': 'original numbered ordinary base only; no reprints/promos/parallels/condition SKUs',
        'physicalCoverageComplete': False, 'decisions': decisions,
        'sets': dict(sorted(summaries.items())),
        'heldReasons': dict(sorted(Counter(d['reason'] for d in decisions if d['status'] == 'held').items()))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--price-root', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    values = reconcile(json.loads((args.corpus / 'registry.json').read_bytes()),
        json.loads((args.corpus / 'products.json').read_bytes()), args.source_root, args.price_root)
    args.output_dir.mkdir(parents=True, exist_ok=False)
    for filename, value in zip(['registry.json', 'base-market-observations.json',
                                'base-market-inventories.json', 'base-market-review.json'], values):
        (args.output_dir / filename).write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')
    print(f'Reviewed {len(values[1])} exact base mappings; no printing IDs allocated')


if __name__ == '__main__': main()
