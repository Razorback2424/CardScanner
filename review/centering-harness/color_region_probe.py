#!/usr/bin/env python3
"""Offline RGB region-transition probe; never writes app geometry or truth.

Recognized-design paths supply search locations. Shared transition position and
blur are fitted across channels, with separate channel means/slopes/amplitudes.
All six strip/family fits must agree; missing support remains missing.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
from scipy.optimize import least_squares
from scipy.special import erf, expit
import pillow_heif
from track_card_paths import samples


def fit_region(profile, offsets, seed, family):
    t=offsets-offsets.mean()
    def model(parameters):
        center,width=parameters
        z=(offsets-center)/width
        step=.5*(1+erf(z/np.sqrt(2))) if family=='erf' else expit(1.7*z)
        design=np.c_[np.ones(len(t)),t,step]
        coefficients=np.linalg.lstsq(design,profile,rcond=None)[0]
        return design@coefficients-profile,coefficients
    fits=[least_squares(lambda p:model(p)[0].ravel(),[seed+shift,2],
        bounds=([seed-12,.5],[seed+12,8]),loss='soft_l1',f_scale=4,max_nfev=100)
        for shift in [-6,0,6]]
    result=min(fits,key=lambda r:r.cost)
    residual,coefficients=model(result.x)
    amplitude=float(np.sqrt(np.mean(coefficients[2]**2)))
    rms=float(np.sqrt(np.mean(residual**2)))
    return dict(center=float(result.x[0]),blurWidth=float(result.x[1]),
        amplitude=amplitude,relativeRMS=rms/max(amplitude,1e-9),
        converged=bool(result.success),centerAtBound=bool(result.active_mask[0]),
        blurAtUpperBound=bool(result.active_mask[1]>0))


def refine(rgb,record,halfwidths=(4,8,16)):
    normal=np.asarray(record['normal']);tangent=np.array([-normal[1],normal[0]])
    rows=[]
    for index,old in enumerate(record['rows']):
        base=np.asarray(old['base']);seed=record['selected']['offsets'][index]
        offsets=np.arange(seed-28,seed+29,dtype=float);trials=[]
        for halfwidth in halfwidths:
            profile=samples(rgb,base[None],normal,tangent,offsets,halfwidth,dense=True)[0]
            for family in ['erf','logistic']:
                trials.append(dict(stripWidth=2*halfwidth+1,family=family,
                    **fit_region(profile,offsets,seed,family)))
        centers=[r['center'] for r in trials];center=float(np.median(centers))
        stable=max(centers)-min(centers)<=4 and all(r['converged'] and
            not r['centerAtBound'] and not r['blurAtUpperBound'] and
            r['amplitude']>=5 and r['relativeRMS']<=.15 for r in trials)
        rows.append(dict(base=base.tolist(),point=(base+center*normal).tolist(),offset=center,
            sensitivityRange=[min(centers),max(centers)],stable=bool(stable),
            estimator='shared_rgb_region_transition',trials=trials))
    return dict(side=record['side'],normal=normal.tolist(),selected=record['selected'],
        rows=rows,stableCount=sum(r['stable'] for r in rows))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['image','candidate','output']:p.add_argument(name,type=Path)
    p.add_argument('--side',choices=['left','top','right','bottom'])
    p.add_argument('--strip-half-widths',type=int,nargs=3,default=[4,8,16],
        help='Fixed spatial averaging perturbations; keeps all fit and agreement limits unchanged')
    a=p.parse_args();pillow_heif.register_heif_opener()
    if not (0<a.strip_half_widths[0]<a.strip_half_widths[1]<a.strip_half_widths[2]<=128):
        p.error('Require three increasing positive strip half-widths no larger than 128')
    candidate=json.loads(a.candidate.read_text());digest=hashlib.sha256(a.image.read_bytes()).hexdigest()
    if digest!=candidate['inputSHA256']:raise ValueError('capture mismatch')
    rgb=np.asarray(ImageOps.exif_transpose(Image.open(a.image)).convert('RGB'),dtype='float32')
    frames={'inner':{}}
    for side,record in candidate['frames']['inner'].items():
        if a.side and side!=a.side:continue
        frames['inner'][side]=refine(rgb,record,a.strip_half_widths)
        print(side,frames['inner'][side]['stableCount'],flush=True)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(dict(fixture=candidate['fixture'],inputSHA256=digest,
        candidateSHA256=hashlib.sha256(a.candidate.read_bytes()).hexdigest(),frames=frames,
        stripHalfWidths=a.strip_half_widths,
        limitation='Region model agreement is not calibrated accuracy or physical boundary identity'),indent=2)+'\n')
