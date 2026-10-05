"""Export the app's checked-in One Piece trust anchors for release verification."""
import argparse
import base64
import json
from pathlib import Path


def pinned_keys(configuration: str) -> dict[str, str]:
    assignments = [line.split("=", 1)[1].strip() for line in configuration.splitlines()
                   if line.strip().startswith("ONE_PIECE_CATALOG_PINNED_KEYS =")]
    if len(assignments) != 1 or not assignments[0]:
        raise ValueError("The app must pin dedicated One Piece public keys before signing")
    keys = {}
    for entry in assignments[0].split(","):
        key_id, encoded = (part.strip() for part in entry.split(":", 1))
        if not key_id.startswith("one-piece-") or key_id == "one-piece-" or key_id in keys:
            raise ValueError("Invalid or duplicate One Piece key ID")
        normalized = encoded.replace("-", "+").replace("_", "/")
        raw = base64.b64decode(normalized + "=" * (-len(normalized) % 4), validate=True)
        if len(raw) != 32:
            raise ValueError("Public keys must contain 32 bytes")
        keys[key_id] = base64.b64encode(raw).decode("ascii")
    return keys


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.write_text(json.dumps(pinned_keys(args.configuration.read_text()), sort_keys=True) + "\n")
