#!/usr/bin/env python3
"""Validate and sign a mapping-only owner update, retaining the previous pin.

Private signing material exists only in memory and the publisher environment.
No deployment, collection migration, production signing or rollout change.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publisher', type=Path, required=True)
    parser.add_argument('--corpus', type=Path, required=True)
    parser.add_argument('--previous', type=Path, required=True)
    parser.add_argument('--trusted-keys', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    publisher = str(args.publisher.resolve(strict=True))
    previous_bytes = args.previous.read_bytes()
    previous_envelope = output / 'previous-envelope.json'
    previous_envelope.write_bytes(previous_bytes)
    envelope = json.loads(previous_bytes)
    payload = envelope['payload']
    previous = base64.urlsafe_b64decode(payload + '=' * (-len(payload) % 4))
    baseline = json.loads(previous)
    previous_path = output / 'previous.json'
    previous_path.write_bytes(previous)
    for stem in ('observations', 'inventories'):
        combined = []
        for prefix in ('', 'tcgcsv-', 'event-', 'retail-', 'starter-booster-', 'base-market-'):
            combined.extend(json.loads((args.corpus / f'{prefix}{stem}.json').read_bytes()))
        (output / f'{stem}.json').write_text(json.dumps(combined))
    revision = baseline['revision'] + 1
    candidate = output / 'candidate.json'
    subprocess.run([publisher, 'build', '--registry', str(args.corpus / 'registry.json'),
        '--observations', str(output / 'observations.json'), '--inventories', str(output / 'inventories.json'),
        '--revision', str(revision), '--generated-at', datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        '--previous', str(previous_path), '--output', str(candidate)], check=True)
    current = json.loads(candidate.read_bytes())
    # Compare publisher-normalized identities. Mapping additions cannot modify
    # a finish, physical UUID, artwork, review, membership, or existing mapping.
    old_registry = baseline['registry']
    new_registry = current['registry']
    old_printings = {p['id']: p for p in old_registry['printings']}
    new_printings = {p['id']: p for p in new_registry['printings']}
    if old_printings.keys() != new_printings.keys():
        raise ValueError('Mapping-only update changed physical printing IDs')
    additions = 0
    for key, old in old_printings.items():
        new = new_printings[key]
        if {k: v for k, v in old.items() if k != 'marketMappings'} != {k: v for k, v in new.items() if k != 'marketMappings'}:
            raise ValueError('Mapping-only update changed physical identity or evidence')
        if old['marketMappings'] and old['marketMappings'] != new['marketMappings']:
            raise ValueError('Existing mappings require an explicit correction')
        additions += not old['marketMappings'] and bool(new['marketMappings'])
    if {k: v for k, v in old_registry.items() if k != 'printings'} != {k: v for k, v in new_registry.items() if k != 'printings'}:
        raise ValueError('Mapping-only update changed registry authority')
    if additions == 0:
        raise ValueError('No mapping additions to publish')
    key_id = f'one-piece-owner-review-r{revision}'
    pins = json.loads(args.trusted_keys.read_bytes())
    if key_id in pins:
        raise ValueError('Fresh owner review key ID already exists')
    private_key = os.urandom(32)
    public_der = subprocess.run(['openssl', 'pkey', '-inform', 'DER', '-pubout', '-outform', 'DER'],
        input=bytes.fromhex('302e020100300506032b657004220420') + private_key,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout
    if len(public_der) != 44 or public_der[:12] != bytes.fromhex('302a300506032b6570032100'):
        raise ValueError('Unexpected Ed25519 public key encoding')
    pins[key_id] = base64.b64encode(public_der[12:]).decode('ascii')
    keys = output / 'public-keys.json'
    keys.write_text(json.dumps(pins, sort_keys=True) + '\n')
    fingerprint = hashlib.sha256(candidate.read_bytes()).hexdigest()
    seed = output / 'one-piece-owner-catalog.json'
    common = ['--trusted-keys', str(keys), '--previous', str(previous_envelope),
              '--reviewed-payload-sha256', fingerprint]
    environment = os.environ.copy()
    environment['ONE_PIECE_CATALOG_SIGNING_KEY'] = base64.b64encode(private_key).decode('ascii')
    subprocess.run([publisher, 'sign', '--input', str(candidate), *common, '--key-id', key_id,
        '--output', str(seed), '--manifest', str(output / 'manifest.json')], env=environment, check=True)
    environment.pop('ONE_PIECE_CATALOG_SIGNING_KEY')
    subprocess.run([publisher, 'verify', '--input', str(seed), *common,
        '--manifest', str(output / 'verified-manifest.json')], check=True)
    if (output / 'manifest.json').read_bytes() != (output / 'verified-manifest.json').read_bytes():
        raise ValueError('Publication verification differs')
    print(f'Verified mapping-only owner revision {revision}: {additions} additions; identities/finishes retained')


if __name__ == '__main__':
    main()
