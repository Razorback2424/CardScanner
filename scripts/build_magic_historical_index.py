#!/usr/bin/env python3
"""Reconcile a disabled EXO pilot by exact provider IDs; inventory all source rows.

AllPrintings is streamed one set at a time. No name join allocates a printing ID,
and a complete MTGJSON download never certifies a current Scryfall universe.
"""
import argparse
import gzip
import hashlib
import json
import unicodedata
from collections import Counter, defaultdict
from datetime import date
from pathlib import Path
from uuid import UUID

VERSION = 1


def canonical_title(value):
    return " ".join(unicodedata.normalize("NFC", value).lower().split())


def evidence_keys(card):
    names = [card.get("name", ""), card.get("faceName", "")]
    number = card.get("number", "")
    if not isinstance(number, str) or not number or number.strip() != number:
        return set()
    return {(canonical_title(name), number.lower()) for name in names if isinstance(name, str) and name.strip()}


def uuid(value):
    return str(UUID(value))


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


class JSONStream:
    """Bound memory by the largest set, and reject incomplete/trailing JSON."""
    def __init__(self, stream):
        self.stream = stream
        self.buffer = ""
        self.eof = False
        self.decoder = json.JSONDecoder(object_pairs_hook=self.unique_object)

    @staticmethod
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError("duplicate JSON key: " + key)
            result[key] = value
        return result

    def read(self):
        chunk = self.stream.read(256 * 1024)
        self.eof = not chunk
        self.buffer += chunk
        if len(self.buffer) > 64 * 1024 * 1024:
            raise ValueError("set exceeds bounded parser limit")

    def peek(self):
        self.buffer = self.buffer.lstrip()
        while not self.buffer and not self.eof:
            self.read()
            self.buffer = self.buffer.lstrip()
        return self.buffer[:1]

    def expect(self, character):
        if self.peek() != character:
            raise ValueError("expected JSON delimiter " + character)
        self.buffer = self.buffer[1:]

    def value(self):
        self.peek()
        while True:
            try:
                value, end = self.decoder.raw_decode(self.buffer)
                self.buffer = self.buffer[end:]
                return value
            except json.JSONDecodeError:
                if self.eof:
                    raise ValueError("incomplete or malformed MTGJSON input")
                self.read()


def all_printings(path, expected_meta):
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8") as stream:
        parser = JSONStream(stream)
        parser.expect("{")
        if parser.value() != "meta":
            raise ValueError("expected MTGJSON meta before data")
        parser.expect(":")
        if parser.value() != expected_meta:
            raise ValueError("pilot and AllPrintings metadata mismatch")
        parser.expect(",")
        if parser.value() != "data":
            raise ValueError("expected AllPrintings data")
        parser.expect(":")
        parser.expect("{")
        seen = set()
        while parser.peek() != "}":
            code = parser.value()
            if not isinstance(code, str) or code in seen:
                raise ValueError("duplicate or invalid set code")
            seen.add(code)
            parser.expect(":")
            value = parser.value()
            if not isinstance(value, dict) or value.get("code") != code:
                raise ValueError("set key/code mismatch")
            yield value
            if parser.peek() == "}":
                break
            parser.expect(",")
        parser.expect("}")
        parser.expect("}")
        if parser.peek():
            raise ValueError("trailing AllPrintings content")


def validate_page(page):
    if page.get("object") != "list" or page.get("has_more") is not False or "next_page" in page:
        raise ValueError("pilot requires a complete single-page Scryfall capture")
    rows = page.get("data")
    if not isinstance(rows, list) or page.get("total_cards") != len(rows) or page.get("warnings"):
        raise ValueError("incomplete or warned Scryfall page")
    result = {}
    for row in rows:
        printing_id = uuid(row["id"])
        if row.get("object") != "card" or printing_id in result:
            raise ValueError("invalid or duplicate Scryfall printing")
        result[printing_id] = row
    return result


def disposition(card, set_data, observed_day):
    if set_data.get("type") in {"memorabilia", "token", "minigame", "art_series"}:
        return "unsupported_layout_or_product"
    if "paper" not in card.get("availability", []):
        return "paper_unproven"
    if card.get("language") != "English":
        return "non_english_or_unknown"
    try:
        released = date.fromisoformat(set_data["releaseDate"])
        if released.isoformat() != set_data["releaseDate"]:
            return "release_unknown"
    except (KeyError, TypeError, ValueError):
        return "release_unknown"
    if released > observed_day:
        return "unreleased"
    if card.get("layout") != "normal" or card.get("isOversized") or card.get("isOnlineOnly"):
        return "unsupported_layout_or_product"
    if released < date(1998, 6, 15):
        return "phase_2"
    if released >= date(2014, 7, 18):
        return "outside_phase_1"
    return "phase_1_physical_review_pending"


