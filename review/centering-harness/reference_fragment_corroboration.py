#!/usr/bin/env python3
"""Compare design-profile observations with retained photo-side hypotheses.

This research tool does not select a path. A reference profile can help identify
the printed rule at a particular station, while the independently retained path
describes its possible continuation. Both still use the same photo pixels: their
agreement is not an independent physical-accuracy measurement.
"""
import argparse
import bisect
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
import pillow_heif

from reference_profile_probe import probe


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compare(profile, candidate, side, tolerance=4.0):
    """Report station-level agreement without extrapolating or choosing a path."""
    if side not in ('left', 'top', 'right', 'bottom'):
        raise ValueError('invalid side')
    axis = 1 if side in ('left', 'right') else 0
    other = 1-axis
    rows = profile['rows']
    if len(rows) != 61 or not np.isfinite(tolerance) or tolerance <= 0:
        raise ValueError('expected 61 profile stations and a positive tolerance')
    results = []
    for index, hypothesis in enumerate(candidate['hypotheses']):
        points = hypothesis['points']
        if any(point['origin'] not in ('observed_candidate', 'interpolated', 'extrapolated')
               for point in points):
            raise ValueError('unknown candidate point provenance')
        if any(len(point['point']) != 2 or not np.all(np.isfinite(point['point'])) for point in points):
            raise ValueError('nonfinite candidate point')
        ordered = sorted(points, key=lambda item: item['point'][axis])
        coordinates = [point['point'][axis] for point in ordered]
        if len(coordinates) < 2 or any(b <= a for a, b in zip(coordinates, coordinates[1:])):
            raise ValueError('candidate is not a single-valued side')
        stations = []
        for station, row in enumerate(rows):
            if not row['stable']:
                continue
            target = row['point']
            if len(target) != 2 or not np.all(np.isfinite(target)):
                raise ValueError('nonfinite profile observation')
            position = target[axis]
            right = bisect.bisect_left(coordinates, position)
            if right < len(ordered) and coordinates[right] == position:
                pair = (ordered[right], ordered[right])
            elif right == 0 or right == len(ordered):
                pair = None
            else:
                pair = (ordered[right-1], ordered[right])
            record = dict(station=station, region=min(4, station*5//len(rows)))
            if pair is None or any(p['origin'] == 'extrapolated' for p in pair):
                record['status'] = 'unsupported'
            else:
                a, b = pair
                t = 0.0 if a is b else (position-a['point'][axis])/(b['point'][axis]-a['point'][axis])
                value = a['point'][other]+t*(b['point'][other]-a['point'][other])
                error = abs(value-target[other])
                record.update(status='agreement' if error <= tolerance else 'disagreement',
                              axisDifferenceNativePixels=float(error),
                              bracketsInferredPoint=any(p['origin'] == 'interpolated' for p in pair))
            stations.append(record)
        def count(status):
            return sum(row['status'] == status for row in stations)
        agreement_counts = [sum(row['status'] == 'agreement' and row['region'] == region
                                for row in stations) for region in range(5)]
        results.append(dict(index=index, proposalSource=hypothesis.get('proposalSource', 'line'),
            possibleTrackHopping=hypothesis['possibleTrackHopping'],
            pointOrigins={origin: sum(point['origin'] == origin for point in points)
                          for origin in ('observed_candidate', 'interpolated', 'extrapolated')},
            agreement=count('agreement'), disagreement=count('disagreement'), unsupported=count('unsupported'),
            agreementRegions=[region for region, count in enumerate(agreement_counts) if count],
            agreementRegionCounts=agreement_counts,
            inferredBrackets=sum(row.get('bracketsInferredPoint', False) for row in stations),
            stations=stations))
    reference_counts = [sum(row['stable'] and min(4, i*5//len(rows)) == region
                            for i, row in enumerate(rows)) for region in range(5)]
    return dict(stableReferenceStations=sum(row['stable'] for row in rows),
        stableReferenceRegions=[region for region, count in enumerate(reference_counts) if count],
        stableReferenceRegionCounts=reference_counts,
        toleranceNativePixels=tolerance, hypotheses=results, selectedCandidate=None, reviewRequired=True)


def run(reference, specification, photo, registration_path, source_path, candidate_path, output):
    if output.exists():
        raise ValueError('output already exists')
    specification_data = json.loads(specification.read_text())
    references = specification_data['references']
    if len(references) != 1:
        raise ValueError('specification must identify exactly one reference')
    spec = references[0]
    registration = json.loads(registration_path.read_text())
    source = json.loads(source_path.read_text())
    candidates = json.loads(candidate_path.read_text())
    if (not registration['accepted'] or digest(reference) != spec['sha256']
            or digest(reference) != registration['referenceSHA256']
            or digest(photo) != registration['inputSHA256']
            or digest(photo) != candidates['inputSHA256']
            or digest(photo) != source['inputSHA256']
            or digest(source_path) != candidates['candidateSHA256']
            or candidates['frame'] != 'inner' or not candidates['reviewRequired']):
        raise ValueError('identity, source, or review-state mismatch')
    side = candidates['side']
    original = source['frames']['inner'][side]['rows']
    saved = candidates['existingPath']
    if len(original) != len(saved) or not all(
        saved[i]['point'] == (row['point'] if row['stable'] else None)
        for i, row in enumerate(original)
    ):
        raise ValueError('previously retained observations changed')
    pillow_heif.register_heif_opener()
    reference_image = np.asarray(Image.open(reference).convert('RGBA').convert('RGB'), dtype='float32').mean(axis=2)
    photo_image = np.asarray(ImageOps.exif_transpose(Image.open(photo)).convert('RGB'), dtype='float32').mean(axis=2)
    profile = probe(reference_image, photo_image, np.asarray(registration['homography']),
                    spec['printedBorder'], side)
    comparison = compare(profile, candidates, side)
    result = dict(referenceID=spec['id'], inputSHA256=digest(photo), side=side,
        sources={str(path): digest(path) for path in [reference, specification, registration_path, source_path, candidate_path]},
        originalObservationsPreserved=True, comparison=comparison, profile=profile,
        limitation=('Research-only, uncalibrated same-photo evidence. Reference matching and candidate gradients '
                    'are correlated; agreement does not validate unobserved stations, physical cut identity, '
                    'or automatic selection. Inferred candidate positions are not direct observations.'))
    output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps({key: value for key, value in comparison.items() if key != 'hypotheses'} |
        {'hypotheses': [{key: value for key, value in row.items() if key != 'stations'}
                        for row in comparison['hypotheses']]}, indent=2), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('reference', 'specification', 'photo', 'registration', 'source', 'candidate', 'output'):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    run(args.reference, args.specification, args.photo, args.registration, args.source, args.candidate, args.output)
