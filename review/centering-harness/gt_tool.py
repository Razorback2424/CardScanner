#!/usr/bin/env python3
"""Independent card-centering ground-truth helper.

This module deliberately has no dependency on the Swift application.  It can
validate the checked-in records, fit virtual corners from edge annotations,
and draw review overlays from ordinary PNG/JPEG exports of the HEIC files.
The production analyzer is never imported or invoked here.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Iterable, Sequence


Point = tuple[float, float]
Line = tuple[float, float, float]  # normalized ax + by = c
SIDES = ("left", "top", "right", "bottom")


def distance(a: Point, b: Point) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def fit_line(points: Sequence[Point]) -> Line:
    """Fit a total-least-squares line to points away from card corners."""
    if len(points) < 2:
        raise ValueError("each edge needs at least two annotation points")
    mean_x = sum(p[0] for p in points) / len(points)
    mean_y = sum(p[1] for p in points) / len(points)
    xx = sum((p[0] - mean_x) ** 2 for p in points)
    yy = sum((p[1] - mean_y) ** 2 for p in points)
    xy = sum((p[0] - mean_x) * (p[1] - mean_y) for p in points)
    angle = 0.5 * math.atan2(2 * xy, xx - yy)
    dx, dy = math.cos(angle), math.sin(angle)
    # (a,b) is the unit normal; make the sign deterministic for JSON output.
    a, b = -dy, dx
    if a < -1e-12 or (abs(a) <= 1e-12 and b < 0):
        a, b = -a, -b
    return a, b, a * mean_x + b * mean_y


def intersect(first: Line, second: Line) -> Point:
    a1, b1, c1 = first
    a2, b2, c2 = second
    determinant = a1 * b2 - a2 * b1
    if abs(determinant) < 1e-10:
        raise ValueError("adjacent annotation edges are parallel")
    return (
        (c1 * b2 - c2 * b1) / determinant,
        (a1 * c2 - a2 * c1) / determinant,
    )


def fit_quad(edges: dict[str, Sequence[Point]]) -> list[list[float]]:
    lines = {name: fit_line(points) for name, points in edges.items()}
    return [
        list(intersect(lines["top"], lines["left"])),
        list(intersect(lines["top"], lines["right"])),
        list(intersect(lines["bottom"], lines["right"])),
        list(intersect(lines["bottom"], lines["left"])),
    ]


def edge_points(quad: Sequence[Point], side: str) -> tuple[Point, Point]:
    indexes = {
        "left": (0, 3),
        "top": (0, 1),
        "right": (1, 2),
        "bottom": (3, 2),
    }[side]
    return quad[indexes[0]], quad[indexes[1]]


def edge_normal(quad: Sequence[Point], side: str) -> Point:
    """Return the unit normal pointing toward the provisional card centre."""
    first, second = edge_points(quad, side)
    tangent = (second[0] - first[0], second[1] - first[1])
    length = max(math.hypot(*tangent), 1e-12)
    normal = (-tangent[1] / length, tangent[0] / length)
    midpoint = ((first[0] + second[0]) / 2, (first[1] + second[1]) / 2)
    centre = (
        sum(point[0] for point in quad) / len(quad),
        sum(point[1] for point in quad) / len(quad),
    )
    if (centre[0] - midpoint[0]) * normal[0] + (centre[1] - midpoint[1]) * normal[1] < 0:
        return -normal[0], -normal[1]
    return normal


def bilinear_luminance(image, x: float, y: float) -> float:
    """Sample an RGB Pillow image without importing application code."""
    x = min(max(x, 0.0), image.width - 1.0)
    y = min(max(y, 0.0), image.height - 1.0)
    x0, y0 = math.floor(x), math.floor(y)
    x1, y1 = min(x0 + 1, image.width - 1), min(y0 + 1, image.height - 1)
    fx, fy = x - x0, y - y0

    def luminance(pixel: tuple[int, int, int]) -> float:
        return (0.2126 * pixel[0] + 0.7152 * pixel[1] + 0.0722 * pixel[2]) / 255.0

    pixels = image.load()
    top_left = luminance(pixels[x0, y0])
    top_right = luminance(pixels[x1, y0])
    bottom_left = luminance(pixels[x0, y1])
    bottom_right = luminance(pixels[x1, y1])
    top = top_left + (top_right - top_left) * fx
    bottom = bottom_left + (bottom_right - bottom_left) * fx
    return top + (bottom - top) * fy


def sample_edge_profile(
    image,
    quad: Sequence[Point],
    side: str,
    *,
    along_count: int,
    search_radius: int,
    span_start: float,
    span_end: float,
) -> tuple[list[float], list[float]]:
    """Average luminance over an edge-normal profile at >=200 edge positions."""
    if along_count < 200:
        raise ValueError("E4 requires at least 200 positions along each edge")
    first, second = edge_points(quad, side)
    normal = edge_normal(quad, side)
    offsets = [float(value) for value in range(-search_radius, search_radius + 1)]
    profile: list[float] = []
    for offset in offsets:
        total = 0.0
        for index in range(along_count):
            progress = span_start + (span_end - span_start) * index / max(along_count - 1, 1)
            edge_point = (
                first[0] + (second[0] - first[0]) * progress,
                first[1] + (second[1] - first[1]) * progress,
            )
            total += bilinear_luminance(
                image,
                edge_point[0] + normal[0] * offset,
                edge_point[1] + normal[1] * offset,
            )
        profile.append(total / along_count)
    return offsets, profile


def smooth(values: Sequence[float], radius: int = 2) -> list[float]:
    return [
        sum(values[max(0, index - radius) : min(len(values), index + radius + 1)])
        / len(values[max(0, index - radius) : min(len(values), index + radius + 1)])
        for index in range(len(values))
    ]


def crossing(offsets: Sequence[float], values: Sequence[float], start: int, target: float, direction: float) -> float | None:
    """Find a linearly interpolated threshold crossing around one transition."""
    lower = max(0, start - 40)
    upper = min(len(values) - 1, start + 40)
    for index in range(lower, upper):
        first = values[index]
        second = values[index + 1]
        first_delta = direction * (first - target)
        second_delta = direction * (second - target)
        if first_delta <= 0 <= second_delta and abs(second - first) > 1e-12:
            amount = (target - first) / (second - first)
            return offsets[index] + amount * (offsets[index + 1] - offsets[index])
    return None


def profile_candidates(offsets: Sequence[float], values: Sequence[float]) -> list[dict[str, float]]:
    """Return local transitions with sub-pixel 10–90 bands."""
    filtered = smooth(values)
    raw_candidates: list[dict[str, float]] = []
    for index in range(25, len(filtered) - 25):
        gradient = (filtered[index + 1] - filtered[index - 1]) / 2
        magnitude = abs(gradient)
        left_gradient = abs((filtered[index] - filtered[index - 1]) / 2)
        right_gradient = abs((filtered[index + 1] - filtered[index]) / 2)
        if magnitude < left_gradient or magnitude < right_gradient:
            continue
        if magnitude < 0.004:
            continue
        left_window = filtered[index - 25 : index - 10]
        right_window = filtered[index + 10 : index + 25]
        left_level = sum(left_window) / len(left_window)
        right_level = sum(right_window) / len(right_window)
        low, high = min(left_level, right_level), max(left_level, right_level)
        amplitude = high - low
        if amplitude < 0.02:
            continue
        direction = 1.0 if right_level >= left_level else -1.0
        ten = crossing(offsets, filtered, index, low + 0.10 * amplitude, direction)
        fifty = crossing(offsets, filtered, index, low + 0.50 * amplitude, direction)
        ninety = crossing(offsets, filtered, index, low + 0.90 * amplitude, direction)
        if ten is None or fifty is None or ninety is None:
            continue
        band = abs(ninety - ten)
        raw_candidates.append(
            {
                "offset10": ten,
                "offset50": fifty,
                "offset90": ninety,
                "band": band,
                "amplitude": amplitude,
                "gradient": magnitude,
            }
        )

    # A broad transition produces several neighbouring local maxima. Keep the
    # strongest representative of each 8 px neighbourhood so candidate counts
    # describe physical transitions rather than derivative noise.
    selected: list[dict[str, float]] = []
    for candidate in sorted(raw_candidates, key=lambda item: item["gradient"], reverse=True):
        if all(abs(candidate["offset50"] - other["offset50"]) >= 8 for other in selected):
            selected.append(candidate)
    return sorted(selected, key=lambda item: item["offset50"])


def choose_candidate(candidates: Sequence[dict[str, float]]) -> dict[str, float] | None:
    if not candidates:
        return None
    strongest = max(item["amplitude"] for item in candidates)
    credible = [item for item in candidates if item["amplitude"] >= strongest * 0.15]
    # The seed is deliberately only a starting coordinate. Choosing the
    # nearest credible transition keeps the output useful for review while
    # avoiding an automatic claim that the strongest interior artwork edge is
    # the card silhouette.
    return min(credible, key=lambda item: abs(item["offset50"]))


def choose_candidate_near(
    candidates: Sequence[dict[str, float]], target_offset: float | None
) -> dict[str, float] | None:
    """Choose the visually adjudicated transition nearest a review target.

    The target is an analyzer-free review decision recorded in the selection
    manifest.  It is intentionally not a production detector output.  When no
    target is supplied, preserve the original candidate-only behaviour.
    """
    if target_offset is None:
        return choose_candidate(candidates)
    if not candidates:
        return None
    return min(candidates, key=lambda item: abs(item["offset50"] - target_offset))


def shifted_edge_points(
    quad: Sequence[Point], side: str, offset: float, point_count: int = 5
) -> list[Point]:
    first, second = edge_points(quad, side)
    normal = edge_normal(quad, side)
    return [
        (
            first[0] + (second[0] - first[0]) * (0.12 + 0.76 * index / max(point_count - 1, 1))
            + normal[0] * offset,
            first[1] + (second[1] - first[1]) * (0.12 + 0.76 * index / max(point_count - 1, 1))
            + normal[1] * offset,
        )
        for index in range(point_count)
    ]


def quad_aspect(quad: Sequence[Point]) -> float:
    width = (distance(quad[0], quad[1]) + distance(quad[3], quad[2])) / 2
    height = (distance(quad[0], quad[3]) + distance(quad[1], quad[2])) / 2
    return width / max(height, 1e-12)


def line_midpoint_distance(first: Line, second: Line, point: Point) -> float:
    return abs(first[0] * point[0] + first[1] * point[1] - first[2]) + abs(
        second[0] * point[0] + second[1] * point[1] - second[2]
    )


def derive_profile_pass(
    image,
    seed_quad: Sequence[Point],
    *,
    along_count: int,
    span_start: float,
    span_end: float,
    search_radius: int,
    selection_targets: dict[str, float] | None = None,
) -> dict:
    edges: dict[str, dict] = {}
    fitted_points: dict[str, list[Point]] = {}
    for side in SIDES:
        offsets, values = sample_edge_profile(
            image,
            seed_quad,
            side,
            along_count=along_count,
            search_radius=search_radius,
            span_start=span_start,
            span_end=span_end,
        )
        candidates = profile_candidates(offsets, values)
        target_offset = selection_targets.get(side) if selection_targets else None
        chosen = choose_candidate_near(candidates, target_offset)
        points = shifted_edge_points(seed_quad, side, chosen["offset50"] if chosen else 0.0)
        fitted_points[side] = points
        edges[side] = {
            "alongCount": along_count,
            "span": [span_start, span_end],
            "offsetRange": [offsets[0], offsets[-1]],
            "profile": values,
            "candidates": candidates,
            "selected": chosen,
            "selectionTarget": target_offset,
            "fitPoints": [list(point) for point in points],
            "line": list(fit_line(points)),
        }
    quad = fit_quad(fitted_points)
    outer_height = (distance(quad[0], quad[3]) + distance(quad[1], quad[2])) / 2
    bands = {
        side: float(edges[side]["selected"]["band"])
        for side in SIDES
        if edges[side]["selected"] is not None
    }
    return {
        "edges": edges,
        "quad": quad,
        "rectifiedAspect": quad_aspect(quad),
        "edgeBands": bands,
        "ambiguousEdges": sorted(side for side in bands if bands[side] > 0.01 * outer_height),
    }


def reconciled_quad(first: dict, second: dict) -> list[list[float]]:
    """Fit one set of edge lines through both independent pass point sets."""
    points: dict[str, list[Point]] = {}
    for side in SIDES:
        first_points = [tuple(point) for point in first["edges"][side]["fitPoints"]]
        second_points = [tuple(point) for point in second["edges"][side]["fitPoints"]]
        points[side] = first_points + second_points
    return fit_quad(points)


def selected_offset_agreement(first: dict, second: dict) -> dict[str, float]:
    agreement: dict[str, float] = {}
    for side in SIDES:
        first_selected = first["edges"][side]["selected"]
        second_selected = second["edges"][side]["selected"]
        agreement[side] = (
            abs(first_selected["offset50"] - second_selected["offset50"])
            if first_selected is not None and second_selected is not None
            else math.inf
        )
    return agreement


def average_selected_band(first: dict, second: dict, side: str) -> float:
    first_selected = first["edges"][side]["selected"]
    second_selected = second["edges"][side]["selected"]
    if first_selected is None or second_selected is None:
        raise ValueError(f"{side}: both independent passes must select a transition")
    return (float(first_selected["band"]) + float(second_selected["band"])) / 2


def quad_skew(quad: Sequence[Point]) -> float:
    """Match the app's long-edge unoriented roll calculation."""
    top_first, top_second = edge_points(quad, "top")
    bottom_first, bottom_second = edge_points(quad, "bottom")
    top_angle = math.atan2(top_second[1] - top_first[1], top_second[0] - top_first[0])
    bottom_angle = math.atan2(bottom_second[1] - bottom_first[1], bottom_second[0] - bottom_first[0])
    sine = math.sin(2 * top_angle) + math.sin(2 * bottom_angle)
    cosine = math.cos(2 * top_angle) + math.cos(2 * bottom_angle)
    angle = 0.5 * math.atan2(sine, cosine)
    if angle > math.pi / 2:
        angle -= math.pi
    if angle < -math.pi / 2:
        angle += math.pi
    return angle * 180 / math.pi


