#!/usr/bin/env python3
"""Retain bounded Lorcast v0 metadata and receipts for offline Swift review.

No images are downloaded. This is source evidence, not a physical catalog.
Existing captures are preserved; rerun into a new directory to refresh them.
"""

import argparse
import datetime
from email.parser import Parser
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.parse


MAXIMUM_BYTES = 2 * 1024 * 1024
API_ROOT = "https://api.lorcast.com/v0"


def capture(url, directory, stem):
    body_path = directory / f"{stem}.json"
    receipt_path = directory / f"{stem}.receipt.json"
    if body_path.exists() or receipt_path.exists():
        raise ValueError(f"Capture already exists: {stem}")
    # curl works with the provider's public HTTPS endpoint on this host. Do not
    # follow redirects, retry 429s, or use an authenticated/browser session.
    with tempfile.TemporaryDirectory(prefix="lorcast-capture-") as temporary:
        temporary_path = Path(temporary)
        result = subprocess.run([
            "curl", "--silent", "--show-error", "--fail", "--max-time", "30",
            "--max-filesize", str(MAXIMUM_BYTES), "--header", "Accept: application/json",
            "--dump-header", str(temporary_path / "headers"), "--output", str(temporary_path / "body"),
            "--write-out", "%{response_code}\n%{url_effective}", url,
        ], check=True, capture_output=True, text=True, timeout=35)
        status, response_url = result.stdout.split("\n", 1)
        header_block = (temporary_path / "headers").read_text().strip().split("\n\n")[-1]
        headers = Parser().parsestr(header_block.split("\n", 1)[1])
        body = (temporary_path / "body").read_bytes()
        if len(body) > MAXIMUM_BYTES:
            raise ValueError("Provider response exceeds the 2 MiB review bound")
        content_type = headers.get("Content-Type", "")
        if status != "200" or response_url != url or content_type.split(";")[0].strip().lower() != "application/json":
            raise ValueError("Expected HTTP 200 application/json")
        pagination_headers = {
            key.lower(): value for key, value in headers.items()
            if key.lower() in {"link", "content-range"}
            or any(token in key.lower() for token in ("page", "cursor", "continuation"))
        }
        receipt = {
            "requestedURL": url,
            "responseURL": response_url,
            "receivedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
            "statusCode": int(status),
            "contentType": content_type,
            "paginationHeaders": pagination_headers,
            "bodySHA256": hashlib.sha256(body).hexdigest(),
        }
    payload = json.loads(body)
    if pagination_headers or not isinstance(payload, dict) or set(payload) != {"results"} or not isinstance(payload["results"], list):
        raise ValueError("Changed/paginated result envelope requires contract review")
    limit = 512 if stem == "sets" else 5000
    if len(payload["results"]) > limit:
        raise ValueError("Too many results for a bounded review capture")
    directory.mkdir(parents=True, exist_ok=True)
    with body_path.open("xb") as output:
        output.write(body)
    with receipt_path.open("x", encoding="utf-8") as output:
        json.dump(receipt, output, indent=2, sort_keys=True)
        output.write("\n")
    print(f"{stem}: {len(payload['results'])} provider records, {len(body)} bytes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--query", action="append", default=[], help="Bounded all-print search; may repeat up to eight times")
    parser.add_argument("--sets", action="store_true", help="Also retain the provider set directory")
    args = parser.parse_args()
    if len(args.query) > 8 or (not args.query and not args.sets):
        parser.error("Choose one to eight queries and/or --sets")
    for query in args.query:
        if not query or query != query.strip() or len(query) > 512 or any(ord(char) < 32 or ord(char) == 127 for char in query):
            parser.error("Queries must be nonempty, trimmed and at most 512 characters")
    requests = []
    if args.sets:
        requests.append((f"{API_ROOT}/sets", "sets"))
    for index, query in enumerate(args.query, 1):
        requests.append((f"{API_ROOT}/cards/search?{urllib.parse.urlencode({'q': query, 'unique': 'prints'})}", f"cards-{index:02d}"))
    for index, (url, stem) in enumerate(requests):
        if index:
            time.sleep(0.1)
        capture(url, args.output, stem)


if __name__ == "__main__":
    main()
