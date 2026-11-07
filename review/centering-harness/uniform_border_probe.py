#!/usr/bin/env python3
"""Offline printed-boundary identity from a directly observed uniform exterior.

Rejects stronger interior rules whose exterior still contains printed material.
Three spatial widths must identify the same transition before six RGB region
fits place it. All old region fit/precision limits remain unchanged. This is a
border-family hypothesis, not a generic cut detector or calibrated confidence.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
import pillow_heif
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks
from scipy.special import erf
from color_region_probe import fit_region
from track_card_paths import samples, gradient_refinement

WIDTHS = (16, 32, 64)
OFFSETS = np.arange(-80, 81)


def proposal(profile, exterior_model='constant', exterior=None):
    exterior = profile[-24:] if exterior is None else exterior
    level = exterior.mean(axis=0)
    noise = float(np.sqrt(np.mean((exterior-level)**2)))
    # One RGB level is the quantization floor; this is a diagnostic region gate,
    # not a probability or a relaxation of accepted boundary-fit requirements.
    tolerance = max(1., 3*noise)
    gradient = np.abs(gaussian_filter1d(profile, 2, axis=0, order=1)).mean(axis=1)
    candidates = []
    for index in find_peaks(gradient, prominence=.5, distance=8)[0]:
        if index < 12 or index+40 >= len(profile):
            continue
        outside_rms = float(np.sqrt(np.mean((profile[index+12:index+40]-level)**2)))
        inside_contrast = float(np.sqrt(np.mean((profile[index-12:index-4].mean(axis=0)-level)**2)))
        if exterior_model == 'linear':
            # Test texture-free border continuity while allowing illumination to
            # vary smoothly. An interior rule still leaves the real seam inside
            # this exterior segment and fails its residual test.
            x = OFFSETS[index+12:]
            design = np.c_[np.ones(len(x)), x]
            coefficients = np.linalg.lstsq(design,profile[index+12:],rcond=None)[0]
            outside_rms = float(np.sqrt(np.mean((design@coefficients-profile[index+12:])**2)))
            expected = np.array([1.,float(OFFSETS[index]-8)])@coefficients
            inside_contrast = float(np.sqrt(np.mean((profile[index-12:index-4].mean(axis=0)-expected)**2)))
        candidates.append(dict(offset=int(OFFSETS[index]), exteriorRMS=outside_rms,
            contrast=inside_contrast, eligible=outside_rms <= tolerance and inside_contrast >= 5))
    eligible = [c['offset'] for c in candidates if c['eligible']]
    return dict(center=eligible[0] if len(eligible) == 1 else None,
                exteriorNoise=noise, exteriorTolerance=tolerance, candidates=candidates)


def controls(exterior_model='constant'):
    def step(center, width):
        return .5*(1+erf((OFFSETS-center)/(width*np.sqrt(2))))
    result = {}
    for name, profile, expected in [
        ('weak_border_stronger_interior', 5+30*(1-step(-20, 2))+10*(1-step(20, 2)), 20),
        ('single_border', 5+15*(1-step(7, 2)), 7),
        ('flat_no_border', np.full(len(OFFSETS), 5.), None),
    ]:
        p = proposal(np.repeat(profile[:, None], 3, axis=1),exterior_model)
        if expected is None:
            assert p['center'] is None, name
        else:
            assert p['center'] is not None and abs(p['center']-expected) <= 1, name
        result[name] = dict(expected=expected, observed=p['center'])
    return result


def physical_depth(base, normal, record):
    supported=[(i,np.array(row['point'])) for i,row in enumerate(record['rows']) if row['stable']]
    intersections=[]
    for (ia,a),(ib,b) in zip(supported,supported[1:]):
        if ib-ia>7:continue
        matrix=np.column_stack((normal,a-b))
        if abs(np.linalg.det(matrix))<1e-8:continue
        depth,fraction=np.linalg.solve(matrix,a-base)
        if depth>0 and 0<=fraction<=1:intersections.append(float(depth))
    if len(intersections)!=1:raise ValueError('physical cut does not bracket border observation')
    return intersections[0]


def refine(rgb, record, widths=WIDTHS, estimator='region',exterior_model='constant',physical=None):
    normal = np.asarray(record['normal']); tangent = np.array([-normal[1], normal[0]])
    rows = []; supported_proposals = 0
    for old in record['rows']:
        base = np.asarray(old['base']); proposals = []
        cut_depth=physical_depth(base,normal,physical) if physical else None
        for width in widths:
            raw = samples(rgb, base[None], normal, tangent, OFFSETS, width, dense=True)[0]
            exterior=(samples(rgb,base[None],normal,tangent,
                cut_depth-np.arange(48,23,-1),width,dense=True)[0] if physical else None)
            p=proposal(raw,exterior_model,exterior)
            if physical and p['center'] is not None and p['center']+12>=cut_depth-48:
                p['center']=None
            proposals.append(dict(halfWidth=width, **p))
        centers = [p['center'] for p in proposals]
        valid = all(c is not None for c in centers) and max(centers)-min(centers) <= 4
        trials = []; center = 0.
        if valid:
            supported_proposals += 1
            seed = float(np.median(centers)); offsets = np.arange(seed-28, seed+29)
            for width in widths:
                raw = samples(rgb, base[None], normal, tangent, offsets, width, dense=True)[0]
                if estimator == 'gradient':
                    for sigma in [1,2]:
                        trials.append(dict(halfWidth=width,sigma=sigma,
                            **gradient_refinement(raw,offsets,seed,sigma)))
                else:
                    for family in ['erf', 'logistic']:
                        trials.append(dict(halfWidth=width, family=family, **fit_region(raw, offsets, seed, family)))
            centers = [p['center'] for p in trials]; center = float(np.median(centers))
            if estimator == 'gradient':
                valid = max(centers)-min(centers) <= 4 and all(t['peak']>=2.5 and not t['boundaryHit'] for t in trials)
            else:
                valid = max(centers)-min(centers) <= 4 and all(t['converged'] and
                    not t['centerAtBound'] and not t['blurAtUpperBound'] and
                    t['amplitude'] >= 5 and t['relativeRMS'] <= .15 for t in trials)
        rows.append(dict(base=base.tolist(), point=(base+center*normal).tolist(), offset=center,
            stable=bool(valid), proposals=proposals, trials=trials,physicalDepth=cut_depth))
    return dict(side=record['side'], normal=normal.tolist(), rows=rows,
        proposalCount=supported_proposals, stableCount=sum(r['stable'] for r in rows))


def refine_consensus_gradient(rgb, record, identity):
    """Use coherent border identity to propose searches, never measured points."""
    observations = []
    for i, row in enumerate(identity['rows']):
        centers = [p['center'] for p in row['proposals']]
        if len(centers)==3 and all(c is not None for c in centers) and max(centers)-min(centers)<=4:
            observations.append((i,float(np.median(centers))))
    if len(observations)<30 or len(set(min(4,i*5//61) for i,d in observations))<4:
        raise ValueError('insufficient spatial boundary identity')
    indices, depths = np.asarray(observations).T
    coefficients = np.polyfit(indices,depths,1)
    residual = float(np.max(np.abs(np.polyval(coefficients,indices)-depths)))
    if residual>4:
        raise ValueError('incoherent identity proposals')
    result=refine_seed_gradient(rgb,record,np.polyval(coefficients,np.arange(61)))
    result.update(identityCount=len(observations),identityResidual=residual)
    return result


def refine_seed_gradient(rgb, record, seeds=None):
    """Refine an existing detector proposal; does not claim new frame identity."""
    seeds=np.zeros(len(record['rows'])) if seeds is None else seeds
    normal = np.asarray(record['normal']); tangent = np.array([-normal[1],normal[0]])
    rows = []
    for i,old in enumerate(record['rows']):
        base = np.asarray(old['base']);seed = float(seeds[i])
        # The line supplies search centers only. All returned observations are
        # independently localized; no line-fitting residual certifies geometry.
        offsets = np.arange(np.floor(seed)-28,np.floor(seed)+29); trials=[]
        for width in (4,8,16):
            raw=samples(rgb,base[None],normal,tangent,offsets,width,dense=True)[0]
            for sigma in (1,2):
                trials.append(dict(halfWidth=width,sigma=sigma,
                    **gradient_refinement(raw,offsets,seed,sigma)))
        centers=[t['center'] for t in trials];center=float(np.median(centers))
        stable=max(centers)-min(centers)<=4 and all(t['peak']>=2.5 and not t['boundaryHit'] for t in trials)
        rows.append(dict(base=base.tolist(),point=(base+center*normal).tolist(),offset=center,
            stable=bool(stable),trials=trials,proposedOffset=seed))
    return dict(side=record['side'],normal=normal.tolist(),rows=rows,
        stableCount=sum(r['stable'] for r in rows))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['image', 'candidate', 'output']:
        parser.add_argument(name, type=Path)
    parser.add_argument('--side', choices=['left', 'top', 'right', 'bottom'], action='append')
    parser.add_argument('--strip-half-widths', type=int, nargs=3, default=WIDTHS)
    parser.add_argument('--estimator', choices=['region','gradient','consensus-gradient','seed-gradient'], default='region')
    parser.add_argument('--identity-proposals', type=Path)
    parser.add_argument('--physical-paths',type=Path,
        help='Anchor exterior color observations 24–48px inward from observed physical cut')
    parser.add_argument('--exterior-model',choices=['constant','linear'],default='constant')
    args = parser.parse_args(); checks = controls(args.exterior_model); pillow_heif.register_heif_opener()
    if not (0<args.strip_half_widths[0]<args.strip_half_widths[1]<args.strip_half_widths[2]<=128):
        parser.error('Require three increasing positive strip half-widths no larger than 128')
    candidate = json.loads(args.candidate.read_text())
    digest = hashlib.sha256(args.image.read_bytes()).hexdigest()
    if digest != candidate['inputSHA256']:
        raise ValueError('capture mismatch')
    identity = None
    physical = None
    if args.physical_paths:
        physical=json.loads(args.physical_paths.read_text())
        if physical['inputSHA256']!=digest:raise ValueError('physical capture mismatch')
        if args.exterior_model!='constant':parser.error('Physical anchor currently supports constant exterior only')
    if args.estimator=='consensus-gradient':
        if not args.identity_proposals:parser.error('Consensus refinement needs separate identity proposals')
        identity=json.loads(args.identity_proposals.read_text())
        if identity['inputSHA256']!=digest:raise ValueError('identity capture mismatch')
    rgb = np.asarray(ImageOps.exif_transpose(Image.open(args.image)).convert('RGB'), dtype='float32')
    records = {}
    for side, record in candidate['frames']['inner'].items():
        if args.side and side not in args.side:
            continue
        if args.estimator=='seed-gradient':records[side]=refine_seed_gradient(rgb,record)
        elif identity:records[side]=refine_consensus_gradient(rgb,record,identity['frames']['inner'][side])
        else:records[side]=refine(rgb, record,args.strip_half_widths,args.estimator,args.exterior_model,
                                 physical['frames']['outer'][side] if physical else None)
        print(side, 'supported', records[side]['stableCount'], flush=True)
    args.output.write_text(json.dumps(dict(fixture=candidate['fixture'], inputSHA256=digest,
        candidateSHA256=hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
        stripHalfWidths=([4,8,16] if args.estimator in ['seed-gradient','consensus-gradient'] else args.strip_half_widths),
        estimator=args.estimator, controls=checks, frames=dict(inner=records),
        exteriorModel=args.exterior_model,
        identitySHA256=hashlib.sha256(args.identity_proposals.read_bytes()).hexdigest() if identity else None,
        physicalSHA256=hashlib.sha256(args.physical_paths.read_bytes()).hexdigest() if physical else None,
        limitation='Uniform border identity hypothesis; inspect full paths before accepting measurement. Spatial averaging correlates observations and is not calibrated certainty.'), indent=2)+'\n')
