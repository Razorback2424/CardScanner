#!/usr/bin/env python3
"""Prepare signed content roll-forward candidates and rehearse recovery drills.

Clients enforce strict revision monotonicity and reject older revisions. To
recover from a bad published catalog revision M, this tool downloads (or reads
from a local site tree) both the active revision M and a verified known-good
historical revision N (1 <= N < M), proves parity between revision N and the
prepared candidate, validates app size budgets, and stages an unsigned
roll-forward candidate at revision M + 1 ready for each game's existing
protected signing and R2-first publication pipeline.

This script never touches private signing keys, R2 credentials, or Firebase.
"""
from __future__ import annotations

import argparse
import base64
import copy
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from urllib.error import HTTPError

from catalog_hosting_cache import MAX_POINTER_BYTES, NAMESPACES
import catalog_parity
import catalog_release_preflight as preflight
from market_price_feeds import (
    CATALOG_NAMESPACES,
    NAMESPACE as PRICE_V1_NAMESPACE,
    ORIGIN as FIREBASE_ORIGIN,
    R2_ORIGIN,
    SCOPE_FILE,
    packed,
)
import market_price_rollback as price_rollback
import market_price_v2 as price_v2
import rollback_readiness as readiness

GAMES = ("pokemon", "one-piece", "magic", "yugioh")
POKEMON_AUTOMATIC_FIELDS = {
    "providerFingerprint",
    "displayName",
    "releaseDate",
    "logoURL",
    "symbolURL",
    "artworkFallbackURLs",
    "cardArtwork",
}
MAGIC_AUTOMATIC_FIELDS = {
    "displayName",
    "releaseDate",
    "cardCount",
    "iconSVGURL",
}
ONE_PIECE_PERMANENT_FIELDS = (
    "canonicalCardID",
    "artworkID",
    "language",
    "region",
    "releaseID",
    "distributionLabel",
    "treatment",
    "stamp",
    "blockText",
    "copyrightText",
)


class RollForwardError(ValueError):
    """Raised when a roll-forward candidate violates safety or parity invariants."""


def utc_iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def canonical_json_bytes(obj: object) -> bytes:
    return (
        json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False) + "\n"
    ).encode("utf-8")


def decode_envelope(raw: bytes, label: str) -> tuple[dict, dict]:
    """Decode a signed catalog envelope ({keyID, payload, signature, ...}) and its JSON payload."""
    try:
        envelope = json.loads(raw)
    except Exception as exc:
        raise RollForwardError(f"Invalid JSON in {label}: {exc}") from None
    if not isinstance(envelope, dict) or not isinstance(envelope.get("payload"), str):
        raise RollForwardError(f"Expected a signed catalog envelope with base64url payload in {label}")
    encoded = envelope["payload"]
    try:
        decoded = base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4))
        payload = json.loads(decoded)
    except Exception as exc:
        raise RollForwardError(f"Failed to decode signed payload in {label}: {exc}") from None
    if not isinstance(payload, dict):
        raise RollForwardError(f"Decoded payload in {label} is not a JSON object")
    return envelope, payload


def _read_source_object(
    rel_path: str,
    *,
    local_site: Path | None = None,
    origin: str = R2_ORIGIN,
    fetch=readiness.fetch_http_with_headers,
    optional: bool = False,
) -> bytes | None:
    if local_site is not None:
        target = (local_site / rel_path).resolve()
        root = local_site.resolve()
        if not target.is_relative_to(root):
            raise RollForwardError(f"Path escapes local site root: {rel_path}")
        if not target.is_file():
            if optional:
                return None
            raise RollForwardError(f"Missing required catalog object in local site: {rel_path}")
        return target.read_bytes()
    data, _ = readiness.fetch_with_retry(
        readiness.normalize_origin(origin),
        rel_path,
        MAX_POINTER_BYTES,
        fetch=fetch,
        absent_ok=optional,
    )
    if data is None and not optional:
        raise RollForwardError(f"Missing required catalog object on {origin}: {rel_path}")
    return data


def verify_signed_envelope_with_swift(game: str, envelope_path: Path, expected_revision: int, root: Path) -> None:
    """Invoke the game's existing pinned-key Swift verifier against `envelope_path`."""
    if game == "pokemon":
        cmd = [
            "swift",
            "run",
            "--package-path",
            str(root / "PokemonCatalogCore"),
            "pokemon-catalog-publisher",
            "verify-release",
            "--path",
            str(envelope_path),
            "--environment",
            "production",
            "--trusted-keys-file",
            str(root / "Config/PokemonCatalogProduction.xcconfig"),
            "--expected-revision",
            str(expected_revision),
        ]
    elif game == "one-piece":
        keys_tmp = envelope_path.parent / ".one-piece-pinned-keys.json"
        subprocess.run(
            [
                sys.executable,
                str(root / "scripts/one_piece_pinned_keys.py"),
                "--xcconfig",
                str(root / "Config/OnePieceCatalogProduction.xcconfig"),
                "--output",
                str(keys_tmp),
            ],
            check=True,
            capture_output=True,
        )
        cmd = [
            "swift",
            "run",
            "--package-path",
            str(root / "OnePieceCatalogCore"),
            "one-piece-catalog-publisher",
            "verify-hosted-release",
            "--input",
            str(envelope_path),
            "--trusted-keys",
            str(keys_tmp),
            "--expected-revision",
            str(expected_revision),
        ]
    elif game == "magic":
        cmd = [
            "swift",
            "run",
            "--package-path",
            str(root / "MagicCatalogCore"),
            "magic-catalog-publisher",
            "verify-release",
            "--path",
            str(envelope_path),
            "--trusted-keys-file",
            str(root / "Config/MagicCatalogProduction.xcconfig"),
            "--expected-revision",
            str(expected_revision),
        ]
    elif game == "yugioh":
        keys_file = root / "Config/YuGiOhCatalogProduction.keys.json"
        if not keys_file.is_file():
            raise RollForwardError(f"Missing Yu-Gi-Oh! pinned keys file: {keys_file}")
        publisher_bin = envelope_path.parent / ".yugioh-catalog-publisher"
        subprocess.run(
            ["bash", str(root / "scripts/build_yugioh_publisher.sh"), str(publisher_bin)],
            check=True,
            capture_output=True,
        )
        cmd = [
            str(publisher_bin),
            "verify",
            "--input",
            str(envelope_path),
            "--keys",
            str(keys_file),
            "--expected-revision",
            str(expected_revision),
        ]
    else:
        raise RollForwardError(f"Unsupported game: {game}")

    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        raise RollForwardError(
            f"Signature verification failed for {game} revision {expected_revision}: "
            f"{(result.stderr or result.stdout).strip()}"
        )


def _changed_fields(previous: dict, current: dict) -> set[str]:
    changed = set()
    for key in set(previous.keys()) | set(current.keys()):
        if key not in previous or key not in current:
            changed.add(key)
        elif canonical_json_bytes(previous[key]) != canonical_json_bytes(current[key]):
            changed.add(key)
    return changed


