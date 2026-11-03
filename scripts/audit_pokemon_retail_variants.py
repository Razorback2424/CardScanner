#!/usr/bin/env python3
"""Read-only bounded retail census; retain physical metadata, never prices.

Network is explicit. Output is evidence, not a catalog patch or completeness
certificate. Jumbo entries must not be admitted under ordinary finish keys.
"""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import re
import urllib.request


def fetch(path):
    url = 'https://api.tcgdex.net/v2/en/' + path
    with urllib.request.urlopen(url, timeout=30) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--retry-errors', action='store_true', help='Retry only failures in the existing output')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    paths = ['TradingCardScanner/Models/TCGdexCard.swift',
             'TradingCardScanner/Services/PokemonTCGCSVMapping.swift',
             'TradingCardScanner/Services/VariantResolver.swift',
             'TradingCardScanner/PokemonChecklistSnapshot/manifest.json']
    hashes = {p: hashlib.sha256((root / p).read_bytes()).hexdigest() for p in paths}
    mapping = (root / paths[1]).read_text()
    mapped = set(re.findall(r'Entry\(cardID: "([^"]+)"', mapping))
    previous = json.loads(args.output.read_text()) if args.retry_errors else None
    ids, families, errors = set(), {}, []
    if previous:
        if previous['sourceHashes'] != hashes:
            raise ValueError('Source changed since original census')
        families = previous['families']
        ids.update(row['id'] for row in previous['errors'])
    for family in ([] if previous else ['30th', 'svp']):
        try:
            cards = fetch('sets/' + family)['cards']
            families[family] = len(cards)
            ids.update(card['id'] for card in cards)
        except Exception as error:
            errors.append({'id': family, 'error': str(error)})
    # Both apparent faces plus all companion evolution/finish controls.
    ids.update([] if previous else ['sv03-125', 'sv03-026', 'sv03-027', 'sv03-166',
                'sv04.5-054', 'sv04.5-007', 'sv04.5-008',
                'me05-040', 'me02.5-097', 'me03-050'])

    def inspect(identity):
        try:
            card = fetch('cards/' + identity)
            details = [{key: row[key] for key in
                        ['type', 'subtype', 'foil', 'size', 'stamp', 'languages', 'thirdParty', 'variantId']
                        if key in row} for row in card.get('variants_detailed', [])]
            return dict(id=identity, name=card['name'], localId=card['localId'],
                        set=card['set'], variants=card.get('variants'), details=details,
                        reviewedHoloShortCircuit=identity in mapped)
        except Exception as error:
            return dict(id=identity, error=str(error))

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        rows = list(pool.map(inspect, sorted(ids)))
    if previous:
        rows.extend(previous['cards'])
    errors.extend(row for row in rows if 'error' in row)
    successful = [row for row in rows if 'error' not in row]
    jumbo = [row['id'] for row in successful if any(d.get('size') == 'jumbo' for d in row['details'])]
    unknown_types = sorted({d.get('type') for row in successful for d in row['details']
                            if d.get('type') and d['type'] not in ['normal', 'holo', 'reverse', 'firstEdition']})
    hidden = [row['id'] for row in successful if row['reviewedHoloShortCircuit']
              and any(d.get('foil') or d.get('stamp') or d.get('size') == 'jumbo'
                      or d.get('type') not in ['holo', 'normal'] for d in row['details'])]
    output = dict(schemaVersion=1, sourceHashes=hashes, families=families,
                  requested=len(rows), received=len(successful), errors=errors,
                  jumboCardIDs=jumbo, unhandledTypes=unknown_types,
                  detailedDiscriminatorsBehindHoloShortCircuit=hidden, cards=successful)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({key: value for key, value in output.items() if key != 'cards'}, indent=2))
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
