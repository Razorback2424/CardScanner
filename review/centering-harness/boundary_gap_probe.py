#!/usr/bin/env python3
"""Research-only line proposal and gap interpolation from supported points.

The output separates direct observations from fitted/inferred points. A line
can fit the wrong feature perfectly, so this tool never establishes boundary
identity, changes app geometry, or makes a ratio reportable.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.stats import theilslopes


def bridge(a, b, target, axis):
    normal_axis = 1-axis
    if b[axis] == a[axis]:
        raise ValueError('non-monotonic bridge endpoints')
    t = (target[axis]-a[axis])/(b[axis]-a[axis])
    if not 0 <= t <= 1:
        raise ValueError('bridge would extrapolate')
    return a[normal_axis]+t*(b[normal_axis]-a[normal_axis])


def run(candidate, frame, side, output, gap=None, alternate=None, known_cut=None):
    source = json.loads(candidate.read_text())
    record = source['frames'][frame][side]
    rows = record['rows']; normal = np.asarray(record['normal'])
    if len(rows) != 61:
        raise ValueError('expected 61 ordered stations')
    ids = np.array([i for i, row in enumerate(rows) if row['stable']])
    if len(ids) < 3:
        raise ValueError('insufficient observed points')
    values = np.array([np.dot(np.asarray(rows[i]['point'])-np.asarray(rows[i]['base']), normal) for i in ids])
    slope, intercept, _, _ = theilslopes(values, ids)
    residuals = values-(intercept+slope*ids)
    inliers = set(int(i) for i, error in zip(ids, residuals) if abs(error) <= 4)
    bins = sorted(set(min(4, i*5//61) for i in inliers))
    points = []
    for i, row in enumerate(rows):
        model = np.asarray(row['base'])+(intercept+slope*i)*normal
        points.append(dict(index=i, observed=row['point'] if row['stable'] else None,
                           lineProposal=model.tolist(), modelInlier=i in inliers))

    axis = 1 if side in ['left', 'right'] else 0
    other = 1-axis
    windows = []
    # The middle 60% of the card is the currently measured span. These
    # overlapping windows assess stability, not independent calibration.
    for start in range(8, 44):
        end = start+8
        if not rows[start-1]['stable'] or not rows[end+1]['stable']:
            continue
        targets = [rows[i]['point'] for i in range(start, end+1) if rows[i]['stable']]
        if len(targets) < 6:
            continue
        a, b = rows[start-1]['point'], rows[end+1]['point']
        errors = [abs(bridge(a, b, target, axis)-target[other]) for target in targets]
        windows.append(dict(start=start, withheld=len(targets), worstPixels=max(errors)))
    cross_validation = dict(windows=len(windows), sizeStations=9)
    if windows:
        worst = [w['worstPixels'] for w in windows]
        cross_validation.update(medianWorstPixels=float(np.median(worst)),
            p95WorstPixels=float(np.percentile(worst, 95)), maximumWorstPixels=max(worst))

    comparison = None
    if gap is not None:
        if alternate is None:
            raise ValueError('gap comparison needs separately recovered observations')
        check = json.loads(alternate.read_text())
        if check['inputSHA256'] != source['inputSHA256']:
            raise ValueError('capture mismatch')
        a, b = gap
        if not (0 < a <= b < 60 and rows[a-1]['stable'] and rows[b+1]['stable']):
            raise ValueError('gap has no two observed endpoints')
        other_rows = check['frames'][frame][side]['rows']
        compared = []
        for i in range(a, b+1):
            if rows[i]['stable'] or not other_rows[i]['stable']:
                continue
            target = other_rows[i]['point']
            value = bridge(rows[a-1]['point'], rows[b+1]['point'], target, axis)
            compared.append(dict(index=i, discrepancyPixels=abs(value-target[other])))
        comparison = dict(gap=list(gap), recoveredPoints=compared,
            worstPixels=max((r['discrepancyPixels'] for r in compared), default=None))

    truth = None
    if known_cut is not None:
        proposals = [points[i]['lineProposal'][other] for i in inliers]
        truth = dict(knownCut=known_cut, medianProposal=float(np.median(proposals)),
                     medianErrorPixels=abs(float(np.median(proposals))-known_cut))
    result = dict(inputSHA256=source['inputSHA256'], candidateSHA256=hashlib.sha256(candidate.read_bytes()).hexdigest(),
        frame=frame, side=side, observedCount=len(ids), lineInlierCount=len(inliers),
        inlierIndices=sorted(inliers), occupiedBins=bins,
        inlierResidualLimitPixels=4, model=dict(type='Theil-Sen line', slopePerStation=float(slope),
                                                intercept=float(intercept)),
        crossValidation=cross_validation, gapComparison=comparison, knownGeometryControl=truth,
        points=points,
        limitation='Proposal only. Withholding reuses same-photo observations and can validate a consistently wrong boundary. No independent physical accuracy or automatic reporting.')
    output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ['points', 'inlierIndices']}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['candidate', 'frame', 'side', 'output']:
        parser.add_argument(name, type=Path if name in ['candidate', 'output'] else str)
    parser.add_argument('--gap', type=int, nargs=2)
    parser.add_argument('--alternate', type=Path)
    parser.add_argument('--known-cut', type=float)
    args = parser.parse_args()
    run(args.candidate, args.frame, args.side, args.output, args.gap, args.alternate, args.known_cut)