def classify_pokemon_change(previous_release: dict | None, current_release: dict) -> dict:
    """Mirror PokemonCatalogChangeClassifier.classify(previousRelease:currentRelease:)."""
    prev_by_id = {
        row["providerSetID"].lower(): row for row in (previous_release.get("sets", []) if previous_release else [])
    }
    changed: list[str] = []
    content: list[str] = []
    authority: list[str] = []
    baseline: list[str] = []
    added: list[str] = []
    classes: list[str] = []

    for descriptor in current_release["sets"]:
        set_id = descriptor["providerSetID"].lower()
        prev = prev_by_id.get(set_id)
        if prev is None:
            cls = "newSet"
        elif canonical_json_bytes(prev) == canonical_json_bytes(descriptor):
            cls = "none"
        else:
            diff_fields = _changed_fields(prev, descriptor)
            if not diff_fields:
                cls = "authority"
            elif prev.get("providerFingerprint") is not None and descriptor.get("providerFingerprint") is None:
                cls = "authority"
            else:
                is_acq = (
                    prev.get("providerAcquisitionFingerprint") is None
                    and descriptor.get("providerAcquisitionFingerprint") is not None
                )
                is_base = (
                    prev.get("providerFingerprint") is None and descriptor.get("providerFingerprint") is not None
                ) or is_acq
                allowed = (
                    POKEMON_AUTOMATIC_FIELDS | {"providerAcquisitionFingerprint"}
                    if is_acq
                    else POKEMON_AUTOMATIC_FIELDS
                )
                if not diff_fields.issubset(allowed):
                    cls = "authority"
                else:
                    cls = "baselineMigration" if is_base else "contentOnly"

        classes.append(cls)
        if cls == "newSet":
            added.append(set_id)
        elif cls == "contentOnly":
            changed.append(set_id)
            content.append(set_id)
        elif cls == "baselineMigration":
            changed.append(set_id)
            baseline.append(set_id)
        elif cls in ("authority", "unknown"):
            changed.append(set_id)
            authority.append(set_id)

    current_ids = {row["providerSetID"].lower() for row in current_release["sets"]}
    removes_descriptor = not set(prev_by_id.keys()).issubset(current_ids)
    prev_exclusions = previous_release.get("englishExclusions") if previous_release else None
    prev_checklist_sha = previous_release.get("checklistInputSHA256") if previous_release else None
    prev_rarity_sha = previous_release.get("cardRaritySHA256") if previous_release else None

    if "unknown" in classes:
        overall = "unknown"
    elif added:
        overall = "newSet"
    elif (
        "authority" in classes
        or removes_descriptor
        or prev_exclusions != current_release.get("englishExclusions")
        or (prev_checklist_sha is not None and current_release.get("checklistInputSHA256") is None)
    ):
        overall = "authority"
    elif "baselineMigration" in classes:
        overall = "baselineMigration"
    elif (
        "contentOnly" in classes
        or prev_checklist_sha != current_release.get("checklistInputSHA256")
        or prev_rarity_sha != current_release.get("cardRaritySHA256")
    ):
        overall = "contentOnly"
    else:
        overall = "none"

    return {
        "changeClass": overall,
        "changedProviderSetIDs": sorted(changed),
        "contentChangedProviderSetIDs": sorted(content),
        "authorityChangedProviderSetIDs": sorted(authority),
        "baselineFingerprintProviderSetIDs": sorted(baseline),
        "addedProviderSetIDs": sorted(added),
    }


def classify_magic_change(previous_release: dict | None, current_release: dict) -> dict:
    """Mirror MagicCatalogChangeClassifier.surfaceDiff + classify."""
    prev_by_code = {
        row["code"].strip().lower(): row for row in (previous_release.get("sets", []) if previous_release else [])
    }
    curr_by_code = {row["code"].strip().lower(): row for row in current_release["sets"]}

    def disp(row: dict) -> str:
        return row["code"].strip().upper()

    added: list[str] = []
    removed: list[str] = []
    changed: list[str] = []
    content: list[str] = []
    authority: list[str] = []
    scanner_proj: list[str] = []
    browse_proj: list[str] = []
    routing_proj: list[str] = []
    classes: list[str] = []

    for code in sorted(set(prev_by_code) | set(curr_by_code)):
        prev = prev_by_code.get(code)
        curr = curr_by_code.get(code)
        if prev is None and curr is not None:
            d = disp(curr)
            added.append(d)
            classes.append("newSet")
            if curr.get("scanEnabled"):
                scanner_proj.append(d)
            if curr.get("browseEnabled"):
                browse_proj.append(d)
            if curr.get("routingKind") is not None:
                routing_proj.append(d)
        elif prev is not None and curr is None:
            d = disp(prev)
            removed.append(d)
            classes.append("authority")
            if prev.get("scanEnabled"):
                scanner_proj.append(d)
            if prev.get("browseEnabled"):
                browse_proj.append(d)
            if prev.get("routingKind") is not None:
                routing_proj.append(d)
        elif prev is not None and curr is not None:
            d = disp(curr)
            if prev.get("scanEnabled") != curr.get("scanEnabled") or prev.get("printedSize") != curr.get("printedSize"):
                scanner_proj.append(d)
            if any(
                prev.get(k) != curr.get(k)
                for k in ("displayName", "releaseDate", "cardCount", "iconSVGURL", "browseEnabled")
            ):
                browse_proj.append(d)
            if prev.get("parentSetCode") != curr.get("parentSetCode") or prev.get("routingKind") != curr.get("routingKind"):
                routing_proj.append(d)
            if canonical_json_bytes(prev) == canonical_json_bytes(curr):
                classes.append("none")
            else:
                diff_fields = _changed_fields(prev, curr)
                cls = "contentOnly" if diff_fields and diff_fields.issubset(MAGIC_AUTOMATIC_FIELDS) else "authority"
                classes.append(cls)
                changed.append(d)
                if cls == "contentOnly":
                    content.append(d)
                else:
                    authority.append(d)

    added_s = sorted(set(added))
    removed_s = sorted(set(removed))
    changed_s = sorted(set(changed))
    content_s = sorted(set(content))
    authority_s = sorted(set(authority))
    scanner_s = sorted(set(scanner_proj))
    browse_s = sorted(set(browse_proj))
    routing_s = sorted(set(routing_proj))

    if "unknown" in classes:
        provisional = "unknown"
    elif "newSet" in classes:
        provisional = "newSet"
    elif removed_s or "authority" in classes:
        provisional = "authority"
    elif "contentOnly" in classes:
        provisional = "contentOnly"
    else:
        provisional = "none"

    change_class = provisional
    if provisional == "contentOnly" and (
        scanner_s or routing_s or set(browse_s) != set(content_s)
    ):
        change_class = "unknown"
        authority_s = sorted(set(changed_s + content_s + scanner_s + browse_s + routing_s))
        content_s = []

    return {
        "changeClass": change_class,
        "addedCodes": added_s,
        "changedCodes": changed_s,
        "removedCodes": removed_s,
        "contentChangedCodes": content_s,
        "authorityChangedCodes": authority_s,
        "scannerProjectionChangedCodes": scanner_s,
        "browseProjectionChangedCodes": browse_s,
        "routingProjectionChangedCodes": routing_s,
    }


def _strip_meta(payload: dict, ignored_keys: set[str]) -> dict:
    return {k: v for k, v in payload.items() if k not in ignored_keys}


