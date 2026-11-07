#!/usr/bin/env python3
"""Conservative offline identity gate for a proposed physical-cut path.

Compare a photo-observed printed-border strip to the material just inside a
proposed cut. Never add support, invent points, or extrapolate a printed path.
This hypothesis is unsafe as an identity gate: a known synthetic interior rule
passes it roughly 25 pixels inside the true cut. It must not gate app output.
"""
import argparse
import collections
import copy
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
import pillow_heif

from selective_path_measurement import supported_path
from track_card_paths import samples
from uniform_border_probe import physical_depth


def run(image, printed, physical, paired, output):
    inner, outer, measurement = (json.loads(path.read_text()) for path in [printed, physical, paired])
    digest = hashlib.sha256(image.read_bytes()).hexdigest()
    if any(item['inputSHA256'] != digest for item in [inner, outer, measurement]):
        raise ValueError('capture mismatch')
    pillow_heif.register_heif_opener()
    rgb = np.asarray(ImageOps.exif_transpose(Image.open(image)).convert('RGB'), dtype='float32').mean(axis=2)
    mapping = np.asarray(measurement['rectificationMatrix'])
    spans = measurement['measurement']['samplingSpans']
    output_frames, summary = {}, {}
    for side, original in outer['frames']['outer'].items():
        record = copy.deepcopy(original)
        normal = np.asarray(record['normal']); tangent = np.array([-normal[1], normal[0]])
        reasons = collections.Counter()
        for row in record['rows']:
            if not row['stable']:
                continue
            try:
                base = np.asarray(row['base'])
                printed_depth = -physical_depth(base, -normal, inner['frames']['inner'][side])
                cut_depth = float(np.dot(np.asarray(row['point']) - base, normal))
                if cut_depth - printed_depth < 60:
                    raise ValueError('no independent border span')
                for width in [4, 8, 16]:
                    border = samples(rgb, base[None], normal, tangent,
                                     printed_depth + np.arange(24, 49), width)[0]
                    near_cut = samples(rgb, base[None], normal, tangent,
                                       cut_depth - np.arange(16, 7, -1), width)[0]
                    level = float(np.median(border))
                    noise = float(1.4826*np.median(abs(border-level)))
                    tolerance = max(5., min(15., 3*noise))
                    if abs(level-float(np.median(near_cut))) > tolerance:
                        raise ValueError('border material differs')
            except ValueError as error:
                row['stable'] = False
                reasons[str(error)] += 1
        record['stableCount'] = sum(row['stable'] for row in record['rows'])
        try:
            _, support = supported_path(record, mapping, spans['y' if side in ['left', 'right'] else 'x'])
            summary[side] = dict(accepted=True, support=support, rejected=dict(reasons))
        except ValueError as error:
            summary[side] = dict(accepted=False, directCount=record['stableCount'],
                                 reason=str(error), rejected=dict(reasons))
        output_frames[side] = record
        print(side, summary[side], flush=True)
    output.write_text(json.dumps(dict(inputSHA256=digest,
        inputHashes={str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in [printed, physical, paired]},
        parameters=dict(printedBorderOffsets=[24, 48], innerCutOffsets=[8, 16],
                        minimumBorderSpan=60, stripHalfWidths=[4, 8, 16],
                        tolerance='max(5, min(15, 3 * robust median absolute deviation))'),
        summary=summary, frames=dict(outer=output_frames),
        limitation='Same-capture photo identity hypothesis; not independently calibrated and no automatic integration.'), indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['image', 'printed', 'physical', 'paired', 'output']:
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    run(args.image, args.printed, args.physical, args.paired, args.output)
