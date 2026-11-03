#!/usr/bin/env python3
"""Prepare unsigned POP membership data only after two-catalog corroboration.

Does not install, sign, publish, or alter finishes/product mappings. Source
names and printed fractions must agree for every numbered card in each set.
"""
import argparse
import concurrent.futures
import hashlib
import html
import json
from pathlib import Path
import re
import unicodedata
import urllib.request


def canonical(value):
    value = unicodedata.normalize('NFKD', value).lower()
    value = ''.join(character for character in value if not unicodedata.combining(character))
    return ' '.join(''.join(character if character.isalnum() else ' ' for character in value).split())


def fetch(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        data = response.read()
    return data, hashlib.sha256(data).hexdigest()


def inspect(number):
    identity = f'pop{number}'
    provider_url = 'https://api.tcgdex.net/v2/en/sets/' + identity
    corroborating_url = f'https://www.serebii.net/card/popseries{number}/'
    raw, digest = fetch(provider_url)
    source = json.loads(raw)
    markup, other_digest = fetch(corroborating_url)
    text = markup.decode('utf-8', errors='replace')
    matches = re.findall(r'(\d+)\s*/\s*17.*?<td class="cen" width="20%"><a[^>]*>(.*?)</a>', text, re.S)
    names = {int(n): html.unescape(re.sub('<[^>]+>', ' ', name)).strip() for n, name in matches}
    assert len(matches) == len(names) == 17, f'{identity}: incomplete independent table'
    assert source['cardCount']['official'] == len(source['cards']) == 17
    members, evidence = [], []
    for card in source['cards']:
        local = int(card['localId'])
        assert canonical(card['name']) == canonical(names[local]), (identity, card['name'], names[local])
        members.append(dict(providerCardID=card['id'], canonicalName=canonical(card['name']),
                            printedLocalID=str(local), printedDenominator=17))
        evidence.append(dict(providerCardID=card['id'], providerName=card['name'],
                             corroboratingName=names[local], printedNumber=f'{local}/17'))
    descriptor = dict(providerSetID=identity, recognitionKind='notScannable', scanEnabled=False,
                      rulesVersion=1, membershipRecognition=dict(members=members))
    receipt = dict(providerSetID=identity, sourceURL=provider_url, sourceSHA256=digest,
                   corroboratingURL=corroborating_url, corroboratingSHA256=other_digest, cards=evidence)
    return descriptor, receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true', required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    args = parser.parse_args()
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        reviewed = list(pool.map(inspect, range(1, 10)))
    args.output_directory.mkdir(parents=True, exist_ok=True)
    for filename, data in [
        ('pop-membership-input.json', dict(sets=[row[0] for row in reviewed])),
        ('pop-membership-evidence.json', dict(schemaVersion=1, date='2026-11-02',
            disposition='unsigned candidate; requires native publisher/runtime validation', sets=[row[1] for row in reviewed]))
    ]:
        (args.output_directory / filename).write_text(json.dumps(data, indent=2, ensure_ascii=False) + '\n')
    print('Corroborated 153 numbered identities across 9 sets; prepared unsigned membership batch.')


if __name__ == '__main__':
    main()
