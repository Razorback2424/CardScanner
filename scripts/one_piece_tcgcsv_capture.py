"""Bounded, paced TCGCSV capture/replay for the supplied catalog builder.

One capture directory represents one upstream daily build. Reusing it replays
retained bytes, never silently refreshes or overwrites a prior response.
"""
from __future__ import annotations

import hashlib
import json
import math
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from urllib.request import Request, urlopen

MAX_BYTES = 32 * 1024 * 1024


def timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def validate_document(doc: object, url: str) -> dict:
    if not isinstance(doc, dict) or doc.get("success") is not True or doc.get("errors") != []:
        raise ValueError(f"Failed or malformed TCGCSV response: {url}")
    rows = doc.get("results")
    if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
        raise ValueError(f"Missing result objects: {url}")
    if not url.endswith("/prices"):
        total = doc.get("totalItems")
        # Empty presale product exports sometimes omit totalItems entirely.
        # Retain the source gap explicitly; it is not a complete inventory.
        if url.endswith("/products") and total is None and rows == []:
            return dict(doc, sourceInventoryComplete=False, sourceInventoryIssue="empty_export_without_totalItems")
        if type(total) is not int or total != len(rows):
            raise ValueError(f"Incomplete result inventory: {url}")
    if any(key in doc for key in ("next", "nextPage", "hasMore", "continuationToken")):
        raise ValueError(f"Unsupported pagination contract: {url}")
    return doc


class TCGCSVSnapshot:
    def __init__(self, directory: Path, user_agent: str, delay: float, offline: bool = False):
        if not math.isfinite(delay) or delay < 0.10:
            raise ValueError("TCGCSV requests must be paced at least 100 ms apart")
        if not user_agent.strip() or "/" not in user_agent or "\n" in user_agent or "\r" in user_agent:
            raise ValueError("A custom versioned User-Agent is required")
        self.directory = directory
        self.user_agent = user_agent
        self.delay = delay
        self.offline = offline
        self.request_count = 0
        directory.mkdir(parents=True, exist_ok=True)
        self.manifest_path = directory / "captures.json"
        if self.manifest_path.exists():
            self.manifest = json.loads(self.manifest_path.read_text())
            if self.manifest.get("schemaVersion") != 1:
                raise ValueError("Unsupported retained capture manifest")
        else:
            self.manifest = {"schemaVersion": 1, "startedAt": timestamp(), "complete": False, "captures": {}}
        start = self._bytes("https://tcgcsv.com/last-updated.txt", "last-updated-start.txt")
        self.upstream_build = start.decode("utf-8").strip()
        if not self.upstream_build or len(self.upstream_build) > 100:
            raise ValueError("Invalid upstream daily-build marker")

    def _save(self) -> None:
        encoded = (json.dumps(self.manifest, indent=2, sort_keys=True) + "\n").encode()
        if self.manifest_path.exists() and self.manifest_path.read_bytes() == encoded:
            return
        temporary = self.manifest_path.with_suffix(".tmp")
        temporary.write_bytes(encoded)
        temporary.replace(self.manifest_path)

    def _bytes(self, url: str, filename: str, key: str | None = None) -> bytes:
        key = key or url
        record = self.manifest["captures"].get(key)
        path = self.directory / filename
        if record is not None:
            if record["rawFile"] != filename:
                raise ValueError("Retained response path changed")
            raw = path.read_bytes()
            if len(raw) != record["byteCount"] or hashlib.sha256(raw).hexdigest() != record["payloadSHA256"]:
                raise ValueError(f"Retained response bytes changed: {filename}")
            return raw
        if self.offline:
            raise ValueError(f"Offline capture missing: {url}")
        age = datetime.now(timezone.utc) - datetime.fromisoformat(self.manifest["startedAt"])
        if age.total_seconds() > 24 * 60 * 60:
            raise ValueError("Cannot extend a retained snapshot after 24 hours; create a newly reviewed daily capture")
        if path.exists():
            raise ValueError(f"Untracked response file would be overwritten: {filename}")
        if self.request_count >= 1_000:
            raise ValueError("One Piece capture exceeded its request budget")
        # Sleep before every request, including marker/first-product requests.
        time.sleep(self.delay)
        self.request_count += 1
        request = Request(url, headers={"User-Agent": self.user_agent, "Accept": "application/json,text/plain"})
        with urlopen(request, timeout=45) as response:
            if response.geturl() != url:
                raise ValueError("Unexpected capture redirect")
            raw = response.read(MAX_BYTES + 1)
        if len(raw) > MAX_BYTES:
            raise ValueError(f"Response exceeds capture byte limit: {url}")
        path.write_bytes(raw)
        self.manifest["captures"][key] = {"sourceURL": url, "rawFile": filename,
            "payloadSHA256": hashlib.sha256(raw).hexdigest(), "byteCount": len(raw), "observedAt": timestamp()}
        self.manifest["complete"] = False
        self._save()
        return raw

    def fetch_json(self, url: str) -> dict:
        if not re.fullmatch(r"https://tcgcsv\.com/tcgplayer/68/(?:groups|[1-9][0-9]*/(?:products|prices))", url):
            raise ValueError("Only One Piece category 68 on the documented TCGCSV origin is allowed")
        filename = url.removeprefix("https://tcgcsv.com/tcgplayer/").replace("/", "-") + ".json"
        raw = self._bytes(url, filename)
        return validate_document(json.loads(raw), url)

    def finish(self) -> None:
        # Retain both marker responses without overwriting the starting bytes.
        url = "https://tcgcsv.com/last-updated.txt"
        end = self._bytes(url, "last-updated-end.txt", key=url + "#end")
        if end.decode("utf-8").strip() != self.upstream_build:
            raise ValueError("Upstream daily build changed during capture; do not treat mixed responses as one inventory")
        self.manifest["upstreamBuild"] = self.upstream_build
        self.manifest["complete"] = True
        self._save()
