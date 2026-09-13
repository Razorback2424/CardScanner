#!/usr/bin/env python3
"""Compare E0 profile selections after undoing each rendered variant.

The XCTest writes one JSON record per fixture/variant plus manifest.json. This
script maps each variant's native (rendered-PNG) edge back into the common
normalized source image, assigns it to the nearest base edge, and emits a
compact Markdown table alongside the raw dumps. The working quad is excluded
from this inversion because it has already passed through the analyzer's
downscale.
"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path


SIDES = ("left", "top", "right", "bottom")


def point(value: dict[str, float]) -> tuple[float, float]:
    return float(value["x"]), float(value["y"])


def edge_points(quad: dict, side: str) -> tuple[tuple[float, float], tuple[float, float]]:
    if side == "left":
        return point(quad["topLeft"]), point(quad["bottomLeft"])
    if side == "top":
        return point(quad["topLeft"]), point(quad["topRight"])
    if side == "right":
        return point(quad["topRight"]), point(quad["bottomRight"])
    return point(quad["bottomLeft"]), point(quad["bottomRight"])


def inverse_variant_point(value: dict, renderer: dict) -> tuple[float, float]:
    """Undo the renderer's C + R(theta) M scale transform."""

    x, y = point(value)
    cx = float(renderer["canvasWidth"]) / 2.0
    cy = float(renderer["canvasHeight"]) / 2.0
    dx = x - cx
    dy = y - cy
    theta = math.radians(float(renderer["rotationDegrees"]))
    cosine = math.cos(theta)
    sine = math.sin(theta)
    # Inverse rotation for the same image-coordinate convention used by the
    # Core Graphics renderer: R^-1 = [[cos, sin], [-sin, cos]].
    unrotated_x = cosine * dx + sine * dy
    unrotated_y = -sine * dx + cosine * dy
    if bool(renderer["mirrorX"]):
        unrotated_x = -unrotated_x
    scale = float(renderer["scale"])
    return (
        unrotated_x / scale + float(renderer["sourceWidth"]) / 2.0,
        unrotated_y / scale + float(renderer["sourceHeight"]) / 2.0,
    )


def inverse_variant_edge(quad: dict, side: str, renderer: dict):
    return inverse_variant_segment(edge_points(quad, side), renderer)


def inverse_variant_segment(edge, renderer: dict):
    return tuple(
        inverse_variant_point({"x": p[0], "y": p[1]}, renderer) for p in edge
    )


def line_distance(value: tuple[float, float], line) -> float:
    (x, y) = value
    (x0, y0), (x1, y1) = line
    dx = x1 - x0
    dy = y1 - y0
    denominator = math.hypot(dx, dy)
    if denominator == 0:
        return math.inf
    return abs(dy * x - dx * y + x1 * y0 - y1 * x0) / denominator


def mean_line_distance(edge, line) -> float:
    return sum(line_distance(p, line) for p in edge) / len(edge)


def signed_line_distance(value: tuple[float, float], line) -> float:
    (x, y) = value
    (x0, y0), (x1, y1) = line
    dx = x1 - x0
    dy = y1 - y0
    denominator = math.hypot(dx, dy)
    if denominator == 0:
        return math.inf
    return (dy * x - dx * y + x1 * y0 - y1 * x0) / denominator


def mean_signed_line_distance(edge, line) -> float:
    return sum(signed_line_distance(p, line) for p in edge) / len(edge)


def selected_inner_edge(quad: dict, side: str, normalized_depth: float):
    endpoints = edge_points(quad, side)
    center = (
        sum(point(quad[name])[0] for name in ("topLeft", "topRight", "bottomRight", "bottomLeft")) / 4.0,
        sum(point(quad[name])[1] for name in ("topLeft", "topRight", "bottomRight", "bottomLeft")) / 4.0,
    )
    tangent_x = endpoints[1][0] - endpoints[0][0]
    tangent_y = endpoints[1][1] - endpoints[0][1]
    length = math.hypot(tangent_x, tangent_y)
    normal = (-tangent_y / length, tangent_x / length)
    midpoint = (
        (endpoints[0][0] + endpoints[1][0]) / 2.0,
        (endpoints[0][1] + endpoints[1][1]) / 2.0,
    )
    if (center[0] - midpoint[0]) * normal[0] + (center[1] - midpoint[1]) * normal[1] < 0:
        normal = (-normal[0], -normal[1])
    if side in ("left", "right"):
        top = edge_points(quad, "top")
        bottom = edge_points(quad, "bottom")
        axis_length = (math.hypot(top[1][0] - top[0][0], top[1][1] - top[0][1])
                       + math.hypot(bottom[1][0] - bottom[0][0], bottom[1][1] - bottom[0][1])) / 2.0
    else:
        left = edge_points(quad, "left")
        right = edge_points(quad, "right")
        axis_length = (math.hypot(left[1][0] - left[0][0], left[1][1] - left[0][1])
                       + math.hypot(right[1][0] - right[0][0], right[1][1] - right[0][1])) / 2.0
    offset = normalized_depth * axis_length
    return tuple((x + normal[0] * offset, y + normal[1] * offset) for x, y in endpoints)


