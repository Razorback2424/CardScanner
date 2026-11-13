#!/usr/bin/env python3
"""Build physical printing additions from retained Bandai fixed foil products."""

import argparse
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
import re
import unicodedata
from urllib.parse import parse_qs, urljoin, urlsplit
from uuid import NAMESPACE_URL, uuid5

from audit_one_piece_coverage import parse_cardlist
from capture_one_piece_products import atomic_json, checked_url
from normalize_one_piece_sources import Document, one
from reconcile_one_piece_launch_products import capture_index, checked_capture


FOIL_COUNT = re.compile(r"・Card(?: x\s*(\d+) \(Holo\+Textured Foil\)| \(Holo\+Textured Foil\) x\s*(\d+))")
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
TREATMENT = "Holo and textured foil"


def fixed_foil_count(raw, rule):
    fields = {}
    for box in Document(raw).root.nodes(cls="prodStatusBox"):
        heading = one(box.nodes(cls="prodStatusTit"), "product specification heading").text()
        value = one(box.nodes(cls="prodStatusContents"), "product specification value")
        if heading in fields:
            raise ValueError("Duplicate product specification field")
        fields[heading] = value
    if fields["Product Name"].text() != rule["specificationTitle"]:
        raise ValueError("Bandai product specification is for a different title")
    contents = fields["Contents"]
    if contents.text() != rule["specificationContents"]:
        raise ValueError("Bandai fixed foil contents changed")
    foil = one((match for line in contents.nodes("li")
                if (match := FOIL_COUNT.fullmatch(unicodedata.normalize("NFKC", line.text())))),
               "fixed foil quantity")
    return int(foil[1] or foil[2])


def event_artwork_urls(raw, rule):
    section = one((node for node in Document(raw).root.nodes("section")
                   if node.attrs.get("id") == rule["eventSectionID"]), "Bandai event section")
    heading = one(section.nodes("h5", "smallTit"), "Bandai event product title")
    if heading.text() != rule["specificationTitle"]:
        raise ValueError("Bandai event specification is for a different title")
    notes = [node.text() for block in section.nodes("ul", "commonNoticeList") for node in block.nodes("li")]
    if notes.count("*Holo+Textured foil") != 1:
        raise ValueError("Bandai event section does not specify holo and textured foil")
    featured = one(section.nodes("ul", "cardPopupWrap"), "Bandai featured card list")
    urls = [urljoin(rule["specificationURL"], link.attrs["href"]) for link in featured.nodes("a", "js_modalOpenImage")]
    if not urls or len(urls) != len(set(urls)):
        raise ValueError("Bandai event card images are missing or duplicated")
    return urls


def png_pixels(raw):
    from PIL import Image

    with Image.open(BytesIO(raw)) as image:
        if image.format != "PNG":
            raise ValueError("Expected a Bandai PNG reference")
        return image.size, image.convert("RGB").tobytes()


