#!/usr/bin/env python3
"""Read-only public-directory/signed-catalog scope census; never publishes.

Signature bytes are retained, not verified here. This inventories catalog
coverage; absence from a recognition descriptor does not prove lookup failure.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import urllib.request


def fetch(url):
    with urllib.request.urlopen(url, timeout=30) as response:
        data = response.read()
    return json.loads(data), hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true', required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    urls = ['https://api.tcgdex.net/v2/en/sets',
            'https://api.tcgdex.net/v2/en/series/tcgp',
            'https://scanstash-catalog-prod.web.app/v1/current.json']
    fetched = [fetch(url) for url in urls]
    directory, pocket, envelope = [row[0] for row in fetched]
    payload = base64.urlsafe_b64decode(envelope['payload'] + '=' * (-len(envelope['payload']) % 4))
    release = json.loads(payload)
    assert release['catalogKind'] == 'pokemon'
    pocket_ids = {s['id'].lower() for s in pocket['sets']}
    served = {s['providerSetID'].lower(): s for s in release['sets']}
    inputs = json.loads((root / 'publisher/catalog-input.json').read_text())['sets']
    configured = {s['providerSetID'].lower() for s in inputs}
    ignored = set(json.loads((root / 'publisher/discovery-policy.json').read_text())['ignoredHistoricalProviderSetIDs'])
    manifest = json.loads((root / 'TradingCardScanner/PokemonChecklistSnapshot/manifest.json').read_text())
    bundled = {s['providerID'] for s in manifest['entries']}
    rows = []
    for card_set in directory:
        identity = card_set['id'].lower()
        rows.append(dict(providerSetID=card_set['id'], name=card_set['name'],
            providerCardCount=card_set['cardCount'], pocketOnly=identity in pocket_ids,
            servedRecognitionKind=served.get(identity, {}).get('recognitionKind'),
            configured=identity in configured, bundledChecklist=identity in bundled,
            ignoredHistoricalDiscovery=identity in ignored))
    physical = [r for r in rows if not r['pocketOnly']]
    output = dict(schemaVersion=1, date='2026-11-02',
        sourceReceipts={u: {'sha256': value[1]} for u, value in zip(urls, fetched)},
        servedRevision=release['revision'], servedGeneratedAt=release['generatedAt'],
        signatureVerification='not performed by this census',
        counts=dict(directory=len(rows), pocketOnly=len(rows)-len(physical), physical=len(physical),
            servedDescriptors=len(served), configuredDescriptors=len(configured), bundledSets=len(bundled)),
        configuredNotServed=sorted(configured-set(served)), servedNotConfigured=sorted(set(served)-configured),
        physicalWithoutServedDescriptor=[r['providerSetID'] for r in physical if not r['servedRecognitionKind']],
        physicalWithoutBundledChecklist=[r['providerSetID'] for r in physical if not r['bundledChecklist']],
        sets=rows)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps({k: v for k, v in output.items() if k != 'sets'}, indent=2))


if __name__ == '__main__':
    main()
