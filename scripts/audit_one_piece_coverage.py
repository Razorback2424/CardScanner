#!/usr/bin/env python3
"""Compare every listed English Bandai card presentation with a One Piece release."""

import argparse
import base64
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
import fcntl
import hashlib
import json
from pathlib import Path
import re
from urllib.parse import parse_qs, urlsplit

from capture_one_piece_products import ProductCapture, atomic_json, safe_path
from discover_one_piece_products import SERIES_INDEX, prefixes, retained
from normalize_one_piece_sources import Document, one
from reconcile_one_piece_launch_products import normalized_name


PRINTED_NUMBER = re.compile(r"[A-Z]{1,8}[0-9]{0,3}-[0-9]{3}")
BROWSE_DISCOVERY = "manufacturer-browse-discovery"


def series_options(document):
    select = one((n for n in document.nodes("select") if n.attrs.get("name") == "series"), "Bandai series selector")
    options = [n for n in select.nodes("option") if n.attrs.get("value")]
    series = {n.attrs["value"]: re.sub(r"<br\b[^>]*>", " ", n.text()).strip() for n in options}
    if not series or len(series) != len(options) or any(not key.isascii() or not key.isdigit() for key in series):
        raise ValueError("Invalid or duplicate English Bandai series")
    return series


def parse_cardlist(raw, series_id):
    document = Document(raw).root
    select = one((n for n in document.nodes("select") if n.attrs.get("name") == "series"), "Bandai series selector")
    selected = one((n for n in select.nodes("option") if "selected" in n.attrs), "selected Bandai series")
    if selected.attrs.get("value") != series_id:
        raise ValueError("Bandai response is for a different series: " + series_id)
    advertised = re.fullmatch(r"([0-9,]+) results?", one(document.nodes(cls="countCol"), "card count").text())
    modals = list(document.nodes("dl", "modalCol"))
    if not advertised or int(advertised[1].replace(",", "")) != len(modals):
        raise ValueError("Incomplete Bandai card list: " + series_id)
    rows = []
    for modal in modals:
        alias = modal.attrs.get("id", "")
        name = one(modal.nodes(cls="cardName"), "card name").text()
        numbers = {span.text() for info in modal.nodes(cls="infoCol") for span in info.nodes("span")
                   if PRINTED_NUMBER.fullmatch(span.text()) and not span.text().startswith("DON-")}
        if len(numbers) > 1:
            raise ValueError("Contradictory printed numbers for " + alias)
        product_labels = [node.text(exclude={"h3"}) for node in modal.nodes(cls="getInfo")
                          if any(h.text() == "Card Set(s)" for h in node.nodes("h3"))]
        rows.append({"number": next(iter(numbers), None), "name": name, "artworkAlias": alias,
                     "productLabels": product_labels})
    aliases = [row["artworkAlias"] for row in rows if row["number"] is not None]
    if "" in aliases or len(set(aliases)) != len(aliases):
        raise ValueError("Missing or duplicate numbered artwork alias in " + series_id)
    return rows


def capture_inventory(capture, requested=()):
    index, raw = retained(capture, SERIES_INDEX, "cardlist-series-index.html")
    options = series_options(Document(raw).root)
    if set(requested) - options.keys():
        raise ValueError("Requested series missing from the official directory")

    def read_series(item):
        series_id, label = item
        url = "https://en.onepiece-cardgame.com/cardlist/?series=" + series_id
        record, raw = retained(capture, url, "bandai-" + series_id + ".html")
        return {"seriesID": series_id, "label": label, "source": record, "rows": parse_cardlist(raw, series_id)}

    scope = [(key, label) for key, label in options.items() if not requested or key in requested]
    # The default card-list URL is already captured by the index read above.
    with ThreadPoolExecutor(max_workers=4) as workers:
        return index, list(workers.map(read_series, scope))


def bandai_row_key(observation):
    source = urlsplit(observation["sourceURL"])
    series = parse_qs(source.query).get("series", [])
    if (observation["alias"]["provider"] != "bandai" or source.scheme != "https"
            or source.netloc != "en.onepiece-cardgame.com" or source.path != "/cardlist/" or len(series) != 1):
        return None
    fields = observation["printedEvidence"]
    return series[0], fields.get("sourceArtworkAlias", observation["alias"]["sourceID"]), fields.get("number")


