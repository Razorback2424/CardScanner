#!/usr/bin/env python3
"""Adjudicate known-group Magic cases with retained card-level product IDs.

No catalog, alias, signature or pricing authority is modified. Collector-number
comparisons are diagnostics; production matching is verified separately by
native tests before an alias can be admitted.
"""
import argparse
import collections
import csv
import json
from pathlib import Path
from urllib.parse import urlencode, urlsplit, parse_qs
from urllib.request import Request, urlopen
from urllib.error import HTTPError

import audit_set_pricing as core


def cards_for(code, root, manifest, fetch):
    query = f'set:{code.lower()} lang:en game:paper'
    url = 'https://api.scryfall.com/cards/search?' + urlencode(dict(q=query, unique='prints', order='set'))
    result, seen, total = [], set(), None
    for page in range(1, 101):
        raw = core.capture(url, root / f'magic-{code.lower()}-cards-{page}.json', manifest, fetch,
            allow_not_found=True, delay=.75)
        if raw is None:
            return None
        document = json.loads(raw)
        if document.get('object') == 'error' and document.get('status') == 404:
            if result:
                raise ValueError('Later page unexpectedly empty')
            return []
        if document.get('object') != 'list' or type(document.get('has_more')) is not bool:
            raise ValueError('Invalid Scryfall card list')
        if total is None:
            total = document['total_cards']
            if type(total) is not int or total < 0:
                raise ValueError('Invalid card inventory total')
        if document['total_cards'] != total:
            raise ValueError('Changing card inventory during pagination')
        for card in document['data']:
            if card['set'].casefold() != code.casefold() or card['lang'] != 'en' or 'paper' not in card['games']:
                raise ValueError('Search returned wrong set/language/game')
            if card['id'] in seen:
                raise ValueError('Repeated card across pages')
            seen.add(card['id']); result.append(card)
        if not document['has_more']:
            if len(result) != total:
                raise ValueError('Incomplete card inventory')
            return result
        url = document['next_page']
        parsed = urlsplit(url)
        parameters = parse_qs(parsed.query)
        if (parsed.scheme != 'https' or parsed.hostname != 'api.scryfall.com' or parsed.path != '/cards/search'
                or parsed.username or parsed.password or parsed.port or parsed.fragment
                or parameters.get('q') != [query] or parameters.get('unique') != ['prints']
                or parameters.get('order') != ['set'] or parameters.get('page') != [str(page + 1)]):
            raise ValueError('Unexpected card pagination URL')
    raise ValueError('Card inventory exceeds 100-page audit bound')


def number_parts(value):
    def normal(part):
        part = part.strip()
        try:
            return str(int(part))
        except ValueError:
            return part.casefold()
    if '//' in value:
        return '//'.join(normal(p) for p in value.split('//')), None
    parts = value.split('/', 1)
    return normal(parts[0]), normal(parts[1]) if len(parts) == 2 else None


def numbers_agree(left, right):
    a, b = number_parts(left), number_parts(right)
    return bool(a[0]) and a[0] == b[0] and (a[1] is None or b[1] is None or a[1] == b[1])


def verify_pinned_proof(path, root):
    """Require exact source projections, including sealed/numberless products.

    A passing native fixture must not silently omit other group members that
    could affect uniqueness. This verifies provenance, not matcher behavior.
    """
    proof, manifest = core.read(path), core.read(root / 'capture.json')
    if proof['upstreamBuild'] != manifest['upstreamBuild']:
        raise ValueError('Proof and capture have different vendor builds')
    for name, receipt in proof['receipts'].items():
        if receipt != manifest['captures'].get(name):
            raise ValueError('Proof receipt differs from retained capture')
        if core.capture(receipt['sourceURL'], root / name, manifest, False) is None:
            raise ValueError('Proof capture is missing')
    for entry in proof['cases']:
        cards = cards_for(entry['code'], root, manifest, False)
        group = int(entry['groupID'])
        raw = core.capture(f'https://tcgcsv.com/tcgplayer/1/{group}/products',
            root / f'1-{group}-products.json', manifest, False)
        if cards is None or raw is None:
            raise ValueError('Proof source inventory is missing')
        products = core.validate_feed(raw, 1, group, 'products')
        expected_cards = [dict(name=c['name'], number=c['collector_number'], productID=str(c['tcgplayer_id'])) for c in cards]
        expected_products = [dict(name=p['name'], number=next((f['value'] for f in p.get('extendedData', [])
            if f['name'] == 'Number'), ''), productID=str(p['productId'])) for p in products]
        if entry['cards'] != expected_cards or entry['products'] != expected_products:
            raise ValueError(f"Incomplete or changed proof projection: {entry['code']}")


