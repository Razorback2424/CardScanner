#!/usr/bin/env python3
"""Audit captured vendor groups and every installed exact market mapping.

Read-only with respect to app catalogs, signatures and user collections. Optional
feed capture is bounded to installed One Piece/Lorcana groups, paced, retained,
and tied to one upstream build. Replays make no network requests. Native XCTest
separately runs the production set resolver against vendor-groups.json.
"""
import argparse
import base64
import collections
import csv
import hashlib
import json
import math
from pathlib import Path
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def read(path):
    return json.loads(path.read_bytes())


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def initialize_capture(directory, fetch):
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / 'capture.json'
    if path.exists():
        return read(path)
    if not fetch:
        raise ValueError('A retained capture is required for offline replay')
    manifest = dict(schemaVersion=1, captures={})
    marker = 'https://tcgcsv.com/last-updated.txt'
    start = capture(marker, directory / 'last-updated-start.txt', manifest, True).decode().strip()
    for category in [1, 2, 3, 68, 71]:
        capture(f'https://tcgcsv.com/tcgplayer/{category}/groups', directory / f'groups-{category}.json', manifest, True)
    end = capture(marker, directory / 'last-updated-end.txt', manifest, True).decode().strip()
    if start != end:
        raise ValueError('Mixed upstream daily build')
    manifest['upstreamBuild'] = start
    path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    return manifest


def export_vendor_fixture(directory, destination):
    manifest = read(directory / 'capture.json')
    categories = {1: 'magic', 2: 'yu-gi-oh', 3: 'pokemon', 68: 'one-piece', 71: 'lorcana'}
    names = ['last-updated-start.txt', 'last-updated-end.txt'] + [f'groups-{c}.json' for c in categories]
    fixture = dict(schemaVersion=1, upstreamBuild=manifest['upstreamBuild'],
        source='TCGCSV group-name inventory; IDs are TCGplayer group IDs, not JustTCG slugs.',
        receipts={name: manifest['captures'][name] for name in names}, groups=[])
    for category, game in categories.items():
        for group in read(directory / f'groups-{category}.json')['results']:
            fixture['groups'].append(dict(category=category, game=game, id=str(group['groupId']), name=group['name'],
                abbreviation=group.get('abbreviation', ''), publishedOn=group.get('publishedOn', '')))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(fixture, sort_keys=True, separators=(',', ':')) + '\n')


def installed_mappings(repo):
    """Project authoritative stored mappings, never infer joins from card names."""
    app = repo / 'TradingCardScanner'
    envelope = read(app / 'OnePieceOwnerCatalog/one-piece-owner-catalog.json')
    payload = envelope['payload']
    release = json.loads(base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4)))['registry']
    canonical = {c['id']: c for c in release['canonicalCards']}
    products = {p['id']: p for p in release['products']}
    rows = []
    for p in release['printings']:
        if p['status'] != 'verified' or p['language'] != 'en':
            continue
        for m in p['marketMappings']:
            if m['status'] != 'exact':
                continue
            rows.append(dict(game='one-piece', category=68, group=int(m['qualifiers']['groupID']),
                printing=p['id'], set=products[p['releaseID']]['label'], product=int(m['productID']),
                name=m['qualifiers']['productName'], number=canonical[p['canonicalCardID']]['printedNumber'],
                lane=m['providerVariantID'], localQuote=None))
    lorcana = read(app / 'LorcanaCatalogSeed/market.json')
    for p in lorcana['physicalPrintings']:
        for m in p.get('marketMappings', []):
            rows.append(dict(game='lorcana', category=71, group=m['groupID'], printing=p['id'],
                set=p['setName'], product=m['productID'], name=m['productName'], number=m['productNumber'],
                lane=m['providerVariantID'], localQuote=None))
    ygo = read(app / 'YuGiOhCatalogSeed/catalog.json')
    sets = {s['g']: s for s in ygo['sets']}
    editions = {'yugioh1stEdition': '1st Edition', 'yugiohUnlimited': 'Unlimited', 'yugiohLimited': 'Limited'}
    for p in ygo['printings']:
        for m in p.get('m', []):
            if m['e'] not in p['e']:
                raise ValueError('Yu-Gi-Oh membership contradicts edition authority')
            rows.append(dict(game='yu-gi-oh', category=2, group=p['g'], printing=p['id'],
                set=sets[p['g']]['n'], product=p['p'], name=p['pn'], number=p['c'],
                lane=editions[m['e']], localQuote=m.get('q')))
    return rows