def compare(inventory, release):
    registry = release["registry"]
    cards = {card["id"]: card for card in registry["canonicalCards"] if card["language"] == "en"}
    names = {card["printedNumber"]: normalized_name(card["name"]) for card in cards.values()}
    observations = {row["id"]: row for row in release["observations"]}
    browse_sources = {bandai_row_key(row) for row in observations.values()
                      if row["printedEvidence"].get("sourceRole") == BROWSE_DISCOVERY}
    appearance_evidence = defaultdict(set)
    for appearance in registry["appearances"]:
        appearance_evidence[appearance["printingID"]].update(appearance["observationIDs"])
    by_source = defaultdict(dict)
    for printing in registry["printings"]:
        card = cards.get(printing["canonicalCardID"])
        if not card or printing["status"] not in {"verified", "provisional", "conflicted"}:
            continue
        evidence = {e["observationID"] for e in (printing.get("review") or {}).get("evidence", [])
                    if e["kind"] == "printedIdentity" and printing.get("releaseID") in
                    observations[e["observationID"]]["productEvidence"]} | appearance_evidence[printing["id"]]
        for observation_id in evidence:
            key = bandai_row_key(observations[observation_id])
            if key and key[2] == card["printedNumber"]:
                by_source[key][printing["id"]] = printing

    result = []
    for series in inventory:
        counts = Counter()
        rows = []
        for row in series["rows"]:
            number = row["number"]
            source_key = (series["seriesID"], row["artworkAlias"], number)
            members = by_source[source_key]
            if number is None:
                is_don = row["name"].upper().startswith("DON!!") or re.fullmatch(r"DON(?:[-_].*)?", row["artworkAlias"].upper())
                status = "don-outside-numbered-scope" if is_don else "unclassified"
            elif number not in names:
                status = "missing-number"
            elif normalized_name(row["name"]) != names[number]:
                status = "name-disagreement"
            elif not members:
                status = "missing-printing-or-appearance"
            elif len(members) > 1:
                status = "ambiguous-source-join"
            else:
                printing = next(iter(members.values()))
                status = "verified" if printing["status"] == "verified" else "held"
            counts[status] += 1
            rows.append({**row, "status": status, "printingIDs": sorted(members),
                         "browseDiscovery": source_key in browse_sources,
                         "verifiedFinishIDs": sorted(next(iter(members.values()))["supportedVariantIDs"])
                         if status == "verified" else []})
        result.append({**series, "rows": rows, "counts": dict(sorted(counts.items()))})
    return result


def discovery_inputs(release, report):
    """Project official gaps as read-only observations, without allocating physical IDs."""
    registry = dict(release["registry"])
    cards = {card["id"]: card for card in registry["canonicalCards"]}
    products = {product["id"]: product for product in registry["products"]}
    printings = {row["id"]: row for row in registry["printings"]}
    observations = {row["id"]: row for row in release["observations"]}
    newly_inventoried = defaultdict(list)
    retired = set()
    names = defaultdict(set)
    for series in report:
        for row in series["rows"]:
            if row["status"] == "missing-number":
                names[row["number"]].add(normalized_name(row["name"]))

    for series in report:
        source = series["source"]
        series_id = series["seriesID"]
        primary = {printings[pid].get("releaseID") for row in series["rows"]
                   if row["status"] in {"verified", "held"} for pid in row["printingIDs"]} - {None}
        # The two aggregate Bandai lists contain many independent products.
        product_id = next(iter(primary)) if prefixes(series["label"]) and len(primary) == 1 else f"product:bandai-series:{series_id}"
        for row in series["rows"]:
            number = row["number"]
            identity = f"bandai-browse:{series_id}:{row['artworkAlias']}"
            previous = observations.get(identity)
            if (row["status"] in {"verified", "held"} and previous and
                    previous["printedEvidence"].get("sourceRole") == BROWSE_DISCOVERY):
                retired.add(identity)
            if row["status"] not in {"missing-number", "missing-printing-or-appearance"}:
                continue
            card_id = "one-piece:en:" + number
            if card_id not in cards and len(names[number]) != 1:
                continue
            cards.setdefault(card_id, {"id": card_id, "printedNumber": number, "language": "en",
                                       "name": row["name"], "printingCoverageComplete": False})
            # Keep a positive certification from becoming stale when an official
            # additional presentation is found for that family.
            if cards[card_id]["printingCoverageComplete"]:
                card = dict(cards[card_id], printingCoverageComplete=False)
                card.pop("coverageReviewReference", None)
                cards[card_id] = card
            label = " | ".join(dict.fromkeys(row["productLabels"]))
            if previous is not None:
                if (label and previous["printedEvidence"].get("sourceRole") == BROWSE_DISCOVERY
                        and "productLabel" not in previous["printedEvidence"]
                        and previous["sourceURL"] == source["sourceURL"]
                        and previous["payloadSHA256"] == source["payloadSHA256"]):
                    # The label comes from the same retained Bandai receipt.
                    observations[identity] = dict(
                        previous, printedEvidence=dict(previous["printedEvidence"], productLabel=label))
                continue
            products.setdefault(product_id, {"id": product_id, "label": series["label"]})
            fields = {"sourceRole": BROWSE_DISCOVERY, "number": number,
                      "name": row["name"], "sourceArtworkAlias": row["artworkAlias"]}
            if label:
                fields["productLabel"] = label
            observations[identity] = {"id": identity, "kind": "catalog", "language": "en",
                                      "alias": {"provider": "bandai", "sourceID": identity},
                                      "sourceURL": source["sourceURL"], "observedAt": source["observedAt"],
                                      "payloadSHA256": source["payloadSHA256"], "productEvidence": [product_id],
                                      "printedEvidence": fields}
            newly_inventoried[(series_id, source["payloadSHA256"])].append(identity)
    registry["canonicalCards"] = list(cards.values())
    registry["products"] = list(products.values())
    inventories = {(row["provider"], row["snapshotID"]):
                   dict(row, observationIDs=[oid for oid in row["observationIDs"] if oid not in retired])
                   for row in release["inventories"]}
    for (series_id, sha), ids in newly_inventoried.items():
        snapshot = f"browse:{series_id}:{sha}"
        record = inventories.setdefault(("bandai", snapshot), {"provider": "bandai", "snapshotID": snapshot,
                                                              "paginationComplete": True, "observationIDs": []})
        record["observationIDs"].extend(ids)
    return {"registry": registry, "observations": [row for key, row in observations.items() if key not in retired],
            "inventories": list(inventories.values())}


