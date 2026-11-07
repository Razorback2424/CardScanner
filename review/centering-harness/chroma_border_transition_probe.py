#!/usr/bin/env python3
"""Research-only selective outer-rim localization against an observed border.

Preserve supported points. At missing points, find a unique six-trial consensus
of outward-brightening peaks whose nearby exterior chroma agrees with a strip
anchored to the independently observed physical cut. This is a restricted
boundary-identity hypothesis, not a general foil detector or calibrated truth.
"""
import argparse
import hashlib
import itertools
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
import pillow_heif
from scipy.ndimage import gaussian_filter1d
from scipy.signal import find_peaks

from track_card_paths import samples
from uniform_border_probe import physical_depth

HALF_WIDTHS = (4, 8, 16)
SIGMAS = (1, 2)
OFFSETS = np.arange(-28, 29, dtype=float)


def chroma(rgb):
    return rgb - np.mean(rgb, axis=-1, keepdims=True)


def candidate_consensus(profiles, exterior):
    """Find one common photo transition; do not turn ambiguous peaks into truth."""
    trials = []
    for width, profile, border in zip(HALF_WIDTHS, profiles, exterior):
        border_chroma = chroma(border)
        level = border_chroma.mean(axis=0)
        noise = float(np.sqrt(np.mean((border_chroma - level) ** 2)))
        tolerance = max(1., 3 * noise)  # Same quantization floor as the border probe.
        for sigma in SIGMAS:
            gradient = gaussian_filter1d(profile.mean(axis=1), sigma, order=1)
            eligible = []
            for index in find_peaks(gradient)[0]:
                offset = float(OFFSETS[index])
                # Look beyond the placement window so an equally supported
                # neighboring transition cannot be hidden by the search edge.
                if abs(offset) > 12 or gradient[index] < 2.5:
                    continue
                if index < 12 or index + 14 >= len(profile):
                    continue
                nearby = profile[index + 6:index + 15]
                error = float(np.sqrt(np.mean((chroma(nearby) - level) ** 2)))
                jump = float(nearby.mean() - profile[index - 12:index - 4].mean())
                if error > tolerance or jump < 5:
                    continue
                curvature = float(gradient[index - 1] - 2 * gradient[index] + gradient[index + 1])
                correction = (float(np.clip(.5 * (gradient[index - 1] - gradient[index + 1]) / curvature, -.5, .5))
                              if curvature < -1e-9 else 0.)
                eligible.append(dict(center=offset + correction, peak=float(gradient[index]),
                                     exteriorChromaRMS=error, exteriorTolerance=tolerance,
                                     outwardBrightnessJump=jump))
            trials.append(dict(halfWidth=width, sigma=sigma, candidates=eligible))

    if any(not trial['candidates'] for trial in trials):
        return dict(stable=False, reason='missing supported trial', trials=trials)

    # Exhaustive combinations are small after the local exterior gate. A
    # separate cluster is ambiguous rather than an invitation to pick a winner.
    clusters = []
    for choice in itertools.product(*(t['candidates'] for t in trials)):
        centers = [candidate['center'] for candidate in choice]
        if max(centers) - min(centers) <= 4:
            clusters.append((float(np.median(centers)), float(max(centers) - min(centers)), choice))
    if not clusters:
        return dict(stable=False, reason='no four-pixel consensus', trials=trials)
    centers = [c[0] for c in clusters]
    if max(centers) - min(centers) > 4:
        return dict(stable=False, reason='multiple supported transitions', trials=trials)
    # Prefer the tightest independently observed consensus, then use the median.
    center, spread, choice = min(clusters, key=lambda c: c[1])
    if abs(center) >= 6:
        return dict(stable=False, reason='transition outside placement window', trials=trials)
    return dict(stable=True, center=center, agreementRange=spread,
                selected=list(choice), trials=trials)