def record_for_group(group, scryfall, descriptors, observed_day):
    """Same Scryfall ID may enclose linked faces, never finish-specific candidates."""
    first, set_data = group[0]
    source_ids = sorted(uuid(card["uuid"]) for card, _ in group)
    printing_id = uuid(first["identifiers"]["scryfallId"])
    for card, enclosing_set in group:
        if enclosing_set["code"] != set_data["code"] or card.get("number") != first.get("number"):
            raise ValueError("one provider ID has inconsistent set/collector identity")
        if card.get("layout") != first.get("layout") or card.get("language") != first.get("language"):
            raise ValueError("one provider ID has inconsistent layout/language")
        if len(group) > 1 or card.get("otherFaceIds"):
            linked = {uuid(value) for value in card.get("otherFaceIds", [])}
            if linked != set(source_ids) - {uuid(card["uuid"])}:
                raise ValueError("duplicate provider ID without complete reciprocal face links")
    aliases = sorted({card.get("faceName") for card, _ in group if card.get("faceName")})
    finishes = sorted(set(first.get("finishes", [])))
    if not finishes or any(set(card.get("finishes", [])) != set(finishes) for card, _ in group):
        raise ValueError("inconsistent or missing finishes")
    finish_refs = defaultdict(set)
    for card, _ in group:
        for finish, source_ref in card.get("skuIds", {}).items():
            if finish not in finishes:
                raise ValueError("finish reference contradicts supported finishes")
            finish_refs[finish].add(uuid(source_ref))
    verified = printing_id in scryfall
    provider = scryfall.get(printing_id, {})
    if verified:
        descriptor = descriptors.get(set_data["code"].lower())
        if not descriptor or provider.get("set_id") != descriptor["scryfallSetID"]:
            raise ValueError("Scryfall set identity differs from bundled descriptor")
        checks = [provider.get("set", "").lower() == set_data["code"].lower(),
                  provider.get("collector_number") == first["number"],
                  provider.get("name") == first["name"], provider.get("lang") == "en",
                  first.get("language") == "English", provider.get("layout") == first.get("layout"),
                  provider.get("released_at") == set_data.get("releaseDate"),
                  "paper" in provider.get("games", []), "paper" in first.get("availability", []),
                  provider.get("oversized") is False, not first.get("isOversized", False),
                  not first.get("isOnlineOnly", False), set(provider.get("finishes", [])) == set(finishes)]
        artwork = first.get("identifiers", {}).get("scryfallIllustrationId")
        if artwork and provider.get("illustration_id") and artwork != provider["illustration_id"]:
            checks.append(False)
        if not all(checks):
            raise ValueError("exact-ID provider metadata disagreement")
    released = set_data.get("releaseDate")
    route = "unknown"
    if released:
        day = date.fromisoformat(released)
        route = ("modernFooter" if day >= date(2014, 7, 18) else
                 "legacyCollectorNumber" if day >= date(1998, 6, 15) else "legacyNoCollectorNumber")
    return {
        "printingID": printing_id, "sourceIDs": source_ids,
        "setCode": set_data["code"].lower(), "setName": set_data["name"],
        "setID": provider.get("set_id"), "collectorNumber": first["number"],
        "name": first["name"], "aliases": aliases, "releaseDate": released,
        "language": "en" if first.get("language") == "English" else first.get("language", "unknown"),
        "layout": first.get("layout", "unknown"), "finishes": finishes,
        "sourceFinishReferences": {finish: sorted(refs) for finish, refs in sorted(finish_refs.items())},
        "paper": "paper" in first.get("availability", []), "reconciled": verified,
        "visibleCollectorNumber": None, "route": route,
        "unresolvedDistinctions": ["physical_review_pending"] if verified else ["scryfall_crosswalk_unverified"],
        "frame": provider.get("frame", first.get("frameVersion")),
        "artworkID": provider.get("illustration_id", first.get("identifiers", {}).get("scryfallIllustrationId")),
        "thumbnailURL": provider.get("image_uris", {}).get("small"),
        "disposition": disposition(first, set_data, observed_day),
    }