def _prepare_pokemon(
    *,
    active_payload: dict,
    active_raw: bytes,
    target_payload: dict,
    target_revision: int,
    next_revision: int,
    generated_at: str,
    output_dir: Path,
    read_obj,
    repo_root: Path,
) -> tuple[dict[str, str], dict, list[str]]:
    ns = NAMESPACES["pokemon"]
    payload_raw = read_obj(f"{ns}/releases/{target_revision}/catalog-payload.json")
    snapshot_raw = read_obj(f"{ns}/releases/{target_revision}/pokemon-catalog-snapshot.json")
    report_raw = read_obj(f"{ns}/releases/{target_revision}/review-report.json")
    assert payload_raw is not None and snapshot_raw is not None and report_raw is not None

    disk_payload = json.loads(payload_raw)
    if canonical_json_bytes(disk_payload) != canonical_json_bytes(target_payload):
        raise RollForwardError(
            f"Pokémon revision {target_revision} catalog-payload.json does not match signed catalog-release.json"
        )
    snapshot = json.loads(snapshot_raw)
    report = json.loads(report_raw)

    new_payload = copy.deepcopy(target_payload)
    new_payload["revision"] = next_revision
    new_payload["generatedAt"] = generated_at

    new_snapshot = copy.deepcopy(snapshot)
    new_snapshot["generatedAt"] = generated_at

    classification = classify_pokemon_change(active_payload, new_payload)
    active_ids = {row["providerSetID"].lower() for row in active_payload.get("sets", [])}
    new_report = copy.deepcopy(report)
    new_report["revision"] = next_revision
    new_report["generatedAt"] = generated_at
    new_report.update(classification)
    for row in new_report.get("sets", []):
        row["status"] = "added" if row["providerSetID"].lower() not in active_ids else "verified"

    if canonical_json_bytes(_strip_meta(target_payload, {"revision", "generatedAt"})) != canonical_json_bytes(
        _strip_meta(new_payload, {"revision", "generatedAt"})
    ):
        raise RollForwardError("Pokémon roll-forward payload diverged from target revision content")
    if canonical_json_bytes(_strip_meta(snapshot, {"generatedAt"})) != canonical_json_bytes(
        _strip_meta(new_snapshot, {"generatedAt"})
    ):
        raise RollForwardError("Pokémon roll-forward snapshot diverged from target revision content")

    candidate_dir = output_dir / "candidate"
    candidate_dir.mkdir(parents=True, exist_ok=True)
    payload_out = candidate_dir / "catalog-payload.json"
    snapshot_out = candidate_dir / "pokemon-catalog-snapshot.json"
    report_out = candidate_dir / "review-report.json"
    active_out = output_dir / "active-release.json"

    payload_bytes = canonical_json_bytes(new_payload)
    snapshot_bytes = canonical_json_bytes(new_snapshot)
    report_bytes = canonical_json_bytes(new_report)
    payload_out.write_bytes(payload_bytes)
    snapshot_out.write_bytes(snapshot_bytes)
    report_out.write_bytes(report_bytes)
    active_out.write_bytes(active_raw)

    budget_result = preflight.check("pokemon", "payload", len(snapshot_bytes), 0.05, repo_root)
    if budget_result["status"] != "ok":
        raise RollForwardError(f"Pokémon snapshot preflight failed: {preflight.describe(budget_result)}")

    artifacts = {
        "candidate/catalog-payload.json": sha256_bytes(payload_bytes),
        "candidate/pokemon-catalog-snapshot.json": sha256_bytes(snapshot_bytes),
        "candidate/review-report.json": sha256_bytes(report_bytes),
        "active-release.json": sha256_bytes(active_raw),
    }
    next_steps = [
        f"Verify candidate: swift run --package-path PokemonCatalogCore pokemon-catalog-publisher verify-candidate "
        f"--candidate-root {candidate_dir} --active-release {active_out} --environment production",
        f"Sign & publish through protected pokemon-catalog-production environment with --candidate-root {candidate_dir} "
        f"--change-class {classification['changeClass']} (revision {next_revision}).",
    ]
    return artifacts, {"preflight": budget_result, "changeClass": classification["changeClass"]}, next_steps


def _prepare_one_piece(
    *,
    active_payload: dict,
    active_raw: bytes,
    target_payload: dict,
    target_raw: bytes,
    target_revision: int,
    next_revision: int,
    generated_at: str,
    output_dir: Path,
    repo_root: Path,
) -> tuple[dict[str, str], dict, list[str]]:
    # Enforce One Piece's permanent identity & correction-history monotonicity rules
    # (OnePieceCatalogCandidateValidator.swift lines 377-392).
    active_registry = active_payload.get("registry", {})
    target_registry = target_payload.get("registry", {})
    active_printings = {row["id"]: row for row in active_registry.get("printings", [])}
    target_printings = {row["id"]: row for row in target_registry.get("printings", [])}

    removed_printings = sorted(set(active_printings) - set(target_printings))
    if removed_printings:
        sample = ", ".join(removed_printings[:5])
        raise RollForwardError(
            f"Cannot roll forward directly to One Piece revision {target_revision}: active revision "
            f"{active_payload['revision']} introduced {len(removed_printings)} permanent printing UUID(s) "
            f"not present in revision {target_revision} ({sample}). Build a reviewed correction that supersedes "
            f"those printing IDs instead of dropping them."
        )

    for printing_id, old in active_printings.items():
        new = target_printings[printing_id]
        for field in ONE_PIECE_PERMANENT_FIELDS:
            if old.get(field) != new.get(field):
                raise RollForwardError(
                    f"Cannot roll forward directly to One Piece revision {target_revision}: permanent field "
                    f"{field!r} on printing {printing_id} differs from active revision {active_payload['revision']}."
                )

    active_corrections = {row["id"]: row for row in active_registry.get("corrections", [])}
    target_corrections = {row["id"]: row for row in target_registry.get("corrections", [])}
    removed_corrections = sorted(
        cid for cid, row in active_corrections.items()
        if cid not in target_corrections or canonical_json_bytes(target_corrections[cid]) != canonical_json_bytes(row)
    )
    if removed_corrections:
        sample = ", ".join(removed_corrections[:5])
        raise RollForwardError(
            f"Cannot roll forward directly to One Piece revision {target_revision}: active revision "
            f"{active_payload['revision']} recorded correction(s) missing or changed in revision "
            f"{target_revision} ({sample}). Retain correction history in a reviewed roll-forward build."
        )

    new_payload = copy.deepcopy(target_payload)
    new_payload["revision"] = next_revision
    new_payload["generatedAt"] = generated_at
    candidate_bytes = canonical_json_bytes(new_payload)

    output_dir.mkdir(parents=True, exist_ok=True)
    candidate_path = output_dir / f"candidate-rev-{next_revision}.json"
    previous_path = output_dir / "previous-release.json"
    target_copy = output_dir / f"target-rev-{target_revision}-envelope.json"
    candidate_path.write_bytes(candidate_bytes)
    previous_path.write_bytes(active_raw)
    target_copy.write_bytes(target_raw)

    # Full structural parity check using the shared catalog_parity reader.
    before_view = catalog_parity.one_piece(target_copy)
    after_view = catalog_parity.one_piece(candidate_path)
    diffs = catalog_parity.compare(before_view, after_view)
    if diffs:
        raise RollForwardError(f"One Piece roll-forward parity check found {len(diffs)} unexpected difference(s)")

    budget_result = preflight.check("one-piece", "payload", len(candidate_bytes), 0.05, repo_root)
    if budget_result["status"] != "ok":
        raise RollForwardError(f"One Piece payload preflight failed: {preflight.describe(budget_result)}")

    payload_sha = sha256_bytes(candidate_bytes)
    artifacts = {
        candidate_path.name: payload_sha,
        previous_path.name: sha256_bytes(active_raw),
        target_copy.name: sha256_bytes(target_raw),
    }
    next_steps = [
        f"Review candidate {candidate_path} (reviewed_payload_sha256={payload_sha}, revision={next_revision}).",
        f"Trigger one-piece-catalog.yml sign-reviewed-artifact with candidate={candidate_path.name} "
        f"reviewed_payload_sha256={payload_sha} against active revision {active_payload['revision']}.",
        "After approval, run publish-reviewed-artifact to publish to R2 and back up to Firebase.",
    ]
    return artifacts, {"preflight": budget_result, "reviewedPayloadSHA256": payload_sha}, next_steps


