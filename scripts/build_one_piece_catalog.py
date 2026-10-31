#!/usr/bin/env python3
"""
Build a printing-level English ONE PIECE Card Game catalog from TCGCSV.

Source product identity (not physical ownership identity):
    catalog_id = "tcgplayer:<productId>"

Why:
TCGplayer uses a separate productId for collector-facing printings/variants even
when several products share the same printed card number (OP01-016, P-085, etc.).
That makes productId a strong external printing identity while card_number remains
the gameplay/card-family identity.

Outputs:
  one_piece_catalog.csv
  one_piece_catalog.json
  one_piece_groups.csv
  one_piece_catalog_audit.json

No third-party Python packages are required.
"""

from __future__ import annotations

import argparse
import csv
import html
import io
import json
import re
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from one_piece_tcgcsv_capture import TCGCSVSnapshot

CATEGORY_ID = 68
DEFAULT_BASE = "https://tcgcsv.com/tcgplayer"
DEFAULT_UA = "Scanstash-OnePiece-CatalogBuilder/1.0"
DEFAULT_DELAY = 0.12  # TCGCSV asks for at least ~100 ms between requests.

SEALED_SIGNALS = (
    "booster box", "booster pack", "sleeved booster", "display", " case",
    "deck box", "playmat", "sleeves", "binder", "(bundle)", "card case",
    "storage box", "double pack set", "gift collection", "collection box",
    "starter deck display", "starter deck case", "booster bundle",
)

VARIANT_PATTERNS = [
    ("super_leader_alt_art", re.compile(r"super leader alternate art", re.I)),
    ("super_alt_art", re.compile(r"super alternate art", re.I)),
    ("manga", re.compile(r"\bmanga\b", re.I)),
    ("treasure_rare", re.compile(r"(?:\btreasure rare\b|\(tr\))", re.I)),
    ("sp", re.compile(r"(?:\(\s*sp\s*\)|\bsp card\b)", re.I)),
    ("serial_numbered", re.compile(r"(?:serial(?:ized| numbered)?|numbered\s*/\s*\d+)", re.I)),
    ("signature", re.compile(r"(?:signature|signed|autograph)", re.I)),
    ("winner_champion", re.compile(r"(?:winner|champion|1st place)", re.I)),
    ("finalist_top", re.compile(r"(?:finalist|top player|top 8|top 16|2nd place|3rd place)", re.I)),
    ("participant", re.compile(r"(?:participant|participation)", re.I)),
    ("judge", re.compile(r"\bjudge\b", re.I)),
    ("regional", re.compile(r"\bregional\b", re.I)),
    ("treasure_cup", re.compile(r"treasure cup", re.I)),
    ("store_championship", re.compile(r"store championship", re.I)),
    ("anniversary", re.compile(r"anniversary", re.I)),
    ("celebration", re.compile(r"celebration", re.I)),
    ("release_event", re.compile(r"release event", re.I)),
    ("pre_release", re.compile(r"pre[- ]?release", re.I)),
    ("tournament", re.compile(r"tournament", re.I)),
    ("winner_pack", re.compile(r"winner pack", re.I)),
    ("event_pack", re.compile(r"event pack", re.I)),
    ("promotion_pack", re.compile(r"promotion pack", re.I)),
    ("illustration_box", re.compile(r"illustration box", re.I)),
    ("premium_card_collection", re.compile(r"premium card collection", re.I)),
    ("sealed_battle", re.compile(r"sealed battle", re.I)),
    ("demo_deck", re.compile(r"demo deck", re.I)),
    ("revision", re.compile(r"\brevision\b", re.I)),
    ("wanted_poster", re.compile(r"wanted poster", re.I)),
    ("jolly_roger_foil", re.compile(r"jolly roger", re.I)),
    ("full_art", re.compile(r"full art", re.I)),
    ("gold", re.compile(r"\bgold\b", re.I)),
    ("special_foil", re.compile(r"special foil", re.I)),
    ("pandaman_art", re.compile(r"pandaman art", re.I)),
    ("reprint", re.compile(r"\breprint\b", re.I)),
    ("alternate_art", re.compile(r"(?:alternate art|\bparallel\b)", re.I)),
]

PRIORITY = [x[0] for x in VARIANT_PATTERNS]

def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()

def write_output(path: Path, text: str, encoding: str = "utf-8") -> None:
    content = text.encode(encoding)
    if path.exists():
        if path.read_bytes() != content:
            raise ValueError(f"Refusing to replace changed reviewed output: {path}")
        return
    path.write_bytes(content)

