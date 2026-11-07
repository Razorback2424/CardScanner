#!/usr/bin/env python3
"""Fit local blurred transitions without forcing a straight physical boundary.

Research only. Supplied regions establish boundary identity; fit residuals and
perturbation ranges do not establish calibrated uncertainty or physical truth.
Never writes annotations or app geometry.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps, ImageDraw
import pillow_heif
from scipy.interpolate import PchipInterpolator
from scipy.optimize import least_squares
from scipy.special import erf, expit


def fit(profile, ys, family):
    t = ys-ys.mean()
    def residual(v):
        z=(ys-v[3])/v[4]
        step=.5*(1+erf(z/np.sqrt(2))) if family=='erf' else expit(z*1.7)
        return v[0]+v[1]*t+v[2]*step-profile
    fits=[]
    for start in np.linspace(ys[0]+10,ys[-1]-10,3):
        initial=[np.clip(profile[:8].mean(),0,255),0,
                 np.clip(profile[-8:].mean()-profile[:8].mean(),1,255),start,5]
        fits.append(least_squares(residual,initial,
            bounds=([0,-2,0,ys[0]+8,1],[255,2,255,ys[-1]-8,20])))
    result=min(fits,key=lambda r:float(r.fun@r.fun))
    base,slope,amplitude,center,width=result.x
    rms=float(np.sqrt(np.mean(result.fun**2)))
    return dict(center=float(center),blurWidth=float(width),amplitude=float(amplitude),
        rms=rms,relativeRMS=rms/max(float(amplitude),1e-9),
        atBound=bool(np.any(result.active_mask)),converged=bool(result.success))


def analyze(path,output,region):
    pillow_heif.register_heif_opener()
    im=ImageOps.exif_transpose(Image.open(path)).convert('RGB')
    a=np.asarray(im,dtype=float).mean(2)
    x0,y0,x1,y1=region
    if not (16<=x0<x1<im.width-16 and 0<=y0<y1<=im.height and y1-y0>=40):
        raise ValueError('region must fit original photo with strip padding')
    xs=np.linspace(x0,x1,61).round().astype(int)
    rows=[]
    for x in xs:
        trials=[]
        for halfwidth in [4,8,16]:
            profile=a[y0:y1,x-halfwidth:x+halfwidth+1].mean(1)
            for family in ['erf','logistic']:
                trials.append(dict(stripWidth=2*halfwidth+1,family=family,
                                   **fit(profile,np.arange(y0,y1),family)))
        centers=[r['center'] for r in trials]
        # Keep poor or unstable observations in the receipt, never discard a
        # weak spatial section and report only a flattering fit residual.
        rows.append(dict(x=int(x),center=float(np.median(centers)),
            sensitivityRange=[min(centers),max(centers)],
            stable=bool(max(centers)-min(centers)<=4 and all(
                r['converged'] and not r['atBound'] and r['relativeRMS']<=.15 for r in trials)),
            trials=trials))
    centers=np.array([r['center'] for r in rows]);train=np.arange(61)%2==0
    predicted=PchipInterpolator(xs[train],centers[train])(xs[~train])
    errors=predicted-centers[~train]
    stable=np.array([r['stable'] for r in rows])
    receipt=dict(inputSHA256=hashlib.sha256(path.read_bytes()).hexdigest(),region=region,
        models='blurred positive step plus linear background; erf and logistic',
        criteria='all six fits converge without active bounds; center range <=4px; relative RMS <=0.15',
        rows=rows,stableCount=int(stable.sum()),
        occupiedBins=sorted(set(np.minimum(4,np.arange(61)[stable]*5//61).tolist())),
        heldOutInterpolation=dict(count=int((~train).sum()),rms=float(np.sqrt(np.mean(errors**2))),
                                  worst=float(np.max(np.abs(errors))),errors=errors.tolist()),
        status='diagnostic_only_not_calibrated_accuracy',
        limitations='Supplied boundary region; shared pixels; model sensitivity is not a confidence interval; no app routing')
    output.mkdir(parents=True,exist_ok=True)
    (output/'local-transition.json').write_text(json.dumps(receipt,indent=2)+'\n')
    crop=im.crop((x0-20,y0-20,x1+20,y1+20));draw=ImageDraw.Draw(crop)
    for row in rows:
        x=row['x']-x0+20;lo,hi=row['sensitivityRange']
        draw.line((x,lo-y0+20,x,hi-y0+20),fill='lime' if row['stable'] else 'red',width=3)
    draw.line([(float(x-x0+20),float(y-y0+20)) for x,y in zip(xs,centers)],fill='cyan',width=1)
    crop.save(output/'local-transition.png')
    print(json.dumps({k:receipt[k] for k in ['stableCount','occupiedBins','heldOutInterpolation']}))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('image',type=Path);p.add_argument('output',type=Path)
    p.add_argument('--region',type=int,nargs=4,required=True)
    args=p.parse_args();analyze(args.image,args.output,args.region)
