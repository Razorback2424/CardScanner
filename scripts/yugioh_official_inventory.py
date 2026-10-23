"""Konami release inventory extraction. No edition or price authority."""
import hashlib
import html
import re

RULE = "konami-release-family-v1"


def extract(data, profile):
    source = data.decode("utf-8")
    assert 'content="en"' in source and profile['releaseName'] in html.unescape(source)
    text = html.unescape(re.sub(r"<[^>]*>", " ", source))
    total = re.search(r"Total of\s+(\d+)\s+Card\(s\)", text)
    assert total and int(total[1]) == profile['count'], "release inventory count changed; review required"
    rows = []
    for block in source.split('<!-- .t_row c_normal -->')[:-1]:
        block = block[block.rfind('<div class="t_row c_normal'):]
        name = re.search(r"class=\"cnm\" value='(.*?)'", block)
        cid = re.search(r'class="cid" value="(\d+)"', block)
        rarities = re.findall(r'<div class="lr_icon rid rid_\d+".*?<span[^>]*>\s*(.*?)\s*</span>', block, re.S)
        artwork = re.findall(r'id="card_image_\d+_(\d+)"', block)
        assert name and cid and rarities and len(artwork) == 1, "unrecognized inventory row"
        rows.append(dict(name=html.unescape(name[1]), cid=int(cid[1]), rarities=rarities, artwork=int(artwork[0])))
    assert len(rows) == int(total[1]) and len({r['cid'] for r in rows}) == len(rows), "partial or duplicate inventory"
    return dict(rule=RULE, url=profile['url'], sha256=hashlib.sha256(data).hexdigest(), count=len(rows), rows=rows)
