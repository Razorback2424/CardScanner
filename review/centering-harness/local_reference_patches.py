#!/usr/bin/env python3
"""Local content-registration diagnostic using reference-only patch rectangles.

Runs fixed scale/translation controls in globally aligned reference coordinates.
These matches diagnose local layout; they do not measure the physical cut.
"""
import argparse,hashlib,json
from pathlib import Path
import cv2
import numpy as np
from PIL import Image,ImageOps
import pillow_heif


def run(reference,photo,registration,spec,output):
    r=json.loads(registration.read_text());patches=json.loads(spec.read_text())
    if not r['accepted']:raise ValueError('reference not recognized')
    for path,key in [(reference,'referenceSHA256'),(photo,'inputSHA256')]:
        if hashlib.sha256(path.read_bytes()).hexdigest()!=r[key]:raise ValueError('capture/reference mismatch')
    pillow_heif.register_heif_opener()
    ref=np.asarray(Image.open(reference).convert('RGBA').convert('RGB'))
    im=np.asarray(ImageOps.exif_transpose(Image.open(photo)).convert('RGB'))
    up=4;h=np.array(r['homography']);zoom=np.diag([up,up,1.])
    warped=cv2.warpPerspective(im,zoom@np.linalg.inv(h),(ref.shape[1]*up,ref.shape[0]*up))
    warped=cv2.cvtColor(warped,cv2.COLOR_RGB2GRAY)
    gray=cv2.cvtColor(ref,cv2.COLOR_RGB2GRAY);results=[]
    for patch in patches:
        x0,y0,x1,y1=patch['rect'];cx=(x0+x1)/2;cy=(y0+y1)/2
        original=gray[y0:y1,x0:x1];trials=[]
        for scale in [.8,.9,1.,1.1,1.2]:
            template=cv2.resize(original,None,fx=up*scale,fy=up*scale,interpolation=cv2.INTER_CUBIC)
            th,tw=template.shape
            sx=int(round(cx*up-tw/2))-16*up;sy=int(round(cy*up-th/2))-16*up
            ex=sx+tw+32*up;ey=sy+th+32*up
            if min(sx,sy)<0 or ex>warped.shape[1] or ey>warped.shape[0]:continue
            response=cv2.matchTemplate(warped[sy:ey,sx:ex],template,cv2.TM_CCOEFF_NORMED)
            _,value,_,location=cv2.minMaxLoc(response);xx,yy=location;sub=[]
            for axis in [0,1]:
                pos=xx if axis==0 else yy;length=response.shape[1-axis]
                if 0<pos<length-1:
                    a,b,c=response[yy,xx-1:xx+2] if axis==0 else response[yy-1:yy+2,xx]
                    curvature=float(a-2*b+c);sub.append(float(np.clip(.5*(a-c)/curvature,-.5,.5)) if curvature<-1e-9 else 0.)
                else:sub.append(0.)
            center=[(sx+xx+sub[0]+tw/2)/up,(sy+yy+sub[1]+th/2)/up]
            trials.append(dict(scale=scale,score=float(value),center=center,
                displacement=[center[0]-cx,center[1]-cy],searchBoundary=bool(xx in [0,response.shape[1]-1] or yy in [0,response.shape[0]-1])))
        best=max(trials,key=lambda v:v['score']);results.append(dict(**patch,best=best,trials=trials))
    output.write_text(json.dumps(dict(referenceSHA256=r['referenceSHA256'],inputSHA256=r['inputSHA256'],
        workingScale=up,searchRadiusReferencePixels=16,results=results,
        status='local printed-content alignment, not centering measurement'),indent=2)+'\n')
    print(json.dumps([dict(name=p['name'],**p['best']) for p in results]))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['reference','photo','registration','spec','output']:p.add_argument(name,type=Path)
    a=p.parse_args();run(a.reference,a.photo,a.registration,a.spec,a.output)
