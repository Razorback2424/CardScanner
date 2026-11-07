#!/usr/bin/env python3
"""Offline boundary-identity probe using the surrounding provider stripe profile.

Registration supplies a search region, never accepted geometry. Six profile
trials must agree before a position is retained. No native measurement or
annotation writes; correlation is diagnostic evidence, not calibrated certainty.
"""
import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageOps
import pillow_heif
from scipy.signal import find_peaks
from scipy.ndimage import gaussian_filter1d
from gt_tool import edge_points
from register_print_reference import project
from track_card_paths import gradient_refinement


def sample(image, points):
    if (np.any(points < 0) or np.any(points[..., 0] >= image.shape[1]-1)
            or np.any(points[..., 1] >= image.shape[0]-1)):
        raise ValueError('profile exceeds observed image')
    return cv2.remap(image, points[..., 0].astype('float32'),
                     points[..., 1].astype('float32'), cv2.INTER_LINEAR)


def probe(reference, photo, homography, quad, side, unsigned_profile=False):
    a, b = np.array(edge_points(quad, side))
    native = project([a, b], homography)
    tangent = native[1]-native[0]
    tangent /= np.linalg.norm(tangent)
    normal = np.array([tangent[1], -tangent[0]])
    if normal@(project(quad, homography).mean(axis=0)-native.mean(axis=0)) > 0:
        normal = -normal
    inverse = np.linalg.inv(homography)
    rows = []
    for fraction in np.linspace(.1, .9, 61):
        base = project([a+fraction*(b-a)], homography)[0]
        trials = []
        profiles = []
        for width in [4, 8, 16]:
            shifts = np.linspace(-width, width, 9)
            offsets = np.arange(-76, 77)
            positions = (base+offsets[None, :, None]*normal
                         + shifts[:, None, None]*tangent)
            raw = sample(photo, positions).mean(axis=0)
            reference_positions = project(positions.reshape(-1, 2), inverse).reshape(positions.shape)
            expected = sample(reference, reference_positions).mean(axis=0)
            profiles.append((width, raw, expected))
            for radius in [24, 36]:
                template = expected[(offsets >= -radius) & (offsets <= radius)]
                if unsigned_profile:
                    template = np.abs(gaussian_filter1d(template,1,order=1))
                template = template-template.mean()
                denominator = np.linalg.norm(template)
                scores = []
                centers = np.arange(-40, 41)
                for center in centers:
                    segment = raw[(offsets >= center-radius) & (offsets <= center+radius)]
                    if unsigned_profile:
                        segment = np.abs(gaussian_filter1d(segment,1,order=1))
                    segment = segment-segment.mean()
                    norm = denominator*np.linalg.norm(segment)
                    scores.append(float(template@segment/norm) if norm > 1e-8 else -1.)
                scores = np.array(scores)
                peak = int(np.argmax(scores))
                alternatives = [i for i in find_peaks(scores)[0] if abs(i-peak) >= 8]
                competitor = max((scores[i] for i in alternatives), default=-1.)
                correction = 0.
                if 0 < peak < len(scores)-1:
                    curvature = scores[peak-1]-2*scores[peak]+scores[peak+1]
                    if curvature < -1e-9:
                        correction = float(np.clip(.5*(scores[peak-1]-scores[peak+1])/curvature, -.5, .5))
                trials.append(dict(stripHalfWidth=width, radius=radius,
                    center=float(centers[peak]+correction), correlation=float(scores[peak]),
                    competitor=float(competitor), boundaryHit=peak in [0, len(scores)-1]))
        centers = [t['center'] for t in trials]
        center = float(np.median(centers))
        profile_stable = (max(centers)-min(centers) <= 4 and all(
            t['correlation'] >= .8 and t['correlation']-t['competitor'] >= .05
            and not t['boundaryHit'] for t in trials))
        # The pattern identifies the rule; local photo gradients place it.
        # Do not use the reference-profile center as the measured boundary.
        refinements = []
        for width, raw, expected in profiles:
            polarity = 1 if expected[78] > expected[74] else -1
            for sigma in [1, 2]:
                refinements.append(dict(stripHalfWidth=width, sigma=sigma,
                    **gradient_refinement(raw[:,None] if unsigned_profile else raw*polarity, offsets, center, sigma)))
        fine_centers = [r['center'] for r in refinements]
        fine_center = float(np.median(fine_centers))
        stable = profile_stable and max(fine_centers)-min(fine_centers) <= 4 and all(
            r['peak'] >= 2.5 and not r['boundaryHit'] for r in refinements)
        rows.append(dict(base=base.tolist(), point=(base+fine_center*normal).tolist(),
                         offset=fine_center, stable=stable, trials=trials,
                         profileStable=profile_stable, profileCenter=center,
                         refinements=refinements,
                         sensitivityRange=[min(fine_centers), max(fine_centers)]))
    return dict(side=side, rows=rows, stableCount=sum(r['stable'] for r in rows), unsignedProfile=unsigned_profile)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['reference', 'specification', 'photo', 'registration', 'output']:
        parser.add_argument(name, type=Path)
    parser.add_argument('--side', choices=['left', 'top', 'right', 'bottom'])
    parser.add_argument('--unsigned-profile', action='store_true', help='Research-only gradient-magnitude identity and localization')
    args = parser.parse_args()
    pillow_heif.register_heif_opener()
    spec = json.loads(args.specification.read_text())
    registration = json.loads(args.registration.read_text())
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    if digest(args.reference) != spec['sha256'] or digest(args.reference) != registration['referenceSHA256']:
        raise ValueError('reference hash mismatch')
    if digest(args.photo) != registration['inputSHA256'] or not registration['accepted']:
        raise ValueError('capture mismatch or unsupported registration')
    reference = np.asarray(Image.open(args.reference).convert('RGB'), dtype='float32').mean(axis=2)
    photo = np.asarray(ImageOps.exif_transpose(Image.open(args.photo)).convert('RGB'), dtype='float32').mean(axis=2)
    sides = [args.side] if args.side else ['left', 'top', 'right', 'bottom']
    records = {side: probe(reference, photo, np.array(registration['homography']), spec['art'], side,args.unsigned_profile)
               for side in sides}
    args.output.write_text(json.dumps(dict(inputSHA256=digest(args.photo),
        referenceSHA256=digest(args.reference), frames=dict(inner=records),
        limitation='Experimental stripe identity; correlation and stability do not certify physical accuracy'), indent=2)+'\n')
    print({side: record['stableCount'] for side, record in records.items()})
