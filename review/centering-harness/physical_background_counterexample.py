#!/usr/bin/env python3
"""Expose a false physical-cut identity from a stronger interior rule.

This is a known-geometry research control for the existing offline background
tracker. A high supported-point count alone must not be treated as physical-cut
truth. The image and coordinates are synthetic; no app geometry is modified.
"""
import argparse
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from track_card_paths import boundary


def run(output):
    image = Image.new('RGB', (600, 800), (255, 255, 255))
    draw = ImageDraw.Draw(image)
    draw.rectangle((80, 80, 519, 769), fill=(170, 170, 170))
    draw.rectangle((105, 105, 494, 744), fill=(20, 20, 20))
    draw.rectangle((111, 111, 488, 738), fill=(170, 170, 170))
    pixels = np.asarray(image, dtype='float32').mean(axis=2)
    seed = [[90, 90], [510, 90], [510, 760], [90, 760]]
    expected = {'left': 79.5, 'top': 79.5, 'right': 519.5, 'bottom': 769.5}
    results = {}
    for side in ['left', 'top', 'right', 'bottom']:
        candidate = boundary(pixels, seed, side, adaptive_sharp=True, physical_background=True)
        axis = 0 if side in ['left', 'right'] else 1
        supported = [row['point'][axis] for row in candidate['rows'] if row['stable']]
        observed = float(np.median(supported)) if supported else None
        results[side] = dict(directCount=len(supported), expectedCut=expected[side],
            observed=observed, errorPixels=abs(observed-expected[side]) if observed is not None else None)
        print(side, results[side], flush=True)
    output.write_text(json.dumps(dict(image='synthetic 600x800, white exterior and stronger dark interior rule',
        seed=seed, results=results,
        conclusion='The current offline tracker follows the stronger interior rule. Do not promote it as physical-cut identity.',
        limitation='Synthetic counterexample; actual capture texture and shadows vary.'), indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    run(args.output)