def build(args):
    pilot_raw = json.loads(args.pilot.read_text())
    pilot = pilot_raw["data"]
    if pilot.get("code") != "EXO":
        raise ValueError("only the EXO disabled pilot is reviewed in processing version 1")
    page = validate_page(json.loads(args.scryfall.read_text()))
    catalog = json.loads(args.catalog.read_text())
    if catalog.get("schemaVersion") != 1 or catalog.get("catalogKind") != "magic":
        raise ValueError("expected schema-1 catalog context")
    descriptors = {row["code"].lower(): row for row in catalog["sets"]}
    keys = set().union(*(evidence_keys(card) for card in pilot["cards"]))
    groups = defaultdict(list)
    unresolved_keys = set()
    counts = Counter()
    seen_source_ids = set()
    seen_pilot = False
    args.output.mkdir(parents=True, exist_ok=True)
    ledger_path = args.output / "reconciliation-ledger.jsonl"
    with ledger_path.open("w") as ledger:
        for set_data in all_printings(args.all_printings, pilot_raw["meta"]):
            if set_data["code"] == "EXO":
                if set_data != pilot:
                    raise ValueError("EXO capture differs from AllPrintings")
                seen_pilot = True
            all_rows = set_data.get("cards", []) + set_data.get("tokens", [])
            matching_ids = {card.get("identifiers", {}).get("scryfallId") for card in all_rows
                            if evidence_keys(card) & keys}
            for card in all_rows:
                source_id = uuid(card["uuid"])
                if source_id in seen_source_ids:
                    raise ValueError("duplicate MTGJSON source UUID")
                seen_source_ids.add(source_id)
                state = disposition(card, set_data, args.observed_on)
                matches = evidence_keys(card) & keys
                raw_id = card.get("identifiers", {}).get("scryfallId")
                try:
                    printing_id = uuid(raw_id)
                except (ValueError, TypeError, AttributeError):
                    printing_id = None
                    if matches:
                        unresolved_keys.update(matches)
                    state = "missing_or_invalid_crosswalk"
                counts[state] += 1
                ledger.write(json.dumps({"sourceID": source_id, "printingID": printing_id,
                    "setCode": set_data["code"], "collectorNumber": card.get("number"),
                    "name": card.get("name"), "disposition": state,
                    "crossEraPilotMatch": bool(matches)}, sort_keys=True) + "\n")
                if printing_id and (matches or raw_id in matching_ids):
                    groups[printing_id].append((card, set_data))
    if not seen_pilot:
        raise ValueError("pilot set missing from AllPrintings")
    records = []
    rejected = []
    for printing_id, group in sorted(groups.items()):
        try:
            records.append(record_for_group(group, page, descriptors, args.observed_on))
        except (ValueError, KeyError, TypeError) as error:
            unresolved_keys.update(set().union(*(evidence_keys(card) & keys for card, _ in group)))
            rejected.append({"printingID": printing_id, "sourceIDs": [card["uuid"] for card, _ in group],
                             "reason": str(error)})
    # No partial pilot capture, source omission or skipped identity can certify uniqueness.
    admitted = {row["printingID"] for row in records if row["reconciled"]}
    if admitted != set(page):
        raise ValueError("not every captured Scryfall printing reconciled exactly")
    sources = [
        {"kind": "mtgjsonAllPrintings", "url": "https://mtgjson.com/api/v5/AllPrintings.json.gz",
         "sha256": digest(args.all_printings), "dataDate": pilot_raw["meta"]["date"]},
        {"kind": "mtgjsonPilot", "url": "https://mtgjson.com/api/v5/EXO.json",
         "sha256": digest(args.pilot), "dataDate": pilot_raw["meta"]["date"]},
        {"kind": "scryfallPilot", "url": "https://api.scryfall.com/cards/search?q=set%3Aexo%20lang%3Aen&unique=prints",
         "sha256": digest(args.scryfall), "dataDate": args.observed_on.isoformat()},
    ]
    artifact = {"schemaVersion": 1, "processingVersion": VERSION, "profileVersion": 1,
        "observedOn": args.observed_on.isoformat(), "catalog": catalog, "sources": sources,
        "records": records,
        "coverage": {"completeKeys": [], "keyReceipts": [], "unresolvedKeys": [dict(title=title, collectorNumber=number)
                      for title, number in sorted(unresolved_keys)], "validUntil": None,
                     "sourceContext": None, "missingSources": ["scryfall_cross_era_reconciliation", "physical_number_review"]}}
    output = args.output / "pilot-index.json"
    output.write_text(json.dumps(artifact, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n")
    report = {"processingVersion": VERSION, "observedOn": args.observed_on.isoformat(),
        "sources": sources, "sourceRows": len(seen_source_ids), "countsByDisposition": dict(sorted(counts.items())),
        "reconciledPilotPrintings": len(admitted), "projectionPrintings": len(records),
        "unverifiedCollisionPrintings": sum(not row["reconciled"] for row in records),
        "unresolvedKeys": len(unresolved_keys), "rejectedGroups": rejected,
        "artifactBytes": output.stat().st_size, "artifactSHA256": digest(output),
        "ledgerSHA256": digest(ledger_path), "automaticUniquenessEnabled": False,
        "physicalPrintingDenominator": None, "catalogSHA256": digest(args.catalog)}
    (args.output / "reconciliation-report.json").write_text(json.dumps(report, sort_keys=True, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all-printings", type=Path, required=True)
    parser.add_argument("--pilot", type=Path, required=True)
    parser.add_argument("--scryfall", type=Path, required=True)
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--observed-on", type=date.fromisoformat, required=True)
    args = parser.parse_args()
    print(json.dumps(build(args), sort_keys=True))


if __name__ == "__main__":
    main()
