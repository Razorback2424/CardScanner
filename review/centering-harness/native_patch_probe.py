#!/usr/bin/env python3
"""Host diagnostic using the app's C patch matcher and saved physical quads.

Pillow image preparation differs from CoreGraphics, so this is not native-app
acceptance. Opposite-polarity matching is an explicit optional experiment.
"""
import argparse,base64,ctypes,hashlib,json
from pathlib import Path
import numpy as np
from PIL import Image,ImageOps
import pillow_heif
from build_print_reference import render_signal


def probe(image,reference,baseline,library,either=False):
    digest=hashlib.sha256(image.read_bytes()).hexdigest()
    row=next(r for r in baseline if r['fixture']==image.stem)
    if row['inputSHA256']!=digest:raise ValueError('capture mismatch')
    quad=np.array([[row['actualOuter'][c][k] for k in ['x','y']]
        for c in ['topLeft','topRight','bottomRight','bottomLeft']])
    im=ImageOps.exif_transpose(Image.open(image))
    scale=min(1,320/((np.linalg.norm(quad[1]-quad[0])+np.linalg.norm(quad[2]-quad[3]))/2))
    w,h=round(im.width*scale),round(im.height*scale)
    corners=np.array(quad*[w/im.width,h/im.height],dtype='float64')
    u8=ctypes.POINTER(ctypes.c_uint8);fp=ctypes.POINTER(ctypes.c_double)
    library.TCSCenteringSamplePrintGrid.argtypes=[u8,ctypes.c_int,ctypes.c_int,fp,u8]
    signals={reference.get('signal','luminance')}|{v['signal'] for p in reference['patches'] for v in p.get('colorAlternatives',[])}
    grids={}
    for signal in signals:
        pixels=render_signal(im,(w,h),signal).copy();grid=np.zeros((448,320),dtype='uint8')
        library.TCSCenteringSamplePrintGrid(pixels.ctypes.data_as(u8),w,h,corners.ctypes.data_as(fp),grid.ctypes.data_as(u8))
        grids[signal]=grid
    matcher=library.TCSCenteringMatchPatch;matcher.restype=ctypes.c_double
    matcher.argtypes=[u8,ctypes.c_int,ctypes.c_int,u8,ctypes.c_int,ctypes.c_int,fp,fp]
    rows=[]
    for patch in reference['patches']:
        trials=[]
        variants=[dict(signal=reference.get('signal','luminance'),pixels=patch['pixels'])]+patch.get('colorAlternatives',[])
        for variant in variants:
            p=np.frombuffer(base64.b64decode(variant['pixels']),dtype='uint8');grid=grids[variant['signal']]
            for sign in ([1,-1] if either else [1]):
                values=p if sign==1 else 255-p;dx=ctypes.c_double();dy=ctypes.c_double()
                score=matcher(grid.ctypes.data_as(u8),320,448,values.ctypes.data_as(u8),patch['x'],patch['y'],ctypes.byref(dx),ctypes.byref(dy))
                trials.append(dict(score=score,dx=dx.value,dy=dy.value,polarity=sign,signal=variant['signal']))
        best=max(trials,key=lambda r:r['score']);rows.append(dict(x=patch['x'],y=patch['y'],interior=patch['interior'],identityArtwork=patch.get('identityArtwork',False),**best))
    good=[r for r in rows if r['score']>=.8];inside=[r for r in good if r['interior']]
    coherent=[]
    if inside:
        dx=sorted(r['dx'] for r in inside)[len(inside)//2];dy=sorted(r['dy'] for r in inside)[len(inside)//2]
        coherent=[r for r in good if abs(r['dx']-dx)<=2 and abs(r['dy']-dy)<=2]
    interior=[r for r in coherent if r['interior']];art=[r for r in interior if r['identityArtwork']]
    mx=(reference['left']+reference['right'])*160;my=(reference['top']+reference['bottom'])*224
    printed=reference.get('kind')=='printedBorder'
    b=reference.get('identityArtworkBounds',reference);ax=(b['left']+b['right'])*160;ay=(b['top']+b['bottom'])*224
    quadrants=lambda points,x,y:len({(r['x']>x,r['y']>y) for r in points})
    upper=any(not r['interior'] and r['y']<(.14 if printed else reference['top'])*448 for r in coherent)
    lower=any(not r['interior'] and r['y']>(.86 if printed else reference['bottom'])*448 for r in coherent)
    full=quadrants(interior,mx,my);aq=quadrants(art,ax,ay)
    accepted=len(inside)>=10 and len(interior)>=10 and full==4 and (not printed or (len(art)>=6 and aq==4)) and upper and lower
    region=None
    if accepted:
        design=np.array([[1,(r['x']+.5)/320,(r['y']+.5)/448] for r in interior])
        fit=np.linalg.lstsq(design,np.array([[r['dx'],r['dy']] for r in interior]),rcond=None)[0]
        region=[]
        for u,v in [(reference['left'],reference['top']),(reference['right'],reference['top']),
                    (reference['right'],reference['bottom']),(reference['left'],reference['bottom'])]:
            du,dv=np.array([1,u,v])@fit;u+=du/320;v+=dv/448
            region.append(((1-u)*((1-v)*quad[0]+v*quad[3])+u*((1-v)*quad[1]+v*quad[2])).tolist())
    return dict(fixture=image.stem,inputSHA256=digest,referenceSHA256=reference['sourceSHA256'],signal=reference.get('signal','luminance'),eitherPolarity=either,
        matched=len(good),interior=len(interior),quadrants=full,artwork=len(art),artworkQuadrants=aq,
        upperCorroboration=upper,lowerCorroboration=lower,
        accepted=accepted,referenceRegionNative=region,
        observations=rows,limitation='Exact C matching arithmetic; Pillow preparation differs from the app; no geometry acceptance')


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['image','reference','baseline','library','output']:p.add_argument(name,type=Path)
    p.add_argument('--either-polarity',action='store_true');a=p.parse_args();pillow_heif.register_heif_opener()
    r=probe(a.image,json.loads(a.reference.read_text()),json.loads(a.baseline.read_text()),ctypes.CDLL(str(a.library)),a.either_polarity)
    a.output.write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k!='observations'}))
