#!/usr/bin/env python3
"""Read-only residual promo census; no catalog edits or signing.

Records price-free physical metadata. Shared product IDs are review leads,
not authority to replace bindings or merge printing identities.
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request


def fetch(path):
    url = 'https://api.tcgdex.net/v2/en/' + path
    try:
        with urllib.request.urlopen(url, timeout=30) as response:
            raw = response.read()
        return json.loads(raw), hashlib.sha256(raw).hexdigest()
    except Exception as error:
        return {'error': str(error), 'sourceURL': url}, None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    families = ['miscp', 'basep', 'wp', 'jumbo', 'sp', 'np', 'rc', 'tk-sm-l']
    originals = ['base2-60', 'base3-50', 'base4-63', 'base5-19', 'base5-32', 'gym1-54', 'gym2-37']
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        sets = list(pool.map(fetch, ['sets/' + identity for identity in families]))
        cards = list(pool.map(fetch, ['cards/' + identity for identity in originals]))
    set_rows, card_rows, errors = [], [], []
    for identity, (source, digest) in zip(families, sets):
        if 'error' in source:
            errors.append(source)
            continue
        set_rows.append(dict(providerSetID=identity, name=source['name'],
            declaredCount=source['cardCount']['official'], providedCount=len(source['cards']),
            sourceURL='https://api.tcgdex.net/v2/en/sets/' + identity, sourceSHA256=digest,
            cards=[{key: card[key] for key in ['id', 'localId', 'name']} for card in source['cards']]))
    for identity, (source, digest) in zip(originals, cards):
        if 'error' in source:
            errors.append(source)
            continue
        details = []
        for row in source.get('variants_detailed', []):
            detail = {key: row[key] for key in
                ['type', 'size', 'foil', 'stamp', 'subtype', 'languages', 'thirdParty'] if key in row}
            quotes = (row.get('pricing') or {}).get('tcgplayer') or {}
            detail['quoteProductIDs'] = {key: quote.get('productId') for key, quote in quotes.items()
                                         if isinstance(quote, dict)}
            details.append(detail)
        standard = [d for d in details if not d.get('stamp') and not d.get('subtype')]
        ordinary_handles = {d.get('thirdParty', {}).get('tcgplayer') for d in standard}
        stamped = [d for d in details if set(d.get('stamp', [])) & {'wotc', 'w-promo'}]
        shared = sorted({d.get('thirdParty', {}).get('tcgplayer') for d in stamped}
                        & ordinary_handles - {None})
        card_rows.append(dict(providerCardID=identity, name=source['name'], localId=source['localId'],
            printedDenominator=source['set']['cardCount']['official'], details=details,
            sourceURL='https://api.tcgdex.net/v2/en/cards/' + identity, sourceSHA256=digest,
            wStampedDetailCount=len(stamped), sharedOrdinaryTCGplayerHandles=shared))
    output = dict(schemaVersion=1, date='2026-11-02', purpose='Investigation only; no production bindings changed',
                  sets=set_rows, wStampOriginals=card_rows, errors=errors)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps(dict(sets=len(set_rows), originals=len(card_rows), errors=errors,
        emptyInventories=[s['providerSetID'] for s in set_rows if not s['providedCount']],
        wStampDetails=sum(c['wStampedDetailCount'] for c in card_rows),
        sharedHandleLeads=[c['providerCardID'] for c in card_rows if c['sharedOrdinaryTCGplayerHandles']]), indent=2))
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
