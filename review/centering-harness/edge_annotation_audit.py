#!/usr/bin/env python3
"""Audit annotation angles against observed native pixels, without app output.

This creates review candidates, never replacement ground truth. A supplied seed
defines the boundary to inspect and the search window; it does not fix its angle.
Review boundary identity on the original image before adopting any candidate.
Two fits of the same capture are not independent annotators or calibrated truth.
Requires Pillow, numpy, scipy and OpenCV; HEIC input also requires pillow-heif.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from scipy.ndimage import gaussian_filter1d

from gt_tool import edge_normal, edge_points, fit_line, intersect


def audit_edge(image, seed, side, *, radius=48, polarity="falling", sample_count=61):
    """Fit real local transition points, retaining rejected observations too."""
    if polarity not in {"falling", "rising", "either"}:
        raise ValueError("unknown transition polarity")
    if radius < 8 or sample_count < 20:
        raise ValueError("insufficient sampling window")
    first, second = (np.asarray(p, dtype=float) for p in edge_points(seed, side))
    vector = second - first
    length = np.linalg.norm(vector)
    if length < 20:
        raise ValueError("edge is too short")
    tangent = vector / length
    normal = np.asarray(edge_normal(seed, side))
    progress = np.linspace(.15, .85, sample_count)
    offsets = np.arange(-radius, radius + .25, .5)
    positions = first + progress[:, None, None] * vector + offsets[None, :, None] * normal
    # Average a short strip along each edge position, not the whole edge. This
    # preserves angle evidence which an edge-wide mean profile discards.
    profiles = []
    for shift in (-4, -2, 0, 2, 4):
        positions_shifted = positions + shift * tangent
        profiles.append(cv2.remap(
            np.asarray(image, dtype=np.float32),
            positions_shifted[:, :, 0].astype(np.float32),
            positions_shifted[:, :, 1].astype(np.float32),
            cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT,
            borderValue=(float("nan"),) * 3,
        ))
    rgb = np.mean(profiles, axis=0)
    # Arithmetic RGB mean, explicitly not perceptual luminance.
    brightness = gaussian_filter1d(rgb.mean(axis=2), 2, axis=1)
    gradient = (np.roll(brightness, -2, axis=1) - np.roll(brightness, 2, axis=1)) / 2
    if polarity == "falling":
        gradient = -gradient
    elif polarity == "either":
        gradient = np.abs(gradient)
    gradient[:, :8] = -np.inf
    gradient[:, -8:] = -np.inf
    gradient = np.nan_to_num(gradient, nan=-np.inf)
    indices = gradient.argmax(axis=1)
    strengths = gradient[np.arange(sample_count), indices]
    measured_offsets = offsets[indices].copy()
    for row, index in enumerate(indices):
        if 0 < index < len(offsets) - 1:
            previous, current, following = gradient[row, index-1:index+2]
            curvature = previous - 2 * current + following
            if np.isfinite(curvature) and curvature < -1e-9:
                correction = np.clip(.5 * (previous - following) / curvature, -.5, .5)
                measured_offsets[row] += .5 * correction
    points = first + progress[:, None] * vector + measured_offsets[:, None] * normal
    supported = np.isfinite(strengths) & (strengths >= 2.5)
    if supported.sum() < max(12, .4 * sample_count):
        raise ValueError(f"{side}: insufficient visible transition support")
    # Robust initialization separates sleeve highlights, foil and text outliers
    # from an extended straight boundary. The final fit uses observed points.
    initial = cv2.fitLine(points[supported].astype(np.float32), cv2.DIST_HUBER, 0, .01, .01).ravel()
    initial_normal = np.array([-initial[1], initial[0]])
    residuals = points @ initial_normal - initial_normal @ initial[2:]
    retained = supported & (np.abs(residuals) <= 4)
    occupied = len(set(np.minimum(4, (np.arange(sample_count)[retained] * 5 // sample_count)).tolist()))
    if retained.sum() < max(12, .4 * sample_count) or occupied < 4:
        raise ValueError(f"{side}: insufficient straight-edge coverage")
    line = np.asarray(fit_line(points[retained].tolist()))
    residuals = points @ line[:2] - line[2]
    if abs(line[:2] @ normal) < .9:
        raise ValueError(f"{side}: fitted line leaves the supplied boundary window")
    endpoint_shifts = [float(-(line[:2] @ p - line[2]) / (line[:2] @ normal)) for p in (first, second)]
    projected_ends = [(p + offset * normal).tolist() for p, offset in zip((first, second), endpoint_shifts)]
    return {
        "side": side, "status": "candidate_requires_boundary_review",
        "polarity": polarity, "searchRadiusNativePixels": radius,
        "signal": "arithmetic_rgb_mean_signed_gradient",
        "span": [.15, .85], "line": line.tolist(), "endpoints": projected_ends,
        "endpointShiftFromSeedNativePixels": endpoint_shifts,
        "retainedCount": int(retained.sum()), "sampleCount": sample_count,
        "occupiedBins": occupied,
        "fitRMSNativePixels": float(np.sqrt(np.mean(residuals[retained] ** 2))),
        "observations": [
            {"point": p.tolist(), "strength": float(s), "retained": bool(keep), "residual": float(r)}
            for p, s, keep, r in zip(points, strengths, retained, residuals)
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("annotation", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--geometry", choices=["cardOuterQuad", "innerQuad"], default="cardOuterQuad")
    parser.add_argument("--polarity", choices=["falling", "rising", "either"], default="falling")
    parser.add_argument("--radius", type=int, default=48)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("output already exists; use a new directory to preserve prior evidence")
    from PIL import Image, ImageDraw, ImageOps
    if args.image.suffix.lower() in {".heic", ".heif"}:
        import pillow_heif
        pillow_heif.register_heif_opener()
    record = json.loads(args.annotation.read_text())
    seed = record[args.geometry]
    if seed is None:
        parser.error("annotation has no selected geometry")
    raw = ImageOps.exif_transpose(Image.open(args.image)).convert("RGB")
    expected_size = record["orientedPixelSize"]
    if raw.size != (expected_size["w"], expected_size["h"]):
        parser.error("oriented source dimensions do not match annotation")
    pixels = np.asarray(raw)
    edges, failures = {}, {}
    for side in ("left", "top", "right", "bottom"):
        try:
            edges[side] = audit_edge(pixels, seed, side, radius=args.radius, polarity=args.polarity)
        except ValueError as error:
            failures[side] = str(error)
    candidate_quad = None
    if len(edges) == 4:
        lines = {s: e["line"] for s, e in edges.items()}
        candidate_quad = [intersect(lines[a], lines[b]) for a, b in
                          [("top", "left"), ("top", "right"), ("bottom", "right"), ("bottom", "left")]]
    digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
    result = {
        "schema": 1, "status": "review_only_not_ground_truth", "image": args.image.name,
        "inputSHA256": digest(args.image), "annotationSHA256": digest(args.annotation),
        "toolSHA256": digest(Path(__file__)), "orientedSize": list(raw.size),
        "geometry": args.geometry, "seedQuad": seed, "candidateQuad": candidate_quad,
        "edges": edges, "failures": failures,
        "limitations": "Boundary identity still needs visual adjudication. Fit residual is not an accuracy interval.",
    }
    args.output.mkdir(parents=True)
    (args.output / "audit.json").write_text(json.dumps(result, indent=2, allow_nan=False) + "\n")
    overlay = raw.copy()
    draw = ImageDraw.Draw(overlay)
    for side in ("left", "top", "right", "bottom"):
        draw.line([tuple(p) for p in edge_points(seed, side)], fill="yellow", width=4)
        if side in edges:
            draw.line([tuple(p) for p in edges[side]["endpoints"]], fill="cyan", width=4)
            for observation in edges[side]["observations"]:
                x, y = observation["point"]
                draw.ellipse((x-3, y-3, x+3, y+3), fill="lime" if observation["retained"] else "red")
    overlay.thumbnail((1200, 1600))
    overlay.save(args.output / "seed-yellow-observed-cyan.png")
    print(json.dumps({"image": args.image.name, "fittedSides": list(edges), "failures": failures}))


if __name__ == "__main__":
    main()