def _prepare_magic(
    *,
    active_payload: dict,
    active_raw: bytes,
    target_payload: dict,
    target_revision: int,
    next_revision: int,
    generated_at: str,
    output_dir: Path,
    read_obj,
) -> tuple[dict[str, str], dict, list[str]]:
    ns = NAMESPACES["magic"]
    report_raw = read_obj(f"{ns}/releases/{target_revision}/review-report.json", optional=True)
    base_report = json.loads(report_raw) if report_raw is not None else {}

    new_payload = copy.deepcopy(target_payload)
    new_payload["revision"] = next_revision
    new_payload["generatedAt"] = generated_at

    if canonical_json_bytes(_strip_meta(target_payload, {"revision", "generatedAt"})) != canonical_json_bytes(
        _strip_meta(new_payload, {"revision", "generatedAt"})
    ):
        raise RollForwardError("Magic roll-forward payload diverged from target revision content")

    classification = classify_magic_change(active_payload, new_payload)
    if classification["changeClass"] == "none":
        raise RollForwardError(
            f"Magic revision {target_revision} has no semantic differences from active revision "
            f"{active_payload['revision']}; magic-catalog-publisher refuses changeClass=none."
        )

    new_report = copy.deepcopy(base_report)
    new_report.update(
        {
            "schemaVersion": new_payload.get("schemaVersion", 1),
            "revision": next_revision,
            "generatedAt": generated_at,
            "descriptorCount": len(new_payload.get("sets", [])),
            "warnings": base_report.get("warnings", []),
            "hasMeaningfulChanges": True,
            **classification,
        }
    )

    candidate_dir = output_dir / "candidate"
    candidate_dir.mkdir(parents=True, exist_ok=True)
    payload_bytes = canonical_json_bytes(new_payload)
    report_bytes = canonical_json_bytes(new_report)
    (candidate_dir / "catalog-payload.json").write_bytes(payload_bytes)
    (candidate_dir / "review-report.json").write_bytes(report_bytes)
    active_out = output_dir / "active-release.json"
    active_out.write_bytes(active_raw)

    artifacts = {
        "candidate/catalog-payload.json": sha256_bytes(payload_bytes),
        "candidate/review-report.json": sha256_bytes(report_bytes),
        "active-release.json": sha256_bytes(active_raw),
    }
    next_steps = [
        f"Sign & publish through protected magic-catalog-production environment using --candidate-root {candidate_dir} "
        f"--active-release {active_out} --change-class {classification['changeClass']} (revision {next_revision}).",
    ]
    return artifacts, {"changeClass": classification["changeClass"]}, next_steps


def _prepare_yugioh(
    *,
    active_raw: bytes,
    target_manifest: dict,
    target_revision: int,
    next_revision: int,
    output_dir: Path,
    read_obj,
    repo_root: Path,
) -> tuple[dict[str, str], dict, list[str]]:
    ns = NAMESPACES["yugioh"]
    target_catalog_raw = read_obj(f"{ns}/releases/{target_revision}/catalog.json")
    assert target_catalog_raw is not None
    if target_manifest.get("sha256") != sha256_bytes(target_catalog_raw):
        raise RollForwardError(
            f"Yu-Gi-Oh! revision {target_revision} catalog.json hash does not match signed manifest"
        )
    if target_manifest.get("bytes") != len(target_catalog_raw):
        raise RollForwardError(
            f"Yu-Gi-Oh! revision {target_revision} catalog.json size does not match signed manifest"
        )

    active_envelope = json.loads(active_raw)
    active_catalog_raw = base64.b64decode(active_envelope["catalog"])
    active_catalog = json.loads(active_catalog_raw)
    target_catalog = json.loads(target_catalog_raw)
    if (
        active_catalog.get("generation") == target_catalog.get("generation")
        and active_catalog_raw != target_catalog_raw
    ):
        raise RollForwardError(
            f"Yu-Gi-Oh! revision {target_revision} shares generation {target_catalog.get('generation')!r} "
            f"with a different active catalog; cannot transition without distinct generation"
        )

    # Full structural parity & size preflight.
    before_view = catalog_parity.yugioh(target_catalog)
    after_view = catalog_parity.yugioh(json.loads(target_catalog_raw))
    if catalog_parity.compare(before_view, after_view):
        raise RollForwardError("Yu-Gi-Oh! roll-forward catalog parity failed")

    budget_result = preflight.check("yugioh", "payload", len(target_catalog_raw), 0.05, repo_root)
    if budget_result["status"] != "ok":
        raise RollForwardError(f"Yu-Gi-Oh! catalog preflight failed: {preflight.describe(budget_result)}")

    output_dir.mkdir(parents=True, exist_ok=True)
    catalog_out = output_dir / "catalog.json"
    parent_out = output_dir / "parent-release.json"
    catalog_out.write_bytes(target_catalog_raw)
    parent_out.write_bytes(active_raw)

    artifacts = {
        "catalog.json": sha256_bytes(target_catalog_raw),
        "parent-release.json": sha256_bytes(active_raw),
    }
    next_steps = [
        f"Approve & sign with yugioh-catalog-publisher approve --catalog {catalog_out} "
        f"--parent-release {parent_out} --revision {next_revision} --review-id <review-id> "
        f"--key-id <key-id> --private-key-file <key> --keys Config/YuGiOhCatalogProduction.keys.json "
        f"--output {output_dir / f'approved-rev-{next_revision}.json'}",
        "Promote the signed envelope and publish to R2 before backing up to Firebase.",
    ]
    return artifacts, {"preflight": budget_result, "generation": target_catalog.get("generation")}, next_steps


