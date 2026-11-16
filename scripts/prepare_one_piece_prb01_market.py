#!/usr/bin/env python3
"""Apply reviewed PRB-01 market references to the signed revision-5 baseline."""
import argparse
import base64
from collections import Counter
import csv
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

from market_price_feeds import digest, validate_response
from reconcile_one_piece_retail_printings import listing_treatment

RELEASE = 'product:prb01-one-piece-card-the-best-2024'
GROUP = 23496
SOURCE = f'https://tcgcsv.com/tcgplayer/68/{GROUP}'
BASELINE_HASH = '15021308af0f62468cb81597f111fd6fce720c67b6603c9155111d5bd940fb35'
SANJI_UUID = 'C9D66679-73D8-4DB7-A294-CA31BE0F6972'
SANJI_LINKS = {'https://tcg.directory/card/586607/sanji-prb01-001',
               'https://www.pricecharting.com/game/one-piece-premium-booster/sanji-prb01-001',
               'https://belitcg.com/cards/prb01-001-sanji'}


def validate_feed(raw, resource):
    """Reject malformed feeds, while holding every duplicated product or lane."""
    doc = json.loads(raw)
    if not isinstance(doc, dict) or not isinstance(doc.get('results'), list):
        raise ValueError('Malformed provider feed')
    rows = doc['results']
    if resource == 'products' and (type(doc.get('totalItems')) is not int or doc['totalItems'] != len(rows)):
        raise ValueError('Incomplete product inventory')
    if resource == 'prices' and 'totalItems' in doc and doc['totalItems'] != len(rows):
        raise ValueError('Incomplete price inventory')
    # Validate every row before removing duplicates; malformed duplicates must
    # never disappear from a supposedly valid provider response.
    for row in rows:
        single = dict(doc, results=[row])
        if 'totalItems' in single:
            single['totalItems'] = 1
        validate_response(json.dumps(single).encode(), 68, GROUP, resource, upstream=True)
    keys = [r.get('productId') if resource == 'products' else (r.get('productId'), r.get('subTypeName')) for r in rows]
    counts = Counter(keys)
    unique = [row for row, key in zip(rows, keys) if counts[key] == 1]
    clean = dict(doc, results=unique)
    if 'totalItems' in clean:
        clean['totalItems'] = len(unique)
    validate_response(json.dumps(clean).encode(), 68, GROUP, resource, upstream=True)
    return unique, {key for key, count in counts.items() if count > 1}


