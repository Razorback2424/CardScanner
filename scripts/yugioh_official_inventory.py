"""Konami release inventory extraction. No edition or price authority."""
import argparse
import datetime
import hashlib
import html
import json
import pathlib
import re
import unicodedata

RULE = "konami-release-family-v1"
RELEASE_CALENDAR_URL = "https://www.db.yugioh-card.com/yugiohdb/card_list.action?wname=CardSearch&request_locale=en"


def norm(value):
    return " ".join(re.sub(r"[^a-z0-9]+", " ", unicodedata.normalize("NFKD", value).lower()).split())


def extract(data, profile, *, require_unique_card_ids=True):
    source = data.decode("utf-8")
    assert 'content="en"' in source and profile['releaseName'] in html.unescape(source)
    text = html.unescape(re.sub(r"<[^>]*>", " ", source))
    total = re.search(r"Total of\s+(\d+)\s+Card\(s\)", text)
    assert total and int(total[1]) > 0, "missing release inventory count"
    if "count" in profile:
        assert int(total[1]) == profile["count"], "release inventory count changed; review required"
    rows = []
    for block in source.split('<!-- .t_row c_normal -->')[:-1]:
        block = block[block.rfind('<div class="t_row c_normal'):]
        name = re.search(r"class=\"cnm\" value='([^<>]*)'\s*/?>", block)
        cid = re.search(r'class="cid" value="(\d+)"', block)
        rarities = re.findall(r'<div class="lr_icon rid rid_\d+".*?<span[^>]*>\s*(.*?)\s*</span>', block, re.S)
        artwork = re.findall(r'id="card_image_\d+_(\d+)"', block)
        assert name and cid and rarities and len(artwork) == 1, "unrecognized inventory row"
        rows.append(dict(name=html.unescape(name[1]), cid=int(cid[1]), rarities=rarities, artwork=int(artwork[0])))
    assert len(rows) == int(total[1]), "partial release inventory"
    if require_unique_card_ids:
        assert len({r["cid"] for r in rows}) == len(rows), "duplicate card IDs in reviewed inventory"
    return dict(rule=RULE, url=profile['url'], sha256=hashlib.sha256(data).hexdigest(), count=len(rows), rows=rows)


def extract_release_calendar(data):
    source = data.decode("utf-8")
    assert 'content="en"' in source, "expected English release directory"
    releases = []
    for block in source.split('<div class="t_row packc')[1:]:
        date = re.search(r'<div class="time">\s*(\d{4}/\d{2}/\d{2})\s*</div>', block)
        name = re.search(r'<div class="main">\s*<p>([^<]+)</p>', block)
        identifier = re.search(r'class="link_value" value="[^"]*[?&]pid=(\d+)', block)
        assert date and name and identifier, "unrecognized English release row"
        releases.append({
            "id": identifier[1],
            "name": html.unescape(name[1]).strip(),
            "date": datetime.date.fromisoformat(date[1].replace("/", "-")).isoformat(),
        })
    assert releases and len({r["id"] for r in releases}) == len(releases), "empty or duplicate release directory"
    return {"url": RELEASE_CALENDAR_URL, "sha256": hashlib.sha256(data).hexdigest(), "releases": releases}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Project release metadata from a retained English Konami directory.")
    parser.add_argument("input", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()
    calendar = extract_release_calendar(args.input.read_bytes())
    header = {key: value for key, value in calendar.items() if key != "releases"}
    header["releases"] = []
    rows = ",\n".join("    " + json.dumps(row, ensure_ascii=False) for row in calendar["releases"])
    args.output.write_text(json.dumps(header, indent=2).replace("[]", "[\n" + rows + "\n  ]") + "\n")