def ext_map(product: dict[str, Any]) -> dict[str, str]:
    out: dict[str, str] = {}
    for item in product.get("extendedData") or []:
        key = str(item.get("name") or "").strip()
        if key:
            value = str(item.get("value") or "").strip()
            if key in out and out[key] != value:
                raise ValueError(f"Conflicting extended field: {key}")
            out[key] = value
    return out

def strip_html(value: str) -> str:
    value = re.sub(r"<br\s*/?>", "\n", value or "", flags=re.I)
    value = re.sub(r"<[^>]+>", "", value)
    return html.unescape(value).replace("\r", "").strip()

def is_don(name: str, ext: dict[str, str]) -> bool:
    return name.strip().upper().startswith("DON!!") or ext.get("CardType", "").lower() == "don!!"

def sealed_signal(name: str) -> str | None:
    n = f" {name.lower()} "
    for s in SEALED_SIGNALS:
        if s in n:
            return s.strip()
    return None

def classify_variant(name: str, group_name: str) -> tuple[str, list[str]]:
    text = f"{name} | {group_name}"
    labels = [label for label, rx in VARIANT_PATTERNS if rx.search(text)]
    # Group-level event context matters even when the product title itself is plain.
    gl = group_name.lower()
    group_labels = []
    for label, phrase in (
        ("release_event", "release event"),
        ("pre_release", "pre-release"),
        ("anniversary", "anniversary"),
        ("promotion", "promotion cards"),
    ):
        if phrase in gl and label not in labels:
            group_labels.append(label)
    labels.extend(group_labels)
    if not labels:
        return "base_or_standard", []
    for p in PRIORITY:
        if p in labels:
            return p, labels
    return labels[0], labels

def price_summary(price_rows: list[dict[str, Any]]) -> dict[str, Any]:
    by_subtype = {}
    for p in price_rows:
        subtype = str(p.get("subTypeName") or "").strip()
        if subtype:
            by_subtype[subtype] = p.get("marketPrice")
    return {
        "market_price_normal": by_subtype.get("Normal"),
        "market_price_foil": by_subtype.get("Foil"),
        "price_lanes": price_rows,
    }

def card_status(product: dict[str, Any], group_name: str, ext: dict[str, str]) -> tuple[str, str]:
    """
    Returns (status, reason).
    We prefer inclusion over silent loss:
    - numbered/typed products are definitely cards,
    - DON!! is a card despite often lacking a printed Number,
    - unnumbered products in promo/event groups are retained as candidates unless
      they have a strong sealed/accessory signal.
    """
    name = str(product.get("name") or "")
    sig = sealed_signal(name)
    if sig and (ext.get("Number") or ext.get("CardType") or ext.get("Rarity")):
        return "metadata_conflict_candidate", f"card_metadata_and_sealed_signal:{sig}"
    if ext.get("Number"):
        return "card", "has_printed_number"
    if ext.get("CardType") or ext.get("Rarity"):
        return "card", "has_card_metadata"
    if is_don(name, ext):
        return "card", "don_card"
    sig = sealed_signal(name)
    if sig:
        return "excluded_non_card_product", f"sealed_or_accessory_signal:{sig}"
    gl = group_name.lower()
    if any(x in gl for x in ("promotion", "event", "pre-release", "anniversary", "revision", "demo deck")):
        return "unnumbered_card_candidate", "promo_or_event_group_without_card_metadata"
    return "excluded_non_card_product", "no_card_metadata"

