#!/usr/bin/env python3
"""Show that matching two border strips can accept a false physical cut.

The synthetic printed-field edge and the actual cut are known. A stronger
interior rule lies more than 60 pixels outside the printed edge, with matching
border material on either side. The experimental material gate accepts it.
"""
import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

from physical_border_identity_probe import run as check_identity
from track_card_paths import boundary


def run(output):
    output.mkdir(parents=True, exist_ok=False)
    image = Image.new('RGB', (600, 800), (255, 255, 255))
    draw = ImageDraw.Draw(image)
    draw.rectangle((80, 80, 519, 769), fill=(170, 170, 170))
    draw.rectangle((105, 105, 494, 744), fill=(20, 20, 20))
    draw.rectangle((111, 111, 488, 738), fill=(170, 170, 170))
    draw.rectangle((180, 180, 419, 669), fill=(40, 80, 130))
    source = output/'source.png'; image.save(source)
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    seed = [[90, 90], [510, 90], [510, 760], [90, 760]]
    physical = boundary(np.asarray(image, dtype='float32').mean(axis=2), seed, 'left',
                        adaptive_sharp=True, physical_background=True)
    printed = dict(side='left', rows=[dict(point=[179.5, 180+(.1+.8*i/60)*490], stable=True)
                                     for i in range(61)])
    physical_file, printed_file, paired_file = (output/name for name in ['physical.json', 'printed.json', 'paired.json'])
    physical_file.write_text(json.dumps(dict(inputSHA256=digest, frames=dict(outer=dict(left=physical)))))
    printed_file.write_text(json.dumps(dict(inputSHA256=digest, frames=dict(inner=dict(left=printed)))))
    mapping = cv2.getPerspectiveTransform(np.float32(seed), np.float32([[0, 0], [1, 0], [1, 1], [0, 1]]))
    paired_file.write_text(json.dumps(dict(inputSHA256=digest, rectificationMatrix=mapping.tolist(),
        measurement=dict(samplingSpans=dict(x=[.3, .7], y=[.3, .7])))))
    result = output/'identity-result.json'
    check_identity(source, printed_file, physical_file, paired_file, result)
    gate = json.loads(result.read_text())['summary']['left']
    observed = float(np.median([r['point'][0] for r in physical['rows'] if r['stable']]))
    summary = dict(expectedCut=79.5, observed=observed, errorPixels=abs(observed-79.5),
                   trackerDirectCount=physical['stableCount'], gate=gate,
                   conclusion='A supported interior rule passes the material gate; do not use it for automatic cut identity.')
    (output/'summary.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(json.dumps(summary), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    run(args.output)
