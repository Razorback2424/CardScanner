#!/usr/bin/env python3
"""Compare global registration with a low-order residual field on held-out features.

The polynomial is fitted to interior feature matches, not photo edge annotations.
RANSAC filtering used all matches before this control; residuals remain optimistic.
"""
import argparse,json
from pathlib import Path
import cv2
import numpy as np
from register_print_reference import project


def basis(points,size):
    x,y=(np.array(points)/size-.5).T
    return np.array([np.ones(len(x)),x,y,x*x,x*y,y*y]).T


def fit(a,b,size):
    h,_=cv2.findHomography(a,b,0)
    design=basis(a,size);residual=b-project(a,h);weights=np.ones(len(a))
    for _ in range(5):
        coefficients=np.linalg.lstsq(design*weights[:,None]**.5,residual*weights[:,None]**.5,rcond=None)[0]
        error=np.linalg.norm(design@coefficients-residual,axis=1)
        weights=np.minimum(1,3/np.maximum(error,1e-9))
    return h,coefficients


def predict(a,h,c,size):return project(a,h)+basis(a,size)@c


def summary(error):return dict(median=float(np.median(error)),p95=float(np.percentile(error,95)),worst=float(max(error)))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('registration',type=Path)
    p.add_argument('output',type=Path);p.add_argument('--size',nargs=2,type=float,required=True)
    p.add_argument('--reference-top',type=float,required=True)
    args=p.parse_args();r=json.loads(args.registration.read_text())
    if not r['accepted']:raise ValueError('registration was not accepted')
    rows=[m for m in r['matchesNative'] if m['inlier']]
    a=np.array([m['reference'] for m in rows]);b=np.array([m['photo'] for m in rows]);size=np.array(args.size)
    groups=(np.floor(a[:,0]/size[0]*8)+np.floor(a[:,1]/size[1]*8)).astype(int)%2
    points=np.c_[np.linspace(.1*size[0],.9*size[0],61),np.full(61,args.reference_top)]
    h,c=fit(a,b,size);prediction=predict(points,h,c,size);controls=[]
    for group in [0,1]:
        train=groups!=group;held=~train;gh,gc=fit(a[train],b[train],size)
        global_error=np.linalg.norm(project(a[held],gh)-b[held],axis=1)
        corrected_error=np.linalg.norm(predict(a[held],gh,gc,size)-b[held],axis=1)
        controls.append(dict(group=group,globalResidual=summary(global_error),
            correctedResidual=summary(corrected_error),
            projectedTopChange=summary(np.linalg.norm(predict(points,gh,gc,size)-prediction,axis=1))))
    result=dict(referenceSHA256=r['referenceSHA256'],inputSHA256=r['inputSHA256'],
        coefficients=c.tolist(),homography=h.tolist(),size=size.tolist(),referenceTop=args.reference_top,
        referenceTopPoints=points.tolist(),predictedTop=prediction.tolist(),
        globalTop=project(points,h).tolist(),controls=controls,
        status='interior-feature distortion control; top boundary not yet scored against native evidence')
    args.output.write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(controls))
