#!/usr/bin/env python3
"""Diagnostic cut-plus-shadow model; never changes app geometry or annotations.

Separates a blurred material step from an outward decaying shadow. Similar fits
at different cut locations are retained as ambiguity, not reported as certainty.
This model assumes a brighter background and is not a general card detector.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.optimize import least_squares
from scipy.special import ndtr, log_ndtr


def profile(x, v, sigma):
    base, slope, contrast, amplitude, center, tau = v
    t = x-center
    step = ndtr(t/sigma)
    # Gaussian convolution of exp(-t/tau) * H(t), computed in log space.
    shadow = np.exp(-t/tau + sigma*sigma/(2*tau*tau)
                    + log_ndtr(t/sigma-sigma/tau))
    return base+slope*x+contrast*step-amplitude*shadow


def fit(values, x, sigma):
    fits = []
    for center in [-30., -15., 0., 15.]:
        for tau in [10., 35.]:
            initial = [float(np.clip(np.median(values[:10]), 1, 254)), 0,
                       float(np.clip(np.median(values[-10:])-np.median(values[:10]), 1, 250)),
                       40., center, tau]
            result = least_squares(lambda v: profile(x, v, sigma)-values, initial,
                bounds=([0, -1, 0, 0, -45, 3], [255, 1, 255, 255, 30, 80]),
                max_nfev=250)
            fits.append(dict(parameters=result.x.tolist(), center=float(result.x[4]),
                rms=float(np.sqrt(np.mean(result.fun**2))), converged=bool(result.success),
                activeBounds=result.active_mask.tolist()))
    best = min(fits, key=lambda f: f['rms'])
    competitive = [f for f in fits if f['rms'] <= best['rms']+.25]
    return dict(best=best, competitiveCenterRange=[min(f['center'] for f in competitive),
        max(f['center'] for f in competitive)], starts=fits)


def synthetic():
    x=np.arange(-70.,71.)
    cases=[]
    for center in [-20., 5.]:
        for amplitude in [30., 100.]:
            truth=[90., .02, 120., amplitude, center, 18.]
            result=fit(profile(x,truth,2),x,2)
            error=abs(result['best']['center']-center)
            assert error < .1, (truth,result)
            cases.append(dict(center=center,amplitude=amplitude,error=error))
    return cases


def run(image, candidate, output):
    from PIL import Image, ImageOps, ImageDraw
    import pillow_heif
    from track_card_paths import samples
    pillow_heif.register_heif_opener()
    source=json.loads(candidate.read_text())
    digest=hashlib.sha256(image.read_bytes()).hexdigest()
    if digest != source['inputSHA256']:raise ValueError('capture mismatch')
    im=ImageOps.exif_transpose(Image.open(image)).convert('RGB')
    pixels=np.asarray(im,dtype=float).mean(2)
    record=source['frames']['outer']['bottom'];normal=np.array(record['normal'])
    tangent=np.array([normal[1],-normal[0]])
    offsets=np.arange(-70.,71.);rows=[]
    # Nine evenly spaced observations diagnose model identity before a full path.
    for index in np.linspace(0,len(record['rows'])-1,9).round().astype(int):
        base=np.array(record['rows'][index]['point']);trials=[]
        for halfwidth in [4,8,16]:
            values=samples(pixels,base[None],normal,tangent,offsets,halfwidth)[0]
            for sigma in [2.,4.]:
                trials.append(dict(halfwidth=halfwidth,sigma=sigma,**fit(values,offsets,sigma)))
        centers=[t['best']['center'] for t in trials]
        lo=min(t['competitiveCenterRange'][0] for t in trials)
        hi=max(t['competitiveCenterRange'][1] for t in trials)
        stable=hi-lo<=4 and all(t['best']['converged'] and not any(t['best']['activeBounds'])
                              and t['best']['rms']<=5 for t in trials)
        point=base+np.median(centers)*normal
        row=dict(index=int(index),base=base.tolist(),point=point.tolist(),
                 centerRange=[lo,hi],stable=bool(stable),trials=trials)
        rows.append(row)
        print(json.dumps({k:v for k,v in row.items() if k!='trials'}),flush=True)
    output.mkdir(parents=True,exist_ok=True)
    result=dict(fixture=source['fixture'],inputSHA256=digest,
        candidateSHA256=hashlib.sha256(candidate.read_bytes()).hexdigest(),rows=rows,
        stableCount=sum(r['stable'] for r in rows),syntheticControls=synthetic(),
        status='diagnostic only; no full supported path or accuracy claim',
        limitation='Brighter-background cut-plus-exponential-shadow assumption; model sensitivity is not calibrated uncertainty')
    (output/'shadow-probe.json').write_text(json.dumps(result,indent=2)+'\n')
    points=np.array([r['base'] for r in rows])
    x0,y0=np.maximum(0,np.floor(points.min(0)-90)).astype(int)
    x1,y1=np.minimum(im.size,np.ceil(points.max(0)+90)).astype(int)
    crop=im.crop((x0,y0,x1,y1));draw=ImageDraw.Draw(crop)
    for row in rows:
        x,y=row['point'];draw.ellipse((x-x0-3,y-y0-3,x-x0+3,y-y0+3),fill='lime' if row['stable'] else 'red')
    crop.save(output/'shadow-probe.png')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['image','candidate','output']:p.add_argument(name,type=Path)
    a=p.parse_args();run(a.image,a.candidate,a.output)