def prepare(release, rows, products_raw, prices_raw, observed_at, inventory_hash):
    products, duplicate_products = validate_feed(products_raw, 'products')
    prices, duplicate_lanes = validate_feed(prices_raw, 'prices')
    product_by_id = {p['productId']: p for p in products}
    price_by_lane = {(p['productId'], p['subTypeName']): p for p in prices}
    registry = release['registry']
    printings = {p['id']: p for p in registry['printings']}
    cards = {c['id']: c for c in registry['canonicalCards']}
    observations = {o['id']: o for o in release['observations']}
    uuid_counts = Counter(r['printing_uuid'] for r in rows)
    product_counts = Counter(r['tcgplayer_product_id'] for r in rows)
    used = {m['productID'] for p in registry['printings'] for m in p['marketMappings']
            if m.get('provider') == 'tcgplayer' and m.get('status') == 'exact'}
    report, new_observations = [], []
    for row in rows:
        uid, pid, number = row['printing_uuid'], row['tcgplayer_product_id'], row['printed_number']
        decision = dict(printingID=uid, number=number, name=row['card_name'], productID=pid,
                        finish=row['finish_variant'], treatment=row['treatment'], status='held')
        report.append(decision)
        def hold(reason):
            decision['reason'] = reason
        if uuid_counts[uid] != 1 or product_counts[pid] != 1:
            hold('duplicate printing UUID or product ID in inventory'); continue
        if not re.fullmatch(r'[1-9][0-9]*', pid) or row['tcgplayer_group_id'] != str(GROUP):
            hold('invalid product ID or group'); continue
        printing = printings.get(uid)
        if not printing:
            hold('printing UUID absent from baseline'); continue
        card = cards.get(printing['canonicalCardID'], {})
        variant = row['finish_variant']
        if (row['decision'] != 'verified' or printing['status'] != 'verified' or printing['language'] != 'en'
                or printing.get('releaseID') != RELEASE or row['release_product_id'] != RELEASE
                or printing['artworkID'] != row['artwork_id'] or printing.get('treatment') != row['treatment']
                or printing.get('distributionLabel', '') != row['distribution_label']
                or printing.get('stamp', '') != row['stamp'] or printing['supportedVariantIDs'] != [variant]
                or card.get('printedNumber') != number or card.get('name') != row['card_name']):
            hold('baseline printing identity, treatment, finish, or release differs'); continue
        if printing['marketMappings'] or pid in used:
            hold('existing mapping or marketplace product collision'); continue
        if variant not in ('normal', 'foil') or row['price_lane'] != {'normal': 'Normal', 'foil': 'Foil'}[variant]:
            hold('inventory finish and marketplace lane disagree'); continue
        product_id = int(pid)
        if product_id in duplicate_products:
            hold('duplicate marketplace product'); continue
        product = product_by_id.get(product_id)
        if not product:
            hold('marketplace product missing'); continue
        if product['name'] != row['tcgplayer_product_name']:
            hold('marketplace title differs from reviewed title'); continue
        numbers = [v.get('value') for v in product.get('extendedData', []) if v.get('name') == 'Number']
        if numbers != [number]:
            hold('marketplace printed number missing or ambiguous'); continue
        market_treatment = listing_treatment(number, row['card_name'], product['name'])
        expected_treatment = 'Manga artwork' if row['treatment'] == 'Manga artwork (non-textured foil)' else row['treatment']
        if market_treatment is None or market_treatment[1] != expected_treatment:
            hold('marketplace title and reviewed treatment disagree'); continue
        evidence_refs = {(e['kind'], e['observationID']) for e in printing['review']['evidence']}
        finish = observations.get(row['source_observation_id'])
        sanji = uid == SANJI_UUID
        if sanji:
            links = set(row['evidence_urls'].split(' | '))
            finish_id = next((oid for kind, oid in evidence_refs if kind == 'finish'), '')
            finish = observations.get(finish_id)
            proof = finish['printedEvidence'] if finish else {}
            if (pid != '586607' or number != 'PRB01-001' or variant != 'normal'
                    or row['evidence_class'] != 'sanji-external-evidence' or not SANJI_LINKS <= links
                    or proof.get('sourceRole') != 'retailer-standard-printing-specification'
                    or proof.get('number') != number or proof.get('finishVariantID') != variant
                    or row['artwork_alias'] != number):
                hold('Sanji independent evidence or existing finish evidence incomplete'); continue
        else:
            proof = finish['printedEvidence'] if finish else {}
            artwork_matches = [observations[oid] for kind, oid in evidence_refs
                               if kind == 'artwork' and oid in observations
                               and observations[oid].get('imageSHA256') == proof.get('matchedBandaiImageSHA256')
                               and RELEASE in observations[oid].get('productEvidence', [])]
            if (('finish', row['source_observation_id']) not in evidence_refs or not finish
                    or finish['language'] != 'en' or RELEASE not in finish['productEvidence']
                    or proof.get('sourceRole') != 'retailer-exact-printing-specification'
                    or proof.get('number') != number or proof.get('finishVariantID') != variant
                    or proof.get('sourceArtworkAlias') != row['artwork_alias']
                    or proof.get('retailerReferenceProductID') != pid or proof.get('treatment') != row['treatment']
                    or proof.get('retailerListingPath') != row['retailer_listing_url'].removeprefix('https://coretcg.com')
                    or not re.fullmatch('[0-9a-f]{64}', proof.get('matchedBandaiImageSHA256', ''))
                    or not re.fullmatch('[0-9a-f]{64}', proof.get('retailerImageSHA256', ''))
                    or len(artwork_matches) != 1
                    or listing_treatment(number, row['card_name'], proof.get('retailerTitle', '')) != market_treatment):
                hold('retained exact retailer artwork, finish, reference, or title evidence differs'); continue
            if row['treatment'] == 'Manga artwork (non-textured foil)' and proof.get('marketplacePrintingSpecification') != 'This card was reprinted from the original set without the original textured foil.':
                hold('non-textured manga printing specification missing'); continue
        lane = (product_id, row['price_lane'])
        if lane in duplicate_lanes:
            hold('duplicate marketplace finish lane'); continue
        if lane not in price_by_lane:
            hold('marketplace finish lane missing'); continue
        oid = f'prb01-market:{uid}:{pid}:{variant}'
        qualifiers = dict(groupID=str(GROUP), productName=product['name'], finish=row['price_lane'])
        fields = dict(number=number, marketProductID=pid, marketVariantID=row['price_lane'], finishVariantID=variant,
                      market='us', currency='USD', condition='aggregate', treatment=row['treatment'],
                      retailerEvidenceID=finish['id'], sourcePricePayloadSHA256=digest(prices_raw),
                      reviewedInventorySHA256=inventory_hash)
        if sanji:
            fields['independentEvidenceURLs'] = row['evidence_urls']
            fields['independentEvidenceSummary'] = row['evidence_summary']
        fields.update({f'qualifier:{k}': v for k, v in qualifiers.items()})
        new_observations.append(dict(id=oid, kind='market', alias=dict(provider='tcgplayer', sourceID=pid),
                                     sourceURL=f'{SOURCE}/products', observedAt=observed_at, language='en',
                                     payloadSHA256=digest(products_raw), productEvidence=[RELEASE], printedEvidence=fields))
        detail = 'Reviewed PRB-01 printing, product, title, number and exact finish lane agree.'
        mapping = dict(printingID=uid, provider='tcgplayer', productID=pid, providerVariantID=row['price_lane'],
                       variantID=variant, market='us', currency='USD', condition='aggregate', qualifiers=qualifiers,
                       status='exact', review=dict(reference=f'{SOURCE}/products#{pid}', evidence=[
                           dict(kind=k, observationID=oid, detail=detail) for k in ('marketIdentity', 'printedIdentity')]))
        printing['marketMappings'].append(mapping)
        used.add(pid)
        decision.update(status='exact', retailerEvidenceID=finish['id'], capturedMarketPrice=price_by_lane[lane]['marketPrice'])
    release['observations'].extend(new_observations)
    if new_observations:
        release['inventories'].append(dict(provider='tcgplayer', snapshotID=f'prb01-market-{observed_at}',
                                           paginationComplete=False, observationIDs=sorted(o['id'] for o in new_observations)))
    return dict(baselineRevision=release['revision'], inventorySHA256=inventory_hash,
                productsSHA256=digest(products_raw), pricesSHA256=digest(prices_raw), decisions=report)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('verified-baseline', 'inventory', 'capture', 'output'):
        parser.add_argument(f'--{name}', required=True, type=Path)
    args = parser.parse_args()
    envelope = json.loads(args.verified_baseline.read_bytes())
    encoded = envelope['payload']
    baseline = base64.urlsafe_b64decode(encoded + '=' * (-len(encoded) % 4))
    release = json.loads(baseline)
    if digest(baseline) != BASELINE_HASH or release['revision'] != 5:
        raise ValueError('Baseline is not the approved revision 5 payload')
    inventory_raw = args.inventory.read_bytes()
    with args.inventory.open(newline='', encoding='utf-8-sig') as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 252 or len({r['printing_uuid'] for r in rows}) != 252 or len({r['tcgplayer_product_id'] for r in rows}) != 252 or Counter(r['price_lane'] for r in rows) != {'Foil': 236, 'Normal': 16}:
        raise ValueError('Inventory control totals do not match reviewed handoff')
    manifest = json.loads((args.capture / 'captures.json').read_bytes())
    if not manifest.get('complete'):
        raise ValueError('Capture is incomplete')
    for key, record in manifest['captures'].items():
        raw = (args.capture / record['rawFile']).read_bytes()
        if len(raw) != record['byteCount'] or digest(raw) != record['payloadSHA256']:
            raise ValueError('Capture receipt mismatch')
    start = (args.capture / 'last-updated-start.txt').read_bytes()
    end = (args.capture / 'last-updated-end.txt').read_bytes()
    if start != end or start.decode().strip() != manifest['upstreamBuild']:
        raise ValueError('Mixed capture build')
    for suffix in ('products', 'prices'):
        key = f'{SOURCE}/{suffix}'
        if manifest['captures'].get(key, {}).get('rawFile') != f'68-{GROUP}-{suffix}.json':
            raise ValueError('Capture source mismatch')
    observed = manifest['captures'][f'{SOURCE}/prices']['observedAt']
    if datetime.fromisoformat(observed) > datetime.now(timezone.utc):
        raise ValueError('Capture timestamp is in the future')
    report = prepare(release, rows, (args.capture / f'68-{GROUP}-products.json').read_bytes(),
                     (args.capture / f'68-{GROUP}-prices.json').read_bytes(), observed, digest(inventory_raw))
    report.update(observedAt=observed, sourceBuild=manifest['upstreamBuild'], baselineEnvelopeSHA256=digest(args.verified_baseline.read_bytes()))
    args.output.mkdir()
    (args.output / 'baseline.json').write_bytes(baseline)
    for name, value in [('gap-report', report), *((key, release[key]) for key in ('registry', 'observations', 'inventories'))]:
        (args.output / f'{name}.json').write_text(json.dumps(value, indent=2) + '\n')


if __name__ == '__main__':
    main()
