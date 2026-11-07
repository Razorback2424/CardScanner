#!/usr/bin/env python3
"""Prepare a debug artwork reference from a publisher image and its reviewed art rectangle.

Usage: build_print_reference.py publisher.webp reference-only.json output.json
The four displayedCut corners describe the full publisher raster. Coordinates
refer to publisher pixel centers. No photographed card or expected ratio enters.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


def render_signal(image, size, signal='luminance'):
    if signal=='luminance':
        return np.asarray(image.convert('L').resize(size,Image.Resampling.BILINEAR))
    if signal not in ['redGreenChromaticity','blueGreenChromaticity']:
        raise ValueError('Unknown diagnostic reference signal')
    rgb=np.asarray(image.convert('RGB').resize(size,Image.Resampling.BILINEAR),dtype=float)
    channel=0 if signal=='redGreenChromaticity' else 2
    value=(rgb[:,:,channel]-rgb[:,:,1])/np.maximum(rgb.sum(2),1)
    return np.clip(np.rint(127.5*(1+value)),0,255).astype('uint8')


def prepare(image_path, specification):
    raw = image_path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != specification["sha256"]:
        raise ValueError("Publisher image differs from the reviewed specification")
    with Image.open(image_path) as image:
        width, height = image.size
        cut = [[-.5, -.5], [width-.5, -.5], [width-.5, height-.5], [-.5, height-.5]]
        if not np.allclose(specification["displayedCut"], cut):
            raise ValueError("Reference preparation requires a full, upright publisher card")
        template = render_signal(image,(320,448),specification.get('signal','luminance'))
        colors = {s:render_signal(image,(320,448),s) for s in
                  ['redGreenChromaticity','blueGreenChromaticity']} if specification.get('includeChromaticity') else {}
    printed = specification.get("kind") == "printedBorder"
    frame = np.asarray(specification["printedBorder"] if printed else specification["art"], dtype=float)
    if frame.shape != (4, 2):
        raise ValueError("Expected four artwork corners")
    left, top = (frame[0] + .5) / (width, height)
    right, bottom = (frame[2] + .5) / (width, height)
    if not (0 < left < right < 1 and 0 < top < bottom < 1
            and np.allclose(frame[1], (frame[2, 0], frame[0, 1]))
            and np.allclose(frame[3], (frame[0, 0], frame[2, 1]))):
        raise ValueError("Expected an upright artwork rectangle inside the published cut")
    patches = []
    identity = None
    if printed:
        x0,y0,x1,y1 = specification['artworkInterior']
        identity = dict(left=(x0+.5)/width,top=(y0+.5)/height,right=(x1+.5)/width,bottom=(y1+.5)/height)
        if not (0 < identity['left'] < identity['right'] < 1 and 0 < identity['top'] < identity['bottom'] < 1):
            raise ValueError('Invalid distinctive artwork region')

    def sample(u, v, interior):
        x, y = round(u * 320 - .5), round(v * 448 - .5)
        patch = template[y-8:y+9, x-8:x+9]
        alternatives=[]
        for signal,values in colors.items():
            candidate=values[y-8:y+9,x-8:x+9]
            if candidate.shape==(17,17) and candidate.std()>=10:
                alternatives.append(dict(signal=signal,pixels=base64.b64encode(candidate.tobytes()).decode('ascii')))
        if patch.shape == (17, 17) and (patch.std() >= 10 or alternatives):
            if printed and any(p['x']==x and p['y']==y for p in patches):return
            item=dict(x=x, y=y, interior=interior,pixels=base64.b64encode(patch.tobytes()).decode("ascii"))
            if alternatives:item['colorAlternatives']=alternatives
            if identity:
                item['identityArtwork']=bool(identity['left']<=x/320<=identity['right'] and identity['top']<=y/448<=identity['bottom'])
            patches.append(item)

    for y in np.linspace(.14, .86, 5):
        for x in np.linspace(.14, .86, 5):
            sample(left + (right-left)*x, top + (bottom-top)*y, True)
    # Corroborate the surrounding title/footer design separately from the art.
    for x in (.14, .22, .3):
        for y in (.08, .947):
            sample(x, y, False)
    if identity:
        for y in np.linspace(.125,.875,4):
            for x in np.linspace(.125,.875,4):
                sample(identity['left']+(identity['right']-identity['left'])*x,
                       identity['top']+(identity['bottom']-identity['top'])*y,True)
        if colors:
            # Choose additional distinctive locations from the provider raster
            # alone. Fixed-grid patches can miss an entire low-contrast quadrant.
            # Spatial suppression keeps nearby color variants from adding votes.
            import cv2
            response=np.maximum.reduce([cv2.cornerMinEigenVal(t.astype('float32'),3,3)
                                        for t in [template,*colors.values()]])
            x0=int(np.ceil(identity['left']*320))+8;x1=int(np.floor(identity['right']*320))-8
            y0=int(np.ceil(identity['top']*448))+8;y1=int(np.floor(identity['bottom']*448))-8
            mx=(identity['left']+identity['right'])*160;my=(identity['top']+identity['bottom'])*224
            for quadrant in [(False,False),(True,False),(False,True),(True,True)]:
                candidates=[(float(response[y,x]),x,y) for y in range(y0,y1+1) for x in range(x0,x1+1)
                            if (x>mx,y>my)==quadrant]
                added=0
                for strength,x,y in sorted(candidates,key=lambda item:(-item[0],item[2],item[1])):
                    if strength<=0 or added==2:break
                    if any((p['x']-x)**2+(p['y']-y)**2<18**2 for p in patches):continue
                    count=len(patches);sample((x+.5)/320,(y+.5)/448,True)
                    added+=len(patches)-count
        if specification.get('includeFrameLandmarks'):
            import cv2
            response=np.maximum.reduce([cv2.cornerMinEigenVal(t.astype('float32'),3,3)
                                        for t in [template,*colors.values()]])
            x0=int(np.ceil(left*320))+8;x1=int(np.floor(right*320))-8
            y0=int(np.ceil(top*448))+8;y1=int(np.floor(bottom*448))-8
            mx=(left+right)*160;my=(top+bottom)*224
            for quadrant in [(False,False),(True,False),(False,True),(True,True)]:
                candidates=[(float(response[y,x]),x,y) for y in range(y0,y1+1) for x in range(x0,x1+1)
                            if (x>mx,y>my)==quadrant]
                added=0
                for strength,x,y in sorted(candidates,key=lambda item:(-item[0],item[2],item[1])):
                    if strength<=0 or added==2 or len(patches)>=64:break
                    if any((p['x']-x)**2+(p['y']-y)**2<18**2 for p in patches):continue
                    count=len(patches);sample((x+.5)/320,(y+.5)/448,True)
                    added+=len(patches)-count
    result = dict(label=specification["printing"], sourceSHA256=specification["sha256"],
                left=left, top=top, right=right, bottom=bottom, patches=patches)
    if printed:result.update(kind='printedBorder',identityArtworkBounds=identity)
    if specification.get('boundaryMethod'):
        if (specification['boundaryMethod']!='printedContinuity' or not printed
                or specification.get('boundaryProfileSides')):
            raise ValueError('Printed continuity requires a printed border without provider profiles')
        result['boundaryMethod']='printedContinuity'
    if specification.get('boundaryProfileSides'):
        if printed:raise ValueError('Boundary profiles currently require artwork mode')
        pixels=np.asarray(Image.open(image_path).convert('RGB'),dtype=float).mean(axis=2).round().astype('uint8')
        strips=[]
        for side in specification['boundaryProfileSides']:
            if side not in ['left','top','right','bottom']:raise ValueError('Unknown profile side')
            x0,y0=frame[0];x1,y1=frame[2]
            if side=='left':x1=x0
            elif side=='right':x0=x1
            elif side=='top':y1=y0
            else:y0=y1
            x0=max(0,int(np.floor(x0))-24);y0=max(0,int(np.floor(y0))-24)
            x1=min(width,int(np.ceil(x1))+25);y1=min(height,int(np.ceil(y1))+25)
            strip=pixels[y0:y1,x0:x1]
            strips.append(dict(side=side,sourceWidth=width,sourceHeight=height,x=x0,y=y0,
                width=x1-x0,height=y1-y0,pixels=base64.b64encode(strip.tobytes()).decode('ascii')))
        result['boundaryProfiles']=strips
    if specification.get('signal','luminance')!='luminance':result['signal']=specification['signal']
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("image", "specification", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    result = prepare(args.image, json.loads(args.specification.read_text()))
    with args.output.open("x") as output:
        json.dump(result, output, indent=2)
        output.write("\n")
