#!/usr/bin/env python3
"""Compare frozen candidates with separately recorded visual photo bands.

All measurements use the same central 50% span to avoid extending the sparse
review beyond observed samples. Results are same-photo review corroboration,
not blind accuracy, calibrated physical truth, or new production corpus passes.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import numpy as np
from selective_path_measurement import CORNERS, measure, paths, synthetic_control


def review_paths(bands, choices):
    frames = {'outer': {}, 'inner': {}}
    for (frame, side), choice in zip(
            [(f, s) for f in frames for s in bands[f]], choices):
        rows = np.asarray(bands[frame][side], dtype=float)
        if np.any(rows[:, 1] > rows[:, 2]):
            raise ValueError('reversed review interval')
        coordinate = rows[:, 1] + choice * (rows[:, 2] - rows[:, 1])
        points = np.c_[rows[:, 0], coordinate]
        if side in ['left', 'right']:
            points = points[:, ::-1]
        frames[frame][side] = points.tolist()
    return frames


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    for name in ['bands', 'packet', 'candidate', 'baseline', 'output']:
        p.add_argument(name, type=Path)
    a = p.parse_args()
    bands, packet, candidate, baseline = [json.loads(v.read_text()) for v in
        [a.bands, a.packet, a.candidate, a.baseline]]
    if packet['inputSHA256'] != candidate['inputSHA256']:
        raise ValueError('photo packet/candidate mismatch')
    if bands['fixture'] != candidate['fixture']:
        raise ValueError('review/candidate fixture mismatch')
    record = next(v for v in baseline if v['fixture'] == bands['fixture'])
    h = np.array(candidate['rectificationMatrix'])
    compact = lambda f: {k: v for k, v in measure(f, h, (.25, .75)).items()
                         if k in ['leftShare', 'topShare']}
    reviewed = compact(review_paths(bands, [.5] * 8))
    alternatives = [compact(review_paths(bands, c))
                    for c in itertools.product([0, 1], repeat=8)]
    envelope = {k: [min(v[k] for v in alternatives), max(v[k] for v in alternatives)]
                for k in reviewed}
    predictions = {'selective': compact(candidate['predictionNativePaths'])}
    for label, prefix in [('production', 'actual'), ('historicalReference', 'expected')]:
        f = {frame: paths([[record[prefix + name][corner][axis] for axis in ['x', 'y']]
                          for corner in CORNERS])
             for frame, name in [('outer', 'Outer'), ('inner', 'Inner')]}
        predictions[label] = compact(f)
    results = {name: dict(measurement=v,
        differenceFromReviewMidpointPP={k: v[k]-reviewed[k] for k in reviewed},
        largestDifferenceAcrossReviewAlternativesPP={k: max(abs(v[k]-x) for x in envelope[k]) for k in reviewed})
        for name, v in predictions.items()}
    result = dict(fixture=bands['fixture'], inputSHA256=packet['inputSHA256'],
        sourceHashes={name: hashlib.sha256(getattr(a, name).read_bytes()).hexdigest()
                      for name in ['bands', 'packet', 'candidate', 'baseline']},
        sampleSpan=[.25, .75], reviewMidpoint=reviewed,
        reviewAlternativeEnvelope=envelope, alternativeCount=len(alternatives), results=results,
        syntheticControl=synthetic_control(),
        limitations=bands['status'] + '; five samples per side, interpolated; envelope covers uniform lower/upper choices per side, not every physical explanation; production pass count unchanged')
    a.output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))
