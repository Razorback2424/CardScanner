#!/usr/bin/env python3
"""Create a photo-boundary search seed from a recognized design specification.

The projected frame is a hypothesis, not a measured boundary. It never replaces
production results or annotations. Caller supplies the reference identity.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageOps, ImageDraw
import pillow_heif
from register_print_reference import project
from selective_path_measurement import CORNERS

if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['specification','registration','baseline','image','output']:
        p.add_argument(name,type=Path)
    p.add_argument('--reference-id',required=True)
    a=p.parse_args()
    spec=next(r for r in json.loads(a.specification.read_text())['references'] if r['id']==a.reference_id)
    registration=json.loads(a.registration.read_text())
    if not registration['accepted']:raise ValueError('reference not recognized')
    if registration['referenceSHA256']!=spec['sha256']:raise ValueError('reference mismatch')
    sha=hashlib.sha256(a.image.read_bytes()).hexdigest()
    if registration['inputSHA256']!=sha:raise ValueError('capture mismatch')
    row=next(r for r in json.loads(a.baseline.read_text()) if r['fixture']==a.image.stem)
    if row['inputSHA256']!=sha:raise ValueError('baseline capture mismatch')
    h=np.asarray(registration['homography'])
    points=project(np.asarray(spec['printedBorder']),h)
    row['productionInner']=row.get('actualInner')
    row['actualInner']={c:dict(x=float(v[0]),y=float(v[1])) for c,v in zip(CORNERS,points)}
    row['seedProvenance']=dict(kind='projected_reference_hypothesis_not_measurement',referenceID=spec['id'],
        referenceSHA256=spec['sha256'],registrationSHA256=hashlib.sha256(a.registration.read_bytes()).hexdigest(),
        specificationSHA256=hashlib.sha256(a.specification.read_bytes()).hexdigest(),
        limitation=spec.get('limitation','Provider rendering is not calibrated physical truth'))
    a.output.mkdir(parents=True,exist_ok=True)
    (a.output/'reference-seed.json').write_text(json.dumps([row],indent=2)+'\n')
    pillow_heif.register_heif_opener()
    im=ImageOps.exif_transpose(Image.open(a.image)).convert('RGB');d=ImageDraw.Draw(im)
    d.line([tuple(v) for v in points]+[tuple(points[0])],fill='lime',width=3)
    im.thumbnail((1008,1344));im.save(a.output/'projected-frame.png')
    print(json.dumps(dict(fixture=row['fixture'],proposal=row['actualInner'])))
