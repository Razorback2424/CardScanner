#!/usr/bin/env python3
"""Measure a selective path repair in the detector's projectively rectified plane.

Preserves existing printed lines. Optional review data is used only for named
counterfactual sensitivity, never prediction. No calibrated physical accuracy
or correction for lens distortion/card bending is claimed.
"""
import argparse
import copy
import hashlib
import json
import itertools
from pathlib import Path

import cv2
import numpy as np
from scipy.interpolate import PchipInterpolator
from gt_tool import edge_points
from edge_annotation_audit import audit_edge

SIDES=['left','top','right','bottom']
CORNERS=['topLeft','topRight','bottomRight','bottomLeft']


def transform(points,h):
    p=np.c_[np.asarray(points,dtype=float),np.ones(len(points))]@h.T
    if np.any(abs(p[:,2])<1e-10):raise ValueError('singular projected point')
    return p[:,:2]/p[:,2,None]


def paths(quad):
    result={}
    for side in SIDES:
        a,b=np.array(edge_points(quad,side))
        result[side]=(a+np.linspace(0,1,101)[:,None]*(b-a)).tolist()
    return result


def supported_path(record,h,sample_span=(.2,.8)):
    """Use supported observations only, with bounded gaps over measured span.

    Reuses the consensus probe's 30-point / six-missing-sample limits. Unsupported
    points remain in the raw record; interpolation never makes them observations.
    No requirement is imposed on unmeasured endpoints, and no extrapolation occurs.
    """
    good=np.array([i for i,r in enumerate(record['rows']) if r['stable']])
    if len(good)<30:raise ValueError('fewer than 30 directly supported observations')
    points=np.array([record['rows'][i]['point'] for i in good])
    axis=0 if record['side'] in ['top','bottom'] else 1
    coordinates=transform(points,h)[:,axis]
    order=np.argsort(coordinates);coordinates=coordinates[order];points=points[order];good=good[order]
    if np.any(np.diff(coordinates)<=0):raise ValueError('non-monotonic supported path')
    before=np.flatnonzero(coordinates<=sample_span[0]);after=np.flatnonzero(coordinates>=sample_span[1])
    if not len(before) or not len(after):raise ValueError('unsupported measurement endpoint; no extrapolation')
    start,end=int(before[-1]),int(after[0])
    indices=good[start:end+1]
    maxgap=int(np.max(np.abs(np.diff(indices)))-1)
    if maxgap>6:raise ValueError('unsupported gap exceeds six samples within measured span')
    return points[start:end+1].tolist(),dict(directCount=len(good),directCountBracketingMeasurement=len(indices),
        maxMissingSamplesWithinMeasurement=maxgap,measurementSpan=list(sample_span),
        interpolation='PCHIP between directly supported observations; gaps remain inferred')


def measure(frames,h,sample_span=(.2,.8)):
    # Match opposing measurements at corresponding rectified positions, not
    # source-image x/y positions. No extrapolation into unobserved corners.
    if not 0 <= sample_span[0] < sample_span[1] <= 1:
        raise ValueError('invalid paired sampling span')
    grid=np.linspace(*sample_span,31);values={}
    for frame,edges in frames.items():
        values[frame]={}
        for side,points in edges.items():
            q=transform(points,h);along=1 if side in ['left','right'] else 0
            q=q[np.argsort(q[:,along])]
            if np.any(np.diff(q[:,along])<=0):raise ValueError('non-monotonic path')
            if q[0,along]>grid[0] or q[-1,along]<grid[-1]:raise ValueError('insufficient paired span')
            values[frame][side]=PchipInterpolator(q[:,along],q[:,1-along])(grid)
    widths={s:(values['inner'][s]-values['outer'][s])*(1 if s in ['left','top'] else -1) for s in SIDES}
    if any(np.any(v<=0) for v in widths.values()):raise ValueError('frames cross or have nonpositive margin')
    mean={s:float(v.mean()) for s,v in widths.items()}
    return dict(meanMargins=mean,leftShare=100*mean['left']/(mean['left']+mean['right']),
        topShare=100*mean['top']/(mean['top']+mean['bottom']),
        sampleSpan=list(sample_span),sampleCount=31,localMargins={s:v.tolist() for s,v in widths.items()})


def synthetic_control():
    unit=[[0,0],[1,0],[1,1],[0,1]]
    frame=dict(outer=paths(unit),inner=paths([[.04,.06],[.94,.06],[.94,.91],[.04,.91]]))
    h=np.array([[1800,150,250],[50,2800,100],[.08,.15,1.]])
    projected={f:{s:transform(p,h).tolist() for s,p in edges.items()} for f,edges in frame.items()}
    a=measure(frame,np.eye(3));b=measure(projected,np.linalg.inv(h))
    error=max(abs(a[k]-b[k]) for k in ['leftShare','topShare'])
    if error>1e-8:raise ValueError('projective control failed')
    return dict(maxShareDifferencePP=error,expectedLeft=40.,expectedTop=40.,
                actualLeft=b['leftShare'],actualTop=b['topShare'])


