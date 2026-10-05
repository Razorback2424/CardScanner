#!/usr/bin/env python3
"""Normalize retained Bandai/Limitless HTML into review-only catalog observations.

No provider row allocates a physical UUID, assigns a finish, or grants completeness.
Raw captures and images are not copied into the repository or application bundle.
"""
import argparse
from datetime import datetime
import hashlib
from html.parser import HTMLParser
import json
from pathlib import Path
import re
from urllib.parse import urljoin, urlsplit, parse_qs, urlencode

MAX_BYTES = 5 * 1024 * 1024
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}
NUMBER = re.compile(r"(?:OP|ST|EB|PRB)\d{2}-\d{3}|P-\d{3}")


class Node:
    def __init__(self, tag, attrs=()):
        self.tag, self.attrs, self.children = tag, dict(attrs), []

    def nodes(self, tag=None, cls=None):
        for child in self.children:
            if isinstance(child, Node):
                if (tag is None or child.tag == tag) and (cls is None or cls in child.attrs.get("class", "").split()):
                    yield child
                yield from child.nodes(tag, cls)

    def text(self, exclude=()):
        pieces = []
        for child in self.children:
            if isinstance(child, str):
                pieces.append(child)
            elif child.tag not in exclude:
                pieces.append(child.text(exclude))
        return " ".join(" ".join(pieces).split())


class Document(HTMLParser):
    def __init__(self, payload):
        super().__init__(convert_charrefs=True)
        if len(payload) > MAX_BYTES:
            raise ValueError("capture exceeds byte limit")
        self.root = Node("root")
        self.stack, self.count = [self.root], 0
        self.feed(payload.decode("utf-8", errors="strict"))
        self.close()

    def handle_starttag(self, tag, attrs):
        self.count += 1
        if self.count > 80000 or len(self.stack) > 256:
            raise ValueError("capture exceeds document bounds")
        node = Node(tag, attrs)
        self.stack[-1].children.append(node)
        if tag not in VOID:
            self.stack.append(node)

    def handle_endtag(self, tag):
        for index in range(len(self.stack) - 1, 0, -1):
            if self.stack[index].tag == tag:
                del self.stack[index:]
                break

    def handle_data(self, data):
        self.stack[-1].children.append(data)


def one(nodes, context):
    values = list(nodes)
    if len(values) != 1:
        raise ValueError(f"expected one {context}, found {len(values)}")
    return values[0]


def source_url(provider, value):
    url = urlsplit(value)
    host = {"bandai": "en.onepiece-cardgame.com", "limitless": "onepiece.limitlesstcg.com"}.get(provider)
    if host is None or url.scheme != "https" or url.netloc != host or url.fragment:
        raise ValueError("unexpected source origin")
    if provider == "bandai" and url.path != "/cardlist/":
        raise ValueError("unexpected Bandai catalog path")
    if provider == "limitless" and re.fullmatch(r"/cards/en/(?:OP|ST|EB|PRB)\d{2}-\d{3}|/cards/en/P-\d{3}", url.path) is None:
        raise ValueError("expected an English numbered Limitless card page")
    return url