def applying_reviewed_additions(release, additions):
    """Retain existing records and add explicit, separately reviewed physical records."""
    def merge(current, new, identity):
        records = {identity(row): row for row in current}
        for row in new:
            old = records.setdefault(identity(row), row)
            if old != row:
                raise ValueError("Reviewed additions would replace a retained record: " + str(identity(row)))
        return list(records.values())

    keys = {"artworks", "printings", "observations", "inventories"}
    if not keys <= additions.keys() or additions.keys() - keys - {"products", "finishUpdates", "productUpdates"}:
        raise ValueError("Invalid reviewed additions fields")
    registry = dict(release["registry"])
    for key in ("artworks", "printings"):
        registry[key] = merge(registry[key], additions[key], lambda row: row["id"].lower())
    if "products" in additions:
        registry["products"] = merge(registry["products"], additions["products"], lambda row: row["id"])
    if additions.get("productUpdates"):
        registry["products"] = apply_product_updates(registry["products"], additions["productUpdates"])
    observations = merge(release["observations"], additions["observations"], lambda row: row["id"])
    if additions.get("finishUpdates"):
        registry["printings"] = apply_finish_updates(registry, observations, additions["finishUpdates"])
    return dict(release, registry=registry,
                observations=observations,
                inventories=merge(release["inventories"], additions["inventories"],
                                  lambda row: (row["provider"], row["snapshotID"])))


def apply_product_updates(products, updates):
    """Name and date a retained product from its official Bandai product page.

    A card-list discovery only knows the raw series label and no release date,
    so Browse cannot order it. The product ID, and every printing's release
    reference to it, stays the same.
    """
    by_id = {row["id"]: row for row in products}
    for update in updates:
        if set(update) != {"id", "label", "releaseDate", "sourceURL"} or update["id"] not in by_id:
            raise ValueError("Product updates must name a retained product: " + str(update.get("id")))
        source = urlsplit(update["sourceURL"])
        if (source.scheme, source.netloc) != ("https", "en.onepiece-cardgame.com") or \
                not source.path.startswith("/products/"):
            raise ValueError("Product updates require an official English Bandai product page")
        if not update["label"].strip() or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", update["releaseDate"]):
            raise ValueError("Product updates require a label and an ISO release date")
        by_id[update["id"]] = {"id": update["id"], "label": update["label"], "releaseDate": update["releaseDate"]}
    return [by_id[row["id"]] for row in products]


