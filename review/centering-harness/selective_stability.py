#!/usr/bin/env python3
"""Fixed seed-perturbation controls for native physical-side refinement.

Image and printed geometry stay fixed. This isolates left/right fitting and
rectification; top/bottom paths are held fixed, so it is not a full-pipeline test.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image,ImageOps
import pillow_heif
from scipy.interpolate import PchipInterpolator
from edge_annotation_audit import audit_edge
from selective_path_measurement import measure,CORNERS
from track_bottom_boundary import analyze as track_bottom
from track_card_paths import boundary


def run(image,baseline,hybrid,output,radius,rerun_curves=False,adaptive_sharp=False):
    pillow_heif.register_heif_opener()
    pixels=np.asarray(ImageOps.exif_transpose(Image.open(image)).convert('RGB'))
    reference=json.loads(hybrid.read_text())
    if hashlib.sha256(image.read_bytes()).hexdigest()!=reference['inputSHA256']:
        raise ValueError('capture mismatch')
    source=next(r for r in json.loads(baseline.read_text()) if r['fixture']==reference['fixture'])
    quad=np.array([[source['actualOuter'][p]['x'],source['actualOuter'][p]['y']] for p in CORNERS])
    variants={'identity':np.zeros((4,2)), 'translate_plus8':np.full((4,2),8),
              'translate_minus8':np.full((4,2),-8),
              'opposing_tilt':np.array([[8,-8],[-8,8],[8,-8],[-8,8]]),
              'opposing_tilt_inverse':np.array([[-8,8],[8,-8],[-8,8],[8,-8]])}
    rows=[]
    for name,delta in variants.items():
        seed=quad+delta;frames=copy.deepcopy(reference['predictionNativePaths']);edges={};failures={}
        if rerun_curves:
            folder=output.parent/(output.stem+'-'+name);folder.mkdir(parents=True,exist_ok=True)
            changed=copy.deepcopy(source)
            changed['actualOuter']={key:dict(x=float(p[0]),y=float(p[1])) for key,p in zip(CORNERS,seed)}
            seed_file=folder/'baseline.json';seed_file.write_text(json.dumps([changed]))
            try:
                track_bottom(image,seed_file,folder,reference['fixture'])
                bottom=json.loads((folder/'tracked-boundary.json').read_text())
                frames['outer']['bottom']=[[r['x'],r['center']] for r in bottom['rows']]
                top=boundary(pixels.astype('float32').mean(2),seed.tolist(),'top',position_sigma=16,adaptive_sharp=adaptive_sharp)
                (folder/'top.json').write_text(json.dumps(top))
                frames['outer']['top']=[r['point'] for r in top['rows']]
                for side in ['top','bottom']:
                    before=np.array(reference['predictionNativePaths']['outer'][side]);after=np.array(frames['outer'][side])
                    before=before[np.argsort(before[:,0])];after=after[np.argsort(after[:,0])]
                    xs=np.linspace(max(before[0,0],after[0,0]),min(before[-1,0],after[-1,0]),101)
                    error=PchipInterpolator(after[:,0],after[:,1])(xs)-PchipInterpolator(before[:,0],before[:,1])(xs)
                    edges[side]=dict(worstShiftFromHybrid=float(np.max(abs(error))))
            except ValueError as e:failures['curves']=str(e)
        for side in ['left','right']:
            try:
                result=audit_edge(pixels,seed.tolist(),side,radius=radius,polarity='falling')
                a,b,c=result['line'];n=np.array([a,b]);p=np.array(frames['outer'][side])
                distances=p@n-c
                frames['outer'][side]=(p-distances[:,None]*n).tolist()
                edges[side]=dict(worstShiftFromHybrid=float(np.max(abs(distances))),
                    rms=result['fitRMSNativePixels'],retained=result['retainedCount'],
                    occupiedBins=result['occupiedBins'],line=result['line'])
            except ValueError as e:failures[side]=str(e)
        measurement=None
        if not failures:
            h=cv2.getPerspectiveTransform(seed.astype('float32'),np.float32([[0,0],[1,0],[1,1],[0,1]]))
            measurement=measure(frames,h)
        difference=None if measurement is None else {k:measurement[k]-reference['selectivePrediction'][k] for k in ['leftShare','topShare']}
        passed=not failures and max(e['worstShiftFromHybrid'] for e in edges.values())<=4 and max(abs(v) for v in difference.values())<=2
        rows.append(dict(name=name,delta=delta.tolist(),edges=edges,failures=failures,
                         shareDifferencePP=difference,passesFixedLimits=passed))
        print(json.dumps(rows[-1]),flush=True)
    output.write_text(json.dumps(dict(inputSHA256=reference['inputSHA256'],radius=radius,adaptiveSharpTop=adaptive_sharp,
        limits=dict(maxSideShiftNativePixels=4,maxShareChangePP=2),rows=rows,
        scope='all physical sides reanalyzed; printed lines held fixed' if rerun_curves else
              'physical left/right refit and rectification; top/bottom paths and printed lines held fixed'),indent=2)+'\n')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['image','baseline','hybrid','output']:p.add_argument(name,type=Path)
    p.add_argument('--radius',type=int,default=16)
    p.add_argument('--rerun-curves',action='store_true')
    p.add_argument('--adaptive-sharp',action='store_true')
    args=p.parse_args()
    if args.adaptive_sharp and not args.rerun_curves:p.error('adaptive sharp requires rerun curves')
    run(args.image,args.baseline,args.hybrid,args.output,args.radius,args.rerun_curves,args.adaptive_sharp)
