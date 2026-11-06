#!/usr/bin/env python3
"""Prepare a debug artwork reference from a publisher image and its reviewed art rectangle.

Usage: build_print_reference.py publisher.webp reference-only.json output.json
The four displayedCut corners describe the full publisher raster. Coordinates
refer to publisher pixel centers. No photographed card or expected ratio enters.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image


def prepare(image_path, specification):
    raw = image_path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != specification["sha256"]:
        raise ValueError("Publisher image differs from the reviewed specification")
    with Image.open(image_path) as image:
        width, height = image.size
        cut = [[-.5, -.5], [width-.5, -.5], [width-.5, height-.5], [-.5, height-.5]]
        if not np.allclose(specification["displayedCut"], cut):
            raise ValueError("Reference preparation requires a full, upright publisher card")
        template = np.asarray(image.convert("L").resize((320, 448), Image.Resampling.BILINEAR))
    frame = np.asarray(specification["art"], dtype=float)
    if frame.shape != (4, 2):
        raise ValueError("Expected four artwork corners")
    left, top = (frame[0] + .5) / (width, height)
    right, bottom = (frame[2] + .5) / (width, height)
    if not (0 < left < right < 1 and 0 < top < bottom < 1
            and np.allclose(frame[1], (frame[2, 0], frame[0, 1]))
            and np.allclose(frame[3], (frame[0, 0], frame[2, 1]))):
        raise ValueError("Expected an upright artwork rectangle inside the published cut")
    patches = []

    def sample(u, v, interior):
        x, y = round(u * 320 - .5), round(v * 448 - .5)
        patch = template[y-8:y+9, x-8:x+9]
        if patch.shape == (17, 17) and patch.std() >= 10:
            patches.append(dict(x=x, y=y, interior=interior,
                                pixels=base64.b64encode(patch.tobytes()).decode("ascii")))

    for y in np.linspace(.14, .86, 5):
        for x in np.linspace(.14, .86, 5):
            sample(left + (right-left)*x, top + (bottom-top)*y, True)
    # Corroborate the surrounding title/footer design separately from the art.
    for x in (.14, .22, .3):
        for y in (.08, .947):
            sample(x, y, False)
    return dict(label=specification["printing"], sourceSHA256=specification["sha256"],
                left=left, top=top, right=right, bottom=bottom, patches=patches)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("image", "specification", "output"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    result = prepare(args.image, json.loads(args.specification.read_text()))
    with args.output.open("x") as output:
        json.dump(result, output, indent=2)
        output.write("\n")