def load_records(directory: Path):
    manifest = directory / "manifest.json"
    with manifest.open(encoding="utf-8") as handle:
        return json.load(handle)


def main() -> int:
    directory = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(
        "review/centering-evidence/diagnostics/E0"
    )
    records = load_records(directory)
    base_by_fixture = {
        record["fixture"]: record for record in records if record["variant"] == "base"
    }
    rows = []
    for record in records:
        base = base_by_fixture[record["fixture"]]
        base_lines = {
            side: inverse_variant_edge(
                base["outerQuadNative"], side, base["renderer"]
            )
            for side in SIDES
        }
        base_inner_lines = {}
        for side in SIDES:
            base_profile = next(
                profile for profile in base["profiles"] if profile["side"] == side
            )
            base_inner_lines[side] = inverse_variant_segment(
                selected_inner_edge(
                    base["outerQuadNative"],
                    side,
                    base_profile["selectedNormalizedDepthAfterRefinement"],
                ),
                base["renderer"],
            )
        for profile in record["profiles"]:
            # `nativeQuad` is native to the rendered PNG passed into the
            # analyzer (including the E0 margin); `workingQuad` has already
            # been downscaled by the analyzer. Renderer inversion therefore
            # must start from the native quad here.
            observed_edge = inverse_variant_edge(
                record["outerQuadNative"], profile["side"], record["renderer"]
            )
            observed_inner_edge = inverse_variant_segment(
                selected_inner_edge(
                    record["outerQuadNative"],
                    profile["side"],
                    profile["selectedNormalizedDepthAfterRefinement"],
                ),
                record["renderer"],
            )
            distances = {
                side: mean_line_distance(observed_edge, base_lines[side])
                for side in SIDES
            }
            base_side = min(distances, key=distances.get)
            base_profile = next(
                item for item in base["profiles"] if item["side"] == base_side
            )
            rows.append(
                {
                    "fixture": record["fixture"],
                    "variant": record["variant"],
                    "observedSide": profile["side"],
                    "baseSide": base_side,
                    "lineDistancePx": distances[base_side],
                    "outerSignedOffsetPx": mean_signed_line_distance(observed_edge, base_lines[base_side]),
                    "innerSignedOffsetPx": mean_signed_line_distance(observed_inner_edge, base_inner_lines[base_side]),
                    "selectedBefore": profile["selectedNormalizedDepthBeforeRefinement"],
                    "selectedAfter": profile["selectedNormalizedDepthAfterRefinement"],
                    "deltaFromBase": (
                        profile["selectedNormalizedDepthAfterRefinement"]
                        - base_profile["selectedNormalizedDepthAfterRefinement"]
                    ),
                    "candidateCount": len(profile["shallowCandidates"]),
                    "radiusPx": profile["sampleRadiusPixels"],
                    "baseline": profile["baseline"],
                    "mad": profile["mad"],
                    "threshold": profile["threshold"],
                }
            )

    rows.sort(key=lambda row: (row["fixture"], row["variant"], SIDES.index(row["baseSide"])))
    comparison_json = directory / "comparison.json"
    comparison_json.write_text(json.dumps(rows, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    lines = [
        "# E0 profile comparison",
        "",
        "Each variant edge is inverse-transformed to the normalized source-image coordinates and assigned to the nearest base outer edge. `lineDistancePx` is the mean distance of the transformed endpoints from that base edge line; it is a correspondence diagnostic, not a detector tolerance.",
        "",
        "| Fixture | Variant | Observed | Base edge | Line distance px | Outer signed px | Inner signed px | Selected normalized depth | Base delta | Candidates | Radius px | Baseline | MAD | Threshold |",
        "|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(
            "| {fixture} | {variant} | {observedSide} | {baseSide} | {lineDistancePx:.2f} | {outerSignedOffsetPx:+.2f} | {innerSignedOffsetPx:+.2f} | {selectedAfter:.6f} | {deltaFromBase:+.6f} | {candidateCount} | {radiusPx:.1f} | {baseline:.3f} | {mad:.3f} | {threshold:.3f} |".format(**row)
        )
    (directory / "comparison.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(directory / "comparison.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
