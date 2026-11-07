#!/usr/bin/env python3
"""Offline multi-candidate boundary reconstruction; never changes app output.

Retain several photo transitions at each station, fit competing whole-side
lines, and distinguish direct observations from interpolated or extrapolated
positions. A coherent track does not establish whether it is the card cut or
the intended printed boundary. Every output therefore remains a review proposal.
"""
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
import pillow_heif
from scipy.ndimage import gaussian_filter1d
from scipy.optimize import least_squares
from scipy.signal import find_peaks

from track_card_paths import samples

OFFSETS = np.arange(-80, 81)
WIDTHS = (4, 8, 16)
SIGMAS = (1, 2)
ANCHORS = (0, 8, 16, 24, 32, 40, 48, 56, 60)
MAX_STARTS = 16
MIN_STRENGTH = 2.5
MAX_DISAGREEMENT = 4.
MIN_OBSERVATIONS = 30


def subpixel(gradient, index, offsets):
    curvature = float(gradient[index-1]-2*gradient[index]+gradient[index+1])
    fraction = float(np.clip(.5*(gradient[index-1]-gradient[index+1])/curvature, -.5, .5)) if curvature < -1e-9 else 0.
    return float(offsets[index]+fraction)


def local_candidates(image, record, dense=False, color=False):
    normal = np.asarray(record['normal'], dtype=float)
    if not np.isclose(np.linalg.norm(normal), 1, atol=1e-4):
        raise ValueError('expected a unit side normal')
    tangent = np.array([-normal[1], normal[0]])
    rows = record['rows']
    if len(rows) != 61:
        raise ValueError('expected 61 ordered stations')
    result, domains = [], []
    for row in rows:
        base = np.asarray(row['base'], dtype=float)
        valid = np.ones(len(OFFSETS), dtype=bool)
        for shift in [-max(WIDTHS), max(WIDTHS)]:
            points = base+OFFSETS[:, None]*normal+shift*tangent
            valid &= ((points[:, 0] >= 0) & (points[:, 0] < image.shape[1]-1) &
                      (points[:, 1] >= 0) & (points[:, 1] < image.shape[0]-1))
        offsets = OFFSETS[valid]
        domains.append([int(offsets[0]), int(offsets[-1])] if len(offsets) else None)
        trials = []
        try:
            if len(offsets) < 57 or len(offsets) != offsets[-1]-offsets[0]+1:
                raise ValueError('insufficient observed search band')
            for width in WIDTHS:
                profile = samples(image, base[None], normal, tangent, offsets, width, dense=dense)[0]
                for sigma in SIGMAS:
                    derivative = gaussian_filter1d(profile, sigma, axis=0, order=1)
                    gradient = np.mean(abs(derivative), axis=1) if color else abs(derivative)
                    peaks = find_peaks(gradient, distance=4, prominence=.5)[0]
                    peaks = [int(i) for i in peaks if gradient[i] >= MIN_STRENGTH and 4 < i < len(offsets)-5]
                    trials.append((gradient, peaks))
        except ValueError:
            # No pixels beyond the image edge may be clamped into evidence.
            if row['stable']:
                depth = float(np.dot(np.asarray(row['point'])-base, normal))
                result.append([dict(offset=depth, strength=None, origin='existing_supported_point', trialRange=None)])
            else:
                result.append([])
            continue
        reference_gradient, reference_peaks = trials[1]
        starts = sorted(reference_peaks, key=lambda index: (-reference_gradient[index], index))[:MAX_STARTS]
        found = []
        for start in starts:
            positions, strengths = [], []
            for gradient, peaks in trials:
                nearby = [index for index in peaks if abs(offsets[index]-offsets[start]) <= MAX_DISAGREEMENT]
                if not nearby:
                    break
                chosen = min(nearby, key=lambda index: (abs(offsets[index]-offsets[start]), -gradient[index]))
                positions.append(subpixel(gradient, chosen, offsets)); strengths.append(float(gradient[chosen]))
            if len(positions) != 6 or max(positions)-min(positions) > MAX_DISAGREEMENT:
                continue
            depth = float(np.median(positions))
            if any(abs(depth-c['offset']) < 1 for c in found):
                continue
            found.append(dict(offset=depth, strength=float(np.median(strengths)),
                              origin='six_local_trials', trialRange=float(max(positions)-min(positions))))
        if row['stable']:
            depth = float(np.dot(np.asarray(row['point'])-base, normal))
            existing = next((candidate for candidate in found if abs(candidate['offset']-depth) < 1), None)
            if existing is None:
                found.append(dict(offset=depth, strength=None, origin='existing_supported_point', trialRange=None))
            else:
                existing['alsoExistingSupportedPoint'] = True
        result.append(sorted(found, key=lambda candidate:candidate['offset']))
    return result, domains