def verify_direct_product_proof(path, root):
    """Check each direct-route sample and both etched/ordinary product facts."""
    proof, manifest = core.read(path), core.read(root / 'capture.json')
    if proof['upstreamBuild'] != manifest['upstreamBuild']:
        raise ValueError('Direct proof and capture use different vendor builds')
    for name, receipt in proof['receipts'].items():
        if receipt != manifest['captures'].get(name) or core.capture(receipt['sourceURL'], root / name, manifest, False) is None:
            raise ValueError('Direct proof receipt is missing or changed')
    group_bytes = core.capture('https://tcgcsv.com/tcgplayer/1/groups', root / 'groups-1.json', manifest, False)
    if group_bytes is None:
        raise ValueError('Direct proof requires the retained group directory')
    groups = {str(g['groupId']): g for g in json.loads(group_bytes)['results']}
    sources, products = {}, {}
    fields = ['id', 'object', 'name', 'set', 'set_name', 'collector_number', 'lang', 'digital',
        'games', 'oversized', 'layout', 'released_at', 'finishes']
    for entry in proof['cases'] + proof.get('etchedCases', []):
        code = entry['code']
        if code not in sources:
            cards = cards_for(code, root, manifest, False)
            if cards is None:
                raise ValueError('Direct proof source inventory is missing')
            sources[code] = {c['id']: c for c in cards}
        card = sources[code][entry['source']['id']]
        expected = {key: card[key] for key in fields}
        for key in ['tcgplayer_id', 'tcgplayer_etched_id']:
            if card.get(key) is not None:
                expected[key] = card[key]
        if card.get('card_faces'):
            expected['card_faces'] = [dict(name=face['name']) for face in card['card_faces']]
        if entry['source'] != expected:
            raise ValueError('Direct proof source projection changed')
        for lane, source_key in [('vendor', 'tcgplayer_id'), ('etchedVendor', 'tcgplayer_etched_id')]:
            if lane not in entry:
                continue
            vendor = entry[lane]
            group = int(vendor['set']['id'])
            if group not in products:
                raw = core.capture(f'https://tcgcsv.com/tcgplayer/1/{group}/products', root / f'1-{group}-products.json', manifest, False)
                if raw is None:
                    raise ValueError('Direct proof vendor inventory is missing')
                products[group] = {p['productId']: p for p in core.validate_feed(raw, 1, group, 'products')}
            product = products[group][card[source_key]]
            expected_vendor = dict(id='tcgplayer-product-' + str(product['productId']), name=product['name'],
                number=next((f['value'] for f in product.get('extendedData', []) if f['name'] == 'Number'), ''),
                game=dict(id='magic-the-gathering'), set=dict(id=str(group), name=groups[str(group)]['name']),
                external_ids=dict(tcgplayer=str(product['productId'])))
            if vendor != expected_vendor:
                raise ValueError('Direct proof vendor projection changed')


