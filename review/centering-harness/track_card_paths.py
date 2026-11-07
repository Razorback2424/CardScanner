#!/usr/bin/env python3
"""All-side detector-seeded path experiment; no annotation or app writes.

Physical and printed boundaries remain separate. Endpoint polarity/strength is
an explicit identity hypothesis, not a certified boundary selection.
"""
import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image,ImageOps,ImageDraw
import pillow_heif
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks
from gt_tool import edge_points,edge_normal
from track_bottom_boundary import track
from local_transition_probe import fit


def samples(gray,bases,normal,tangent,offsets,halfwidth,dense=False):
    result=[]
    count=max(9,int(np.ceil(2*halfwidth))+1) if dense else 9
    for shift in np.linspace(-halfwidth,halfwidth,count):
        pts=bases[:,None,:]+offsets[None,:,None]*normal+shift*tangent
        if np.any(pts<0) or np.any(pts[:,:,0]>=gray.shape[1]-1) or np.any(pts[:,:,1]>=gray.shape[0]-1):
            raise ValueError('sampling band exceeds image')
        result.append(cv2.remap(gray,pts[:,:,0].astype('float32'),pts[:,:,1].astype('float32'),cv2.INTER_LINEAR))
    return np.mean(result,axis=0)


def gradient_refinement(profile,offsets,center,sigma):
    g=gaussian_filter1d(profile,sigma,order=1,axis=0)
    if profile.ndim==2:g=np.abs(g).mean(axis=1)
    region=np.flatnonzero(abs(offsets-center)<=6)
    i=int(region[np.argmax(g[region])]);peak=float(g[i]);correction=0.
    if 0<i<len(g)-1:
        curvature=float(g[i-1]-2*g[i]+g[i+1])
        if curvature < -1e-9:correction=float(np.clip(.5*(g[i-1]-g[i+1])/curvature,-.5,.5))
    left=right=i
    while left>0 and g[left-1]>=peak/2:left-=1
    while right<len(g)-1 and g[right+1]>=peak/2:right+=1
    return dict(center=float(offsets[i]+correction),width=right-left+1,peak=peak,
                boundaryHit=bool(i in [region[0],region[-1]]))


