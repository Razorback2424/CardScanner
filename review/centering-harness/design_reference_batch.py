#!/usr/bin/env python3
"""Recognize supplied designs across development captures without filename routing.

Requires both full-design coverage and distributed artwork-interior matches.
No reference is selected when multiple supplied designs pass. Recognition only
selects a boundary hypothesis; foil variants and geometry need separate checks.
"""
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageOps
import pillow_heif
from register_print_reference import register


def artwork_evidence(result, region):
    x0,y0,x1,y1=region
    points=np.array([r['reference'] for r in result.get('matchesNative',[]) if r['inlier']])
    if points.size==0:return dict(count=0,quadrants=0,accepted=False)
    points=points[(points[:,0]>=x0)&(points[:,0]<=x1)&(points[:,1]>=y0)&(points[:,1]<=y1)]
    quadrants=len({(int(x>(x0+x1)/2),int(y>(y0+y1)/2)) for x,y in points})
    return dict(count=len(points),quadrants=quadrants,accepted=bool(len(points)>=20 and quadrants==4))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['specification','reference_directory','manifest','image_directory','output']:
        p.add_argument(name,type=Path)
    a=p.parse_args();pillow_heif.register_heif_opener()
    specs=json.loads(a.specification.read_text())['references']
    files={hashlib.sha256(f.read_bytes()).hexdigest():f for f in a.reference_directory.glob('*.png')}
    refs=[(s,np.asarray(Image.open(files[s['sha256']]).convert('RGB'))) for s in specs]
    entries=[r for r in json.loads(a.manifest.read_text())['entries'] if r['split'].startswith('DEV')]
    a.output.mkdir(parents=True,exist_ok=True);rows=[]
    for entry in entries:
        path=a.image_directory/entry['file'];sha=hashlib.sha256(path.read_bytes()).hexdigest()
        if sha!=entry['sha256']:raise ValueError('capture mismatch')
        photo=np.asarray(ImageOps.exif_transpose(Image.open(path)).convert('RGB'))
        results=[]
        for spec,ref in refs:
            r=register(ref,photo);art=artwork_evidence(r,spec['artworkInterior'])
            accepted=bool(r['accepted'] and art['accepted'])
            r.update(referenceSHA256=spec['sha256'],inputSHA256=sha,artworkEvidence=art,designAccepted=accepted)
            output=a.output/path.stem;output.mkdir(exist_ok=True)
            (output/(spec['id']+'.json')).write_text(json.dumps(r,indent=2)+'\n')
            results.append(dict(referenceID=spec['id'],accepted=accepted,globalAccepted=r['accepted'],
                inliers=r.get('inliers',0),artworkEvidence=art))
        recognized=[r['referenceID'] for r in results if r['accepted']]
        row=dict(file=entry['file'],inputSHA256=sha,selectedReference=recognized[0] if len(recognized)==1 else None,
                 ambiguous=len(recognized)>1,candidates=results)
        rows.append(row);print(json.dumps(row),flush=True)
        (a.output/'recognition.json').write_text(json.dumps(dict(rows=rows,
            specificationSHA256=hashlib.sha256(a.specification.read_bytes()).hexdigest(),
            limitations='Supplied two-design library; no global catalog coverage, exact-finish identity, geometry acceptance, or app integration'),indent=2)+'\n')
