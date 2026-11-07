#!/usr/bin/env python3
"""Known-geometry controls for the offline multi-hypothesis prototype."""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from multi_hypothesis_boundary_probe import run as probe


def fixture(kind):
    if kind == 'hidden_cut':
        image = Image.new('RGB', (600, 800), (170, 170, 170))
        ImageDraw.Draw(image).rectangle((100, 0, 599, 799), fill=(20, 20, 20))
        return image
    image = Image.new('RGB', (600, 800), (255, 255, 255))
    draw = ImageDraw.Draw(image)
    if kind == 'flat':
        return image
    if kind == 'curve':
        for y in range(80, 770):
            edge = round(80+14*((y-425)/335)**2)
            draw.line((edge, y, 519, y), fill=(170, 170, 170))
        return image
    if kind == 'shadow':
        draw.rectangle((55, 0, 79, 799), fill=(100, 100, 100))
    draw.rectangle((80, 80, 519, 769), fill=(170, 170, 170))
    if kind == 'interior_rule':
        draw.rectangle((105, 105, 494, 744), fill=(20, 20, 20))
        draw.rectangle((111, 111, 488, 738), fill=(170, 170, 170))
    return image


def run(output):
    output.mkdir(parents=True, exist_ok=False)
    summary = {}
    for kind in ['single', 'flat', 'interior_rule', 'shadow', 'hidden_cut', 'curve']:
        image_path = output/(kind+'.png');fixture(kind).save(image_path)
        digest = hashlib.sha256(image_path.read_bytes()).hexdigest()
        rows = []
        for i in range(61):
            y = 90+(.1+.8*i/60)*670
            observed = kind == 'curve' and not 20 <= i <= 28 and i % 11 != 2
            x = 79.5+14*((y-425)/335)**2 if observed else 90.
            rows.append(dict(base=[90.,y],point=[x,y],stable=observed))
        candidate = dict(inputSHA256=digest, signal='rgb_mean', frames=dict(outer=dict(left=dict(
            side='left', normal=[-1., 0.], rows=rows))))
        candidate_path = output/(kind+'-candidate.json');candidate_path.write_text(json.dumps(candidate)+'\n')
        result_path = output/(kind+'-result.json')
        probe(image_path, candidate_path, 'outer', 'left', result_path)
        result = json.loads(result_path.read_text())
        positions = [float(np.median([p['point'][0] for p in h['points'][8:53]]))
                     for h in result['hypotheses'] if not h['possibleTrackHopping']]
        summary[kind] = dict(status=result['status'], reviewRequired=result['reviewRequired'],
                             candidatePositions=positions, totalProposals=result['totalProposals'])
        if not result['reviewRequired']:
            raise AssertionError(kind+': prototype must not certify physical identity')
        if kind == 'flat' and result['status'] != 'insufficient_support':
            raise AssertionError('flat source produced a candidate')
        if kind == 'single' and (result['status'] != 'single_track_identity_unverified' or
                                 not any(abs(v-79.5) <= 1 for v in positions)):
            raise AssertionError('single visible cut was not located')
        if kind in ['interior_rule', 'shadow']:
            other = 104.5 if kind == 'interior_rule' else 54.5
            if (result['status'] != 'multiple_plausible_tracks' or
                    not any(abs(v-79.5) <= 1 for v in positions) or
                    not any(abs(v-other) <= 1 for v in positions)):
                raise AssertionError(kind+': competing visible boundaries not retained')
        if kind == 'hidden_cut' and not any(abs(v-99.5) <= 1 for v in positions):
            raise AssertionError('hidden-cut misleading line was not exposed for review')
        if kind == 'curve':
            curves = [h for h in result['hypotheses'] if h.get('proposalSource') == 'robust_existing_curve']
            if not curves:
                raise AssertionError('supported curve was not retained')
            errors = []
            for i in range(20,29):
                point = curves[0]['points'][i]
                if point['origin'] != 'interpolated':
                    raise AssertionError('missing curve evidence was not marked inferred')
                y = rows[i]['base'][1]
                errors.append(abs(point['point'][0]-(79.5+14*((y-425)/335)**2)))
            if max(errors) > 1:
                raise AssertionError('inferred curve missed known geometry')
            summary[kind]['maximumGapErrorPixels'] = max(errors)
    (output/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    print('known-geometry controls passed',json.dumps(summary),flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    run(args.output)
