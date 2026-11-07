#!/usr/bin/env python3
"""Render production native-coordinate proposals for coverage/identity review.

Contact sheets support visual triage, not pixel-accuracy scoring. Individual
overlays retain native resolution. Source hashes prevent stale-image overlays.
"""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps
import pillow_heif

if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['receipt', 'images', 'output']:
        p.add_argument(name, type=Path)
    a = p.parse_args()
    pillow_heif.register_heif_opener()
    rows = json.loads(a.receipt.read_text())
    a.output.mkdir(parents=True, exist_ok=True)
    font = ImageFont.load_default(size=13)
    sheets = []
    for i, row in enumerate(rows):
        source = a.images / row['file']
        if hashlib.sha256(source.read_bytes()).hexdigest() != row['inputSHA256']:
            raise ValueError('capture mismatch: ' + row['file'])
        im = ImageOps.exif_transpose(Image.open(source)).convert('RGB')
        draw = ImageDraw.Draw(im)
        for key, color in [('actualOuter', 'cyan'), ('actualInner', 'lime')]:
            if row.get(key):
                points = [(row[key][corner]['x'], row[key][corner]['y']) for corner in
                          ['topLeft', 'topRight', 'bottomRight', 'bottomLeft']]
                draw.line(points + points[:1], fill=color, width=max(2, im.width // 600))
        im.save(a.output / (row['fixture'] + '-overlay.png'))
        if i % 8 == 0:
            sheets.append(Image.new('RGB', (1200, 840), 'white'))
        sheet = sheets[-1]; x, y = (i % 4) * 300, ((i % 8) // 4) * 420
        im.thumbnail((288, 376))
        sheet.paste(im, (x + (300-im.width)//2, y + 40))
        d = ImageDraw.Draw(sheet)
        d.text((x+4, y+2), row['file'], fill='black', font=font)
        status = row.get('error') or ('inner proposed' if row.get('actualInner') else 'no inner proposal')
        d.text((x+4, y+20), status[:42], fill='black', font=font)
    for i, sheet in enumerate(sheets):
        sheet.save(a.output / f'contact-{i+1}.png')
    print(f'Rendered {len(rows)} overlays and {len(sheets)} sheets; not accuracy scores')
