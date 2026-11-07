#!/usr/bin/env python3
"""Native inner-edge reacquisition from physical geometry, not the inner guide.

Fixed 2–12% search depth reuses the production profile's shallow interval.
Native observed-point fits may still identify artwork: inspect identity before
promotion. Independent side proposals and failures are retained; no ratios or
ground-truth input, and no automatic app routing.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageOps
import pillow_heif
from edge_annotation_audit import audit_edge
from selective_path_measurement import CORNERS


def run(image, baseline, fixture, output, sides):
    pillow_heif.register_heif_opener()
    im = ImageOps.exif_transpose(Image.open(image)).convert('RGB')
    source_hash = hashlib.sha256(image.read_bytes()).hexdigest()
    record = next(r for r in json.loads(baseline.read_text()) if r['fixture'] == fixture)
    if record.get('inputSHA256') and record['inputSHA256'] != source_hash:
        raise ValueError('capture mismatch')
    outer = np.array([[record['actualOuter'][p][a] for a in ['x', 'y']] for p in CORNERS])
    width = (np.linalg.norm(outer[1]-outer[0])+np.linalg.norm(outer[2]-outer[3]))/2
    height = (np.linalg.norm(outer[3]-outer[0])+np.linalg.norm(outer[2]-outer[1]))/2
    # A search seed, not assumed print geometry. Each side is fit independently.
    def point(u, v):
        return (1-v)*((1-u)*outer[0]+u*outer[1])+v*((1-u)*outer[3]+u*outer[2])
    seed = [point(.07,.07), point(.93,.07), point(.93,.93), point(.07,.93)]
    pixels = np.asarray(im); results = {}; draw = ImageDraw.Draw(im)
    for side in sides:
        radius = int(round(.05*(width if side in ['left','right'] else height)))
        try:
            result = audit_edge(pixels, seed, side, radius=radius, polarity='either')
            results[side] = result
            draw.line([tuple(p) for p in result['endpoints']], fill='lime', width=5)
        except ValueError as e:
            results[side] = dict(error=str(e))
    output.mkdir(parents=True, exist_ok=True)
    receipt = dict(fixture=fixture, inputSHA256=source_hash,
        baselineSHA256=hashlib.sha256(baseline.read_bytes()).hexdigest(),
        seed= np.asarray(seed).tolist(), nominalDepthBand=[.02,.12], sides=results,
        limitations='Physical quad defines search only; offsets are native normals and band is approximate under perspective. Strongest local transitions can be artwork. Not an accepted frame.')
    (output/'candidates.json').write_text(json.dumps(receipt,indent=2)+'\n')
    im.thumbnail((1008,1344)); im.save(output/'overlay.png')
    print(json.dumps({s: ({k:r[k] for k in ['retainedCount','occupiedBins','fitRMSNativePixels']} if 'line' in r else r) for s,r in results.items()}))


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['image','baseline','output']: p.add_argument(name,type=Path)
    p.add_argument('--fixture',required=True)
    p.add_argument('--sides',nargs='+',choices=['left','top','right','bottom'],default=['left','top','right','bottom'])
    a=p.parse_args();run(a.image,a.baseline,a.fixture,a.output,a.sides)
