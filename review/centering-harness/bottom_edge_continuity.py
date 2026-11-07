#!/usr/bin/env python3
"""Bounded native-photo boundary diagnostic, never replacement ground truth.

The caller supplies a visually reviewed region excluding rounded corners.
Compare local brightening transitions at three fixed scales and fit a curve
on alternating samples. Held-out samples test interpolation, not independence
from the image. No app output or expected centering enters selection.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps, ImageDraw
import pillow_heif
from scipy.ndimage import gaussian_filter1d


def analyze(path, region, output):
    pillow_heif.register_heif_opener()
    im = ImageOps.exif_transpose(Image.open(path)).convert("RGB")
    gray = np.asarray(im, dtype=float).mean(axis=2)
    x0, y0, x1, y1 = region
    if not (4 <= x0 < x1 < im.width-4 and 0 <= y0 < y1 <= im.height):
        raise ValueError("region must fit the original image")
    xs = np.linspace(x0, x1, 61).round().astype(int)
    peaks = []
    strengths = []
    for sigma in (1, 2, 4):
        ys, scores = [], []
        for x in xs:
            profile = gray[y0:y1, x-4:x+5].mean(axis=1)
            gradient = gaussian_filter1d(profile, sigma, order=1)
            gradient[:8] = gradient[-8:] = -np.inf
            i = int(gradient.argmax())
            ys.append(float(y0+i))
            scores.append(float(gradient[i]))
        peaks.append(ys)
        strengths.append(scores)
    peaks, strengths = np.array(peaks), np.array(strengths)
    # Fixed diagnostic criteria, not tuned after observing fit residuals.
    stable = (np.ptp(peaks, axis=0) <= 4) & (strengths.min(axis=0) >= 2.5)
    t = (xs-xs.mean()) / (x1-x0)
    train = stable & (np.arange(61) % 2 == 0)
    held = stable & ~train
    if train.sum() < 6 or held.sum() < 6:
        raise ValueError("insufficient stable evidence for held-out comparison")
    ys = peaks[1]
    models = {}
    for degree in (1, 2):
        c = np.polyfit(t[train], ys[train], degree)
        residuals = ys-np.polyval(c,t)
        models[str(degree)] = dict(coefficients=c.tolist(),
            heldOutRMS=float(np.sqrt(np.mean(residuals[held]**2))),
            heldOutWorst=float(np.max(np.abs(residuals[held]))),
            predictions=np.polyval(c,t).tolist())
    bins = sorted(set(np.minimum(4,np.arange(61)[stable]*5//61).tolist()))
    # Post-primary diagnostic: separate contrast strength from localization
    # stability. This does not relax the primary acceptance criterion.
    scale_stable = np.ptp(peaks, axis=0) <= 4
    exploratory = {}
    for degree in (1, 2):
        train2 = scale_stable & (np.arange(61) % 2 == 0)
        held2 = scale_stable & ~train2
        if train2.sum() < 6 or held2.sum() < 6:
            continue
        c = np.polyfit(t[train2], ys[train2], degree)
        errors = ys[held2]-np.polyval(c,t[held2])
        exploratory[str(degree)] = dict(coefficients=c.tolist(),
            heldOutRMS=float(np.sqrt(np.mean(errors**2))),
            heldOutWorst=float(np.max(np.abs(errors))))
    receipt = dict(inputSHA256=hashlib.sha256(path.read_bytes()).hexdigest(),
        region=region, polarity="brightening outward/downward", scales=[1,2,4],
        stableCriterion="scale spread <=4 native px and each gradient >=2.5",
        x=xs.tolist(), yByScale=peaks.tolist(), strengthByScale=strengths.tolist(),
        stable=stable.tolist(), stableCount=int(stable.sum()), occupiedBins=bins,
        models=models, status="research_candidate_requires_semantic_review",
        exploratoryScaleOnly=dict(count=int(scale_stable.sum()), models=exploratory,
            status="post-primary diagnostic, not a relaxed pass"),
        limitations="One photo, supplied region, no independent precision truth or automatic routing")
    output.mkdir(parents=True, exist_ok=True)
    (output/'continuity.json').write_text(json.dumps(receipt,indent=2)+'\n')
    crop = im.crop((x0-20,y0-20,x1+20,y1+20))
    draw = ImageDraw.Draw(crop)
    for x,y,ok in zip(xs,ys,stable):
        cx,cy=int(x-x0+20),int(y-y0+20)
        draw.ellipse((cx-2,cy-2,cx+2,cy+2),fill='lime' if ok else 'red')
    for key,color in [('1','cyan'),('2','orange')]:
        draw.line([(float(x-x0+20),float(y-y0+20)) for x,y in
                   zip(xs,models[key]['predictions'])],fill=color,width=2)
    crop.save(output/'continuity.png')
    print(json.dumps({k:receipt[k] for k in ['stableCount','occupiedBins']}))
    print(json.dumps({k:{a:b for a,b in v.items() if a!='predictions'} for k,v in models.items()}))


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('image',type=Path)
    parser.add_argument('output',type=Path)
    parser.add_argument('--region',type=int,nargs=4,required=True,metavar=('X0','Y0','X1','Y1'))
    args=parser.parse_args()
    analyze(args.image,args.region,args.output)