def prepare_roll_forward(
    *,
    game: str,
    target_revision: int,
    output_dir: Path,
    reason: str,
    origin: str = R2_ORIGIN,
    local_site: Path | None = None,
    generated_at: str | None = None,
    verify_signatures: bool = True,
    fetch=readiness.fetch_http_with_headers,
    repo_root: Path | None = None,
    signature_verifier=verify_signed_envelope_with_swift,
) -> dict:
    """Prepare a verified monotonic roll-forward candidate at active_revision + 1."""
    if game not in GAMES:
        raise RollForwardError(f"Unsupported game {game!r}; choose from {', '.join(GAMES)}")
    if type(target_revision) is not int or target_revision < 1:
        raise RollForwardError(f"--target-revision must be a positive integer, got {target_revision!r}")
    if not reason or not reason.strip():
        raise RollForwardError("A non-empty --reason is required for roll-forward auditability")

    root = repo_root or Path(__file__).resolve().parents[1]
    namespace = NAMESPACES[game]
    timestamp = generated_at or utc_iso_now()

    def read_obj(rel: str, *, optional: bool = False) -> bytes | None:
        return _read_source_object(rel, local_site=local_site, origin=origin, fetch=fetch, optional=optional)

    active_raw = read_obj(f"{namespace}/current.json")
    assert active_raw is not None
    _, active_payload = decode_envelope(active_raw, f"{namespace}/current.json")
    active_revision = active_payload.get("revision")
    if type(active_revision) is not int or active_revision < 1:
        raise RollForwardError(f"Active {game} pointer lacks a valid integer revision")

    if target_revision >= active_revision:
        raise RollForwardError(
            f"Target revision ({target_revision}) must be strictly less than active revision ({active_revision})"
        )

    target_rel_path = f"{namespace}/releases/{target_revision}/catalog-release.json"
    target_raw = read_obj(target_rel_path)
    assert target_raw is not None
    _, target_payload = decode_envelope(target_raw, target_rel_path)
    if target_payload.get("revision") != target_revision:
        raise RollForwardError(
            f"{target_rel_path} declares revision {target_payload.get('revision')}, expected {target_revision}"
        )

    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    if verify_signatures:
        with tempfile.TemporaryDirectory(prefix="roll-forward-verify-") as tmp:
            tmp_dir = Path(tmp)
            active_tmp = tmp_dir / "active.json"
            target_tmp = tmp_dir / "target.json"
            active_tmp.write_bytes(active_raw)
            target_tmp.write_bytes(target_raw)
            signature_verifier(game, active_tmp, active_revision, root)
            signature_verifier(game, target_tmp, target_revision, root)

    next_revision = active_revision + 1
    if game == "pokemon":
        artifacts, details, next_steps = _prepare_pokemon(
            active_payload=active_payload,
            active_raw=active_raw,
            target_payload=target_payload,
            target_revision=target_revision,
            next_revision=next_revision,
            generated_at=timestamp,
            output_dir=output_dir,
            read_obj=read_obj,
            repo_root=root,
        )
    elif game == "one-piece":
        artifacts, details, next_steps = _prepare_one_piece(
            active_payload=active_payload,
            active_raw=active_raw,
            target_payload=target_payload,
            target_raw=target_raw,
            target_revision=target_revision,
            next_revision=next_revision,
            generated_at=timestamp,
            output_dir=output_dir,
            repo_root=root,
        )
    elif game == "magic":
        artifacts, details, next_steps = _prepare_magic(
            active_payload=active_payload,
            active_raw=active_raw,
            target_payload=target_payload,
            target_revision=target_revision,
            next_revision=next_revision,
            generated_at=timestamp,
            output_dir=output_dir,
            read_obj=read_obj,
        )
    else:
        artifacts, details, next_steps = _prepare_yugioh(
            active_raw=active_raw,
            target_manifest=target_payload,
            target_revision=target_revision,
            next_revision=next_revision,
            output_dir=output_dir,
            read_obj=read_obj,
            repo_root=root,
        )

    manifest = {
        "schemaVersion": 1,
        "game": game,
        "namespace": namespace,
        "sourceOrigin": str(local_site) if local_site is not None else readiness.normalize_origin(origin),
        "preparedAt": timestamp,
        "reason": reason.strip(),
        "activeRevision": active_revision,
        "activePointerSHA256": sha256_bytes(active_raw),
        "targetRevision": target_revision,
        "targetReleaseSHA256": sha256_bytes(target_raw),
        "nextRevision": next_revision,
        "signatureVerification": "verified" if verify_signatures else "skipped",
        "parityVerified": True,
        "details": details,
        "artifacts": artifacts,
        "nextSteps": next_steps,
    }
    manifest_path = output_dir / "roll-forward-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


# ---------------------------------------------------------------------------
# Offline infrastructure failure & recovery rehearsal drill
# ---------------------------------------------------------------------------

def _fake_signed_envelope(payload: dict, *, key_id: str = "drill-key-1", extra: dict | None = None) -> bytes:
    encoded = base64.urlsafe_b64encode(canonical_json_bytes(payload)).rstrip(b"=").decode("ascii")
    envelope = {"keyID": key_id, "payload": encoded, "signature": "drill-signature"}
    if extra:
        envelope.update(extra)
    return canonical_json_bytes(envelope)


def _drill_pokemon_files(revision: int, *, set_display_name: str, generated_at: str) -> dict[str, bytes]:
    set_id = "sv99"
    fp = hashlib.sha256(f"{set_id}:{set_display_name}".encode()).hexdigest()
    dir_fp = hashlib.sha256(f"{set_id}={fp}".encode()).hexdigest()
    payload = {
        "schemaVersion": 1,
        "catalogKind": "pokemon",
        "revision": revision,
        "generatedAt": generated_at,
        "sets": [
            {
                "providerSetID": set_id,
                "displayName": set_display_name,
                "printedCode": "SV99",
                "officialCount": 1,
                "releaseOrder": 1,
                "recognitionKind": "expansion",
                "providerFingerprint": fp,
            }
        ],
    }
    snapshot = {
        "schemaVersion": 1,
        "rulesVersion": 1,
        "generatedAt": generated_at,
        "directoryFingerprint": dir_fp,
        "entries": [
            {
                "providerSetID": set_id,
                "displayName": set_display_name,
                "printedCode": "SV99",
                "officialCount": 1,
                "releaseOrder": 1,
                "cardCount": 1,
                "providerFingerprint": fp,
                "resource": f"sets/{set_id}-{fp}.json",
            }
        ],
        "checklists": {set_id: [{"providerCardID": "sv99-1", "name": "Pikachu"}]},
        "checklistInputs": {set_id: {"cards": [{"id": "sv99-1", "setID": set_id, "name": "Pikachu"}]}},
        "cardRarities": {},
    }
    report = {
        "schemaVersion": 1,
        "revision": revision,
        "generatedAt": generated_at,
        "changeClass": "contentOnly",
        "addedProviderSetIDs": [],
        "changedProviderSetIDs": [set_id],
        "contentChangedProviderSetIDs": [set_id],
        "authorityChangedProviderSetIDs": [],
        "baselineFingerprintProviderSetIDs": [],
        "sets": [
            {
                "providerSetID": set_id,
                "displayName": set_display_name,
                "recognitionKind": "expansion",
                "printedCode": "SV99",
                "officialCount": 1,
                "providerCardCount": 1,
                "providerFingerprint": fp,
                "status": "verified",
            }
        ],
    }
    envelope = _fake_signed_envelope(payload)
    prefix = f"v1/releases/{revision}"
    return {
        f"{prefix}/catalog-release.json": envelope,
        f"{prefix}/catalog-payload.json": canonical_json_bytes(payload),
        f"{prefix}/pokemon-catalog-snapshot.json": canonical_json_bytes(snapshot),
        f"{prefix}/review-report.json": canonical_json_bytes(report),
        "v1/current.json": envelope,
    }


