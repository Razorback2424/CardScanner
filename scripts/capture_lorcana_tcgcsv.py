#!/usr/bin/env python3
"""Capture one complete, hash-pinned TCGCSV snapshot of Lorcana (category 71).

Live capture: contacts tcgcsv.com once per file and never overwrites an
existing snapshot. The output has the two layouts the offline producers read:

* ``groups.json`` and ``products/<group>.json`` for
  ``build_lorcana_discovery_catalog.py --groups/--products``;
* ``market/groups-selected.json`` and ``market/<group>-{products,prices}.json``
  for ``build_lorcana_market_catalog.py --sources`` and
  ``reconcile_lorcana_promo_distributions.py --market``.

``--selected`` names the reviewed code→group list (normally the previous
snapshot's ``groups-selected.json``); every selected group must still exist.
``SHA256SUMS`` and ``receipt.json`` pin the bytes and the TCGCSV build.
"""
import argparse
import datetime
import hashlib
import json
from pathlib import Path
import time
import urllib.request

ROOT = 'https://tcgcsv.com/tcgplayer/71'
USER_AGENT = 'catalog-capture/1.0'


def fetch(url):
    request = urllib.request.Request(url, headers={'User-Agent': USER_AGENT, 'Accept': 'application/json'})
    with urllib.request.urlopen(request, timeout=60) as response:
        if response.status != 200:
            raise ValueError(f'HTTP {response.status}: {url}')
        return response.read()


def complete(body, url):
    batch = json.loads(body)
    if not batch.get('success') or batch.get('errors') or batch.get('totalItems', len(batch['results'])) != len(batch['results']):
        raise ValueError(f'Incomplete or failed TCGCSV batch: {url}')
    return batch


def capture(output, selected):
    if output.exists():
        raise ValueError(f'Snapshot already exists: {output}')
    reviewed = json.loads(selected.read_bytes())
    before = fetch('https://tcgcsv.com/last-updated.txt').decode().strip()
    files = {}
    groups_body = fetch(ROOT + '/groups')
    groups = complete(groups_body, ROOT + '/groups')['results']
    files['groups.json'] = groups_body
    known = {group['groupId'] for group in groups}
    missing = [entry for entry in reviewed if entry['groupID'] not in known]
    if missing:
        raise ValueError(f'Reviewed groups are absent from TCGCSV: {missing}')
    for group in groups:
        identity = group['groupId']
        for kind in ('products', 'prices'):
            url = f'{ROOT}/{identity}/{kind}'
            body = fetch(url)
            complete(body, url)
            files[f'market/{identity}-{kind}.json'] = body
            if kind == 'products':
                files[f'products/{identity}.json'] = body
            time.sleep(0.1)
    after = fetch('https://tcgcsv.com/last-updated.txt').decode().strip()
    if before != after:
        raise ValueError('TCGCSV published a new build during capture; capture again')
    files['market/groups-selected.json'] = (json.dumps(reviewed, indent=1) + '\n').encode()
    for relative, body in files.items():
        path = output / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('xb') as stream:
            stream.write(body)
    sums = ''.join(f'{hashlib.sha256(body).hexdigest()}  {relative}\n' for relative, body in sorted(files.items()))
    (output / 'SHA256SUMS').write_text(sums)
    receipt = dict(category=71, tcgcsvBuild=after, groups=len(groups), files=len(files),
                   capturedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'))
    (output / 'receipt.json').write_text(json.dumps(receipt, indent=1, sort_keys=True) + '\n')
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--output', required=True, type=Path, help='New snapshot directory (external SSD)')
    parser.add_argument('--selected', required=True, type=Path, help='Reviewed groups-selected.json to carry forward')
    args = parser.parse_args()
    print(json.dumps(capture(args.output, args.selected), sort_keys=True))


if __name__ == '__main__':
    main()