def fit_hypotheses(candidates):
    positions = np.full((61, max(1, max(map(len, candidates)))), np.inf)
    for station, row in enumerate(candidates):
        for i, candidate in enumerate(row):
            positions[station, i] = candidate['offset']
    stations = np.arange(61, dtype=float)

    def choose(intercept, slope):
        distances = abs(positions-(intercept+slope*stations)[:, None])
        nearest = np.argmin(distances, axis=1)
        errors = distances[np.arange(61), nearest]
        near = distances <= MAX_DISAGREEMENT
        low = np.min(np.where(near, positions, np.inf), axis=1)
        high = np.max(np.where(near, positions, -np.inf), axis=1)
        ambiguous = (high-low) > MAX_DISAGREEMENT
        return nearest, errors, np.flatnonzero((errors <= MAX_DISAGREEMENT) & ~ambiguous)

    def fit(intercept, slope):
        selected = None
        for _ in range(3):
            # Two distinct local peaks inside the same tolerance are not a
            # single observation. Do not switch between them just to obtain a
            # smooth-looking global fit.
            nearest, errors, selected = choose(intercept, slope)
            if len(selected) < MIN_OBSERVATIONS:
                return None
            values = positions[selected, nearest[selected]]
            slope, intercept = np.polyfit(stations[selected], values, 1)
        nearest, errors, selected = choose(intercept, slope)
        bins = sorted(set(min(4, int(i)*5//61) for i in selected))
        if (len(selected) < MIN_OBSERVATIONS or len(bins) < 4 or
                selected[0] > 7 or selected[-1] < 53 or abs(slope) > 2):
            return None
        chosen = {int(i): candidates[i][int(nearest[i])] for i in selected}
        # Neighboring supported points, including across a gap, must not jump
        # between parallel features while the fitted line passes between them.
        if any(abs(chosen[int(b)]['offset']-chosen[int(a)]['offset']-slope*(b-a))>MAX_DISAGREEMENT
               for a,b in zip(selected,selected[1:])):
            return None
        residual = float(np.sqrt(np.mean(errors[selected]**2)))
        return dict(intercept=float(intercept), slopePerStation=float(slope),
                    directCount=len(selected), occupiedBins=bins, rmsPixels=residual,
                    observations=chosen)

    proposals = []
    for ai, first in enumerate(ANCHORS):
        for second in ANCHORS[ai+1:]:
            if second-first < 16:
                continue
            for a in candidates[first]:
                for b in candidates[second]:
                    slope = (b['offset']-a['offset'])/(second-first)
                    if abs(slope) > 2:
                        continue
                    candidate = fit(a['offset']-slope*first, slope)
                    if candidate is not None:
                        proposals.append(candidate)
    proposals.sort(key=lambda p:(-p['directCount'], p['rmsPixels'], p['intercept'], p['slopePerStation']))
    distinct = []
    for candidate in proposals:
        def same(other):
            return max(abs(candidate['intercept']+candidate['slopePerStation']*i
                           -other['intercept']-other['slopePerStation']*i) for i in [8, 30, 52]) <= MAX_DISAGREEMENT
        if not any(same(other) for other in distinct):
            distinct.append(candidate)
    # A tilted line can be made by joining portions of two already supported
    # parallel rules. Retain that proposal for inspection but flag it instead
    # of presenting it as another coherent track.
    primary = []
    for candidate in distinct:
        counts = [0]*len(primary)
        for station, observation in candidate['observations'].items():
            matches = [(abs(observation['offset']-(other['intercept']+other['slopePerStation']*station)), index)
                       for index,other in enumerate(primary)]
            if matches:
                error,index = min(matches)
                if error <= 2:
                    counts[index] += 1
        substantial = [count for count in counts if count >= max(6, int(np.ceil(candidate['directCount']*.15)))]
        mixed = len(substantial)>=2 and sum(substantial)>=candidate['directCount']*.8
        candidate['possibleTrackHopping'] = mixed
        candidate['overlapWithPriorTracks'] = counts
        if not mixed:
            primary.append(candidate)
    return distinct


def curve_from_existing(record):
    """Offer a robust curved proposal without replacing existing observations."""
    rows = record['rows'];normal = np.asarray(record['normal'], dtype=float)
    ids = np.array([i for i,row in enumerate(rows) if row['stable']], dtype=int)
    if len(ids) < MIN_OBSERVATIONS:
        return None
    offsets = np.array([np.dot(np.asarray(rows[i]['point'])-np.asarray(rows[i]['base']),normal) for i in ids])
    x = ids-30
    design = np.column_stack([np.ones(len(ids)),x,x*x])
    try:
        initial = np.linalg.lstsq(design,offsets,rcond=None)[0]
        fitted = least_squares(lambda values:design@values-offsets,initial,loss='soft_l1',f_scale=2,max_nfev=120)
    except (ValueError, np.linalg.LinAlgError):
        return None
    if not fitted.success:
        return None
    errors = abs(design@fitted.x-offsets)
    retained = ids[errors <= MAX_DISAGREEMENT]
    bins = sorted(set(min(4,int(i)*5//61) for i in retained))
    if (len(retained)<MIN_OBSERVATIONS or len(bins)<4 or retained[0]>7 or retained[-1]<53
            or abs(fitted.x[1])>2 or abs(fitted.x[2])>.1):
        return None
    observations = {int(i):dict(offset=float(np.dot(np.asarray(rows[i]['point'])-np.asarray(rows[i]['base']),normal)),
                                point=rows[i]['point'],strength=None,origin='preserved_existing_point',trialRange=None)
                    for i in retained}
    return dict(intercept=float(fitted.x[0]-30*fitted.x[1]),slopePerStation=float(fitted.x[1]),
        curvaturePerStationSquared=float(fitted.x[2]),directCount=len(retained),occupiedBins=bins,
        rmsPixels=float(np.sqrt(np.mean(errors[errors<=MAX_DISAGREEMENT]**2))),
        observations=observations,possibleTrackHopping=False,overlapWithPriorTracks=[],
        proposalSource='robust_existing_curve')


def predicted(hypothesis, station):
    return (hypothesis['intercept']+hypothesis['slopePerStation']*station+
            hypothesis.get('curvaturePerStationSquared',0)*(station-30)**2)


def decorate(hypothesis, record):
    normal = np.asarray(record['normal'], dtype=float)
    observations = hypothesis.pop('observations')
    good = sorted(observations)
    output = []
    for i, row in enumerate(record['rows']):
        if i in observations:
            depth, origin = observations[i]['offset'], 'observed_candidate'
        elif good[0] < i < good[-1]:
            left = max(index for index in good if index < i)
            right = min(index for index in good if index > i)
            fraction = (i-left)/(right-left)
            depth = observations[left]['offset']+fraction*(observations[right]['offset']-observations[left]['offset'])
            origin = 'interpolated'
        else:
            depth = predicted(hypothesis,i)
            origin = 'extrapolated'
        point = observations[i].get('point') if i in observations else None
        if point is None:
            point = (np.asarray(row['base'])+depth*normal).tolist()
        output.append(dict(point=point, origin=origin,
                           evidence=observations.get(i)))
    hypothesis['maximumMissingStations'] = max((b-a-1 for a,b in zip(good,good[1:])), default=0)
    hypothesis['points'] = output
    return hypothesis


def run(image, candidate, frame, side, output):
    source = json.loads(candidate.read_text())
    digest = hashlib.sha256(image.read_bytes()).hexdigest()
    if source['inputSHA256'] != digest:
        raise ValueError('capture mismatch')
    pillow_heif.register_heif_opener()
    rgb = np.asarray(ImageOps.exif_transpose(Image.open(image)).convert('RGB'), dtype='float32')
    color = source.get('signal') == 'color_contrast'
    pixels = rgb if color else rgb.mean(axis=2)
    record = source['frames'][frame][side]
    candidates, domains = local_candidates(pixels, record, dense=source.get('denseStripSampling', False), color=color)
    raw = fit_hypotheses(candidates)
    curve = curve_from_existing(record)
    if curve is not None:
        differences = [max(abs(predicted(curve,i)-predicted(other,i)) for i in [8, 19, 30, 41, 52])
                       for other in raw]
        closest = int(np.argmin(differences)) if differences else None
        if closest is None or differences[closest] > .25:
            # Similar location does not make the curve and line equivalent.
            # Keep different shapes as models of one identity, rather than
            # inventing another independent boundary.
            curve['shapeAlternativeOf'] = closest if closest is not None and differences[closest] <= MAX_DISAGREEMENT else None
            raw.append(curve)
    hypotheses = [decorate(item, record) for item in raw[:12]]
    primary_count = sum(not hypothesis['possibleTrackHopping'] and hypothesis.get('shapeAlternativeOf') is None
                        for hypothesis in raw)
    status = 'insufficient_support' if not primary_count else ('multiple_plausible_tracks' if primary_count>1 else 'single_track_identity_unverified')
    result = dict(inputSHA256=digest, candidateSHA256=hashlib.sha256(candidate.read_bytes()).hexdigest(),
        frame=frame, side=side, status=status, reviewRequired=True,
        distinctHypotheses=primary_count, totalProposals=len(raw), candidateCounts=[len(row) for row in candidates], searchDomains=domains,
        existingPath=[dict(point=row['point'] if row['stable'] else None,
                           origin='existing_observed' if row['stable'] else 'unsupported') for row in record['rows']],
        hypotheses=hypotheses, limitation='Offline line proposals only. Same-image multiscale trials are correlated; no candidate is certified as a printed edge or physical cut. Existing app output is untouched.')
    output.write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(dict(frame=frame,side=side,status=status,distinctHypotheses=primary_count,totalProposals=len(raw),
        summaries=[{k:v for k,v in h.items() if k!='points'} for h in hypotheses[:6]]),indent=2),flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['image', 'candidate', 'frame', 'side', 'output']:
        parser.add_argument(name, type=Path if name in ['image', 'candidate', 'output'] else str)
    args = parser.parse_args()
    run(args.image, args.candidate, args.frame, args.side, args.output)