def load_selection_manifest(path: Path) -> dict:
    manifest = read_record(path)
    if manifest.get("schema") != 1:
        raise ValueError("selection manifest schema must be 1")
    if manifest.get("method") != "analyzer_free_visual_transition_adjudication":
        raise ValueError("selection manifest method must identify analyzer-free visual adjudication")
    fixtures = manifest.get("fixtures")
    if not isinstance(fixtures, dict) or len(fixtures) != 10:
        raise ValueError("selection manifest must contain ten fixture entries")
    return manifest


def manifest_targets(manifest: dict, name: str, key: str) -> dict[str, float]:
    fixture = manifest["fixtures"].get(name)
    if not isinstance(fixture, dict):
        raise ValueError(f"selection manifest is missing {name}")
    geometry = fixture.get(key)
    if not isinstance(geometry, dict):
        raise ValueError(f"selection manifest is missing {name}.{key}")
    targets = geometry.get("targetOffsets")
    if not isinstance(targets, dict) or set(targets) != set(SIDES):
        raise ValueError(f"{name}.{key}.targetOffsets must contain all four sides")
    return {side: float(targets[side]) for side in SIDES}


def manifest_geometry(manifest: dict, name: str, key: str) -> dict:
    fixture = manifest["fixtures"].get(name)
    if not isinstance(fixture, dict):
        raise ValueError(f"selection manifest is missing {name}")
    geometry = fixture.get(key)
    if not isinstance(geometry, dict):
        raise ValueError(f"selection manifest is missing {name}.{key}")
    return geometry


