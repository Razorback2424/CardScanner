#!/usr/bin/env python3
"""Reproduce the rejected seed-sensitive whole-perimeter experiment.

This is a bounded research counterexample, not an app boundary detector. The
hidden synthetic image has a complete interior rectangle but no visible cut;
its retained interior-rule candidates are comparison coordinates only.
"""
import argparse
import concurrent.futures
import hashlib
import json
import subprocess
import sys
from pathlib import Path

CHILD = r'''
import json, sys, cv2, numpy as np
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps
import pillow_heif
pillow_heif.register_heif_opener()
cv2.setRNGSeed(4827); cv2.setNumThreads(1)
name, image_file, seed_file, candidate_file, axis, shift = sys.argv[1:]
shift=float(shift)
if name == 'hidden_closed':
    img=Image.new('RGB',(600,800),(170,170,170))
    ImageDraw.Draw(img).rectangle((105,105,494,744),fill=(20,20,20))
else:
    img=ImageOps.exif_transpose(Image.open(image_file)).convert('RGB')
img=np.asarray(img); h,w=img.shape[:2]; scale=min(1.,640/max(h,w))
a=cv2.resize(img,None,fx=scale,fy=scale,interpolation=cv2.INTER_AREA)
H,W=a.shape[:2]
if seed_file == 'synthetic':
    q=np.array([[90,90],[510,90],[510,760],[90,760]],float)
else:
    p=json.loads(Path(seed_file).read_text())[0]['actualOuter']
    q=np.array([[p[k]['x'],p[k]['y']] for k in ['topLeft','topRight','bottomRight','bottomLeft']])
q[:,0 if axis=='x' else 1] += shift
q=np.rint(q*[W/w,H/h]).astype('int32')
mask_quad=np.zeros((H,W),np.uint8); cv2.fillConvexPoly(mask_quad,q,255)
kernel=lambda n:cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(2*n+1,2*n+1))
pad=cv2.dilate(mask_quad,kernel(max(2,round(120*scale))))
core=cv2.erode(mask_quad,kernel(max(1,round(16*scale))))
mask=np.full((H,W),cv2.GC_BGD,np.uint8)
mask[pad>0]=cv2.GC_PR_BGD; mask[mask_quad>0]=cv2.GC_PR_FGD; mask[core>0]=cv2.GC_FGD
mask[:2,:]=mask[-2:,:]=mask[:,:2]=mask[:,-2:]=cv2.GC_BGD
cv2.grabCut(cv2.cvtColor(a,cv2.COLOR_RGB2BGR),mask,None,np.zeros((1,65),np.float64),np.zeros((1,65),np.float64),1,cv2.GC_INIT_WITH_MASK)
fg=np.where((mask==cv2.GC_FGD)|(mask==cv2.GC_PR_FGD),255,0).astype(np.uint8)
contours,_=cv2.findContours(fg,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)
c=max(contours,key=cv2.contourArea); clean=np.zeros_like(fg); cv2.drawContours(clean,[c],-1,255,-1)
d=cv2.distanceTransform(255-cv2.Canny(clean,40,100),cv2.DIST_L2,5)
t=json.loads(Path(candidate_file).read_text()); scores=[]
for i,z in enumerate(t['hypotheses']):
    if z['possibleTrackHopping']: continue
    v=[]
    for pt in z['points'][8:53]:
        if pt['origin']=='extrapolated': continue
        x,y=pt['point']; v.append(float(d[int(np.clip(round(y*H/h),0,H-1)),int(np.clip(round(x*W/w),0,W-1))]/scale))
    scores.append(dict(index=i,median=round(float(np.median(v)),2), p90=round(float(np.percentile(v,90)),2)))
print(json.dumps(dict(name=name,shift=shift,bbox=cv2.boundingRect(c),scores=scores)))
'''