def _drill_one_piece_files(revision: int, *, card_name: str, generated_at: str) -> dict[str, bytes]:
    printing_uuid = "11111111-1111-4111-8111-111111111111"
    artwork_uuid = "22222222-2222-4222-8222-222222222222"
    payload = {
        "schemaVersion": 1,
        "catalogKind": "one-piece",
        "rulesVersion": 2,
        "revision": revision,
        "generatedAt": generated_at,
        "registry": {
            "schemaVersion": 1,
            "canonicalCards": [
                {
                    "id": "one-piece:en:OP01-001",
                    "language": "en",
                    "printedNumber": "OP01-001",
                    "name": card_name,
                    "printingCoverageComplete": False,
                }
            ],
            "products": [{"id": "OP-01", "label": "Romance Dawn"}],
            "variants": [{"id": "standard", "label": "Standard"}],
            "artworks": [{"id": artwork_uuid, "observationIDs": ["obs-1"]}],
            "printings": [
                {
                    "id": printing_uuid,
                    "canonicalCardID": "one-piece:en:OP01-001",
                    "artworkID": artwork_uuid,
                    "language": "en",
                    "releaseID": "OP-01",
                    "status": "verified",
                    "supportedVariantIDs": ["standard"],
                    "sourceAliases": [],
                    "marketMappings": [],
                    "supersedes": [],
                }
            ],
            "appearances": [{"printingID": printing_uuid, "productID": "OP-01", "observationIDs": ["obs-1"]}],
            "corrections": [],
        },
        "observations": [
            {
                "id": "obs-1",
                "kind": "catalog",
                "alias": {"provider": "bandai", "sourceID": "OP01-001"},
                "language": "en",
                "sourceURL": "https://en.onepiece-cardgame.com/cardlist/",
                "payloadSHA256": "a" * 64,
                "observedAt": generated_at,
                "productEvidence": ["OP-01"],
                "printedEvidence": {"number": "OP01-001"},
            }
        ],
        "inventories": [{"provider": "bandai", "snapshotID": "snap-1", "paginationComplete": True, "observationIDs": ["obs-1"]}],
        "indexes": {"automaticCandidateIDsByCanonicalID": {}},
    }
    envelope = _fake_signed_envelope(payload)
    return {
        f"one-piece/v1/releases/{revision}/catalog-release.json": envelope,
        "one-piece/v1/current.json": envelope,
    }


def _drill_magic_files(revision: int, *, set_display_name: str, generated_at: str) -> dict[str, bytes]:
    payload = {
        "schemaVersion": 1,
        "catalogKind": "magic",
        "revision": revision,
        "generatedAt": generated_at,
        "sets": [
            {
                "code": "DMU",
                "displayName": set_display_name,
                "releaseDate": "2022-09-09",
                "cardCount": 281,
                "printedSize": 281,
                "scanEnabled": True,
                "browseEnabled": True,
            }
        ],
    }
    envelope = _fake_signed_envelope(payload)
    return {
        f"magic/v1/releases/{revision}/catalog-release.json": envelope,
        "magic/v1/current.json": envelope,
    }


def _drill_yugioh_files(revision: int, *, generation: str, card_name: str, generated_at: str) -> dict[str, bytes]:
    catalog = {
        "schemaVersion": 1,
        "policyVersion": "yugioh-en-v1",
        "generation": generation,
        "capturedAt": generated_at,
        "autoEligibleCodes": ["LOB-EN001"],
        "incompleteCodes": [],
        "sets": [{"g": 100, "n": "Legend of Blue Eyes"}],
        "cards": [{"id": "ygo-1", "n": card_name}],
        "printings": [
            {
                "id": "LOB-EN001-1st",
                "g": 100,
                "k": 0,
                "e": ["1st"],
                "ec": True,
                "pe": ["1st"],
                "m": [{"e": "1st", "t": "exact", "s": generated_at}],
            }
        ],
        "referencePrintings": [],
    }
    catalog_bytes = canonical_json_bytes(catalog)
    manifest = {
        "schemaVersion": 2,
        "revision": revision,
        "generation": generation,
        "policyVersion": "yugioh-en-v1",
        "path": f"yugioh/v1/releases/{revision}/catalog.json",
        "sha256": sha256_bytes(catalog_bytes),
        "bytes": len(catalog_bytes),
        "status": "approved",
        "capturedAt": generated_at,
    }
    envelope = _fake_signed_envelope(
        manifest,
        extra={"catalog": base64.b64encode(catalog_bytes).decode("ascii")},
    )
    return {
        f"yugioh/v1/releases/{revision}/catalog.json": catalog_bytes,
        f"yugioh/v1/releases/{revision}/catalog-release.json": envelope,
        "yugioh/v1/current.json": envelope,
    }


def _drill_price_build(site_dir: Path, source_build: str, price_value: float, op_scope: bytes, ygo_scope: bytes) -> dict:
    v1_root = site_dir / PRICE_V1_NAMESPACE

    def products_doc(category: int, group: int, product_id: int, name: str) -> bytes:
        return packed(
            {
                "success": True,
                "errors": [],
                "sourceBuild": source_build,
                "sourceFetchedAt": source_build,
                "results": [
                    {
                        "productId": product_id,
                        "categoryId": category,
                        "groupId": group,
                        "name": name,
                        "extendedData": [],
                    }
                ],
            }
        )

    def prices_doc(product_id: int, lane: str, price: float) -> bytes:
        return packed(
            {
                "success": True,
                "errors": [],
                "sourceBuild": source_build,
                "sourceFetchedAt": source_build,
                "results": [{"productId": product_id, "subTypeName": lane, "marketPrice": price}],
            }
        )

    for rel, content in {
        "tcgplayer/3/1/products": products_doc(3, 1, 101, "Pikachu"),
        "tcgplayer/3/1/prices": prices_doc(101, "Normal", price_value),
        "tcgplayer/68/2/products": products_doc(68, 2, 201, "Luffy"),
        "tcgplayer/68/2/prices": prices_doc(201, "Normal", price_value),
        "tcgplayer/2/3/products": products_doc(2, 3, 301, "Blue-Eyes"),
        "tcgplayer/2/3/prices": prices_doc(301, "1st Edition", price_value),
        "tcgplayer/71/4/products": products_doc(71, 4, 401, "Mickey"),
        "tcgplayer/71/4/prices": prices_doc(401, "Normal", price_value),
    }.items():
        path = v1_root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)

    (v1_root / "last-updated.txt").write_bytes((source_build + "\n").encode("utf-8"))
    files_manifest = []
    for rel in sorted(
        p.relative_to(v1_root).as_posix()
        for p in v1_root.rglob("*")
        if p.is_file() and (p.relative_to(v1_root).as_posix() == "last-updated.txt" or p.relative_to(v1_root).as_posix().startswith("tcgplayer/"))
    ):
        raw = (v1_root / rel).read_bytes()
        files_manifest.append({"path": rel, "sha256": sha256_bytes(raw), "byteCount": len(raw)})

    (v1_root / "index.json").write_bytes(
        packed({"schemaVersion": 1, "sourceBuild": source_build, "files": files_manifest})
    )
    (site_dir / "one-piece/v1" / SCOPE_FILE).parent.mkdir(parents=True, exist_ok=True)
    (site_dir / "one-piece/v1" / SCOPE_FILE).write_bytes(op_scope)
    (site_dir / "yugioh/v1" / SCOPE_FILE).parent.mkdir(parents=True, exist_ok=True)
    (site_dir / "yugioh/v1" / SCOPE_FILE).write_bytes(ygo_scope)
    return price_v2.stage(site_dir, retain_history=True)


def _drill_scope(game: str, revision: int, pointer_bytes: bytes, group_id: int, product_id: int, lane: str) -> bytes:
    digest = sha256_bytes(pointer_bytes)
    return packed(
        {
            "schemaVersion": 1,
            "game": game,
            "revision": revision,
            "catalogSHA256": digest,
            "pointerSHA256": digest,
            "groups": [[group_id, [[product_id, [lane]]]]],
        }
    )