def boundary(gray,quad,side,position_sigma=None,adaptive_sharp=False,physical_background=False,dense=False,expected_polarity=None):
    color_contrast=gray.ndim==3
    if expected_polarity not in [None,1,-1]:raise ValueError('invalid expected polarity')
    if expected_polarity is not None and (physical_background or color_contrast):
        raise ValueError('reference polarity cannot override background or RGB inference')
    if color_contrast and physical_background:raise ValueError('background polarity needs a scalar signal')
    a,b=np.array(edge_points(quad,side));vector=b-a
    tangent=vector/np.linalg.norm(vector);normal=-np.array(edge_normal(quad,side))
    bases=a+np.linspace(.1,.9,61)[:,None]*vector
    offsets=np.arange(-80,81)
    background_evidence=None
    if physical_background:
        if position_sigma is not None:
            raise ValueError('background probe does not use a positional prior')
        # Keep only positions actually present in the image. Do not pad or
        # clamp an exterior strip into artificial supporting observations.
        valid=np.ones(len(offsets),dtype=bool)
        for shift in [-4,4]:
            pts=bases[:,None,:]+offsets[None,:,None]*normal+shift*tangent
            valid&=np.all((pts[:,:,0]>=0)&(pts[:,:,0]<gray.shape[1]-1)&
                          (pts[:,:,1]>=0)&(pts[:,:,1]<gray.shape[0]-1),axis=0)
        offsets=offsets[valid]
        if len(offsets)<57:raise ValueError('insufficient observed background search span')
    raw=samples(gray,bases,normal,tangent,offsets,4,dense)
    polarities=[expected_polarity] if expected_polarity is not None else [1,-1]
    if physical_background:
        # The normal points outward. Require agreement across the sampled side
        # before using background contrast to distinguish cut from print.
        delta=np.median(raw[:,-10:],axis=1)-np.median(raw[:,:10],axis=1)
        positive=float(np.mean(delta>=10));negative=float(np.mean(delta<=-10))
        if max(positive,negative)<.8:raise ValueError('inconsistent exterior contrast')
        polarities=[1 if positive>negative else -1]
        background_evidence=dict(outwardPolarity=polarities[0],agreement=max(positive,negative),
            contrastThreshold=10,requiredAgreement=.8,medianContrast=float(np.median(delta)),
            observedSearchRange=[int(offsets[0]),int(offsets[-1])],
            limitation='Background polarity is an identity hypothesis; shadows and sleeves remain possible')
    gradient=gaussian_filter1d(raw,2,axis=1,order=1)
    if color_contrast:
        # Printed foil may reverse luminance polarity along one side. Retain
        # observed RGB contrast rather than selecting one polarity for the side.
        gradient=np.abs(gradient).mean(axis=2)
        polarities=[1]
    hypotheses=[]
    for sign in polarities:
        g=sign*gradient;g[:,:8]=g[:,-8:]=0
        anchors=[]
        for row in [g[0],g[-1]]:
            peaks=find_peaks(row,distance=12,prominence=.5)[0]
            anchors.append(sorted(peaks,key=lambda i:row[i],reverse=True)[:3])
        if any(not v for v in anchors):continue
        for ai,start in enumerate(anchors[0]):
            for bi,end in enumerate(anchors[1]):
                path,cost=track(g,start,end,position_sigma=position_sigma)
                endpoint_support=float(min(g[0,start],g[-1,end]))
                if position_sigma is not None:
                    endpoint_support=min(float(g[0,start])/(1+(offsets[start]/position_sigma)**2),
                                         float(g[-1,end])/(1+(offsets[end]/position_sigma)**2))
                hypotheses.append(dict(polarity=sign,endpointRanks=[ai,bi],cost=cost,
                    endpointSupport=endpoint_support,offsets=offsets[path].tolist()))
    if not hypotheses:raise ValueError('no supported endpoint pair')
    # Choose polarity/anchors once, without consulting image annotations.
    selected=max(hypotheses,key=lambda h:h['endpointSupport'])
    path=np.array(selected['offsets']);rows=[]
    for i,base in enumerate(bases):
        local=np.arange(path[i]-28,path[i]+29);trials=[];gradient_trials=[]
        for halfwidth in [4,8,16]:
            p=samples(gray,base[None],normal,tangent,local,halfwidth,dense)[0]
            if selected['polarity']==-1:p=255-p
            for sigma in [1,2]:
                gradient_trials.append(dict(stripWidth=2*halfwidth+1,sigma=sigma,
                    **gradient_refinement(p,local,path[i],sigma)))
            if not color_contrast:
                for family in ['erf','logistic']:
                    trials.append(dict(stripWidth=2*halfwidth+1,family=family,**fit(p,local,family)))
        use_gradient=color_contrast or (adaptive_sharp and np.median([r['width'] for r in gradient_trials])<=8)
        centers=[r['center'] for r in (gradient_trials if use_gradient else trials)]
        center=float(np.median(centers))
        supported=all(r['peak']>=2.5 and not r['boundaryHit'] for r in gradient_trials) if use_gradient else all(
            r['converged'] and not r['atBound'] and r['relativeRMS']<=.15 for r in trials)
        rows.append(dict(base=base.tolist(),point=(base+center*normal).tolist(),offset=center,
            sensitivityRange=[min(centers),max(centers)],
            stable=bool(max(centers)-min(centers)<=4 and supported),trials=trials,
            estimator='rgb_gradient_peak' if color_contrast else ('gradient_peak' if use_gradient else 'blurred_step'),gradientTrials=gradient_trials))
    stable=np.array([r['stable'] for r in rows])
    return dict(side=side,normal=normal.tolist(),selected=selected,hypotheses=hypotheses,rows=rows,
        backgroundEvidence=background_evidence,
        stableCount=int(stable.sum()),occupiedBins=sorted(set(np.minimum(4,np.arange(61)[stable]*5//61).tolist())))


def image_signal(im,signal='rgb_mean'):
    rgb=np.asarray(im,dtype='float32')
    if signal=='color_contrast':return rgb
    if signal=='lab_chroma':
        lab=cv2.cvtColor(rgb/255,cv2.COLOR_RGB2LAB)
        return np.sqrt(lab[:,:,1]**2+lab[:,:,2]**2)
    return rgb.mean(2)


def analyze(image,baseline,output,fixture,position_sigma=None,frame_filter=None,side_filter=None,adaptive_sharp=False,signal='rgb_mean',physical_background=False,dense=False,expected_polarity=None):
    if physical_background and (frame_filter!='outer' or signal!='rgb_mean'):
        raise ValueError('background contrast applies only to physical RGB-mean paths')
    pillow_heif.register_heif_opener();im=ImageOps.exif_transpose(Image.open(image)).convert('RGB')
    gray=image_signal(im,signal)
    record=next(r for r in json.loads(baseline.read_text()) if r['fixture']==fixture)
    results={};overlay=im.copy();draw=ImageDraw.Draw(overlay)
    for frame,key in [('outer','actualOuter'),('inner','actualInner')]:
        if frame_filter and frame!=frame_filter:continue
        q=record.get(key)
        if q is None:results[frame]=dict(error='no baseline frame');continue
        quad=[[q[p]['x'],q[p]['y']] for p in ['topLeft','topRight','bottomRight','bottomLeft']]
        results[frame]={}
        for side in ['left','top','right','bottom']:
            if side_filter and side!=side_filter:continue
            try:
                r=boundary(gray,quad,side,position_sigma,adaptive_sharp,physical_background,dense,expected_polarity);results[frame][side]=r
                draw.line([tuple(row['point']) for row in r['rows']],fill='cyan' if frame=='outer' else 'lime',width=5)
                print(frame,side,'polarity',r['selected']['polarity'],'stable',r['stableCount'],flush=True)
            except ValueError as e:results[frame][side]=dict(error=str(e))
    output.mkdir(parents=True,exist_ok=True)
    receipt=dict(fixture=fixture,inputSHA256=hashlib.sha256(image.read_bytes()).hexdigest(),
        baselineSHA256=hashlib.sha256(baseline.read_bytes()).hexdigest(),frames=results,
        positionSigma=position_sigma,
        frameFilter=frame_filter,sideFilter=side_filter,adaptiveSharp=adaptive_sharp,signal=signal,
        physicalBackground=physical_background,
        denseStripSampling=dense,
        expectedOutwardPolarity=expected_polarity,
        status='identity hypothesis; inspect all boundaries before calculating centering')
    (output/'card-paths.json').write_text(json.dumps(receipt,indent=2)+'\n')
    overlay.thumbnail((1008,1344));overlay.save(output/'card-paths.png')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('image',type=Path);p.add_argument('baseline',type=Path)
    p.add_argument('output',type=Path);p.add_argument('--fixture',required=True)
    p.add_argument('--position-sigma',type=float)
    p.add_argument('--frame',choices=['outer','inner'])
    p.add_argument('--side',choices=['left','top','right','bottom'])
    p.add_argument('--adaptive-sharp',action='store_true')
    p.add_argument('--signal',choices=['rgb_mean','lab_chroma','color_contrast'],default='rgb_mean')
    p.add_argument('--physical-background',action='store_true',help='Research-only exterior-contrast polarity and observed search clipping')
    p.add_argument('--dense-strips',action='store_true',help='Diagnostic tangent samples at no more than one-pixel spacing')
    p.add_argument('--outward-polarity',type=int,choices=[-1,1],help='Explicit reference-boundary polarity; never inferred from expected ratios')
    args=p.parse_args()
    if args.position_sigma is not None and args.position_sigma<=0:p.error('position sigma must be positive')
    analyze(args.image,args.baseline,args.output,args.fixture,args.position_sigma,args.frame,args.side,args.adaptive_sharp,args.signal,args.physical_background,args.dense_strips,args.outward_polarity)
