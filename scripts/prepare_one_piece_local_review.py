#!/usr/bin/env python3
"""Prepare the reviewed catalog for an isolated debug app launch.

Requires the existing one-piece-catalog-publisher executable and OpenSSL.
No network, images, production keys, publication or provider-ID allocation.
The ephemeral signing private key is never written to disk or printed.
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
    parser.add_argument("--publisher", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True,
                        help="New external review artifact directory; never overwritten")
    args = parser.parse_args()
    publisher = args.publisher.resolve(strict=True)
    corpus = Path(__file__).resolve().parents[1] / "OnePieceCatalogCore/ReviewCorpus/english-stress"
    output = args.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=False)
    for stem in ("observations", "inventories"):
        combined = []
        for filename in (f"{stem}.json", f"tcgcsv-{stem}.json", f"event-{stem}.json", f"retail-{stem}.json", f"starter-booster-{stem}.json", f"base-market-{stem}.json"):
            combined.extend(json.loads((corpus / filename).read_text()))
        (output / f"{stem}.json").write_text(json.dumps(combined, sort_keys=True))
    candidate = output / "candidate.json"
    subprocess.run([str(publisher), "build", "--registry", str(corpus / "registry.json"),
                    "--observations", str(output / "observations.json"),
                    "--inventories", str(output / "inventories.json"),
                    "--revision", "1", "--generated-at", datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "--bootstrap-registry", "yes", "--output", str(candidate)], check=True)
    private_key = os.urandom(32)
    # PKCS#8 Ed25519 private key: fixed DER header followed by the 32-byte seed.
    public_der = subprocess.run(["openssl", "pkey", "-inform", "DER", "-pubout", "-outform", "DER"],
                                input=bytes.fromhex("302e020100300506032b657004220420") + private_key,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True).stdout
    if len(public_der) != 44 or public_der[:12] != bytes.fromhex("302a300506032b6570032100"):
        raise ValueError("Unexpected Ed25519 public-key encoding")
    public_key = base64.b64encode(public_der[12:]).decode("ascii")
    keys = output / "public-keys.json"
    keys.write_text(json.dumps({"one-piece-local-review": public_key}))
    environment = os.environ.copy()
    environment["ONE_PIECE_CATALOG_SIGNING_KEY"] = base64.b64encode(private_key).decode("ascii")
    seed = output / "one-piece-local-review.json"
    subprocess.run([str(publisher), "sign", "--input", str(candidate),
                    "--trusted-keys", str(keys), "--bootstrap-registry", "yes",
                    "--reviewed-payload-sha256", hashlib.sha256(candidate.read_bytes()).hexdigest(),
                    "--key-id", "one-piece-local-review", "--output", str(seed),
                    "--manifest", str(output / "manifest.json")], env=environment, check=True)
    environment.pop("ONE_PIECE_CATALOG_SIGNING_KEY")
    arguments = ["-one_piece_local_review", "-one_piece_review_seed", str(seed),
                 "-one_piece_review_public_key", public_key]
    (output / "launch-arguments.json").write_text(json.dumps(arguments, indent=2) + "\n")
    print(f"Local review kit: {output}")
    print("DebugRemoteLocal only; reviewed printings and exact base market mappings; no production sync.")


if __name__ == "__main__":
    main()