def reconcile(rules, cardlist_root, specification_root):
    def captures(root):
        records = json.loads((root / "capture-manifest.json").read_bytes())["captures"]
        return capture_index(records, "sourceURL")

    def retained(root, records, url, digest=None):
        checked_url(url, "en.onepiece-cardgame.com")
        record = records[url]
        if digest is not None and record["payloadSHA256"] != digest:
            raise ValueError("Bandai capture differs from the reviewed bytes")
        return record, checked_capture(root, record)

    if rules["schemaVersion"] != 1:
        raise ValueError("Unsupported fixed foil review rules")
    cardlist = captures(cardlist_root)
    specifications = captures(specification_root)
    url = rules["cardList"]["sourceURL"]
    parsed = urlsplit(url)
    if parsed.path != "/cardlist/":
        raise ValueError("Expected an official card-list page")
    series = one(parse_qs(parsed.query).get("series", []), "Bandai card-list series")
    list_source, list_bytes = retained(cardlist_root, cardlist, url, rules["cardList"]["payloadSHA256"])
    rows = parse_cardlist(list_bytes, series)
    modals = {node.attrs.get("id"): node for node in Document(list_bytes).root.nodes("dl", "modalCol")}
    products = capture_index(rules["products"], "id")
    if len(products) != len(rules["products"]) or not products:
        raise ValueError("Missing or duplicate reviewed product")

    result = {key: [] for key in ("products", "artworks", "printings", "observations", "inventories")}
    reviewed_aliases = set()
    for product_id, rule in sorted(products.items()):
        specification_url = rule["specificationURL"]
        event = "eventSectionID" in rule
        if not urlsplit(specification_url).path.startswith("/events/" if event else "/products/"):
            raise ValueError("Expected a Bandai specification page for the reviewed release")
        spec_source, spec_bytes = retained(specification_root, specifications, specification_url,
                                           rule["specificationSHA256"])
        selected = [row for row in rows if rule["label"] in row["productLabels"]]
        if event:
            if len({row["number"] for row in selected}) != len(selected):
                raise ValueError("Bandai event needs distinct collector numbers within the distribution")
            aliases = set(rule["artworkAliases"])
            selected = [row for row in selected if row["artworkAlias"] in aliases]
            if not aliases or len(selected) != len(aliases):
                raise ValueError("Bandai event aliases do not match the official distribution")
            event_images = [retained(specification_root, specifications, image_url)
                            for image_url in event_artwork_urls(spec_bytes, rule)]
            event_images = [(source, png_pixels(png)) for source, png in event_images]
        elif len(selected) != fixed_foil_count(spec_bytes, rule) or not selected:
            raise ValueError("Official card list does not match the fixed foil quantity")
        result["products"].append({"id": product_id, "label": rule["label"]})
        observation_ids = []
        for row in sorted(selected, key=lambda member: member["artworkAlias"]):
            number, alias = row["number"], row["artworkAlias"]
            if not number or alias in reviewed_aliases or row["productLabels"] != [rule["label"]]:
                raise ValueError("Fixed foil artwork has ambiguous product membership")
            reviewed_aliases.add(alias)
            image = one((node for node in modals[alias].nodes("img") if "data-src" in node.attrs),
                        "Bandai artwork image")
            image_url = urljoin(url, image.attrs["data-src"])
            if urlsplit(image_url).path != f"/images/cardlist/card/{alias}.png":
                raise ValueError("Bandai artwork image does not match the card-list alias")
            art_source, png = retained(specification_root, specifications, image_url)
            if not png.startswith(PNG_SIGNATURE):
                raise ValueError("Bandai reference image is not PNG")
            source_id = f"{product_id}:{alias}"
            source_alias = {"provider": "bandai", "sourceID": source_id}
            artwork_id = str(uuid5(NAMESPACE_URL, f"{url}#{source_id}/artwork")).upper()
            printing_id = str(uuid5(NAMESPACE_URL, f"{url}#{source_id}/printing")).upper()
            evidence = []
            sources = [
                ("list", list_source, {"productLabel": rule["label"]},
                 {"printedIdentity": "Exact alias in the English card list.", "language": "English card list.",
                  "release": "The card list identifies this exact release." if event else
                  "The card list identifies this exact fixed product."}),
                ("render", art_source, {"sourceRole": "watermarked-digital-render"},
                 {"artwork": "Captured Bandai artwork fingerprint for the exact alias."}),
                ("specification", spec_source, {"sourceRole": "manufacturer-physical-product-specification",
                  "treatment": TREATMENT, "finishVariantID": "foil"},
                 {"finish": "Bandai specifies holo and textured foil for this event's featured card list." if event else
                  "Bandai lists the full numbered product contents as holo and textured foil.",
                  "treatment": "Bandai specifies holo and textured foil for this product."}),
            ]
            if event:
                pixels = png_pixels(png)
                featured = one((source for source, event_pixels in event_images if event_pixels == pixels),
                               "exact Bandai event artwork")
                sources.append(("event-artwork", featured, {"sourceRole": "event-featured-card",
                                "distribution": rule["label"]},
                                {"distribution": "Bandai's featured card has identical pixels to this card-list alias."}))
            for role, source, fields, claims in sources:
                observation_id = f"{source_id}:{role}"
                observation = {"id": observation_id, "kind": "catalog", "language": "en", "alias": source_alias,
                               "sourceURL": source["sourceURL"], "observedAt": source["observedAt"],
                               "payloadSHA256": source["payloadSHA256"], "productEvidence": [product_id],
                               "printedEvidence": dict(fields, number=number, sourceArtworkAlias=alias)}
                if role == "render":
                    observation["imageSHA256"] = source["payloadSHA256"]
                result["observations"].append(observation)
                observation_ids.append(observation_id)
                evidence.extend({"kind": kind, "observationID": observation_id, "detail": detail}
                                for kind, detail in claims.items())
            result["artworks"].append({"id": artwork_id, "imageSHA256": art_source["payloadSHA256"],
                                       "observationIDs": [source_id + ":render"]})
            result["printings"].append({"id": printing_id, "canonicalCardID": "one-piece:en:" + number,
                                        "artworkID": artwork_id, "language": "en", "releaseID": product_id,
                                        "treatment": TREATMENT, "status": "verified", "supportedVariantIDs": ["foil"],
                                        "sourceAliases": [source_alias], "marketMappings": [], "supersedes": [],
                                        "review": {"reference": specification_url, "evidence": evidence}})
            if event:
                result["printings"][-1]["distributionLabel"] = rule["label"]
        inventory_id = product_id + ":fixed-foil"
        if event:
            membership = sha256(json.dumps(observation_ids, separators=(",", ":")).encode()).hexdigest()
            inventory_id = product_id + ":event-foil:" + membership
        result["inventories"].append({"provider": "bandai", "snapshotID": inventory_id,
                                      "paginationComplete": not event, "observationIDs": observation_ids})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rules", type=Path, required=True)
    parser.add_argument("--cardlist-captures", type=Path, required=True)
    parser.add_argument("--specification-captures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise ValueError("Fixed foil additions already exist")
    result = reconcile(json.loads(args.rules.read_bytes()), args.cardlist_captures, args.specification_captures)
    atomic_json(args.output, result)
    print(f"Reconciled {len(result['printings'])} exact foil printings in {len(result['products'])} fixed products")


if __name__ == "__main__":
    main()
