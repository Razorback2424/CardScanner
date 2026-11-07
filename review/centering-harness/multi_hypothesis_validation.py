#!/usr/bin/env python3
"""Focused validation of saved multi-hypothesis research outputs.

Frozen observations come from the same captures; they do not establish
independent physical accuracy. Competing paths remain unselected proposals.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.interpolate import PchipInterpolator

from selective_path_measurement import transform


def compare(points, targets, side):
    axis = 1 if side in ['left', 'right'] else 0
    other = 1-axis
    ordered = sorted(points, key=lambda row:row['point'][axis])
    errors, inferred, missing = [], 0, 0
    for target in targets:
        pair = next(((a,b) for a,b in zip(ordered,ordered[1:])
                     if a['point'][axis] <= target[axis] <= b['point'][axis]),None)
        if pair is None or any(p['origin']=='extrapolated' for p in pair):
            missing += 1
            continue
        a,b = pair
        fraction = (target[axis]-a['point'][axis])/(b['point'][axis]-a['point'][axis])
        value = a['point'][other]+fraction*(b['point'][other]-a['point'][other])
        errors.append(abs(value-target[other]))
        inferred += any(p['origin']=='interpolated' for p in pair)
    return dict(targets=len(targets),bracketed=len(errors),missing=missing,
                withinFourPixels=sum(error<=4 for error in errors),
                worstPixels=max(errors,default=None),inferredBrackets=inferred)


def values(points, mapping, axis, grid):
    p = transform(points, mapping)
    along = 1 if axis == 'y' else 0
    p = p[np.argsort(p[:,along])]
    if p[0,along]>grid[0] or p[-1,along]<grid[-1] or np.any(np.diff(p[:,along])<=0):
        raise ValueError('unsupported or nonmonotonic path')
    return PchipInterpolator(p[:,along],p[:,1-along],extrapolate=False)(grid)


def sensitivity(result, measurement, mapping, axis):
    span = measurement['samplingSpans'][axis]
    grid = np.linspace(*span,31)
    paths = measurement['retainedNativePaths']
    if axis == 'y':
        outer_first = values(paths['outer']['left'],mapping,axis,grid)
        inner_first = values(paths['inner']['left'],mapping,axis,grid)
        outer_second = values(paths['outer']['right'],mapping,axis,grid)
        first = inner_first-outer_first
        baseline = measurement['leftShare']
    else:
        outer_first = values(paths['outer']['top'],mapping,axis,grid)
        inner_first = values(paths['inner']['top'],mapping,axis,grid)
        inner_second = values(paths['inner']['bottom'],mapping,axis,grid)
        first = inner_first-outer_first
        baseline = measurement['topShare']
    output = []
    for index,hypothesis in enumerate(result['hypotheses']):
        # Sensitivity may interpolate inside supported bounds; it must not use
        # a model's extrapolated endpoint as a measured boundary.
        candidate = values([point['point'] for point in hypothesis['points']
                            if point['origin']!='extrapolated'],mapping,axis,grid)
        second = outer_second-candidate if axis == 'y' else candidate-inner_second
        if np.any(first<=0) or np.any(second<=0):
            output.append(dict(index=index,rejected='nonpositive margins'))
            continue
        share = float(np.mean(100*first/(first+second)))
        output.append(dict(index=index,share=share,deltaFromReferencePP=share-baseline,
            nonObservedStations=sum(p['origin']!='observed_candidate' for p in hypothesis['points'])))
    return output


def run(root, builds, output):
    frozen_root = Path('TestFixtures/TradingCards/Supplementary')
    magic = json.loads((frozen_root/'magic-back-selective-photo-paths.json').read_text())
    squirtle = json.loads((frozen_root/'squirtle-foil-photo-paths.json').read_text())
    backs = {row['file']:row for row in json.loads((frozen_root/'pokemon-back-paired-photo-paths.json').read_text())}
    cases = [
        ('squirtle-right',builds/'CardScanner-Squirtle-20261107/printed-color-dense/card-paths.json','inner','right',squirtle),
        ('dewott-bottom',builds/'CardScanner-Dewott-20261107/printed/card-paths.json','inner','bottom',None),
        ('squirtle-bottom-cut',builds/'CardScanner-Squirtle-20261107/physical-background/card-paths.json','outer','bottom',squirtle),
        ('magic-bottom',builds/'CardScanner-MagicBack-20261107/IMG_0810/printed-selective-paths.json','inner','bottom',magic),
        ('pokemon-0798-right',builds/'CardScanner-PokemonBack-20261107/IMG_0798/dense-color/card-paths.json','inner','right',backs['IMG_0798.HEIC']),
        ('pokemon-0800-bottom',builds/'CardScanner-PokemonBack-20261107/IMG_0800/dense-color/card-paths.json','inner','bottom',backs['IMG_0800.HEIC']),
    ]
    results = {}
    for name,source,frame,side,frozen in cases:
        saved = json.loads((root/(name+'-v7.json')).read_text())
        original = json.loads(source.read_text())
        if saved['candidateSHA256'] != hashlib.sha256(source.read_bytes()).hexdigest():
            raise AssertionError(name+': source changed')
        if not saved['reviewRequired']:
            raise AssertionError(name+': prototype certified boundary identity')
        rows = original['frames'][frame][side]['rows']
        preserved = all((saved['existingPath'][i]['point'] == row['point'] if row['stable']
                         else saved['existingPath'][i]['point'] is None) for i,row in enumerate(rows))
        if not preserved:
            raise AssertionError(name+': an existing observation changed')
        compared = []
        if frozen:
            if frozen['inputSHA256'] != saved['inputSHA256']:
                raise AssertionError(name+': capture differs')
            targets = frozen[frame][side]
            compared = [compare(h['points'],targets,side) for h in saved['hypotheses']]
            if not any(c['missing']==0 and c['withinFourPixels']==len(targets) for c in compared):
                raise AssertionError(name+': no proposal reproduced the frozen path')
        results[name] = dict(status=saved['status'],tracks=saved['distinctHypotheses'],
                             originalObservationsPreserved=preserved,comparisons=compared)

    squirtle_path = json.loads((root/'squirtle-right-v7.json').read_text())
    if squirtle_path['status']!='multiple_plausible_tracks':
        raise AssertionError('Squirtle competing printed edges were hidden')
    curve_index = next(i for i,h in enumerate(squirtle_path['hypotheses'])
                       if h.get('proposalSource')=='robust_existing_curve')
    curve = squirtle_path['hypotheses'][curve_index]
    if any(curve['points'][i]['origin']!='interpolated' for i in range(18,27)):
        raise AssertionError('Squirtle missing positions were not marked inferred')
    recovered = json.loads((builds/'CardScanner-Squirtle-20261107/chroma-border-shift-+0-v2.json').read_text())['frames']['inner']['right']['rows']
    gaps = [abs(curve['points'][i]['point'][0]-recovered[i]['point'][0]) for i in [18,19,23,24,25,26]]
    if max(gaps)>4:
        raise AssertionError('Squirtle gap did not agree with the recovered points')
    results['squirtle-right']['curveIndex'] = curve_index
    results['squirtle-right']['gapWorstPixels'] = max(gaps)

    dewott = json.loads((root/'dewott-bottom-v7.json').read_text())
    expected = json.loads((builds/'CardScanner-Dewott-20261107/bottom-line-probe-v1.json').read_text())
    line = dewott['hypotheses'][0]
    errors = [abs(line['points'][i]['point'][1]-expected['points'][i]['lineProposal'][1]) for i in range(12,54)]
    number_errors = [abs(line['points'][i]['point'][1]-expected['points'][i]['lineProposal'][1]) for i in [3,4,5,8,9]]
    if max(errors+number_errors)>4:
        raise AssertionError('Dewott candidate diverged from the previously reviewed line')
    results['dewott-bottom']['reviewedLineWorstPixels'] = max(errors)
    results['dewott-bottom']['cardNumberWorstPixels'] = max(number_errors)

    controls = json.loads((root/'controls-v7/summary.json').read_text())
    if controls['curve']['maximumGapErrorPixels']>1 or controls['interior_rule']['status']!='multiple_plausible_tracks':
        raise AssertionError('known-geometry controls did not pass')
    paired = json.loads((builds/'CardScanner-Squirtle-20261107/paired-selective-chroma-v2.json').read_text())
    mapping = np.asarray(paired['rectificationMatrix']);measurement = paired['measurement']
    conditional = dict(right=sensitivity(squirtle_path,measurement,mapping,'y'),
        bottomCut=sensitivity(json.loads((root/'squirtle-bottom-cut-v7.json').read_text()),measurement,mapping,'x'))
    report = dict(status='Offline prototype only; no automatic boundary selection',controls=controls,cases=results,
        conditionalRatioSensitivity=conditional,
        limitation='Same-photo frozen observations and overlapping candidate methods are correlated. Ratios hold other paths and rectification fixed; inferred points are not direct evidence.')
    output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(status=report['status'],cases={k:dict(status=v['status'],tracks=v['tracks'])
        for k,v in results.items()},conditionalRatioSensitivity=conditional),indent=2),flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root',type=Path)
    parser.add_argument('builds',type=Path)
    parser.add_argument('output',type=Path)
    args = parser.parse_args()
    run(args.root,args.builds,args.output)