def local_set_coverage(repo):
    """Keep discovery, admitted physical printings and mapped lanes separate."""
    app = repo / 'TradingCardScanner'
    result = []
    magic = read(app / 'MagicCatalogSeed/catalog.json')
    for s in magic['sets']:
        result.append(dict(game='magic', catalogID=s['code'], name=s['displayName'],
            scope='browse' if s['browseEnabled'] else 'hiddenDescriptor', records=s['cardCount'],
            eligiblePrintings='', mappedLanes='', note='Names tested natively for Browse descriptors; card pricing coverage is not inferred'))
    pokemon = read(app / 'PokemonChecklistSnapshot/manifest.json')
    for e in pokemon['entries']:
        result.append(dict(game='pokemon', catalogID=e['providerID'], name=e['set']['name'], scope='browsePrintRunEntry',
            records=e['expandedSlotCount'], eligiblePrintings='', mappedLanes='', note='Print-run entry; native name census deduplicates provider sets'))
    envelope = read(app / 'OnePieceOwnerCatalog/one-piece-owner-catalog.json')['payload']
    registry = json.loads(base64.urlsafe_b64decode(envelope + '=' * (-len(envelope) % 4)))['registry']
    for product in registry['products']:
        rows = [p for p in registry['printings'] if p['releaseID'] == product['id'] and p['language'] == 'en']
        eligible = [p for p in rows if p['status'] == 'verified']
        result.append(dict(game='one-piece', catalogID=product['id'], name=product['label'], scope='declaredRelease',
            records=len(rows), eligiblePrintings=len(eligible), mappedLanes=sum(len(p['marketMappings']) for p in eligible),
            note='No mapping is an authority/coverage gap, not a vendor name-match failure'))
    discovery = read(app / 'LorcanaCatalogSeed/discovery.json')
    physical = read(app / 'LorcanaCatalogSeed/market.json')['physicalPrintings']
    by_code = collections.defaultdict(list)
    for card in discovery['cards']:
        by_code[card['sourceSetCode']].append(card)
    for code, cards in sorted(by_code.items()):
        admitted = [p for p in physical if p['providerSetCode'] == code]
        result.append(dict(game='lorcana', catalogID=code, name=cards[0]['setName'], scope='sourceSet', records=len(cards),
            eligiblePrintings=len(admitted), mappedLanes=sum(len(p.get('marketMappings', [])) for p in admitted),
            note='Discovery records do not grant physical identity or pricing authority'))
    ygo = read(app / 'YuGiOhCatalogSeed/catalog.json')
    by_group = collections.defaultdict(list)
    for printing in ygo['printings']:
        by_group[printing['g']].append(printing)
    for s in ygo['sets']:
        rows = by_group[s['g']]
        result.append(dict(game='yu-gi-oh', catalogID=str(s['g']), name=s['n'], scope='snapshotSet', records=len(rows),
            eligiblePrintings=sum(bool(p['e']) and not p.get('ir') for p in rows),
            mappedLanes=sum(len(p.get('m', [])) for p in rows), note='Dated snapshot; live per-card refresh remains disabled'))
    return result


