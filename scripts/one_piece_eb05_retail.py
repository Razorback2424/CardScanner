"""Read exact English EB-05 finish listings from retained retailer responses."""

import json
import re
from urllib.parse import urlsplit

from audit_one_piece_coverage import PRINTED_NUMBER
from capture_one_piece_products import CARDBOARD_ARTWORK_URL, ROCKET_ARTWORK_URL
from normalize_one_piece_sources import Document
from reconcile_one_piece_launch_products import capture_index, checked_capture


EB05_PRODUCT = ("product:bandai-series:569205", "24820", "https://en.onepiece-cardgame.com/cardlist/?series=569205")
SET_NAME = "Extra Booster: One Piece Heroines Edition Vol. 2"
CARDBOARD_PRODUCT = re.compile(
    r"https://www\.cardboardcolosseumnj\.com/onepiece/singles/extra-booster-one-piece-heroines-edition-vol-2/"
    r"[a-z0-9-]+-p([1-9][0-9]*)"
)
ROCKET_PRODUCT = re.compile(r"https://www\.rocketcitytoys\.com/products/([a-z0-9-]+)\.js")
CONDITIONS = {
    "NM": "Near Mint", "LP": "Lightly Played", "MP": "Moderately Played", "HP": "Heavily Played", "DMG": "Damaged",
}
FINISHES = {"Normal", "Foil"}
ROCKET_TITLE = re.compile(
    r"(Normal|Foil) (.+) (" + PRINTED_NUMBER.pattern + r") (" + "|".join(CONDITIONS.values()) + r") " + re.escape(SET_NAME)
)


def cardboard_listings(url, raw):
    product = CARDBOARD_PRODUCT.fullmatch(url)
    if product is None:
        return
    tree = Document(raw).root
    titles = [node.text() for node in tree.nodes("h1")]
    canonical = [node.attrs.get("href") for node in tree.nodes("link") if node.attrs.get("rel") == "canonical"]
    images = [node.attrs.get("content", "") for node in tree.nodes("meta") if node.attrs.get("property") == "og:image"]
    if len(titles) != 1 or canonical != [url] or len(images) != 1:
        return
    image = CARDBOARD_ARTWORK_URL.fullmatch(images[0])
    if image is None or image[1] != product[1]:
        return
    numbers = []
    for details in tree.nodes("dl"):
        labels = [node.text() for node in details.nodes("dt")]
        values = [node.text() for node in details.nodes("dd")]
        if len(labels) == len(values) and labels.count("Set") == labels.count("Collector number") == 1:
            if values[labels.index("Set")] == SET_NAME:
                numbers.append(values[labels.index("Collector number")].removeprefix("#"))
    if len(numbers) != 1 or not PRINTED_NUMBER.fullmatch(numbers[0]):
        return

    for table in tree.nodes("table"):
        if [node.text() for node in table.nodes("th")][:3] != ["Printing", "Condition", "Language"]:
            continue
        for row in table.nodes("tr"):
            cells = list(row.nodes("td"))
            if len(cells) < 3 or cells[2].text() != "EN" or cells[1].text() not in CONDITIONS:
                continue
            finishes = [node.text() for node in cells[0].nodes("span", "font-medium")]
            if len(finishes) != 1 or finishes[0] not in FINISHES:
                continue
            finish = finishes[0]
            yield {"provider": "cardboard-colosseum", "sourceID": product[1], "path": urlsplit(url).path,
                   "number": numbers[0], "title": titles[0], "finish": finish.lower(),
                   "lane": f"EN - {CONDITIONS[cells[1].text()]} - {finish}",
                   "imageURL": images[0], "imageProductID": image[1]}


def rocket_listings(url, raw):
    path = ROCKET_PRODUCT.fullmatch(url)
    if path is None:
        return
    product = json.loads(raw)
    if (product.get("handle") != path[1] or product.get("vendor") != SET_NAME
            or product.get("type") != "One Piece Card Game Singles"):
        return
    image_url = product.get("featured_image") or ""
    if image_url.startswith("//"):
        image_url = "https:" + image_url
    image = ROCKET_ARTWORK_URL.fullmatch(image_url)
    title = ROCKET_TITLE.fullmatch(product.get("title", ""))
    options = [(option.get("position"), option.get("name")) for option in product.get("options", [])]
    if image is None or title is None or options != [(1, "Condition"), (2, "Language"), (3, "Printing")]:
        return
    for variant in product.get("variants", []):
        variant_id = variant.get("id")
        if (type(variant_id) is not int or variant_id < 1 or variant.get("option2") != "English"
                or variant.get("option3") != title[1] or variant.get("option1") not in CONDITIONS.values()):
            continue
        yield {"provider": "rocket-city-toys", "sourceID": str(variant_id), "path": urlsplit(url).path.removesuffix(".js"),
               "number": title[3], "title": title[2], "finish": title[1].lower(),
               "lane": f"English - {variant['option1']} - {title[1]}",
               "imageURL": image_url, "imageProductID": image[1]}


def eb05_listings(roots):
    for root in roots:
        records = json.loads((root / "capture-manifest.json").read_bytes())["captures"]
        for url, receipt in sorted(capture_index(records, "sourceURL").items()):
            if CARDBOARD_PRODUCT.fullmatch(url):
                parse = cardboard_listings
            elif ROCKET_PRODUCT.fullmatch(url):
                parse = rocket_listings
            else:
                continue
            for listing in parse(url, checked_capture(root, receipt)):
                yield listing, receipt