def run(baseline,tracked,review,output,physical_paths=None,repair_sides=(),refine_straight_image=None,straight_radius=16):
    path=json.loads(tracked.read_text())
    record=next(r for r in json.loads(baseline.read_text()) if r['fixture']==path['fixture'])
    quad=lambda name:[[record[name][p]['x'],record[name][p]['y']] for p in CORNERS]
    outer=quad('actualOuter');inner=quad('actualInner')
    h=cv2.getPerspectiveTransform(np.float32(outer),np.float32([[0,0],[1,0],[1,1],[0,1]]))
    frames=dict(outer=paths(outer),inner=paths(inner));unmodified=measure(frames,h)
    frames['outer']['bottom']=[[r['x'],r['center']] for r in path['rows']]
    straight_evidence={}
    if refine_straight_image:
        from PIL import Image,ImageOps
        import pillow_heif
        pillow_heif.register_heif_opener()
        if hashlib.sha256(refine_straight_image.read_bytes()).hexdigest()!=path['inputSHA256']:
            raise ValueError('straight-edge capture mismatch')
        image=np.asarray(ImageOps.exif_transpose(Image.open(refine_straight_image)).convert('RGB'))
        for side in ['left','right']:
            evidence=audit_edge(image,outer,side,radius=straight_radius,polarity='falling')
            straight_evidence[side]=evidence
            a,b,c=evidence['line'];n=np.array([a,b]);p=np.array(frames['outer'][side])
            frames['outer'][side]=(p-(p@n-c)[:,None]*n).tolist()
    candidate_sources={};candidate_edges={}
    if physical_paths:
        candidates=json.loads(physical_paths.read_text())
        if candidates['inputSHA256']!=path['inputSHA256']:raise ValueError('candidate capture mismatch')
        for side in repair_sides:
            if side=='bottom':raise ValueError('bottom already supplied by dedicated tracker')
            source=candidates['frames']['outer'][side]
            frames['outer'][side]=[r['point'] for r in source['rows']]
            candidate_edges[side]=source
            candidate_sources[side]=dict(stableCount=source['stableCount'],sourceSHA256=hashlib.sha256(physical_paths.read_bytes()).hexdigest())
    predicted=measure(frames,h)
    variations={}
    for indexes in itertools.product([0,1],repeat=1+len(candidate_edges)):
        varied=copy.deepcopy(frames)
        varied['outer']['bottom']=[[r['x'],r['sensitivityRange'][indexes[0]]] for r in path['rows']]
        for (side,source),index in zip(candidate_edges.items(),indexes[1:]):
            normal=np.array(source['normal'])
            varied['outer'][side]=[(np.array(r['base'])+r['sensitivityRange'][index]*normal).tolist() for r in source['rows']]
        variations['bounds_'+''.join(map(str,indexes))]=measure(varied,h)
    # Score-only substitutions make remaining sources of error visible. The
    # automatic prediction above is frozen before any review data is read.
    counterfactual={}
    if review:
        r=json.loads(review.read_text())[path['fixture'][-4:]]
        for side in ['left','top','right']:
            varied=copy.deepcopy(frames);a,b,c=r['frames']['cut']['edges'][side]['line']
            p=np.array(varied['outer'][side]);n=np.array([a,b]);p-=(p@n-c)[:,None]*n
            varied['outer'][side]=p.tolist();counterfactual[side]=measure(varied,h)
    result=dict(fixture=path['fixture'],inputSHA256=path['inputSHA256'],
        trackedSHA256=hashlib.sha256(tracked.read_bytes()).hexdigest(),
        baseline=unmodified,selectivePrediction=predicted,fitSensitivity=variations,
        predictionNativePaths=frames,rectificationMatrix=h.tolist(),
        scoreOnlyReviewSubstitutions=counterfactual,syntheticControl=synthetic_control(),
        extraPhysicalCandidates=candidate_sources,
        straightPhysicalEvidence=straight_evidence,
        provenance=dict(inner='unchanged independent production lines',outerBottom='tracked native path',
                        otherOuter='unchanged production lines except named extraPhysicalCandidates and straightPhysicalEvidence',rectification='production outer quad'),
        status='research measurement, no calibrated accuracy acceptance',
        limitations='Local sensitivity is not a confidence interval; bending/lens distortion and remaining cut uncertainty unresolved')
    output.write_text(json.dumps(result,indent=2)+'\n')
    compact=lambda v:{k:v[k] for k in ['leftShare','topShare']}
    print(json.dumps(dict(baseline=compact(unmodified),selective=compact(predicted),
        sensitivity={k:compact(v) for k,v in variations.items()},
        reviewCounterfactuals={k:compact(v) for k,v in counterfactual.items()},control=result['syntheticControl'])))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('baseline',type=Path);p.add_argument('tracked',type=Path)
    p.add_argument('output',type=Path);p.add_argument('--review',type=Path)
    p.add_argument('--physical-paths',type=Path)
    p.add_argument('--refine-straight-image',type=Path)
    p.add_argument('--straight-radius',type=int,default=16)
    p.add_argument('--repair-sides',nargs='+',choices=['left','top','right'],default=[])
    args=p.parse_args()
    if args.repair_sides and not args.physical_paths:p.error('repair sides require physical paths')
    run(args.baseline,args.tracked,args.review,args.output,args.physical_paths,args.repair_sides,args.refine_straight_image,args.straight_radius)