def build(args: argparse.Namespace) -> None:
    base = args.base.rstrip("/")
    if base != DEFAULT_BASE:
        raise ValueError("The catalog builder accepts only the documented TCGCSV origin")
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    capture = TCGCSVSnapshot(Path(args.capture_dir) if args.capture_dir else output_dir / "source",
                            args.user_agent, args.delay, args.offline)
    groups_doc = capture.fetch_json(f"{base}/{CATEGORY_ID}/groups")
    groups = groups_doc["results"]
    if not groups or len({g.get("groupId") for g in groups}) != len(groups):
        raise ValueError("Empty or duplicate group inventory")
    if any(type(g.get("groupId")) is not int or g["groupId"] <= 0 or g.get("categoryId") != CATEGORY_ID for g in groups):
        raise ValueError("Invalid category/group identity")
    groups.sort(key=lambda x: (x.get("publishedOn") or "", x.get("groupId") or 0))

    catalog: list[dict[str, Any]] = []
    excluded: list[dict[str, Any]] = []
    group_rows: list[dict[str, Any]] = []

    for idx, group in enumerate(groups, 1):
        gid = int(group["groupId"])
        gname = str(group.get("name") or "")
        print(f"[{idx:>3}/{len(groups)}] {gid}  {gname}", flush=True)

        prod_doc = capture.fetch_json(f"{base}/{CATEGORY_ID}/{gid}/products")
        products = prod_doc["results"]
        prices = capture.fetch_json(f"{base}/{CATEGORY_ID}/{gid}/prices")["results"] if args.include_prices else []
        if len({p.get("productId") for p in products}) != len(products) or any(
            type(p.get("productId")) is not int or p["productId"] <= 0
            or p.get("categoryId") != CATEGORY_ID or p.get("groupId") != gid for p in products
        ):
            raise ValueError(f"Invalid/duplicate product identity in group {gid}")
        if any(p.get("productId") not in {row["productId"] for row in products} for p in prices):
            raise ValueError(f"Price lane references unknown product in group {gid}")
        price_by_product: dict[int, list[dict[str, Any]]] = {}
        for p in prices:
            if p.get("productId") is not None:
                price_by_product.setdefault(int(p["productId"]), []).append(p)

        kept = 0
        for product in products:
            ext = ext_map(product)
            status, reason = card_status(product, gname, ext)
            pid = int(product["productId"])
            if status == "excluded_non_card_product":
                excluded.append({
                    "tcgplayer_product_id": pid,
                    "group_id": gid,
                    "group_name": gname,
                    "product_name": product.get("name"),
                    "reason": reason,
                })
                continue

            kept += 1
            name = str(product.get("name") or "")
            variant_class, variant_labels = classify_variant(name, gname)
            ps = price_summary(price_by_product.get(pid, []))
            number = ext.get("Number") or ""
            rarity = ext.get("Rarity") or ""
            card_type = ext.get("CardType") or ("DON!!" if is_don(name, ext) else "")
            description_html = ext.get("Description") or ""

            row = {
                "catalog_id": f"tcgplayer:{pid}",
                "tcgplayer_product_id": pid,
                "tcgplayer_group_id": gid,
                "group_name": gname,
                "group_abbreviation": group.get("abbreviation") or "",
                "group_published_on": group.get("publishedOn") or "",
                "is_supplemental_group": bool(group.get("isSupplemental")),
                "product_name": name,
                "clean_name": product.get("cleanName") or "",
                "printed_card_number": number,
                "gameplay_identity": number or None,
                "rarity": rarity,
                "card_type": card_type,
                "color": ext.get("Color") or "",
                "cost": ext.get("Cost") or "",
                "life": ext.get("Life") or "",
                "power": ext.get("Power") or "",
                "counter": ext.get("Counter") or "",
                "attribute": ext.get("Attribute") or "",
                "subtypes": ext.get("Subtypes") or "",
                "effect_text": strip_html(description_html),
                "effect_html": description_html,
                "variant_class": variant_class,
                "variant_labels": variant_labels,
                "is_parallel_or_alt": variant_class in {"alternate_art", "super_alt_art", "super_leader_alt_art"} or "alternate_art" in variant_labels,
                "is_manga": "manga" in variant_labels,
                "is_sp": "sp" in variant_labels,
                "is_treasure_rare": "treasure_rare" in variant_labels,
                "is_serial_numbered": "serial_numbered" in variant_labels,
                "is_winner_or_champion": "winner_champion" in variant_labels,
                "is_participant": "participant" in variant_labels,
                "is_judge": "judge" in variant_labels,
                "catalog_status": status,
                "catalog_status_reason": reason,
                "image_url": product.get("imageUrl") or "",
                "tcgplayer_url": product.get("url") or "",
                "modified_on": product.get("modifiedOn") or "",
                "is_presale": bool((product.get("presaleInfo") or {}).get("isPresale")),
                "market_price_normal": ps["market_price_normal"],
                "market_price_foil": ps["market_price_foil"],
                "price_lanes": ps["price_lanes"],
                "extended_data": product.get("extendedData") or [],
            }
            catalog.append(row)

        group_rows.append({
            "group_id": gid,
            "group_name": gname,
            "abbreviation": group.get("abbreviation") or "",
            "published_on": group.get("publishedOn") or "",
            "modified_on": group.get("modifiedOn") or "",
            "is_supplemental": bool(group.get("isSupplemental")),
            "source_product_count": len(products),
            "source_inventory_complete": prod_doc.get("sourceInventoryComplete", True),
            "source_inventory_issue": prod_doc.get("sourceInventoryIssue"),
            "catalog_card_count": kept,
        })

    catalog.sort(key=lambda r: (
        r["printed_card_number"] or "~",
        r["group_published_on"] or "",
        r["tcgplayer_group_id"],
        r["tcgplayer_product_id"],
    ))

    capture.finish()
    generated_at = capture.manifest["startedAt"]
    json_payload = {
        "meta": {
            "generated_at": generated_at,
            "category_id": CATEGORY_ID,
            "source": "TCGCSV / TCGplayer catalog",
            "source_base": base,
            "upstream_build": capture.upstream_build,
            "physical_coverage_complete": False,
            "price_lanes_requested": args.include_prices,
            "identity_model": {
                "source_product": "tcgplayer_product_id (market alias, not an app-owned printing UUID)",
                "gameplay_or_card_family": "printed_card_number when present",
                "note": "Multiple physical/market printings may share the same printed card number.",
            },
        },
        "cards": catalog,
    }
    write_output(output_dir / "one_piece_catalog.json", json.dumps(json_payload, ensure_ascii=False, indent=2))

    scalar_fields = [
        "catalog_id","tcgplayer_product_id","tcgplayer_group_id","group_name","group_abbreviation",
        "group_published_on","is_supplemental_group","product_name","clean_name","printed_card_number",
        "gameplay_identity","rarity","card_type","color","cost","life","power","counter","attribute",
        "subtypes","effect_text","variant_class","variant_labels","is_parallel_or_alt","is_manga",
        "is_sp","is_treasure_rare","is_serial_numbered","is_winner_or_champion","is_participant",
        "is_judge","catalog_status","catalog_status_reason","image_url","tcgplayer_url","modified_on",
        "is_presale","market_price_normal","market_price_foil"
    ]
    with io.StringIO(newline="") as f:
        w = csv.DictWriter(f, fieldnames=scalar_fields)
        w.writeheader()
        for r in catalog:
            out = {k: r.get(k) for k in scalar_fields}
            out["variant_labels"] = ";".join(r["variant_labels"])
            w.writerow(out)
        write_output(output_dir / "one_piece_catalog.csv", f.getvalue(), "utf-8-sig")

    with io.StringIO(newline="") as f:
        fields = list(group_rows[0].keys()) if group_rows else []
        w = csv.DictWriter(f, fieldnames=fields)
        if fields:
            w.writeheader()
            w.writerows(group_rows)
        write_output(output_dir / "one_piece_groups.csv", f.getvalue(), "utf-8-sig")

    audit = {
        "generated_at": generated_at,
        "category_id": CATEGORY_ID,
        "group_count": len(groups),
        "all_declared_group_inventories_complete": all(g["source_inventory_complete"] for g in group_rows),
        "incomplete_group_inventories": [g["group_id"] for g in group_rows if not g["source_inventory_complete"]],
        "catalog_row_count": len(catalog),
        "numbered_card_rows": sum(bool(r["printed_card_number"]) for r in catalog),
        "unnumbered_card_candidates": sum(r["catalog_status"] == "unnumbered_card_candidate" for r in catalog),
        "don_rows": sum(r["card_type"] == "DON!!" for r in catalog),
        "excluded_non_card_products": len(excluded),
        "unique_printed_card_numbers": len({r["printed_card_number"] for r in catalog if r["printed_card_number"]}),
        "variant_class_counts": {},
        "group_counts": group_rows,
        "excluded_examples": excluded[:100],
        "reference_only_not_validation_rule": {
            "pullnomics_2026_10_03_cards_tracked": 7255,
            "pullnomics_2026_10_03_sets_and_promo_groups": 85,
            "note": "Use only as a rough completeness benchmark; Pullnomics and this builder may classify future, sealed, unnumbered, and event products differently."
        }
    }
    for r in catalog:
        vc = r["variant_class"]
        audit["variant_class_counts"][vc] = audit["variant_class_counts"].get(vc, 0) + 1
    write_output(output_dir / "one_piece_catalog_audit.json", json.dumps(audit, ensure_ascii=False, indent=2))

    print()
    print(f"Catalog rows: {len(catalog):,}")
    print(f"Groups:       {len(groups):,}")
    print(f"Excluded:     {len(excluded):,}")
    print(f"Output:       {output_dir.resolve()}")

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--output-dir", default="one_piece_catalog_output")
    ap.add_argument("--base", default=DEFAULT_BASE)
    ap.add_argument("--user-agent", default=DEFAULT_UA)
    ap.add_argument("--delay", type=float, default=DEFAULT_DELAY)
    ap.add_argument("--capture-dir", help="Persistent daily raw-response snapshot; reusing it avoids repeated HTTP pulls")
    ap.add_argument("--offline", action="store_true", help="Replay retained bytes only")
    ap.add_argument("--include-prices", action="store_true", help="Retain unreviewed source price lanes, never app quotes")
    args = ap.parse_args()
    build(args)

if __name__ == "__main__":
    main()