def derive_visual_trace_pass(seed_quad: Sequence[Point], offsets: dict[str, float]) -> dict:
    """Fit a separately reviewed sleeve trace when its clear edge is not measurable.

    Transparent sleeves frequently have no stable luminance transition against the
    paper background.  In that case the manifest records the independently reviewed
    virtual edge and this path preserves it without pretending a noisy profile was a
    measurement.  Card and inner-reference geometry always use the profile path.
    """
    edges: dict[str, dict] = {}
    fitted_points: dict[str, list[Point]] = {}
    for side in SIDES:
        offset = float(offsets[side])
        points = shifted_edge_points(seed_quad, side, offset)
        fitted_points[side] = points
        edges[side] = {
            "method": "independent_visual_trace",
            "selectionTarget": offset,
            "selected": {"offset50": offset, "band": 0.0},
            "fitPoints": [list(point) for point in points],
            "line": list(fit_line(points)),
        }
    quad = fit_quad(fitted_points)
    return {
        "method": "independent_visual_trace",
        "edges": edges,
        "quad": quad,
        "rectifiedAspect": quad_aspect(quad),
        "edgeBands": {},
        "ambiguousEdges": [],
    }


def rederive_record(
    image_path: Path,
    record_path: Path,
    manifest: dict,
    output_dir: Path,
    *,
    search_radius: int,
) -> dict:
    """Produce one verified candidate record from two analyzer-free passes."""
    try:
        from PIL import Image, ImageOps
    except ImportError as error:  # pragma: no cover - environment dependent
        raise SystemExit("rederive requires Pillow") from error

    record = read_record(record_path)
    name = record_path.name.removesuffix(".gt.json")
    image = ImageOps.exif_transpose(Image.open(image_path).convert("RGB"))
    expected_size = (record["orientedPixelSize"]["w"], record["orientedPixelSize"]["h"])
    if image.size != expected_size:
        raise ValueError(f"{name}: oriented image is {image.size}, expected {expected_size}")

    geometry_outputs: dict[str, dict] = {}
    reconciled: dict[str, list[list[float]]] = {}
    for key in ("cardOuterQuad", "encasementOuterQuad", "innerQuad"):
        seed = record_quad(record, key)
        if seed is None:
            if key == "innerQuad" and record.get("innerReference") == "none":
                continue
            if key == "encasementOuterQuad" and record.get("encasement") == "none":
                continue
            raise ValueError(f"{name}: {key} is required for a verified record")
        geometry_manifest = manifest_geometry(manifest, name, key)
        selection_mode = geometry_manifest.get("selectionMode", "profile")
        if selection_mode == "independent_visual_trace":
            first_offsets = geometry_manifest.get("passAOffsets", geometry_manifest.get("targetOffsets"))
            second_offsets = geometry_manifest.get("passBOffsets", geometry_manifest.get("targetOffsets"))
            if not isinstance(first_offsets, dict) or not isinstance(second_offsets, dict):
                raise ValueError(f"{name}.{key}: visual trace needs passAOffsets and passBOffsets")
            first = derive_visual_trace_pass(
                seed,
                {side: float(first_offsets[side]) for side in SIDES},
            )
            second = derive_visual_trace_pass(
                seed,
                {side: float(second_offsets[side]) for side in SIDES},
            )
        else:
            targets = manifest_targets(manifest, name, key)
            first = derive_profile_pass(
                image,
                seed,
                along_count=240,
                span_start=0.12,
                span_end=0.88,
                search_radius=search_radius,
                selection_targets=targets,
            )
            second = derive_profile_pass(
                image,
                seed,
                along_count=257,
                span_start=0.14,
                span_end=0.86,
                search_radius=search_radius,
                selection_targets=targets,
            )
        agreement_by_edge = selected_offset_agreement(first, second)
        if not all(math.isfinite(value) for value in agreement_by_edge.values()):
            raise ValueError(f"{name}.{key}: both passes must select all four edges")
        geometry_outputs[key] = {
            "selectionMode": selection_mode,
            "seed": [list(point) for point in seed],
            "targetOffsets": geometry_manifest.get("targetOffsets"),
            "passA": first,
            "passB": second,
            "agreementPxByEdge": agreement_by_edge,
            "agreementPx": max(agreement_by_edge.values()),
        }
        reconciled[key] = reconciled_quad(first, second)

    outer = [tuple(point) for point in reconciled["cardOuterQuad"]]
    outer_height = (distance(outer[0], outer[3]) + distance(outer[1], outer[2])) / 2
    outer_aspect = quad_aspect(outer)
    if abs(outer_aspect - 2.5 / 3.5) > 0.02 * (2.5 / 3.5):
        raise ValueError(f"{name}: reconciled outer aspect {outer_aspect:.6f} is outside 2% of 0.7143")

    edge_bands = {
        side: average_selected_band(
            geometry_outputs["cardOuterQuad"]["passA"],
            geometry_outputs["cardOuterQuad"]["passB"],
            side,
        )
        for side in SIDES
    }
    ambiguous_edges = sorted(
        side for side, band in edge_bands.items() if band > 0.01 * outer_height
    )
    inner = reconciled.get("innerQuad")
    expected: dict[str, float | None]
    if inner is None:
        expected = {"lrRatio": None, "tbRatio": None, "skewDegrees": round(quad_skew(outer), 6)}
    else:
        inner_points = [tuple(point) for point in inner]
        left, top, right, bottom = border_distances(outer, inner_points)
        expected = {
            "lrRatio": round(ratio(left, right), 6),
            "tbRatio": round(ratio(top, bottom), 6),
            "skewDegrees": round(quad_skew(outer), 6),
        }

    agreement_values = [output["agreementPx"] for output in geometry_outputs.values()]
    agreement_px = max(agreement_values)
    output = {
        "schema": 1,
        "fixture": record["fixture"],
        "sourcePixelSize": record["sourcePixelSize"],
        "orientedPixelSize": record["orientedPixelSize"],
        "exifOrientation": record["exifOrientation"],
        "face": record["face"],
        "encasement": record["encasement"],
        "capture": record["capture"],
        "cardOuterQuad": reconciled["cardOuterQuad"],
        "cardCornerRadiusPx": record["cardCornerRadiusPx"],
        "encasementOuterQuad": reconciled.get("encasementOuterQuad"),
        "innerQuad": inner,
        "innerReference": record["innerReference"],
        "edgeBands": {side: round(value, 6) for side, value in edge_bands.items()},
        "ambiguousEdges": ambiguous_edges,
        "expected": expected,
        "conditions": record["conditions"],
        "provenance": {
            "method": "analyzer_free_dual_profile_fit_with_visual_adjudication",
            "annotators": ["generic_profile_pass_A", "generic_profile_pass_B"],
            "agreementPx": round(agreement_px, 6),
            "toolVersion": "gt-tool 3.0-rederive",
            "date": "2026-09-12",
            "notes": (
                "Two independent analyzer-free luminance profile passes were visually "
                "adjudicated against the physical silhouette; selected transitions and "
                "full pass diagnostics are retained in diagnostics/GT-rederived. "
                "The physical silhouette was chosen where sleeve, glare, or printed "
                "transitions produced multiple candidates. No CardCenteringAnalyzer "
                "output seeded or adjusted any field. agreementPx is the maximum "
                "pre-reconciliation 50% crossing disagreement across card, sleeve, "
                "and inner reference edges."
            ),
        },
    }
    artifact = {
        "schema": 1,
        "toolVersion": "gt-tool 3.0-rederive",
        "fixture": record["fixture"],
        "image": str(image_path),
        "seedSource": str(record_path),
        "selectionManifest": str(manifest.get("source", "selection-manifest.json")),
        "status": "verified_candidate_ready_for_write",
        "record": output,
        "geometryDiagnostics": geometry_outputs,
    }
    artifact_path = output_dir / f"{name}.json"
    artifact_path.parent.mkdir(parents=True, exist_ok=True)
    artifact_path.write_text(json.dumps(artifact, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return output


def rederive_records(
    image_dir: Path,
    gt_dir: Path,
    manifest_path: Path,
    output_dir: Path,
    *,
    search_radius: int,
    write_ground_truth: bool,
) -> None:
    manifest = load_selection_manifest(manifest_path)
    output_dir.mkdir(parents=True, exist_ok=True)
    records_dir = output_dir / "records"
    records_dir.mkdir(parents=True, exist_ok=True)
    for record_path in sorted(gt_dir.glob("IMG_*.gt.json")):
        name = record_path.name.removesuffix(".gt.json")
        image_path = image_dir / f"{name}.png"
        if not image_path.exists():
            raise SystemExit(f"missing converted oriented image: {image_path}")
        record = rederive_record(
            image_path,
            record_path,
            manifest,
            output_dir,
            search_radius=search_radius,
        )
        destination = (gt_dir / record_path.name) if write_ground_truth else (records_dir / record_path.name)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        print(destination)


def derive_candidates(image_path: Path, record_path: Path, output_path: Path, search_radius: int) -> None:
    try:
        from PIL import Image, ImageOps
    except ImportError as error:  # pragma: no cover - environment dependent
        raise SystemExit("profile candidates require Pillow") from error

    record = read_record(record_path)
    seed_quad = record_quad(record, "cardOuterQuad")
    if seed_quad is None:
        raise ValueError(f"{record_path.name}: cardOuterQuad is required as an E4 review seed")
    image = ImageOps.exif_transpose(Image.open(image_path).convert("RGB"))
    if image.size != (record["orientedPixelSize"]["w"], record["orientedPixelSize"]["h"]):
        raise ValueError(
            f"{image_path.name}: oriented image is {image.size}, expected "
            f"{record['orientedPixelSize']['w']}x{record['orientedPixelSize']['h']}"
        )

    passes = [
        derive_profile_pass(
            image,
            seed_quad,
            along_count=240,
            span_start=0.12,
            span_end=0.88,
            search_radius=search_radius,
        ),
        derive_profile_pass(
            image,
            seed_quad,
            along_count=257,
            span_start=0.14,
            span_end=0.86,
            search_radius=search_radius,
        ),
    ]
    agreement: dict[str, float] = {}
    for side in SIDES:
        first = passes[0]["edges"][side]["selected"]
        second = passes[1]["edges"][side]["selected"]
        agreement[side] = abs(first["offset50"] - second["offset50"]) if first and second else math.inf
    agreement_px = max(agreement.values())

    output = {
        "schema": 1,
        "toolVersion": "gt-tool 2.0-e4-candidate",
        "fixture": record["fixture"],
        "image": str(image_path),
        "seedSource": str(record_path),
        "seedMethod": record.get("provenance", {}).get("method"),
        "searchRadiusPx": search_radius,
        "passes": [
            {"name": "profile_pass_A", **passes[0]},
            {"name": "profile_pass_B", **passes[1]},
        ],
        "agreementPxByEdge": agreement,
        "agreementPx": agreement_px,
        "status": "candidate_only_needs_human_adjudication",
        "proposedRecordFields": {
            "cardOuterQuad": passes[0]["quad"],
            "edgeBands": passes[0]["edgeBands"],
            "ambiguousEdges": passes[0]["ambiguousEdges"],
            "rectifiedAspect": passes[0]["rectifiedAspect"],
        },
        "notes": [
            "Both passes are analyzer-free luminance diagnostics, not two human annotations.",
            "The provisional quad is only a review seed; no production detector output is used.",
            "A human or second reviewer must choose the physical silhouette when multiple transitions exist before a GT record can become verified.",
        ],
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def normal_distance(point: Point, line_start: Point, line_end: Point) -> float:
    dx = line_end[0] - line_start[0]
    dy = line_end[1] - line_start[1]
    length = math.hypot(dx, dy)
    if length == 0:
        return 0.0
    return abs(dx * (point[1] - line_start[1]) - dy * (point[0] - line_start[0])) / length


def border_distances(outer: Sequence[Point], inner: Sequence[Point]) -> tuple[float, float, float, float]:
    left = (normal_distance(inner[0], outer[0], outer[3]) + normal_distance(inner[3], outer[0], outer[3])) / 2
    top = (normal_distance(inner[0], outer[0], outer[1]) + normal_distance(inner[1], outer[0], outer[1])) / 2
    right = (normal_distance(inner[1], outer[1], outer[2]) + normal_distance(inner[2], outer[1], outer[2])) / 2
    bottom = (normal_distance(inner[3], outer[3], outer[2]) + normal_distance(inner[2], outer[3], outer[2])) / 2
    return left, top, right, bottom


def ratio(first: float, second: float) -> float:
    return 100.0 * first / max(first + second, 1e-12)


def read_record(path: Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def record_quad(record: dict, key: str) -> list[Point] | None:
    values = record.get(key)
    if values is None:
        return None
    if len(values) != 4 or any(len(point) != 2 for point in values):
        raise ValueError(f"{record.get('fixture')}: {key} must contain four [x,y] points")
    return [(float(point[0]), float(point[1])) for point in values]


def validate_records(gt_dir: Path) -> list[str]:
    errors: list[str] = []
    paths = sorted(gt_dir.glob("IMG_*.gt.json"))
    if len(paths) != 10:
        errors.append(f"expected 10 records, found {len(paths)}")
    for path in paths:
        try:
            record = read_record(path)
            name = path.name.removesuffix(".gt.json")
            if record.get("schema") != 1:
                raise ValueError("schema must be 1")
            if record.get("fixture") != f"{name}.HEIC":
                raise ValueError("fixture name does not match filename")
            if record.get("sourcePixelSize") != {"w": 4032, "h": 3024}:
                raise ValueError("sourcePixelSize must be 4032x3024")
            if record.get("orientedPixelSize") != {"w": 3024, "h": 4032}:
                raise ValueError("orientedPixelSize must be 3024x4032")
            if record.get("exifOrientation") != 6:
                raise ValueError("exifOrientation must be 6")
            outer = record_quad(record, "cardOuterQuad")
            assert outer is not None
            width = (distance(outer[0], outer[1]) + distance(outer[3], outer[2])) / 2
            height = (distance(outer[0], outer[3]) + distance(outer[1], outer[2])) / 2
            aspect = width / max(height, 1e-12)
            if abs(aspect - 2.5 / 3.5) > 0.02 * (2.5 / 3.5):
                raise ValueError(f"rectified aspect {aspect:.4f} is outside 2% of 0.7143")
            bands = record.get("edgeBands", {})
            if set(bands) != {"left", "top", "right", "bottom"} or any(float(v) <= 0 for v in bands.values()):
                raise ValueError("edgeBands must contain four positive values")
            provenance = record.get("provenance", {})
            if provenance.get("method") == "provisional_five_pixel_grid_estimate":
                # Provisional records are intentionally valid schema records, but
                # they must be unmistakable and cannot be used to close REQ-001.
                if provenance.get("annotators") != ["unverified"]:
                    raise ValueError("provisional records must use the unverified annotator marker")
                if provenance.get("agreementPx") is not None:
                    raise ValueError("provisional records must not report annotator agreement")
                if "re-annotation required" not in str(provenance.get("notes", "")).lower():
                    raise ValueError("provisional records must require re-annotation in notes")
            else:
                if len(provenance.get("annotators", [])) < 2:
                    raise ValueError("two annotators must be recorded")
                if "agreementPx" not in provenance or provenance["agreementPx"] is None:
                    raise ValueError("agreementPx is required for verified records")
                if float(provenance["agreementPx"]) > 0.01 * 4032:
                    raise ValueError("agreementPx exceeds the 1% reconciliation band")
            inner = record_quad(record, "innerQuad")
            expected = record.get("expected", {})
            if inner is None:
                if record.get("innerReference") != "none" or expected.get("lrRatio") is not None or expected.get("tbRatio") is not None:
                    raise ValueError("declined records must have no inner reference or ratios")
            else:
                if record.get("innerReference") == "none":
                    raise ValueError("an inner quad needs an inner reference")
                left, top, right, bottom = border_distances(outer, inner)
                if abs(ratio(left, right) - float(expected["lrRatio"])) > 0.25:
                    raise ValueError("lrRatio is not reproducible from the quads")
                if abs(ratio(top, bottom) - float(expected["tbRatio"])) > 0.25:
                    raise ValueError("tbRatio is not reproducible from the quads")
        except (AssertionError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
            errors.append(f"{path.name}: {error}")
    return errors


def draw_overlay(image_path: Path, record_path: Path, output_path: Path) -> None:
    try:
        from PIL import Image, ImageDraw, ImageFont, ImageOps
    except ImportError as error:  # pragma: no cover - environment dependent
        raise SystemExit("overlay requires Pillow") from error

    record = read_record(record_path)
    image = ImageOps.exif_transpose(Image.open(image_path).convert("RGB"))
    # A 1000px long edge keeps the sheet legible while leaving room for the
    # photo itself under the 1.5 MB tracked-artifact limit.
    scale = min(1.0, 1000.0 / max(image.size))
    if scale < 1:
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)

    def scaled(values: Sequence[Sequence[float]]) -> list[tuple[float, float]]:
        return [(float(x) * scale, float(y) * scale) for x, y in values]

    draw = ImageDraw.Draw(image)
    font = ImageFont.load_default()

    def polygon(key: str, colour: tuple[int, int, int], label: str) -> None:
        values = record.get(key)
        if values is None:
            return
        points = scaled(values)
        draw.line(points + [points[0]], fill=colour, width=max(2, round(3 * scale)))
        for index, point in enumerate(points):
            draw.ellipse((point[0] - 5, point[1] - 5, point[0] + 5, point[1] + 5), fill=colour)
            draw.text((point[0] + 7, point[1] + 4), f"{label}{index}", fill=colour, font=font)

    polygon("cardOuterQuad", (255, 70, 40), "O")
    polygon("encasementOuterQuad", (255, 180, 0), "S")
    polygon("innerQuad", (20, 210, 255), "I")
    bands = record["edgeBands"]
    draw.rectangle((8, 8, 300, 32), fill=(0, 0, 0))
    draw.text((14, 14), "bands px: " + "  ".join(f"{key[0].upper()} {bands[key]:.1f}" for key in ("left", "top", "right", "bottom")), fill="white", font=font)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    image.quantize(colors=128, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).save(
        output_path,
        format="PNG",
        optimize=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate", help="validate all checked-in GT records")
    validate.add_argument("gt_dir", type=Path)

    candidates = subparsers.add_parser(
        "profile-candidates",
        help="derive analyzer-free E4 profile candidates without changing GT records",
    )
    candidates.add_argument("image_dir", type=Path)
    candidates.add_argument("gt_dir", type=Path)
    candidates.add_argument("output_dir", type=Path)
    candidates.add_argument("--search-radius", type=int, default=170)

    rederive = subparsers.add_parser(
        "rederive",
        help="run two analyzer-free profile passes and write verified GT candidates",
    )
    rederive.add_argument("image_dir", type=Path)
    rederive.add_argument("gt_dir", type=Path)
    rederive.add_argument("selection_manifest", type=Path)
    rederive.add_argument("output_dir", type=Path)
    rederive.add_argument("--search-radius", type=int, default=170)
    rederive.add_argument(
        "--write-ground-truth",
        action="store_true",
        help="promote generated records into gt_dir after the candidate run is reviewed",
    )

    overlay = subparsers.add_parser("overlay", help="draw a review overlay from a PNG/JPEG image")
    overlay.add_argument("image", type=Path)
    overlay.add_argument("record", type=Path)
    overlay.add_argument("output", type=Path)

    args = parser.parse_args()
    if args.command == "validate":
        errors = validate_records(args.gt_dir)
        if errors:
            for error in errors:
                print(error)
            return 1
        print(f"validated 10 ground-truth records in {args.gt_dir}")
        return 0
    if args.command == "profile-candidates":
        args.output_dir.mkdir(parents=True, exist_ok=True)
        paths = sorted(args.gt_dir.glob("IMG_*.gt.json"))
        if len(paths) != 10:
            raise SystemExit(f"expected 10 GT records, found {len(paths)}")
        for record_path in paths:
            name = record_path.name.removesuffix(".gt.json")
            image_path = args.image_dir / f"{name}.png"
            if not image_path.exists():
                raise SystemExit(f"missing converted oriented image: {image_path}")
            derive_candidates(
                image_path,
                record_path,
                args.output_dir / f"{name}.json",
                args.search_radius,
            )
            print(args.output_dir / f"{name}.json")
        return 0
    if args.command == "rederive":
        rederive_records(
            args.image_dir,
            args.gt_dir,
            args.selection_manifest,
            args.output_dir,
            search_radius=args.search_radius,
            write_ground_truth=args.write_ground_truth,
        )
        return 0
    draw_overlay(args.image, args.record, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