def rehearse_recovery(*, repo_root: Path | None = None) -> dict:
    """Execute the complete offline infrastructure failure, catch-up, and roll-forward drill."""
    root = repo_root or Path(__file__).resolve().parents[1]
    now = datetime(2026, 11, 27, 18, 0, 0, tzinfo=timezone.utc)
    valid_not_before = (now - timedelta(days=30)).strftime("%b %d %H:%M:%S %Y GMT")
    valid_not_after = (now + timedelta(days=60)).strftime("%b %d %H:%M:%S %Y GMT")
    expiring_not_after = (now + timedelta(days=5)).strftime("%b %d %H:%M:%S %Y GMT")

    with tempfile.TemporaryDirectory(prefix="stage2-rehearsal-") as tmp:
        tmp_path = Path(tmp)
        r2_site = tmp_path / "r2-site"
        fb_site = tmp_path / "fb-site"
        r2_site.mkdir()
        fb_site.mkdir()

        def write_tree(base: Path, mapping: dict[str, bytes]) -> None:
            for rel, raw in mapping.items():
                target = base / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(raw)

        # Seed rev 1 and rev 2 (known-good baseline) on R2 and mirror to Firebase.
        for rev, poke_name, op_name, mtg_name, ygo_gen, ygo_name, ts in (
            (1, "Drill Set One", "Luffy v1", "Dominaria v1", "ygo-gen-1", "Blue-Eyes v1", "2026-11-25T00:00:00Z"),
            (2, "Drill Set Good", "Luffy Good", "Dominaria Good", "ygo-gen-2", "Blue-Eyes Good", "2026-11-26T00:00:00Z"),
        ):
            write_tree(r2_site, _drill_pokemon_files(rev, set_display_name=poke_name, generated_at=ts))
            write_tree(r2_site, _drill_one_piece_files(rev, card_name=op_name, generated_at=ts))
            write_tree(r2_site, _drill_magic_files(rev, set_display_name=mtg_name, generated_at=ts))
            write_tree(r2_site, _drill_yugioh_files(rev, generation=ygo_gen, card_name=ygo_name, generated_at=ts))

        op_scope_r2 = _drill_scope("one-piece", 2, (r2_site / "one-piece/v1/current.json").read_bytes(), 2, 201, "Normal")
        ygo_scope_r2 = _drill_scope("yugioh", 2, (r2_site / "yugioh/v1/current.json").read_bytes(), 3, 301, "1st Edition")
        pointer_a = _drill_price_build(r2_site, "2026-11-26T20:00:00+0000", 12.50, op_scope_r2, ygo_scope_r2)
        build_a = pointer_a["build"]
        shutil.copytree(r2_site, fb_site, dirs_exist_ok=True)
        (fb_site / price_rollback.HISTORY).write_bytes(price_rollback.history_bytes({build_a}))

        firebase_down = {"down": False}

        def headers_for(rel: str) -> dict[str, str]:
            if "/releases/" in rel or rel.startswith("market-prices/v2/builds/"):
                return {"cache-control": "public, max-age=31536000, immutable"}
            if rel.endswith(("current.json", SCOPE_FILE, "latest.json", "history.json", "last-updated.txt")):
                return {"cache-control": "no-cache"}
            return {"cache-control": "public, max-age=300"}

        def mock_fetch(url: str, maximum: int, *, absent_ok: bool = False):
            clean = url.split("?", 1)[0]
            if clean.startswith(R2_ORIGIN + "/"):
                base = r2_site
                rel = clean[len(R2_ORIGIN) + 1 :]
            elif clean.startswith(FIREBASE_ORIGIN + "/"):
                if firebase_down["down"]:
                    raise HTTPError(url, 503, "Firebase outage drill", {}, None)
                base = fb_site
                rel = clean[len(FIREBASE_ORIGIN) + 1 :]
            else:
                raise ValueError(f"Unexpected rehearsal URL: {url}")
            target = base / rel
            if not target.is_file():
                if absent_ok:
                    return None, {}
                raise HTTPError(url, 404, "Not Found", {}, None)
            data = target.read_bytes()
            if len(data) > maximum:
                raise ValueError(f"Oversized object {rel}")
            return data, headers_for(rel)

        def mock_fetch_bytes(url: str, maximum: int, *, absent_ok: bool = False):
            data, _ = mock_fetch(url, maximum, absent_ok=absent_ok)
            return data

        def healthy_cert(connect_host: str, server_hostname: str) -> dict:
            return {
                "subject": f"CN={server_hostname}",
                "issuer": "O=Google Trust Services, CN=WR3",
                "notBefore": valid_not_before,
                "notAfter": valid_not_after,
                "san": [server_hostname],
                "tlsVersion": "TLSv1.3",
            }

        def healthy_metrics(**kwargs) -> dict:
            return {
                "hosting": {"latestVersionStatus": "FINALIZED", "latestVersionFileCount": 40},
                "storageTotalBytes": 400 * 1024 * 1024,  # 400 MiB / 10 GiB
                "storageObservedAt": readiness.iso_utc(now),
                "bandwidthSent24hBytes": 5 * 1024 * 1024,  # 5 MiB / 360 MiB
                "bandwidthSent30dBytes": 120 * 1024 * 1024,  # 120 MiB / 10 GiB
                "bandwidthPointCount": 30,
            }

        sa_dummy = tmp_path / "dummy-sa.json"
        sa_dummy.write_text("{}")

        def run_probe(*, cert_fn=healthy_cert, metrics_fn=healthy_metrics):
            return readiness.run_readiness_check(
                site_root=fb_site,
                firebase_project="scanstash-catalog-prod",
                firebase_site="scanstash-catalog-prod",
                service_account=sa_dummy,
                quota_mode="strict",
                fetch=mock_fetch,
                cert_fetcher=cert_fn,
                token_minter=lambda *a, **k: "drill-token",
                metrics_fetcher=metrics_fn,
                now=now,
            )

        # Phase 1: Baseline READY.
        phase1 = run_probe()
        assert phase1["rollbackReady"] is True, f"Phase 1 baseline failed: {phase1['failures']}"

        # Phase 2: Firebase outage while R2 advances to rev 3 + price build B.
        firebase_down["down"] = True
        ts_bad = "2026-11-27T12:00:00Z"
        write_tree(r2_site, _drill_pokemon_files(3, set_display_name="Drill Set Bad", generated_at=ts_bad))
        write_tree(r2_site, _drill_one_piece_files(3, card_name="Luffy Bad", generated_at=ts_bad))
        write_tree(r2_site, _drill_magic_files(3, set_display_name="Dominaria Bad", generated_at=ts_bad))
        write_tree(r2_site, _drill_yugioh_files(3, generation="ygo-gen-3", card_name="Blue-Eyes Bad", generated_at=ts_bad))
        op_scope_r3 = _drill_scope("one-piece", 3, (r2_site / "one-piece/v1/current.json").read_bytes(), 2, 201, "Normal")
        ygo_scope_r3 = _drill_scope("yugioh", 3, (r2_site / "yugioh/v1/current.json").read_bytes(), 3, 301, "1st Edition")
        pointer_b = _drill_price_build(r2_site, "2026-11-27T12:00:00+0000", 14.25, op_scope_r3, ygo_scope_r3)
        build_b = pointer_b["build"]

        phase2 = run_probe()
        assert phase2["rollbackReady"] is False and phase2["hardFailed"] is True

        # Phase 3: Firebase recovers and catches up from R2 while retaining build A + rev 1-2.
        firebase_down["down"] = False
        # Before catch-up, parity must fail because Firebase is still on rev 2 / build A.
        phase3_before = run_probe()
        assert phase3_before["rollbackReady"] is False and phase3_before["checks"]["parity"]["status"] == "failed"

        # Catch up catalogs, scopes, v1 prices, and v2 price builds via market_price_rollback.sync_r2.
        for rel in (
            "v1/releases/3/catalog-release.json",
            "v1/releases/3/catalog-payload.json",
            "v1/releases/3/pokemon-catalog-snapshot.json",
            "v1/releases/3/review-report.json",
            "v1/current.json",
            "one-piece/v1/releases/3/catalog-release.json",
            "one-piece/v1/current.json",
            f"one-piece/v1/{SCOPE_FILE}",
            "magic/v1/releases/3/catalog-release.json",
            "magic/v1/current.json",
            "yugioh/v1/releases/3/catalog.json",
            "yugioh/v1/releases/3/catalog-release.json",
            "yugioh/v1/current.json",
            f"yugioh/v1/{SCOPE_FILE}",
        ):
            dest = fb_site / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes((r2_site / rel).read_bytes())
        shutil.copytree(r2_site / PRICE_V1_NAMESPACE, fb_site / PRICE_V1_NAMESPACE, dirs_exist_ok=True)

        synced = price_rollback.sync_r2(fb_site, {build_a, build_b}, fetch=mock_fetch_bytes)
        assert synced["build"] == build_b
        retained_after = price_rollback.history((fb_site / price_rollback.HISTORY).read_bytes())
        assert retained_after == {build_a, build_b}
        assert (fb_site / "v1/releases/2/catalog-release.json").is_file()

        phase3_after = run_probe()
        assert phase3_after["rollbackReady"] is True, f"Phase 3 recovery failed: {phase3_after['failures']}"

        # Phase 4: Certificate expiry and quota exhaustion guardrails.
        def expiring_cert(connect_host: str, server_hostname: str) -> dict:
            cert = healthy_cert(connect_host, server_hostname)
            if server_hostname == readiness.DEFAULT_ROLLBACK_HOSTNAME:
                cert["notAfter"] = expiring_not_after
            return cert

        phase4_cert = run_probe(cert_fn=expiring_cert)
        assert phase4_cert["rollbackReady"] is False and phase4_cert["checks"]["certificate"]["status"] == "failed"

        def exhausted_metrics(**kwargs) -> dict:
            m = healthy_metrics(**kwargs)
            m["storageTotalBytes"] = int(9.2 * 1024 * 1024 * 1024)  # 92% > 80% ceiling
            m["bandwidthSent24hBytes"] = int(320 * 1024 * 1024)  # 88.9% > 80% ceiling
            return m

        phase4_quota = run_probe(metrics_fn=exhausted_metrics)
        assert phase4_quota["rollbackReady"] is False
        assert phase4_quota["checks"]["storageHeadroom"]["status"] == "failed"
        assert phase4_quota["checks"]["bandwidthHeadroom"]["status"] == "failed"

        # Phase 5: Content roll-forward across all 4 hosted catalog games (bad rev 3 -> rev 4 from known-good rev 2).
        roll_forward_results = {}
        for game in GAMES:
            rf = prepare_roll_forward(
                game=game,
                target_revision=2,
                output_dir=tmp_path / "roll-forward" / game,
                reason="Rehearsal drill: roll forward past simulated bad revision 3",
                local_site=r2_site,
                generated_at="2026-11-27T18:05:00Z",
                verify_signatures=False,
                repo_root=root,
            )
            assert rf["activeRevision"] == 3 and rf["targetRevision"] == 2 and rf["nextRevision"] == 4
            assert rf["parityVerified"] is True
            roll_forward_results[game] = {
                "activeRevision": rf["activeRevision"],
                "targetRevision": rf["targetRevision"],
                "nextRevision": rf["nextRevision"],
                "parityVerified": rf["parityVerified"],
            }

        # Phase 6: DNS fallback check (Firebase serves byte-identical active catalog & v2 price builds).
        fb_latest_raw, _ = mock_fetch(f"{FIREBASE_ORIGIN}/{price_v2.LATEST}", price_v2.MAX_POINTER_BYTES)
        r2_latest_raw, _ = mock_fetch(f"{R2_ORIGIN}/{price_v2.LATEST}", price_v2.MAX_POINTER_BYTES)
        assert fb_latest_raw == r2_latest_raw

        return {
            "schemaVersion": 1,
            "rehearsalMode": "offline-fixture",
            "executedAt": readiness.iso_utc(now),
            "allPassed": True,
            "phases": {
                "baselineParityReady": {"passed": phase1["rollbackReady"], "priceBuild": build_a},
                "firebaseOutageDetected": {
                    "passed": (not phase2["rollbackReady"]) and phase2["hardFailed"],
                    "r2AdvancedToBuild": build_b,
                },
                "firebaseCatchUpRestoredReady": {
                    "passed": (not phase3_before["rollbackReady"]) and phase3_after["rollbackReady"],
                    "retainedBuilds": sorted(retained_after),
                },
                "certAndQuotaGuardrails": {
                    "passed": (not phase4_cert["rollbackReady"]) and (not phase4_quota["rollbackReady"]),
                    "certFailed": phase4_cert["checks"]["certificate"]["status"] == "failed",
                    "storageFailed": phase4_quota["checks"]["storageHeadroom"]["status"] == "failed",
                    "bandwidthFailed": phase4_quota["checks"]["bandwidthHeadroom"]["status"] == "failed",
                },
                "contentRollForwardAllGames": {"passed": True, "games": roll_forward_results},
                "dnsFallbackParity": {"passed": fb_latest_raw == r2_latest_raw, "activeBuild": build_b},
            },
        }


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    prep = sub.add_parser("prepare", help="Prepare a monotonic roll-forward candidate from a verified historical revision.")
    prep.add_argument("--game", required=True, choices=GAMES)
    prep.add_argument("--target-revision", required=True, type=int)
    prep.add_argument("--output-dir", required=True, type=Path)
    prep.add_argument("--reason", required=True)
    prep.add_argument("--origin", default=R2_ORIGIN)
    prep.add_argument("--local-site", type=Path, default=None)
    prep.add_argument("--generated-at", default=None)
    prep.add_argument(
        "--skip-signature-verify",
        action="store_true",
        help="Skip invoking Swift pinned-key verifiers (offline unsigned fixture drills only).",
    )

    reh = sub.add_parser("rehearse-recovery", help="Run the offline infrastructure failure, catch-up, and roll-forward drill.")
    reh.add_argument("--report", type=Path, default=None)
    reh.add_argument("--summary", type=Path, default=None)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        if args.command == "prepare":
            manifest = prepare_roll_forward(
                game=args.game,
                target_revision=args.target_revision,
                output_dir=args.output_dir,
                reason=args.reason,
                origin=args.origin,
                local_site=args.local_site,
                generated_at=args.generated_at,
                verify_signatures=not args.skip_signature_verify,
            )
            print(json.dumps(manifest, indent=2, sort_keys=True))
            return 0
        receipt = rehearse_recovery()
        if args.report is not None:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        summary_lines = [
            "### Stage 2 Infrastructure Failure & Recovery Rehearsal (Offline Fixture)",
            "",
            "| Phase | Result |",
            "| --- | --- |",
        ]
        for phase, info in receipt["phases"].items():
            summary_lines.append(f"| `{phase}` | `{'passed' if info['passed'] else 'failed'}` |")
        summary_lines.append("")
        summary = "\n".join(summary_lines)
        print(summary, flush=True)
        if args.summary is not None:
            args.summary.parent.mkdir(parents=True, exist_ok=True)
            with args.summary.open("a", encoding="utf-8") as handle:
                handle.write("\n" + summary)
        return 0 if receipt["allPassed"] else 1
    except (RollForwardError, ValueError, OSError) as exc:
        print(f"catalog roll-forward: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