def capture(url, path, manifest, fetch, allow_not_found=False, delay=.15):
    """Reuse hash-bound bytes; never overwrite a capture or silently refresh it."""
    key = path.name
    previous = manifest['captures'].get(key)
    if path.exists():
        if previous is None or previous['sourceURL'] != url or previous['sha256'] != digest(path):
            raise ValueError(f'Untracked or changed capture: {path.name}')
        return path.read_bytes()
    if not fetch:
        return None
    if not math.isfinite(delay) or delay < .15:
        raise ValueError('Capture delay must be at least 150 ms')
    time.sleep(delay)
    request = Request(url, headers={'User-Agent': 'TradingCardScanner-SetAudit/1.0', 'Accept': 'application/json,text/plain'})
    status = 200
    try:
        response = urlopen(request, timeout=35)
    except HTTPError as error:
        if not allow_not_found or error.code != 404:
            raise
        response, status = error, 404
    with response:
        if response.geturl() != url:
            raise ValueError('Unexpected feed redirect')
        raw = response.read(8 * 1024 * 1024 + 1)
    if len(raw) > 8 * 1024 * 1024:
        raise ValueError('Feed exceeds audit bound')
    path.write_bytes(raw)
    manifest['captures'][key] = dict(sourceURL=url, sha256=hashlib.sha256(raw).hexdigest(), bytes=len(raw))
    if status != 200:
        manifest['captures'][key]['httpStatus'] = status
    (path.parent / 'capture.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    return raw


def validate_feed(raw, category, group, resource):
    doc = json.loads(raw)
    rows = doc.get('results', [])
    if doc.get('success') is not True or doc.get('errors') != []:
        raise ValueError('Failed feed envelope')
    if doc.get('totalItems', len(rows)) != len(rows):
        raise ValueError('Incomplete feed')
    if resource == 'products':
        if any(r['categoryId'] != category or r['groupId'] != group for r in rows):
            raise ValueError('Wrong category or group')
        keys = [r['productId'] for r in rows]
    else:
        keys = [(r['productId'], r['subTypeName']) for r in rows]
        for row in rows:
            amount = row.get('marketPrice')
            if amount is not None and (type(amount) not in [int, float] or not math.isfinite(amount) or amount < 0):
                raise ValueError('Invalid market amount')
    if len(set(keys)) != len(keys):
        raise ValueError('Duplicate product or finish lane')
    return rows


def audit(repo, capture_dir, output, fetch=False, native_report=None):
    output.mkdir(parents=True, exist_ok=True)
    manifest = initialize_capture(capture_dir, fetch)
    upstream = manifest['upstreamBuild']
    if fetch:
        request = Request('https://tcgcsv.com/last-updated.txt', headers={'User-Agent': 'TradingCardScanner-SetAudit/1.0'})
        with urlopen(request, timeout=20) as response:
            if response.read(1024).decode().strip() != upstream:
                raise ValueError('Capture is from another daily build; create a new capture directory')
    groups = {}
    for category in [1, 2, 3, 68, 71]:
        name = f'groups-{category}.json'
        path = capture_dir / name
        if digest(path) != manifest['captures'][name]['sha256']:
            raise ValueError('Vendor group capture changed')
        doc = read(path)
        if doc.get('success') is not True or doc.get('errors') != [] or doc.get('totalItems') != len(doc['results']):
            raise ValueError('Incomplete group inventory')
        groups[category] = {g['groupId']: g for g in doc['results']}
    mappings = installed_mappings(repo)
    inventory = local_set_coverage(repo)
    with (output / 'catalog-coverage.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=['game', 'catalogID', 'name', 'scope', 'records', 'eligiblePrintings', 'mappedLanes', 'note'])
        writer.writeheader(); writer.writerows(inventory)
    issues, coverage = [], []
    for (category, group), mapped in sorted_grouped(mappings):
        vendor = groups[category].get(group)
        row = dict(game=mapped[0]['game'], category=category, group=group,
            vendorSet=vendor['name'] if vendor else '', mappedLanes=len(mapped), status='directoryVerified',
            mappedPrintings=len({m['printing'] for m in mapped}), livePriced=0, liveUnpriced=0)
        if vendor is None:
            row['status'] = 'vendorGroupMissing'
            issues.append(dict(game=row['game'], group=group, product='', lane='',
                issue='vendorGroupMissing', detail='Installed group absent from captured directory; not proof of product absence'))
        elif category == 2:
            row['status'] = 'datedSnapshotOnly'
            row['snapshotPriced'] = sum(m['localQuote'] is not None for m in mapped)
            row['snapshotUnpriced'] = sum(m['localQuote'] is None for m in mapped)
        else:
            responses = {}
            for resource in ['products', 'prices']:
                try:
                    raw = capture(f'https://tcgcsv.com/tcgplayer/{category}/{group}/{resource}',
                        capture_dir / f'{category}-{group}-{resource}.json', manifest, fetch)
                    if raw is not None:
                        responses[resource] = validate_feed(raw, category, group, resource)
                except (HTTPError, URLError, TimeoutError, ValueError, KeyError, json.JSONDecodeError) as error:
                    row['status'] = 'sourceUnavailable'
                    issues.append(dict(game=row['game'], group=group, product='', lane='', issue='sourceUnavailable', detail=str(error)))
            if len(responses) == 2:
                products = {p['productId']: p for p in responses['products']}
                prices = {(p['productId'], p['subTypeName']): p.get('marketPrice') for p in responses['prices']}
                row['status'] = 'liveIdentityVerified'
                for m in mapped:
                    product = products.get(m['product'])
                    reason = None
                    if product is None:
                        reason = 'productMissing'
                    elif [f['value'] for f in product.get('extendedData', []) if f['name'] == 'Number'] != [m['number']]:
                        reason = 'collectorNumberDrift'
                    elif product['name'] != m['name']:
                        reason = 'productNameDrift'
                    if reason:
                        row['status'] = 'mappingMismatch'
                        issues.append(dict(game=m['game'], group=group, product=m['product'], lane=m['lane'],
                            issue=reason, detail=json.dumps(dict(expectedName=m['name'], expectedNumber=m['number'],
                                observedName=product.get('name') if product else None), ensure_ascii=False)))
                    quote = prices.get((m['product'], m['lane']))
                    row['livePriced' if quote is not None else 'liveUnpriced'] += 1
        coverage.append(row)
    if fetch:
        time.sleep(.15)
        request = Request('https://tcgcsv.com/last-updated.txt', headers={'User-Agent': 'TradingCardScanner-SetAudit/1.0'})
        with urlopen(request, timeout=20) as response:
            if response.read(1024).decode().strip() != upstream:
                raise ValueError('Daily build changed during feed capture; results cannot be adopted')
        manifest['mappedFeedsUpstreamBuild'] = upstream
        (capture_dir / 'capture.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    paths = ['TradingCardScanner/OnePieceOwnerCatalog/one-piece-owner-catalog.json',
        'TradingCardScanner/LorcanaCatalogSeed/market.json', 'TradingCardScanner/YuGiOhCatalogSeed/catalog.json']
    summary = dict(schemaVersion=1, upstreamBuild=upstream,
        boundary='Directory and exact installed product mapping audit. Null/missing quotes are availability, not identity. Yu-Gi-Oh remains dated snapshot pricing. No catalog or signature changes.',
        sources={p: digest(repo / p) for p in paths},
        vendorGroupCounts={str(k): len(v) for k, v in groups.items()},
        mappingCounts=dict(collections.Counter(m['game'] for m in mappings)),
        catalogSetEntries=dict(collections.Counter(r['game'] for r in inventory)),
        groupStatuses=dict(collections.Counter(r['status'] for r in coverage)),
        issues=dict(collections.Counter(r['issue'] for r in issues)), groups=coverage)
    summary['mappedPrintingCounts'] = {game: len({m['printing'] for m in mappings if m['game'] == game})
        for game in ['one-piece', 'lorcana', 'yu-gi-oh']}
    summary['reviewedPrintingsWithoutMappings'] = {game:
        sum(int(r['eligiblePrintings']) for r in inventory if r['game'] == game) - summary['mappedPrintingCounts'][game]
        for game in ['one-piece', 'lorcana']}
    summary['captureManifestSHA256'] = digest(capture_dir / 'capture.json')
    for row in coverage:
        for resource in ['products', 'prices']:
            key = f"{row['category']}-{row['group']}-{resource}.json"
            if key in manifest['captures']:
                row[resource + 'SHA256'] = manifest['captures'][key]['sha256']
    if native_report is not None:
        native = read(native_report)
        if native['upstreamBuild'] != upstream:
            raise ValueError('Native report and feed capture use different upstream builds')
        name_rows = native['rows']
        summary['nativeReportSHA256'] = digest(native_report)
        scryfall_path = capture_dir / 'scryfall-sets.json'
        source_sets = {}
        if scryfall_path.exists():
            if digest(scryfall_path) != manifest['captures'][scryfall_path.name]['sha256']:
                raise ValueError('Scryfall set capture changed')
            source = read(scryfall_path)
            if source.get('has_more'):
                raise ValueError('Incomplete Scryfall directory')
            source_sets = {s['code'].upper(): s for s in source['data']}
            summary['scryfallSetCount'] = len(source_sets)
        conflicts = []
        for row in name_rows:
            source_group = source_sets.get(row['catalogID'], {}).get('tcgplayer_id') if row['game'] == 'magic' else None
            if row['status'] != 'resolved' or not source_group or str(source_group) == row['vendorGroupID']:
                continue
            resolution = 'needsCardLevelReview'
            if row['catalogID'] == 'GN2':
                paths = [capture_dir / 'scryfall-gn2-cards.json', capture_dir / '1-2359-products.json', capture_dir / '1-2562-products.json']
                if all(p.exists() for p in paths):
                    for p in paths:
                        if digest(p) != manifest['captures'][p.name]['sha256']:
                            raise ValueError('Game Night card-level evidence changed')
                    cards = read(paths[0])
                    ids = {c['tcgplayer_id'] for c in cards['data'] if c.get('tcgplayer_id')}
                    wrong = {p['productId'] for p in validate_feed(paths[1].read_bytes(), 1, 2359, 'products')}
                    correct = {p['productId'] for p in validate_feed(paths[2].read_bytes(), 1, 2562, 'products')}
                    if not cards.get('has_more') and all(c['set'] == 'gn2' for c in cards['data']) and ids and ids <= correct and ids.isdisjoint(wrong):
                        resolution = f'cardLevelVerified:{len(ids)} products in 2019 group; none in 2018 group'
            conflicts.append(dict(catalogID=row['catalogID'], catalogName=row['catalogName'], sourceGroup=source_group,
                resolvedGroup=row['vendorGroupID'], resolvedName=row['vendorName'], disposition=resolution))
        summary['setIdentifierConflicts'] = conflicts
        summary['setNameCounts'] = {game: dict(collections.Counter(r['status'] for r in name_rows if r['game'] == game))
            for game in ['pokemon', 'magic']}
        with (output / 'set-concordance.csv').open('w', newline='') as stream:
            fields = ['game', 'catalogID', 'catalogName', 'vendorGroupID', 'vendorName', 'status']
            writer = csv.DictWriter(stream, fieldnames=fields)
            writer.writeheader(); writer.writerows(name_rows)
        review = []
        for row in name_rows:
            if row['status'] != 'unresolved':
                continue
            category = 1 if row['game'] == 'magic' else 3
            candidates = [g for g in groups[category].values()
                if g.get('abbreviation', '').casefold() == row['catalogID'].casefold()]
            source_group = source_sets.get(row['catalogID'], {}).get('tcgplayer_id') if row['game'] == 'magic' else None
            source_vendor = groups[category].get(source_group, {})
            review.append(dict(**row, codeCandidates='; '.join(f"{g['groupId']}: {g['name']}" for g in candidates),
                sourceGroupID=source_group or '', sourceGroupName=source_vendor.get('name', ''),
                disposition='Needs independent set/release evidence; never an automatic pricing join'))
        with (output / 'unresolved-sets.csv').open('w', newline='') as stream:
            fields = ['game', 'catalogID', 'catalogName', 'vendorGroupID', 'vendorName', 'status', 'codeCandidates', 'sourceGroupID', 'sourceGroupName', 'disposition']
            writer = csv.DictWriter(stream, fieldnames=fields)
            writer.writeheader(); writer.writerows(review)
        summary['unresolvedWithCodeCandidates'] = sum(bool(r['codeCandidates']) for r in review)
        summary['unresolvedMagicSourceGroups'] = dict(collections.Counter(
            'sourceGroupKnown' if r['sourceGroupID'] else 'noSourceGroup' for r in review if r['game'] == 'magic'))
    (output / 'mapping-summary.json').write_text(json.dumps(summary, indent=2, sort_keys=True) + '\n')
    with (output / 'mapping-issues.csv').open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=['game', 'group', 'product', 'lane', 'issue', 'detail'])
        writer.writeheader(); writer.writerows(issues)
    return summary


def sorted_grouped(rows):
    grouped = collections.defaultdict(list)
    for row in rows:
        grouped[(row['category'], row['group'])].append(row)
    return sorted(grouped.items())


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--capture-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--fetch-mapped-feeds', action='store_true', help='Capture each installed One Piece/Lorcana group once; no Yu-Gi-Oh live refresh')
    parser.add_argument('--native-report', type=Path, help='JSON attachment exported by the systematic native concordance test')
    parser.add_argument('--export-vendor-fixture', type=Path, help='Write the compact native-test group inventory from this validated capture')
    args = parser.parse_args()
    result = audit(args.repo, args.capture_dir, args.output_dir, args.fetch_mapped_feeds, args.native_report)
    if args.export_vendor_fixture:
        export_vendor_fixture(args.capture_dir, args.export_vendor_fixture)
    print(json.dumps({k: v for k, v in result.items() if k not in ['sources', 'groups']}, indent=2))
