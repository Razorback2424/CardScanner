#!/usr/bin/env python3
"""Capture the live predecessor and immutable checks for the protected deploy job."""

import argparse
import hashlib
import json
from pathlib import Path
import secrets

from market_price_feeds import ORIGIN, R2_ORIGIN, read_http


NAMESPACE = "one-piece/v1"
APPROVED_ORIGINS = (ORIGIN, R2_ORIGIN)
MAX_ENVELOPE_BYTES = 64 * 1024 * 1024  # OnePieceCatalogSignature.maximumEnvelopeBytes


def publication_inputs(approved, manifest, bootstrap, fetch):
    revision = manifest.get("revision")
    previous = manifest.get("previousRevision")
    previous_hash = manifest.get("previousEnvelopeSHA256")
    if type(revision) is not int or not 1 <= revision <= 100_000:
        raise ValueError("Invalid One Piece publication revision")
    if bootstrap:
        if revision != 1 or previous is not None or previous_hash is not None:
            raise ValueError("One Piece bootstrap requires revision 1 without a predecessor")
    elif type(previous) is not int or not 1 <= previous < revision:
        raise ValueError("One Piece continuation requires a reviewed predecessor")

    current = fetch(f"{NAMESPACE}/current.json", absent_ok=True)
    immutable = fetch(f"{NAMESPACE}/releases/{revision}/catalog-release.json", absent_ok=True)
    if immutable is not None and immutable != approved:
        raise ValueError("Existing immutable One Piece release differs from the approved artifact")
    if current == approved and immutable != approved:
        raise ValueError("The active One Piece release has no matching immutable artifact")

    if bootstrap:
        if current is not None and current != approved:
            raise ValueError("One Piece bootstrap encountered a different production pointer")
        return revision, current, None

    baseline = (fetch(f"{NAMESPACE}/releases/{previous}/catalog-release.json", absent_ok=False)
                if current == approved else current)
    if baseline is None or hashlib.sha256(baseline).hexdigest() != previous_hash:
        raise ValueError("The live One Piece predecessor differs from the reviewed predecessor")
    return revision, current, baseline


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--bootstrap", choices=["true", "false"], required=True)
    parser.add_argument("--origin", default=ORIGIN, choices=APPROVED_ORIGINS)
    parser.add_argument("--one-piece-only", action="store_true",
                        help="Capture only One Piece predecessor inputs without reading other namespaces")
    args = parser.parse_args(argv)

    nonce = secrets.token_hex(8)

    def fetch(path, *, absent_ok):
        suffix = f"?r2v={nonce}" if args.origin == R2_ORIGIN else ""
        return read_http(f"{args.origin}/{path}{suffix}", MAX_ENVELOPE_BYTES, absent_ok=absent_ok)

    envelope = (args.artifact / "release-envelope.json").read_bytes()
    manifest = json.loads((args.artifact / "verified-manifest.json").read_bytes())
    revision, current, baseline = publication_inputs(envelope, manifest, args.bootstrap == "true", fetch)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    outputs = [("one-piece-current", current), ("one-piece-predecessor", baseline)]
    if not args.one_piece_only:
        outputs.extend([
            ("pokemon-current", fetch("v1/current.json", absent_ok=False)),
            ("magic-current", fetch("magic/v1/current.json", absent_ok=True)),
        ])
    for name, data in outputs:
        if data is not None:
            (args.output_dir / f"{name}.json").write_bytes(data)
    print(revision)


if __name__ == "__main__":
    main()
