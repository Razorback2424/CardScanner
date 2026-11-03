#!/usr/bin/env python3
"""Read public, price-free primary identity evidence. Never signs or edits input."""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def fetch(url):
    try:
        with urlopen(Request(url), timeout=25) as response:
            data = response.read()
            status = response.status
        return {"url": url, "status": status, "sha256": hashlib.sha256(data).hexdigest()}, json.loads(data)
    except HTTPError as error:
        return {"url": url, "status": error.code, "error": str(error)}, None
    except Exception as error:
        return {"url": url, "error": str(error)}, None


def product(identity):
    receipt, value = fetch(f"https://mp-search-api.tcgplayer.com/v1/product/{identity}/details")
    receipt["requestedProductID"] = identity
    if value is not None:
        receipt["identity"] = {key: value.get(key) for key in [
            "productId", "productName", "setId", "setCode", "setName",
            "productLineName", "productTypeName", "foilOnly", "normalOnly"
        ]}
        receipt["identity"]["number"] = value.get("customAttributes", {}).get("number")
    return receipt


def card(identity):
    receipt, value = fetch(f"https://api.tcgdex.net/v2/en/cards/{identity}")
    receipt["requestedCardID"] = identity
    if value is not None:
        receipt["identity"] = {key: value.get(key) for key in ["id", "localId", "name", "set", "variants"]}
        receipt["identity"]["variants_detailed"] = [
            {key: entry[key] for key in ["type", "subtype", "foil", "size", "stamp", "languages", "thirdParty", "variantId"] if key in entry}
            for entry in value.get("variants_detailed", [])
        ]
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", required=True, action="store_true")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--retry-errors", action="store_true", help="Retry only transient failures, retaining prior receipts")
    args = parser.parse_args()
    if args.retry_errors:
        result = json.loads(args.output.read_text())
        for key, loader, identity_key in [("products", product, "requestedProductID"), ("cards", card, "requestedCardID")]:
            for index, entry in enumerate(result[key]):
                if "error" not in entry or (entry.get("status") is not None and entry["status"] < 500):
                    continue
                refreshed = loader(entry[identity_key])
                refreshed["priorAttempts"] = entry.get("priorAttempts", []) + [
                    {k: v for k, v in entry.items() if k != "priorAttempts"}
                ]
                result[key][index] = refreshed
        result["lastRetryAtUTC"] = datetime.now(timezone.utc).isoformat()
        args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
        print(json.dumps({"remainingErrors": sum("error" in entry for key in ["products", "cards"] for entry in result[key])}))
        return
    root = Path(__file__).resolve().parents[1]
    queue = json.loads((root / "docs/audits/pokemon-retail-variant-review-2026-11-02.json").read_text())["cards"]
    products = sorted({entry["providerProductHandles"]["tcgplayer"] for entry in queue} | {596423, 714357, 717879})
    cards = sorted({entry["catalogID"] for entry in queue} | {"30th-116"})
    # These are unauthenticated catalog identity reads, not paid quote lookups.
    with ThreadPoolExecutor(max_workers=6) as pool:
        product_receipts = list(pool.map(product, products))
        card_receipts = list(pool.map(card, cards))
    result = {
        "schemaVersion": 1,
        "observedAtUTC": datetime.now(timezone.utc).isoformat(),
        "purpose": "Primary-source evidence only; no numeric prices, signatures, or publication",
        "products": product_receipts,
        "cards": card_receipts,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
    failures = [entry for entry in product_receipts + card_receipts if "error" in entry]
    print(json.dumps({"productsRequested": len(products), "cardsRequested": len(cards), "failures": failures}))


if __name__ == "__main__":
    main()