def apply_finish_updates(registry, observations, updates):
    """Promote a retained provisional printing only with evidence for its exact artwork."""
    printings = {row["id"].lower(): row for row in registry["printings"]}
    artworks = {row["id"]: row for row in registry["artworks"]}
    cards = {row["id"]: row for row in registry["canonicalCards"]}
    by_observation = {row["id"]: row for row in observations}
    finish_ids = {row["id"] for row in registry["variants"]}
    for update in updates:
        key = update["printingID"].lower()
        old = printings[key]
        observation = by_observation[update["observationID"]]
        fields = observation["printedEvidence"]
        finish = fields.get("finishVariantID")
        alias = observation["alias"]
        source = urlsplit(observation["sourceURL"])
        artwork_hash = artworks[old["artworkID"]].get("imageSHA256")
        if (observation["kind"] != "catalog" or alias["provider"] != "coretcg"
                or source.scheme != "https" or source.netloc != "coretcg.com"
                or fields.get("sourceRole") != "retailer-exact-printing-specification"
                or observation["language"] != old["language"]
                or fields.get("number") != cards[old["canonicalCardID"]]["printedNumber"]
                or old["releaseID"] not in observation["productEvidence"]
                or fields.get("treatment") != old.get("treatment")
                or not artwork_hash or fields.get("matchedBandaiImageSHA256") != artwork_hash
                or finish not in finish_ids or old.get("review") is None):
            raise ValueError("Finish review does not match the retained printing: " + old["id"])
        evidence = old["review"]["evidence"]
        if (old["status"] == "verified" and old["supportedVariantIDs"] == [finish]
                and alias in old["sourceAliases"] and any(item["kind"] == "finish" and
                item["observationID"] == observation["id"] for item in evidence)):
            continue
        if old["status"] != "provisional" or old["supportedVariantIDs"]:
            raise ValueError("Finish review requires a provisional printing without finish authority: " + old["id"])
        finish_evidence = {"kind": "finish", "observationID": observation["id"],
                           "detail": "An exact retailer artwork match identifies the retained printing and its English finish."}
        aliases = old["sourceAliases"] if alias in old["sourceAliases"] else [*old["sourceAliases"], alias]
        printings[key] = dict(old, status="verified", supportedVariantIDs=[finish], sourceAliases=aliases,
                              review=dict(old["review"], evidence=[*evidence, finish_evidence]))
    return list(printings.values())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--capture-root", type=Path, required=True)
    parser.add_argument("--release", type=Path, required=True, help="Verified envelope or unsigned candidate under review")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--series", action="append", default=[])
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--discovery-inputs", type=Path, help="Write unsigned registry, observations, and inventories for publisher review")
    parser.add_argument("--reviewed-additions", type=Path, action="append", default=[],
                        help="Add explicitly reviewed physical records to the discovery inputs")
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("Coverage report already exists")
    if args.discovery_inputs is not None and args.discovery_inputs.exists():
        raise ValueError("Discovery inputs directory already exists")
    if args.reviewed_additions and args.discovery_inputs is None:
        parser.error("--reviewed-additions requires --discovery-inputs")
    payload = args.release.read_bytes()
    release = json.loads(payload)
    if "payload" in release:
        payload = base64.urlsafe_b64decode(release["payload"] + "===")
        release = json.loads(payload)
    args.capture_root.mkdir(parents=True, exist_ok=True)
    with safe_path(args.capture_root, ".product-capture.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        capture = ProductCapture(args.capture_root, offline=args.offline)
        index, inventory = capture_inventory(capture, args.series)
        result = compare(inventory, release)
        counts = Counter()
        for series in result:
            counts.update(series["counts"])
        atomic_json(args.output, {"schemaVersion": 1, "sourceIndex": index, "requestedSeries": args.series,
                                 "revision": release["revision"], "payloadSHA256": hashlib.sha256(payload).hexdigest(),
                                 "counts": dict(sorted(counts.items())), "series": result})
        if args.discovery_inputs is not None:
            inputs = discovery_inputs(release, result)
            if args.reviewed_additions:
                candidate = dict(release, **inputs)
                for path in args.reviewed_additions:
                    candidate = applying_reviewed_additions(candidate, json.loads(path.read_bytes()))
                inputs = discovery_inputs(candidate, compare(inventory, candidate))
            args.discovery_inputs.mkdir()
            for key, rows in inputs.items():
                atomic_json(args.discovery_inputs / (key + ".json"), rows)
    print(f"Compared {sum(counts.values())} official rows in {len(result)} series: {dict(sorted(counts.items()))}")


if __name__ == "__main__":
    main()