def run(task):
    case, shift = task
    try:
        p=subprocess.run([sys.executable,'-c',CHILD,*case,str(shift)],capture_output=True,text=True,timeout=20)
        return json.loads(p.stdout) if p.returncode == 0 else dict(name=case[0],shift=shift,error=p.stderr[-200:])
    except subprocess.TimeoutExpired:
        return dict(name=case[0],shift=shift,error='timeout')


def main(builds, photo, output):
    multi = builds/'CardScanner-MultiHypothesis-20261107'
    squirtle = builds/'CardScanner-Squirtle-20261107'
    rows = [
        ('interior', str(multi/'controls-v7/interior_rule.png'), 'synthetic', str(multi/'controls-v7/interior_rule-result.json'), 'x'),
        ('shadow', str(multi/'controls-v7/shadow.png'), 'synthetic', str(multi/'controls-v7/shadow-result.json'), 'x'),
        ('hidden_closed', '', 'synthetic', str(multi/'controls-v7/interior_rule-result.json'), 'x'),
        ('squirtle', str(photo), str(squirtle/'proposal/reference-seed.json'), str(multi/'squirtle-bottom-cut-v7.json'), 'y'),
    ]
    def digest(path):
        return hashlib.sha256(path.read_bytes()).hexdigest()
    for name, image, seed, candidate, _ in rows:
        result = json.loads(Path(candidate).read_text())
        if name != 'hidden_closed' and digest(Path(image)) != result['inputSHA256']:
            raise ValueError(name+': photo/candidate hash mismatch')
        if seed != 'synthetic' and json.loads(Path(seed).read_text())[0]['inputSHA256'] != result['inputSHA256']:
            raise ValueError(name+': seed/photo hash mismatch')
    if output.exists():
        raise ValueError('output already exists')
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        result=list(pool.map(run,[(case,shift) for case in rows for shift in [-24,0,24]]))
    if any('error' in row for row in result):
        raise RuntimeError('incomplete or timed-out experiment: '+json.dumps(result))
    def median(name, shift, index):
        row = next(row for row in result if row['name'] == name and row['shift'] == shift)
        return next(score['median'] for score in row['scores'] if score['index'] == index)
    for name in ('interior', 'shadow'):
        if any(median(name, shift, 0) > 3 or median(name, shift, 1) < 18 for shift in (-24,0,24)):
            raise AssertionError(name+': control no longer reproduces; inspect rather than infer a result')
    if not (median('hidden_closed',-24,0) < 3 and median('hidden_closed',-24,1) > 18
            and median('hidden_closed',0,0) > 18 and median('hidden_closed',0,1) < 3):
        raise AssertionError('hidden-cut candidate switch did not reproduce')
    if max(median('squirtle',shift,1) for shift in (-24,0,24)) - min(
        median('squirtle',shift,1) for shift in (-24,0,24)) < 10:
        raise AssertionError('Squirtle seed sensitivity did not reproduce')
    inputs = sorted({value for _, image, seed, candidate, _ in rows
                     for value in (image,seed,candidate) if value and value != 'synthetic'})
    receipt = dict(status='research only; seed-sensitive silhouette rejected for automatic selection',
        selectedCandidate=None, reviewRequired=True, shiftsNativePixels=[-24,0,24],
        controls=dict(simpleInteriorAndShadow='pass', hiddenCutCandidateSwitch='reproduced',
                      squirtleSeedSensitivity='reproduced'),
        inputHashes={path:digest(Path(path)) for path in inputs}, results=result,
        limitation=('Known synthetic closed panel has no visible physical cut; its candidate positions are comparison '
                    'coordinates only. Downsampling prevents subpixel distinction. No app geometry is changed.'))
    output.write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps(receipt,indent=2),flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('builds',type=Path,help='External build root holding the prior multi-hypothesis and Squirtle evidence')
    parser.add_argument('photo',type=Path,help='Squirtle source photo')
    parser.add_argument('output',type=Path,help='New JSON receipt; will not overwrite an existing file')
    args=parser.parse_args()
    main(args.builds,args.photo,args.output)
