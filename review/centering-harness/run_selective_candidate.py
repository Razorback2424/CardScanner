#!/usr/bin/env python3
"""Frozen selective-method transfer runner; no per-photo tuning or annotation input.

Existing printed lines are preserved. This intentionally does not assert that
those lines identify the correct design feature on every card.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image,ImageOps,ImageDraw
import pillow_heif
from track_bottom_boundary import analyze as track_bottom
from track_card_paths import boundary
from selective_path_measurement import run,CORNERS


def candidate(image,baseline,output,fixture):
    output.mkdir(parents=True,exist_ok=True)
    pillow_heif.register_heif_opener()
    im=ImageOps.exif_transpose(Image.open(image)).convert('RGB')
    record=next(r for r in json.loads(baseline.read_text()) if r['fixture']==fixture)
    quad=[[record['actualOuter'][p]['x'],record['actualOuter'][p]['y']] for p in CORNERS]
    track_bottom(image,baseline,output/'bottom',fixture)
    top=boundary(np.asarray(im,dtype='float32').mean(2),quad,'top',position_sigma=16,adaptive_sharp=True)
    topfile=output/'physical-top.json'
    topfile.write_text(json.dumps(dict(inputSHA256=hashlib.sha256(image.read_bytes()).hexdigest(),
                                     frames=dict(outer=dict(top=top))),indent=2)+'\n')
    run(baseline,output/'bottom/tracked-boundary.json',None,output/'measurement.json',
        topfile,['top'],image,32)
    result=json.loads((output/'measurement.json').read_text())
    draw=ImageDraw.Draw(im)
    for frame,edges in result['predictionNativePaths'].items():
        for pts in edges.values():
            draw.line([tuple(p) for p in pts],fill='cyan' if frame=='outer' else 'lime',width=4)
    im.thumbnail((1008,1344));im.save(output/'selective-overlay.png')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['image','baseline','output']:p.add_argument(name,type=Path)
    p.add_argument('--fixture',required=True)
    args=p.parse_args();candidate(args.image,args.baseline,args.output,args.fixture)
