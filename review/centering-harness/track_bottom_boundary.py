#!/usr/bin/env python3
"""Continuity experiment from a saved detector cut, without reviewed coordinates.

Tracks competing brightening boundaries inside a broad detector-relative band.
Endpoint strength is a hypothesis, not proof of physical-card identity. Raw path,
competing paths and all local fits remain available for semantic review.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps, ImageDraw
import pillow_heif
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks
from local_transition_probe import fit


def track(gradients, start, end, smooth_sigma=4,position_sigma=None):
    n,m=gradients.shape
    unary=-np.log(np.maximum(gradients,0)/np.maximum(gradients.max(1,keepdims=True),1e-6)+.01)
    if position_sigma is not None:
        unary+=(np.arange(m)-(m-1)/2)**2/(2*position_sigma**2)
    idx=np.arange(m);delta=idx[:,None]-idx[None,:]
    transition=delta**2/(2*smooth_sigma**2)
    transition[np.abs(delta)>8]=np.inf
    score=np.full(m,np.inf);score[start]=unary[0,start]
    previous=np.zeros((n,m),dtype=int)
    for i in range(1,n):
        choices=score[:,None]+transition
        previous[i]=choices.argmin(0)
        score=choices.min(0)+unary[i]
    path=np.zeros(n,dtype=int);path[-1]=end
    for i in range(n-1,0,-1):path[i-1]=previous[i,path[i]]
    return path,float(score[end])


def analyze(image,baseline,output,fixture,seed_offset=0):
    pillow_heif.register_heif_opener()
    im=ImageOps.exif_transpose(Image.open(image)).convert('RGB')
    a=np.asarray(im,dtype=float).mean(2)
    record=next(r for r in json.loads(baseline.read_text()) if r['fixture']==fixture)
    q=record['actualOuter'];left=q['bottomLeft'];right=q['bottomRight']
    u=np.linspace(.1,.9,61)
    xs=np.rint(left['x']+u*(right['x']-left['x'])).astype(int)
    seeds=np.rint(left['y']+u*(right['y']-left['y'])).astype(int)+seed_offset
    offsets=np.arange(-80,81)
    if xs.min()<16 or xs.max()>=im.width-16 or seeds.min()-80<0 or seeds.max()+80>=im.height:
        raise ValueError('detector band does not fit photo')
    gradients=[]
    for x,y in zip(xs,seeds):
        p=a[y+offsets,x-4:x+5].mean(1)
        g=gaussian_filter1d(p,2,order=1);g[:8]=g[-8:]=0;gradients.append(g)
    gradients=np.array(gradients)
    anchors=[]
    for row in [gradients[0],gradients[-1]]:
        peaks=find_peaks(row,distance=12,prominence=.5)[0]
        peaks=sorted(peaks,key=lambda i:row[i],reverse=True)[:3]
        if not peaks:raise ValueError('no endpoint boundary support')
        anchors.append(peaks)
    hypotheses=[]
    for ai,start in enumerate(anchors[0]):
        for bi,end in enumerate(anchors[1]):
            path,cost=track(gradients,start,end)
            hypotheses.append(dict(endpointRanks=[ai,bi],cost=cost,
                                   y=(seeds+offsets[path]).tolist()))
    # Freeze endpoint-strength choice. Other paths are evidence, not silently
    # selected according to reviewed coordinates or expected centering.
    selected=hypotheses[0]
    rows=[]
    for x,y in zip(xs,selected['y']):
        trials=[]
        for halfwidth in [4,8,16]:
            ys=np.arange(y-28,y+29)
            profile=a[ys,x-halfwidth:x+halfwidth+1].mean(1)
            for family in ['erf','logistic']:
                trials.append(dict(stripWidth=2*halfwidth+1,family=family,**fit(profile,ys,family)))
        centers=[r['center'] for r in trials]
        rows.append(dict(x=int(x),pathY=y,center=float(np.median(centers)),
            sensitivityRange=[min(centers),max(centers)],
            stable=bool(max(centers)-min(centers)<=4 and all(
                r['converged'] and not r['atBound'] and r['relativeRMS']<=.15 for r in trials)),trials=trials))
    stable=np.array([r['stable'] for r in rows])
    receipt=dict(inputSHA256=hashlib.sha256(image.read_bytes()).hexdigest(),fixture=fixture,
        baselineSHA256=hashlib.sha256(baseline.read_bytes()).hexdigest(),
        search='saved detector bottom +/-80 native pixels; central 80% span',
        parameters=dict(sampleCount=61,gradientSigma=2,smoothSigma=4,maxStep=8,fitRadius=28,
                        seedOffset=seed_offset),
        hypotheses=hypotheses,rows=rows,stableCount=int(stable.sum()),
        occupiedBins=sorted(set(np.minimum(4,np.arange(61)[stable]*5//61).tolist())),
        status='endpoint-strength hypothesis requires card/sleeve identity review')
    output.mkdir(parents=True,exist_ok=True)
    (output/'tracked-boundary.json').write_text(json.dumps(receipt,indent=2)+'\n')
    box=(int(xs.min()-20),int(seeds.min()-90),int(xs.max()+20),int(seeds.max()+90))
    crop=im.crop(box);draw=ImageDraw.Draw(crop)
    for hypothesis in hypotheses:
        if hypothesis['endpointRanks'] in [[0,0],[1,1]]:
            draw.line([(float(x-box[0]),float(y-box[1])) for x,y in zip(xs,hypothesis['y'])],
                      fill='yellow' if hypothesis['endpointRanks']==[0,0] else 'magenta',width=2)
    for row in rows:
        x=row['x']-box[0];y=row['center']-box[1]
        draw.ellipse((x-2,y-2,x+2,y+2),fill='lime' if row['stable'] else 'red')
    crop.save(output/'tracked-boundary.png')
    print(json.dumps(dict(stableCount=receipt['stableCount'],occupiedBins=receipt['occupiedBins'],
        hypotheses=[{k:v for k,v in h.items() if k!='y'} for h in hypotheses])))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('image',type=Path);p.add_argument('baseline',type=Path)
    p.add_argument('output',type=Path);p.add_argument('--fixture',required=True)
    p.add_argument('--seed-offset',type=int,default=0)
    args=p.parse_args();analyze(args.image,args.baseline,args.output,args.fixture,args.seed_offset)