def audit(queue, root, output, fetch=False):
    output.mkdir(parents=True, exist_ok=True)
    manifest = core.read(root / 'capture.json')
    upstream = manifest['upstreamBuild']
    if fetch:
        request = Request('https://tcgcsv.com/last-updated.txt', headers={'User-Agent': 'TradingCardScanner-SetAudit/1.0'})
        with urlopen(request, timeout=20) as response:
            if response.read(1024).decode().strip() != upstream:
                raise ValueError('Use a new capture directory for the new vendor daily build')
    with queue.open() as stream:
        requested = [r for r in csv.DictReader(stream) if r['game'] == 'magic' and r['sourceGroupID']]
    group_bytes = core.capture('https://tcgcsv.com/tcgplayer/1/groups', root / 'groups-1.json', manifest, False)
    if group_bytes is None:
        raise ValueError('Retained vendor group inventory is required')
    group_document = json.loads(group_bytes)
    if group_document.get('success') is not True or group_document.get('errors') != []:
        raise ValueError('Failed vendor group inventory')
    groups = {str(g['groupId']): g for g in group_document['results']}
    if len(groups) != len(group_document['results']):
        raise ValueError('Duplicate vendor groups')
    products_by_group, cases, details = {}, [], []
    for row in requested:
        code, group = row['catalogID'], int(row['sourceGroupID'])
        if group not in products_by_group:
            raw = core.capture(f'https://tcgcsv.com/tcgplayer/1/{group}/products',
                root / f'1-{group}-products.json', manifest, fetch)
            products_by_group[group] = None if raw is None else core.validate_feed(raw, 1, group, 'products')
        products = products_by_group[group]
        try:
            cards = cards_for(code, root, manifest, fetch)
        except HTTPError as error:
            if error.code != 429:
                raise
            print(f'MAGIC_REVIEW_RATE_LIMIT: next={code} retryAfter={error.headers.get("Retry-After", "unspecified")}', flush=True)
            cases.append(dict(catalogID=code, catalogName=row['catalogName'], status='rateLimited',
                sourceGroupID=group, retryAfter=error.headers.get('Retry-After', '')))
            break
        case = dict(catalogID=code, catalogName=row['catalogName'], sourceGroupID=group,
            vendorName=groups[str(group)]['name'], englishPaperPrints=len(cards) if cards is not None else None,
            productIdentityMatched=0, noProductID=0, productOutsideExpectedGroup=0, numberConcordant=0,
            numberMissing=0, numberDifferent=0, vendorNumberDuplicates=0)
        if cards is None or products is None:
            case['status'] = 'captureMissing'
            cases.append(case); continue
        if not cards:
            case['status'] = 'noEnglishPaperCards'
            cases.append(case); continue
        index = {p['productId']: p for p in products}
        number_count = collections.Counter(f['value'] for p in products for f in p.get('extendedData', []) if f['name'] == 'Number')
        for card in cards:
            product_id = card.get('tcgplayer_id')
            product = index.get(product_id)
            numbers = [f['value'] for f in product.get('extendedData', []) if f['name'] == 'Number'] if product else []
            if not product_id:
                status = 'noProductID'; case[status] += 1
            elif product is None:
                status = 'productOutsideExpectedGroup'; case[status] += 1
            else:
                case['productIdentityMatched'] += 1
                if len(numbers) != 1 or not numbers[0].strip():
                    status = 'numberMissing'
                elif not numbers_agree(card['collector_number'], numbers[0]):
                    status = 'numberDifferent'
                else:
                    status = 'numberConcordant'
                case[status] += 1
                if numbers and number_count[numbers[0]] > 1:
                    case['vendorNumberDuplicates'] += 1
            details.append(dict(catalogID=code, scryfallID=card['id'], name=card['name'],
                collectorNumber=card['collector_number'], productID=product_id or '',
                sourceGroupID=group, vendorName=product['name'] if product else '',
                vendorNumbers=' | '.join(numbers), status=status))
        case['status'] = 'cardIdentityCaptured'
        cases.append(case)
        print(f"MAGIC_REVIEW: {code} {len(cards)} cards, {case['productIdentityMatched']} product IDs matched, "
              f"{case['numberConcordant']} concordant numbers", flush=True)
    if fetch:
        request = Request('https://tcgcsv.com/last-updated.txt', headers={'User-Agent': 'TradingCardScanner-SetAudit/1.0'})
        with urlopen(request, timeout=20) as response:
            if response.read(1024).decode().strip() != upstream:
                raise ValueError('Vendor daily build changed during review')
    report = dict(schemaVersion=1, upstreamBuild=upstream, queueSHA256=core.digest(queue),
        captureManifestSHA256=core.digest(root / 'capture.json'),
        boundary='Card product membership and number diagnostics; not graded availability or automatic physical admission.',
        cases=cases)
    (output / 'magic-product-review.json').write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    fields = ['catalogID', 'scryfallID', 'name', 'collectorNumber', 'productID', 'sourceGroupID', 'vendorName', 'vendorNumbers', 'status']
    with (output / 'magic-product-review-cards.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields); writer.writeheader(); writer.writerows(details)
    return report


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--queue', type=Path, required=True)
    parser.add_argument('--capture-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--fetch', action='store_true')
    parser.add_argument('--verify-pinned-proof', type=Path, help='Check the native Magic proof against complete retained source inventories')
    parser.add_argument('--verify-direct-proof', type=Path, help='Check direct product and etched samples against retained source facts')
    args = parser.parse_args()
    if args.verify_pinned_proof:
        verify_pinned_proof(args.verify_pinned_proof, args.capture_dir)
    if args.verify_direct_proof:
        verify_direct_product_proof(args.verify_direct_proof, args.capture_dir)
    result = audit(args.queue, args.capture_dir, args.output_dir, args.fetch)
    print('Reviewed', len(result['cases']), 'sets')
