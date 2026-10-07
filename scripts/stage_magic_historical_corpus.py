#!/usr/bin/env python3
"""Stage hash-pinned private corpus images in an external build's test bundle.

Run after build-for-testing and before test-without-building. Originals remain
unchanged; no source archive scripts are executed and no images enter the repo.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path
from build_magic_historical_index import validate_page


def stage(manifest, images, bundle, provider_search, general_captures=None):
    data = json.loads(manifest.read_text())
    if data.get("schemaVersion") != 1 or not bundle.is_dir() or bundle.suffix != ".xctest":
        raise ValueError("version-1 manifest and existing test bundle required")
    rows = data["records"]
    names = [row["filename"] for row in rows]
    if len(set(names)) != len(names) or len(set(row["index"] for row in rows)) != len(rows):
        raise ValueError("duplicate corpus identity")
    for row in rows:
        name = row["filename"]
        if Path(name).name != name or not name.endswith(".jpg"):
            raise ValueError("local JPEG filename required")
        if hashlib.sha256((images / name).read_bytes()).hexdigest() != row["sha256"]:
            raise ValueError("corpus source changed: " + name)
    # Validate every input before writing any bundle resources.
    if hashlib.sha256(provider_search.read_bytes()).hexdigest() != data["providerSearchSHA256"]:
        raise ValueError("provider capture changed")
    validate_page(json.loads(provider_search.read_text()))
    if general_captures is not None:
        if hashlib.sha256(general_captures.read_bytes()).hexdigest() != data["generalProviderCaptureSHA256"]:
            raise ValueError("general provider captures changed")
    target = bundle / "MagicHistoricalCorpus"
    target.mkdir(exist_ok=True)
    for name in names:
        shutil.copyfile(images / name, target / name)
    shutil.copyfile(manifest, target / "evaluation.json")
    shutil.copyfile(provider_search, target / "Survival-search.json")
    if general_captures is not None:
        shutil.copyfile(general_captures, target / "general-provider-captures.json")
    return len(rows)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--images", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--provider-search", type=Path, required=True)
    parser.add_argument("--general-provider-captures", type=Path)
    args = parser.parse_args()
    print("Staged images:", stage(args.manifest, args.images, args.bundle, args.provider_search, args.general_provider_captures))