def controls():
    x = OFFSETS
    def smooth(value):
        return gaussian_filter1d(value.astype(float), .6, axis=0)
    def evaluate(profile):
        profile = smooth(np.asarray(profile, dtype=float))
        border = np.repeat([[180., 180., 180.]], 25, axis=0)
        return candidate_consensus([profile] * 3, [border] * 3)

    single = np.where(x[:, None] < 2, [30., 70., 110.], [180., 180., 180.])
    flat = np.repeat([[180., 180., 180.]], len(x), axis=0)
    two_steps = (30 + 65 * (x >= -4) + 85 * (x >= 4))[:, None] * np.ones((1, 3))
    reverse = np.where(x[:, None] < 2, [180., 180., 180.], [30., 70., 110.])
    # When a bright neighboring rule hides the transition's local contrast,
    # rejecting is safer than assuming the stronger or outermost peak is right.
    strong_neighbor = np.repeat([[30., 70., 110.]], len(x), axis=0)
    strong_neighbor[x >= -5] = [140., 175., 220.]
    strong_neighbor[x >= 0] = [20., 20., 50.]
    strong_neighbor[x >= 3] = [100., 100., 100.]
    wrong_border = np.where(x[:, None] < 2, [30., 70., 110.], [120., 150., 200.])
    cases = dict(single=evaluate(single), flat=evaluate(flat),
                 two_gray_steps=evaluate(two_steps), reverse=evaluate(reverse),
                 strong_neighbor=evaluate(strong_neighbor), wrong_border=evaluate(wrong_border))
    assert cases['single']['stable'] and abs(cases['single']['center'] - 1.5) <= 1
    assert not cases['flat']['stable']
    assert not cases['two_gray_steps']['stable']
    assert not cases['reverse']['stable']
    assert not cases['strong_neighbor']['stable']
    assert not cases['wrong_border']['stable']
    return {name: dict(stable=result['stable'], center=result.get('center'),
                       reason=result.get('reason')) for name, result in cases.items()}


def run(image, candidate, physical, output, seed_shift):
    checks = controls()
    source = json.loads(candidate.read_text())
    cut = json.loads(physical.read_text())
    digest = hashlib.sha256(image.read_bytes()).hexdigest()
    if source['inputSHA256'] != digest or cut['inputSHA256'] != digest:
        raise ValueError('capture mismatch')
    pillow_heif.register_heif_opener()
    rgb = np.asarray(ImageOps.exif_transpose(Image.open(image)).convert('RGB'), dtype='float32')
    record = source['frames']['inner']['right']
    physical_record = cut['frames']['outer']['right']
    normal = np.asarray(record['normal'])
    tangent = np.array([-normal[1], normal[0]])
    rows = []
    for i, original in enumerate(record['rows']):
        if original['stable']:
            rows.append(original)
            continue
        base = np.asarray(original['base'])
        seed = float(record['selected']['offsets'][i] + seed_shift)
        try:
            depth = physical_depth(base, normal, physical_record)
            if seed + 20 >= depth - 48:
                raise ValueError('no independent border strip')
            profiles = [samples(rgb, base[None], normal, tangent, seed + OFFSETS, width, dense=True)[0]
                        for width in HALF_WIDTHS]
            exterior = [samples(rgb, base[None], normal, tangent,
                                depth - np.arange(48, 23, -1), width, dense=True)[0]
                        for width in HALF_WIDTHS]
            result = candidate_consensus(profiles, exterior)
        except ValueError as error:
            result = dict(stable=False, reason=str(error))
        row = dict(original)
        row['selectiveChromaProbe'] = result
        if result['stable']:
            offset = seed + result['center']
            row.update(point=(base + offset * normal).tolist(), offset=offset, stable=True,
                       estimator='physical_border_chroma_outer_rim')
        rows.append(row)
    combined = dict(record, rows=rows, stableCount=sum(row['stable'] for row in rows))
    recovered = [i for i, (old, new) in enumerate(zip(record['rows'], rows))
                 if not old['stable'] and new['stable']]
    output.write_text(json.dumps(dict(fixture=source['fixture'], inputSHA256=digest,
        candidateSHA256=hashlib.sha256(candidate.read_bytes()).hexdigest(),
        physicalSHA256=hashlib.sha256(physical.read_bytes()).hexdigest(),
        seedShift=seed_shift, controls=checks, recoveredIndices=recovered,
        frames=dict(inner=dict(right=combined)),
        limitation='Single-photo research hypothesis; retained points and exterior strips are correlated, not calibrated physical truth.'), indent=2) + '\n')
    print('recovered', recovered, 'combined support', combined['stableCount'], flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['image', 'candidate', 'physical', 'output']:
        parser.add_argument(name, type=Path)
    parser.add_argument('--seed-shift', type=float, default=0)
    args = parser.parse_args()
    run(args.image, args.candidate, args.physical, args.output, args.seed_shift)
