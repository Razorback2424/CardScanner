#!/usr/bin/env python3
"""Read-only Jumbo census for one English provider family; never edits input.

Retains all member identity receipts, then independently fetches marketplace
metadata for the Jumbo handles. Results are a review queue, not admission proof.
Use --retry-errors to retry transient failures only and retain earlier attempts.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import json
from pathlib import Path

from audit_pokemon_jumbo_products import card, fetch, product


def transient(row):
    return "error" in row and (row.get("status") is None or row["status"] >= 500)


def retry(loader, row, key):
    refreshed = loader(row[key])
    refreshed["priorAttempts"] = row.get("priorAttempts", []) + [
        {k: v for k, v in row.items() if k != "priorAttempts"}
    ]
    return refreshed


def jumbo_rows(cards):
    result = []
    for receipt in cards:
        identity = receipt.get("identity", {})
        details = [row for row in identity.get("variants_detailed", [])
                   if row.get("size", "").lower() == "jumbo"]
        if details:
            result.append({"providerCardID": receipt["requestedCardID"],
                           "name": identity.get("name"),
                           "localId": identity.get("localId"), "details": details})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", required=True, action="store_true")
    parser.add_argument("--set-id", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--retry-errors", action="store_true")
    args = parser.parse_args()
    if args.retry_errors:
        result = json.loads(args.output.read_text())
        if result["providerSetID"] != args.set_id:
            raise ValueError("Existing receipt belongs to another family")
    else:
        receipt, value = fetch(f"https://api.tcgdex.net/v2/en/sets/{args.set_id}")
        if value is None:
            raise RuntimeError(json.dumps(receipt))
        ids = [entry["id"] for entry in value["cards"]]
        if len(ids) != len(set(ids)):
            raise ValueError("Duplicate set member IDs")
        with ThreadPoolExecutor(max_workers=6) as pool:
            cards = list(pool.map(card, ids))
        result = {"schemaVersion": 1, "providerSetID": args.set_id,
                  "observedAtUTC": datetime.now(timezone.utc).isoformat(),
                  "purpose": "Price-free primary-source review evidence; unsigned, unpublished",
                  "setReceipt": receipt, "declaredCardCount": value.get("cardCount"),
                  "memberIDs": ids, "cards": cards, "products": []}

    if args.retry_errors:
        with ThreadPoolExecutor(max_workers=6) as pool:
            retries = list(pool.map(lambda row: retry(card, row, "requestedCardID"),
                                    [row for row in result["cards"] if transient(row)]))
        by_id = {row["requestedCardID"]: row for row in retries}
        result["cards"] = [by_id.get(row["requestedCardID"], row) for row in result["cards"]]
        result["lastRetryAtUTC"] = datetime.now(timezone.utc).isoformat()

    result["jumboCandidates"] = jumbo_rows(result["cards"])
    ids = sorted({detail.get("thirdParty", {}).get("tcgplayer")
                  for row in result["jumboCandidates"] for detail in row["details"]
                  if isinstance(detail.get("thirdParty", {}).get("tcgplayer"), int)
                  and detail["thirdParty"]["tcgplayer"] > 0})
    previous = {row["requestedProductID"]: row for row in result["products"]}
    def inspect(identity):
        old = previous.get(identity)
        if old is None:
            return product(identity)
        if args.retry_errors and transient(old):
            return retry(product, old, "requestedProductID")
        return old
    with ThreadPoolExecutor(max_workers=6) as pool:
        result["products"] = list(pool.map(inspect, ids))
    result["summary"] = {
        "members": len(result["memberIDs"]),
        "successfulCardReceipts": sum("identity" in row for row in result["cards"]),
        "jumboCardIdentities": len(result["jumboCandidates"]),
        "jumboDetailedObjects": sum(len(row["details"]) for row in result["jumboCandidates"]),
        "requestedProducts": len(ids),
        "successfulProductReceipts": sum("identity" in row for row in result["products"]),
        "failures": [{k: v for k, v in row.items() if k != "priorAttempts"}
                     for row in result["cards"] + result["products"] if "error" in row]
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(result["summary"]))


if __name__ == "__main__":
    main()
