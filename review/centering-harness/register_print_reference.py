#!/usr/bin/env python3
"""Exact-print recognition control using interior features, never photo annotations.

Global alignment supplies feature identity. Residuals and spatial coverage are
reported separately; recognition does not certify edge geometry or centering.
"""
import argparse,hashlib,json
from pathlib import Path
import cv2
import numpy as np
from PIL import Image,ImageOps,ImageDraw
import pillow_heif


def project(points,h):
    p=np.c_[points,np.ones(len(points))]@h.T
    return p[:,:2]/p[:,2,None]


def register(reference,photo,native_resolution=False,signal='luminance'):
    cv2.setRNGSeed(4827);cv2.setNumThreads(1)
    mask=np.zeros(reference.shape[:2],np.uint8);rh,rw=mask.shape
    mask[int(.05*rh):int(.95*rh),int(.05*rw):int(.95*rw)]=255
    ordinary_scale=min(1,1200/max(photo.shape[:2]));scale=1 if native_resolution else ordinary_scale
    small=photo if scale==1 else cv2.resize(photo,None,fx=scale,fy=scale,interpolation=cv2.INTER_AREA)
    def feature_image(rgb):
        gray=cv2.cvtColor(rgb,cv2.COLOR_RGB2GRAY)
        if signal=='luminance':return gray
        if signal!='gradientMagnitude':raise ValueError('unknown registration signal')
        # A bounded diagnostic for foil-induced contrast reversals. Registration
        # still needs independent artwork coverage; edge energy is not identity.
        blurred=cv2.GaussianBlur(gray.astype('float32'),(0,0),1)
        gx=cv2.Sobel(blurred,cv2.CV_32F,1,0,ksize=3)
        gy=cv2.Sobel(blurred,cv2.CV_32F,0,1,ksize=3)
        magnitude=cv2.magnitude(gx,gy)
        return cv2.normalize(magnitude,None,0,255,cv2.NORM_MINMAX).astype('uint8')
    sift=cv2.SIFT_create();kr,dr=sift.detectAndCompute(feature_image(reference),mask)
    kp,dp=sift.detectAndCompute(feature_image(small),None)
    pairs=[] if dr is None or dp is None or len(dp)<2 else cv2.BFMatcher().knnMatch(dr,dp,k=2)
    pairs=[a for a,b in pairs if a.distance<.72*b.distance]
    seen=set();unique=[]
    for m in sorted(pairs,key=lambda m:m.distance):
        if m.trainIdx not in seen:unique.append(m);seen.add(m.trainIdx)
    receipt=dict(matches=len(unique),accepted=False,signal=signal,photoWorkingSize=[small.shape[1],small.shape[0]],
                 ransacThresholdWorking=2.5*scale/ordinary_scale)
    if len(unique)<20:return receipt
    a=np.array([kr[m.queryIdx].pt for m in unique]);b=np.array([kp[m.trainIdx].pt for m in unique])
    h,keep=cv2.findHomography(a,b,cv2.RANSAC,receipt['ransacThresholdWorking'])
    if h is None:return receipt
    selected=keep.ravel().astype(bool);norm=a[selected]/[rw,rh]
    quadrants=len(set(tuple(v>.5) for v in norm));span=np.ptp(norm,axis=0)
    sx,sy=photo.shape[1]/small.shape[1],photo.shape[0]/small.shape[0]
    upscale=np.array([[sx,0,(sx-1)/2],[0,sy,(sy-1)/2],[0,0,1.]])
    native=project(b,upscale);h=upscale@h
    residual=project(a,h)-native;error=np.linalg.norm(residual,axis=1)
    bands={}
    for name,condition in [('top',a[:,1]<.2*rh),('middle',(a[:,1]>=.2*rh)&(a[:,1]<=.8*rh)),('bottom',a[:,1]>.8*rh)]:
        take=condition&selected
        bands[name]=dict(count=int(take.sum()),median=float(np.median(error[take])) if take.any() else None,
                         p95=float(np.percentile(error[take],95)) if take.any() else None)
    # Spatial checkerboard holdout avoids random halves sharing every region.
    groups=(np.floor(a[:,0]/rw*8)+np.floor(a[:,1]/rh*8)).astype(int)%2
    controls=[]
    for group in [0,1]:
        train=selected&(groups!=group);test=selected&(groups==group)
        if train.sum()<20 or test.sum()<10:continue
        fit,_=cv2.findHomography(a[train],native[train],0)
        e=np.linalg.norm(project(a[test],fit)-native[test],axis=1)
        controls.append(dict(group=group,train=int(train.sum()),heldOut=int(test.sum()),
                             median=float(np.median(e)),p95=float(np.percentile(e,95)),worst=float(e.max())))
    receipt.update(accepted=bool(selected.sum()>=20 and quadrants==4 and min(span)>.5),
        inliers=int(selected.sum()),quadrants=quadrants,referenceSpan=span.tolist(),homography=h.tolist(),
        bandResiduals=bands,spatialHoldout=controls,
        matchesNative=[dict(reference=x.tolist(),photo=y.tolist(),inlier=bool(k),error=float(e)) for x,y,k,e in zip(a,native,selected,error)],
        limitation='RANSAC-filtered holdout residuals are optimistic; projected boundaries remain unverified')
    return receipt


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['reference','photo','output']:p.add_argument(name,type=Path)
    p.add_argument('--native',action='store_true')
    p.add_argument('--signal',choices=['luminance','gradientMagnitude'],default='luminance')
    args=p.parse_args();pillow_heif.register_heif_opener()
    ref=np.asarray(Image.open(args.reference).convert('RGB'))
    photo=np.asarray(ImageOps.exif_transpose(Image.open(args.photo)).convert('RGB'))
    result=register(ref,photo,args.native,args.signal)
    result.update(referenceSHA256=hashlib.sha256(args.reference.read_bytes()).hexdigest(),
                  inputSHA256=hashlib.sha256(args.photo.read_bytes()).hexdigest())
    args.output.mkdir(parents=True,exist_ok=True)
    (args.output/'registration.json').write_text(json.dumps(result,indent=2)+'\n')
    if result['accepted']:
        im=Image.fromarray(photo);d=ImageDraw.Draw(im)
        for m in result['matchesNative']:
            if m['inlier']:
                x,y=m['photo'];d.ellipse((x-5,y-5,x+5,y+5),fill='cyan')
        im.thumbnail((756,1008));im.save(args.output/'matches.png')
    print(json.dumps({k:v for k,v in result.items() if k not in ['matchesNative','homography']}))