def normalize_page(capture, payload):
    provider, url = capture["provider"], capture["sourceURL"]
    parsed_url = source_url(provider, url)
    if datetime.fromisoformat(capture["observedAt"].replace("Z", "+00:00")).tzinfo is None:
        raise ValueError("capture time must include its timezone")
    if capture.get("byteCount", len(payload)) != len(payload):
        raise ValueError("retained capture byte count mismatch")
    fingerprint = hashlib.sha256(payload).hexdigest()
    if fingerprint != capture["payloadSHA256"]:
        raise ValueError("retained capture hash mismatch")
    targets = set(capture["numbers"])
    if not targets or any(NUMBER.fullmatch(number) is None for number in targets):
        raise ValueError("invalid numbered-card review scope")
    document = Document(payload).root
    rows, appearances = [], []
    if provider == "bandai":
        for modal in document.nodes("dl", "modalCol"):
            info = one(modal.nodes(cls="infoCol"), "Bandai identity")
            number = one((n for n in info.nodes("span") if NUMBER.fullmatch(n.text())), "printed number").text()
            if number not in targets:
                continue
            alias = modal.attrs.get("id", "")
            if not re.fullmatch(re.escape(number) + r"(?:_p\d+)?", alias):
                raise ValueError("unexpected Bandai artwork alias")
            image = one(modal.nodes("div", "frontCol"), "Bandai front image")
            image_path = one(image.nodes("img"), "Bandai image").attrs.get("data-src", "")
            image_url = urljoin(url, image_path)
            if urlsplit(image_url).scheme != "https" or urlsplit(image_url).netloc != parsed_url.netloc or not urlsplit(image_url).path.startswith("/images/cardlist/card/"):
                raise ValueError("unexpected Bandai artwork URL")
            rows.append({"sourceID": alias, "number": number,
                         "name": one(modal.nodes(cls="cardName"), "Bandai name").text(),
                         "sourceLabel": one((node for node in modal.nodes(cls="getInfo")
                             if any(heading.text() == "Card Set(s)" for heading in node.nodes("h3"))),
                             "Bandai product").text(exclude={"h3"}),
                         "blockText": one(modal.nodes(cls="block"), "Bandai block").text(exclude={"h3"}),
                         "referenceImageURL": image_url})
    else:
        number = parsed_url.path.rsplit("/", 1)[-1]
        if targets != {number}:
            raise ValueError("Limitless page and review scope disagree")
        title = one(document.nodes(cls="card-text-name"), "Limitless name")
        title_link = one(title.nodes("a"), "Limitless title link")
        if urlsplit(urljoin(url, title_link.attrs.get("href", ""))).path != parsed_url.path:
            raise ValueError("Limitless title identity mismatch")
        table = one(document.nodes("table", "card-prints-versions"), "Limitless print table")
        for row in table.nodes("tr"):
            cells = list(row.nodes("td"))
            if not cells:
                continue
            if len(cells) != 3:
                raise ValueError("Limitless print table schema changed")
            anchor = one(cells[0].nodes("a"), "Limitless print link")
            marker = one(anchor.nodes("span", "prints-table-card-number"), "Limitless print marker").text()
            link = urlsplit(urljoin(url, anchor.attrs.get("href") or url))
            query = parse_qs(link.query, keep_blank_values=True)
            if link.scheme != "https" or link.netloc != parsed_url.netloc or link.path != parsed_url.path or link.fragment or set(query) - {"v"}:
                raise ValueError("Limitless print points outside its identity")
            variant = query.get("v", [])
            if variant and (len(variant) != 1 or not variant[0].isdigit()):
                raise ValueError("invalid Limitless variant alias")
            alias = "en/" + number + ("?" + urlencode({"v": variant[0]}) if variant else "")
            rows.append({"sourceID": alias, "number": number, "name": title.text(),
                         "sourceLabel": anchor.text(exclude={"span"}), "sourceMarker": marker})
        # This list is separate from print-table rows and must not disappear.
        for group in document.nodes(cls="card-prints-reprints"):
            for anchor in group.nodes("a"):
                product_url = urlsplit(urljoin(url, anchor.attrs.get("href", "")))
                if product_url.scheme != "https" or product_url.netloc != parsed_url.netloc or not product_url.path.startswith("/cards/"):
                    raise ValueError("unexpected reprint appearance link")
                appearances.append({"number": number, "sourceID": "en/" + number + "|appearance:" + product_url.path,
                                    "name": title.text(), "sourceLabel": anchor.text(),
                                    "productSourceURL": product_url.geturl()})
    if targets != {row["number"] for row in rows}:
        raise ValueError("capture omitted a requested canonical number")
    seen = set()
    observations = []
    for row in rows + appearances:
        if row["sourceID"] in seen or not row["name"] or not row["sourceLabel"]:
            raise ValueError("duplicate alias or empty source metadata")
        seen.add(row["sourceID"])
        observation_id = f"{provider}:{row['sourceID']}:{fingerprint}"
        observations.append({"id": observation_id, "kind": "catalog",
            "alias": {"provider": provider, "sourceID": row["sourceID"]},
            "sourceURL": url, "observedAt": capture["observedAt"], "language": "en",
            "payloadSHA256": fingerprint, "productEvidence": [],
            "printedEvidence": {key: value for key, value in row.items() if key != "sourceID"}})
    inventory = {"provider": provider, "snapshotID": f"{capture['id']}:{fingerprint}",
                 "paginationComplete": False, "observationIDs": sorted(o["id"] for o in observations)}
    return observations, inventory


def normalize_manifest(manifest, capture_dir):
    if manifest.get("schemaVersion") != 1 or not manifest.get("captures"):
        raise ValueError("unsupported or empty capture manifest")
    observations, inventories = [], []
    ids = set()
    for capture in manifest["captures"]:
        filename = capture["rawFile"]
        if Path(filename).name != filename or capture["id"] in ids:
            raise ValueError("unsafe capture filename or duplicate capture ID")
        ids.add(capture["id"])
        path = capture_dir / filename
        if path.is_symlink() or path.stat().st_size > MAX_BYTES:
            raise ValueError("unsafe or oversized retained capture")
        records, inventory = normalize_page(capture, path.read_bytes())
        observations.extend(records)
        inventories.append(inventory)
    # The same source alias may occur on different product pages. Retain those
    # observations separately; uniqueness of an owned printing is a later review.
    if len({o["id"] for o in observations}) != len(observations):
        raise ValueError("duplicate observation identity across captures")
    return sorted(observations, key=lambda o: o["id"]), sorted(inventories, key=lambda i: i["snapshotID"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--capture-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    observations, inventories = normalize_manifest(json.loads(args.manifest.read_text()), args.capture_dir)
    artifacts = {"observations.json": observations, "inventories.json": inventories}
    encoded = {name: (json.dumps(value, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode()
               for name, value in artifacts.items()}
    # Validate every destination before writing; never replace a changed review.
    for name, data in encoded.items():
        target = args.output_dir / name
        if target.exists() and (target.is_symlink() or target.read_bytes() != data):
            raise ValueError("different existing review output: " + str(target))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for name, data in encoded.items():
        target = args.output_dir / name
        if not target.exists():
            with target.open("xb") as handle:
                handle.write(data)
    print(f"Normalized {len(observations)} observations; {len(inventories)} incomplete discovery inventories")


if __name__ == "__main__":
    main()
