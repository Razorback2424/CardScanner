#!/usr/bin/env python3
"""Research-only paired measurement of observed physical and artwork paths.

The provisional outer quad defines a projective coordinate system. The reference
seed defines common sampling spans inside the artwork; it never supplies measured
edges. PCHIP interpolation stays between supported observations. Local opposing
margin fractions cancel a common scale at each station, including axis-aligned
bow/stretch controls. This does not invert arbitrary 3D deformation or lens error.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from scipy.interpolate import PchipInterpolator
from selective_path_measurement import CORNERS, SIDES, supported_path, transform
from gt_tool import edge_points


def sampling_spans(inner_seed, mapping):
    q = transform(inner_seed, mapping)
    spans = {}
    for axis, sides in [('x', ['top', 'bottom']), ('y', ['left', 'right'])]:
        coordinate = 0 if axis == 'x' else 1
        intervals = []
        for side in sides:
            a, b = np.array(edge_points(q, side))[:, coordinate]
            lo, hi = sorted([a, b])
            intervals.append((lo+.2*(hi-lo), lo+.8*(hi-lo)))
        span = [max(v[0] for v in intervals), min(v[1] for v in intervals)]
        if not 0 < span[0] < span[1] < 1:
            raise ValueError('invalid common artwork sampling span')
        spans[axis] = span
    return spans


def measure(records, mapping, spans):
    values, support, retained = {}, {}, {}
    for frame in ['outer', 'inner']:
        values[frame], support[frame], retained[frame] = {}, {}, {}
        for side in SIDES:
            axis = 1 if side in ['left', 'right'] else 0
            span = spans['y' if axis == 1 else 'x']
            pts, evidence = supported_path(records[frame][side], mapping, span)
            q = transform(pts, mapping)
            q = q[np.argsort(q[:, axis])]
            grid = np.linspace(*span, 31)
            if q[0, axis] > grid[0] or q[-1, axis] < grid[-1]:
                raise ValueError('unsupported paired endpoint')
            values[frame][side] = PchipInterpolator(q[:, axis], q[:, 1-axis], extrapolate=False)(grid)
            support[frame][side], retained[frame][side] = evidence, pts
    widths = {s: (values['inner'][s]-values['outer'][s])*(1 if s in ['left', 'top'] else -1)
              for s in SIDES}
    if any(not np.all(np.isfinite(v)) or np.any(v <= 0) for v in widths.values()):
        raise ValueError('crossing frames or unsupported margin')
    local = {axis: 100*widths[a]/(widths[a]+widths[b])
             for axis, a, b in [('left', 'left', 'right'), ('top', 'top', 'bottom')]}
    means = {s: float(v.mean()) for s, v in widths.items()}
    return dict(leftShare=float(local['left'].mean()), topShare=float(local['top'].mean()),
        localShares={k: v.tolist() for k, v in local.items()},
        localShareRange={k: [float(v.min()), float(v.max())] for k, v in local.items()},
        ratioOfMeanMargins=dict(left=100*means['left']/(means['left']+means['right']),
                               top=100*means['top']/(means['top']+means['bottom'])),
        meanMargins=means, samplingSpans=spans, samplesPerAxis=31, support=support,
        retainedNativePaths=retained)


def controls():
    outer = np.array([[0., 0.], [1., 0.], [1., 1.], [0., 1.]])
    inner = np.array([[.04, .12], [.94, .12], [.94, .52], [.04, .52]])
    spans = sampling_spans(inner, np.eye(3))
    projection = np.array([[1800., 150., 250.], [50., 2800., 100.], [.08, .15, 1.]])
    def records(deform, projective):
        result = {}
        for frame, q in [('outer', outer), ('inner', inner)]:
            result[frame] = {}
            for side in SIDES:
                a, b = np.array(edge_points(q, side))
                p = a+np.linspace(.1, .9, 61)[:, None]*(b-a)
                p = deform(p)
                if projective:
                    p = transform(p, projection)
                result[frame][side] = dict(side=side,
                    rows=[dict(point=v.tolist(), stable=True) for v in p])
        return result
    def bow(p, axis):
        out = p.copy()
        t = p[:, 1-axis]
        out[:, axis] = p[:, axis]*(.9+.2*t)+.02*(2*t-1)**2
        return out
    results = {}
    for name, deformation, projective in [
        ('flat', lambda p: p, False), ('projective', lambda p: p, True),
        ('vertical_bow_and_stretch', lambda p: bow(p, 1), True),
        ('horizontal_bow_and_stretch', lambda p: bow(p, 0), True),
    ]:
        output = measure(records(deformation, projective), np.linalg.inv(projection) if projective else np.eye(3), spans)
        error = max(abs(output['leftShare']-40), abs(output['topShare']-20))
        if error > .005:
            raise ValueError(name+' fails known geometry: '+str(error))
        results[name] = dict(leftShare=output['leftShare'], topShare=output['topShare'], worstErrorPP=error)
    clean = records(lambda p: p, False)
    for name in ['missing_endpoint', 'long_gap', 'crossing_frames']:
        broken = copy.deepcopy(clean)
        if name == 'missing_endpoint':
            for row in broken['inner']['left']['rows'][:25]: row['stable'] = False
        elif name == 'long_gap':
            for row in broken['inner']['top']['rows'][25:33]: row['stable'] = False
        else:
            for row in broken['inner']['left']['rows']: row['point'][0] = -.01
        try:
            measure(broken, np.eye(3), spans)
        except ValueError as error:
            results[name] = dict(rejected=True, reason=str(error))
        else:
            raise ValueError(name+' incorrectly accepted')
    return results


def run(baseline, artwork, physical, output, alternate=None, replace_sides=()):
    art, cut = json.loads(artwork.read_text()), json.loads(physical.read_text())
    candidates = json.loads(baseline.read_text())
    row = next(r for r in candidates if r['inputSHA256'] == art['inputSHA256'])
    if cut['inputSHA256'] != row['inputSHA256']:
        raise ValueError('physical capture mismatch')
    records = dict(inner=copy.deepcopy(art['frames']['inner']), outer=cut['frames']['outer'])
    if alternate:
        extra = json.loads(alternate.read_text())
        if extra['inputSHA256'] != row['inputSHA256']:
            raise ValueError('alternate capture mismatch')
        for side in replace_sides:
            records['inner'][side] = extra['frames']['inner'][side]
    elif replace_sides:
        raise ValueError('replacement sides require alternate paths')
    quad = lambda key: [[row[key][corner][axis] for axis in ['x', 'y']] for corner in CORNERS]
    mapping = cv2.getPerspectiveTransform(np.float32(quad('actualOuter')), np.float32([[0,0],[1,0],[1,1],[0,1]]))
    spans = sampling_spans(quad('actualInner'), mapping)
    result = dict(fixture=row['fixture'], inputSHA256=row['inputSHA256'],
        controls=controls(), replacedArtworkSides=list(replace_sides),
        inputHashes={str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in [baseline, artwork, physical]+([alternate] if alternate else [])},
        limitation='Research photo-plane ratios, not arbitrary 3D unwarping, calibrated physical accuracy or a native automatic pass')
    try:
        result.update(acceptedForResearchMeasurement=True, measurement=measure(records, mapping, spans),
                      rectificationMatrix=mapping.tolist())
    except ValueError as error:
        result.update(acceptedForResearchMeasurement=False, reason=str(error))
    output.write_text(json.dumps(result, indent=2)+'\n')
    print({k: v for k, v in result.items() if k not in ['measurement', 'rectificationMatrix', 'inputHashes', 'controls']})
    if result['acceptedForResearchMeasurement']:
        print({k: result['measurement'][k] for k in ['leftShare', 'topShare', 'samplingSpans', 'localShareRange']})


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['baseline', 'artwork', 'physical', 'output']:
        parser.add_argument(name, type=Path)
    parser.add_argument('--alternate', type=Path)
    parser.add_argument('--replace-side', action='append', choices=SIDES, default=[])
    args = parser.parse_args()
    run(args.baseline, args.artwork, args.physical, args.output, args.alternate, args.replace_side)
