#!/usr/bin/env python3
"""Publish a signed One Piece catalog release to R2 first, then back up Firebase.

Runs the same checks as `.github/workflows/one-piece-catalog.yml` without a
GitHub-hosted runner, publishes directly to Cloudflare R2 and reads back the
immutable release, scope and pointer, then optionally backs up the complete
shared site from R2 to Firebase Hosting. Signing stays in GitHub; this script
only publishes an already signed artifact.

Every step runs in a fresh detached worktree of `origin/main` under --work-dir,
so local edits never reach production. Put --work-dir on the external SSD.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ORIGINS = ("https://scanstash-catalog-prod.web.app", "https://catalog.scan-stash.com")
R2_ORIGIN = "https://catalog-staging.scan-stash.com"
PROJECT = "scanstash-catalog-prod"
REPOSITORY = "Razorback2424/CardScanner"
WORKFLOW_PATH = ".github/workflows/one-piece-catalog.yml"
SITE_ROOT = "publisher/site"
# Every namespace the shared site can serve. A Firebase deploy replaces the whole
# site, so each one that is live must be present and unchanged in the staged tree.
PRESERVED_POINTERS = ("v1/current.json", "magic/v1/current.json", "yugioh/v1/current.json",
                      "lorcana/v1/current.json", "market-prices/v1/index.json")
ONE_PIECE_POINTER = "one-piece/v1/current.json"
MARKET_SCOPES = ("one-piece/v1/market-price-scope.json", "yugioh/v1/market-price-scope.json")
# Workflows that publish to R2 or deploy the shared Firebase backup site.
SHARED_SITE_WORKFLOWS = ("one-piece-catalog.yml", "magic-catalog.yml", "pokemon-catalog.yml", "yugioh-catalog.yml")
DIGEST = re.compile(r"[0-9a-f]{64}\Z")


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--signed-run-id", help="Successful One Piece signing run on main")
    source.add_argument("--artifact-dir", type=Path, help="Already downloaded signed artifact directory")
    parser.add_argument("--reviewed-sha256", required=True, help="SHA-256 of the reviewed payload")
    parser.add_argument("--envelope-sha256", required=True, help="SHA-256 of the reviewed signed envelope")
    parser.add_argument("--manifest-sha256", required=True, help="SHA-256 of the reviewed verified manifest")
    parser.add_argument("--work-dir", type=Path, required=True, help="Scratch directory (external SSD)")
    parser.add_argument("--bootstrap", action="store_true", help="First publication at revision one")
    parser.add_argument("--r2-bucket", default=os.environ.get("R2_BUCKET_NAME"),
                        help="Target R2 bucket name (default: R2_BUCKET_NAME)")
    parser.add_argument("--r2-account-id", default=os.environ.get("R2_ACCOUNT_ID"),
                        help="32-hex Cloudflare account ID (default: R2_ACCOUNT_ID)")
    parser.add_argument("--skip-firebase-backup", action="store_true",
                        help="Publish and verify on R2 without backing up to Firebase")
    parser.add_argument("--skip-github-run-check", action="store_true",
                        help="Do not refuse when GitHub catalog runs are queued or running")
    parser.add_argument("--yes", action="store_true", help="Deploy without the interactive confirmation")
    args = parser.parse_args(argv)
    for name in ("reviewed_sha256", "envelope_sha256", "manifest_sha256"):
        if not DIGEST.match(getattr(args, name)):
            parser.error(f"--{name.replace('_', '-')} must be 64 lowercase hex characters")
    if args.signed_run_id is not None and not args.signed_run_id.isdigit():
        parser.error("--signed-run-id must be numeric")
    return args


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(command, cwd=None, capture=False, env=None):
    print("+ " + " ".join(str(part) for part in command), flush=True)
    result = subprocess.run([str(part) for part in command], cwd=cwd, check=True, text=True,
                            env=env, stdout=subprocess.PIPE if capture else None)
    return result.stdout if capture else None


def fetch(url, absent_ok=True):
    """Return (bytes, headers) or None for a 404 when absent_ok."""
    request = Request(url, headers={"User-Agent": "ScanStashLocalPublisher/1.0", "Cache-Control": "no-cache"})
    for attempt in range(3):
        try:
            with urlopen(request, timeout=60) as response:
                return response.read(), {k.lower(): v for k, v in response.headers.items()}
        except HTTPError as error:
            if error.code == 404 and absent_ok:
                return None
            if error.code not in (429, 500, 502, 503, 504) or attempt == 2:
                raise
        time.sleep(2 * (attempt + 1))
    raise RuntimeError("unreachable")


def busy_github_runs(runs):
    """Non-PR catalog runs that may hold the shared hosting lock."""
    return [r for r in runs if r.get("event") != "pull_request"
            and r.get("status") in ("queued", "in_progress", "waiting", "pending", "requested")]


def preservation_problems(site, live_fetch):
    """Live namespaces missing from, or different in, the staged site."""
    problems = []
    for relative in PRESERVED_POINTERS:
        live = live_fetch(relative)
        staged = site / relative
        if live is None:
            continue
        if not staged.is_file():
            problems.append(f"{relative} is live but missing from the staged site")
        elif staged.read_bytes() != live:
            problems.append(f"{relative} differs from the live bytes")
    return problems


def readback_problems(site, revision, live_fetch_with_headers):
    """Compare every staged pointer with each production origin, as the workflow does."""
    problems = []
    paths = (ONE_PIECE_POINTER, f"one-piece/v1/releases/{revision}/catalog-release.json") + PRESERVED_POINTERS + MARKET_SCOPES
    stamp = int(time.time())
    for origin in ORIGINS:
        for relative in paths:
            expected = site / relative
            if not expected.is_file():
                continue
            result = live_fetch_with_headers(f"{origin}/{relative}?publication_check=local-{stamp}")
            if result is None:
                problems.append(f"{origin}/{relative} is missing")
                continue
            body, headers = result
            cache = headers.get("cache-control", "").lower()
            found = []
            if body != expected.read_bytes():
                found.append(f"{origin}/{relative} bytes differ")
            elif relative in (ONE_PIECE_POINTER, *MARKET_SCOPES) and "no-cache" not in cache:
                found.append(f"{origin}/{relative} lacks no-cache")
            elif relative.startswith("one-piece/v1/releases/") and not (
                    "max-age=31536000" in cache and "immutable" in cache):
                found.append(f"{origin}/{relative} is not cached as immutable")
            problems += found
            if not found:
                print(f"Verified {origin}/{relative}")
    return problems


def gh_json(args):
    return json.loads(run(["gh"] + args, capture=True))


def check_github_runs(skip):
    if skip:
        print("Skipping the GitHub run check by request.")
        return
    busy = []
    for workflow in SHARED_SITE_WORKFLOWS:
        for status in ("queued", "in_progress", "waiting"):
            busy += busy_github_runs(gh_json(["run", "list", "--repo", REPOSITORY, "--workflow", workflow,
                                              "--status", status, "--json",
                                              "databaseId,event,status,workflowName"]))
    if busy:
        listing = ", ".join(f"{r['workflowName']} {r['databaseId']} ({r['status']})" for r in busy)
        sys.exit(f"Refusing to deploy while GitHub catalog runs may publish: {listing}. "
                 "Wait for or cancel them, or pass --skip-github-run-check.")


def obtain_artifact(args, scratch):
    artifact = scratch / "artifact"
    if args.artifact_dir:
        shutil.copytree(args.artifact_dir, artifact)
        return artifact
    signing = gh_json(["api", f"repos/{REPOSITORY}/actions/runs/{args.signed_run_id}"])
    if not (signing.get("path") == WORKFLOW_PATH and signing.get("head_branch") == "main"
            and signing.get("event") == "workflow_dispatch" and signing.get("conclusion") == "success"):
        sys.exit("The signed run is not a successful One Piece workflow_dispatch run on main.")
    run(["gh", "run", "download", args.signed_run_id, "--repo", REPOSITORY,
         "--name", f"one-piece-signed-artifact-{args.signed_run_id}", "--dir", artifact])
    return artifact


def main(argv=None):
    args = parse_args(argv)
    repo = Path(run(["git", "rev-parse", "--show-toplevel"], capture=True).strip())
    check_github_runs(args.skip_github_run_check)

    work = args.work_dir.resolve()
    scratch = work / "scratch"
    checkout = work / "checkout"
    if scratch.exists():
        shutil.rmtree(scratch)
    scratch.mkdir(parents=True)
    run(["git", "fetch", "origin", "main"], cwd=repo)
    if checkout.exists():
        run(["git", "worktree", "remove", "--force", checkout], cwd=repo)
    run(["git", "worktree", "add", "--detach", checkout, "origin/main"], cwd=repo)

    try:
        if not args.r2_bucket or not re.fullmatch(r"[0-9a-f]{32}", args.r2_account_id or ""):
            sys.exit("Set --r2-bucket/R2_BUCKET_NAME and a 32-hex --r2-account-id/R2_ACCOUNT_ID.")
        if not os.environ.get("AWS_ACCESS_KEY_ID") or not os.environ.get("AWS_SECRET_ACCESS_KEY"):
            sys.exit("Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY for R2 publication.")

        artifact = obtain_artifact(args, scratch)
        envelope = artifact / "release-envelope.json"
        if sha256(envelope) != args.envelope_sha256:
            sys.exit("The signed envelope does not match --envelope-sha256.")
        if sha256(artifact / "verified-manifest.json") != args.manifest_sha256:
            sys.exit("The verified manifest does not match --manifest-sha256.")

        inputs = scratch / "inputs"
        revision = run(["python3", "scripts/prepare_one_piece_hosting.py", "--artifact", artifact,
                        "--output-dir", inputs, "--bootstrap", "true" if args.bootstrap else "false",
                        "--origin", R2_ORIGIN, "--one-piece-only"],
                       cwd=checkout, capture=True).strip()
        if not revision.isdigit():
            sys.exit(f"Unexpected revision from hosting preparation: {revision!r}")
        keys = scratch / "keys.json"
        run(["python3", "scripts/one_piece_pinned_keys.py", "Config/OnePieceCatalogProduction.xcconfig", keys],
            cwd=checkout)
        baseline = (["--bootstrap-registry", "yes"] if args.bootstrap
                    else ["--previous", inputs / "one-piece-predecessor.json"])
        verified = scratch / "verified-manifest.json"
        run(["swift", "run", "--scratch-path", work / "build", "--package-path", "OnePieceCatalogCore",
             "one-piece-catalog-publisher", "verify", "--input", envelope, "--trusted-keys", keys,
             "--reviewed-payload-sha256", args.reviewed_sha256, *baseline, "--manifest", verified], cwd=checkout)
        if verified.read_bytes() != (artifact / "verified-manifest.json").read_bytes():
            sys.exit("Local verification produced a different manifest than the signing run.")

        r2_site = scratch / "r2-site"
        destination = r2_site / "one-piece/v1"
        immutable = destination / "releases" / revision / "catalog-release.json"
        immutable.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(envelope, immutable)
        shutil.copyfile(envelope, destination / "current.json")
        run(["python3", "scripts/market_price_feeds.py", "write-catalog-scopes", "--site-root", r2_site,
             "--game", "one-piece"], cwd=checkout)
        metadata_path = scratch / "catalog-publish-metadata.json"
        metadata_args = ["python3", "scripts/r2_catalog_publish.py", "--site", r2_site,
                         "--write-catalog-metadata", metadata_path,
                         "--namespace", "one-piece/v1", "--revision", revision]
        if not args.bootstrap:
            previous_revision = json.loads(verified.read_bytes())["previousRevision"]
            metadata_args += ["--previous-revision", str(previous_revision),
                              "--previous-pointer", inputs / "one-piece-predecessor.json"]
        run(metadata_args, cwd=checkout)
        run(["bash", "scripts/verify_pokemon_catalog_hosting_config.sh"], cwd=checkout)

        print(f"\nReady to publish One Piece revision {revision} (envelope {args.envelope_sha256[:16]}…) "
              f"to R2 ({R2_ORIGIN}).")
        if not args.yes and input("Type 'publish' to deploy: ").strip() != "publish":
            sys.exit("Not deployed.")

        run(["python3", "scripts/r2_catalog_publish.py", "--primary-catalog", "one-piece/v1",
             "--catalog-metadata", metadata_path, "--site", r2_site,
             "--bucket", args.r2_bucket, "--account-id", args.r2_account_id,
             "--public-base", R2_ORIGIN, "--verify-all"], cwd=checkout)
        print(f"One Piece revision {revision} is live and verified on {R2_ORIGIN}.")

        if args.skip_firebase_backup:
            print("Skipping Firebase backup by request.")
            return

        try:
            r2_inventory = scratch / "r2-inventory"
            r2_inventory.mkdir(parents=True, exist_ok=True)
            aws_env = {**os.environ, "AWS_DEFAULT_REGION": "auto"}
            list_base = ["aws", "--endpoint-url", f"https://{args.r2_account_id}.r2.cloudflarestorage.com",
                         "--cli-connect-timeout", "10", "--cli-read-timeout", "60", "--no-cli-pager",
                         "--output", "json", "s3api", "list-objects-v2", "--bucket", args.r2_bucket]
            (r2_inventory / "r2-verified-builds.json").write_text(
                run(list_base + ["--prefix", "market-prices/v2/verified-builds/", "--query", "Contents[].Key"],
                    cwd=checkout, capture=True, env=aws_env))
            (r2_inventory / "r2-legacy-inventory.json").write_text(
                run(list_base + ["--prefix", "market-prices/v2/builds/", "--delimiter", "/",
                                 "--query", "CommonPrefixes[].Prefix"],
                    cwd=checkout, capture=True, env=aws_env))

            cache_dir = scratch / "r2-cache"
            cache_work = scratch / "r2-pointers"
            run(["python3", "scripts/catalog_hosting_cache.py", "prepare", "--origin", R2_ORIGIN,
                 "--site", SITE_ROOT, "--cache", cache_dir, "--work", cache_work], cwd=checkout)
            restore_env = {**os.environ, "CATALOG_RESTORE_CACHE_WORK": str(cache_work),
                           "PREFER_R2_PRICE_HISTORY": "true"}
            run(["bash", "scripts/restore_catalog_hosting_site.sh",
                 cache_work / "pokemon-current.json", cache_work / "magic-current.json",
                 SITE_ROOT, R2_ORIGIN, "PokemonCatalogCore", "Config/PokemonCatalogProduction.xcconfig",
                 "MagicCatalogCore", "Config/MagicCatalogProduction.xcconfig",
                 cache_work / "one-piece-current.json", "OnePieceCatalogCore",
                 "Config/OnePieceCatalogProduction.xcconfig", cache_work / "yugioh-current.json"],
                cwd=checkout, env=restore_env)
            site = checkout / SITE_ROOT
            run(["python3", "scripts/catalog_hosting_cache.py", "confirm", "--origin", R2_ORIGIN,
                 "--site", SITE_ROOT, "--work", cache_work], cwd=checkout)
            run(["python3", "scripts/catalog_hosting_cache.py", "confirm-r2-scopes", "--site", SITE_ROOT],
                cwd=checkout)
            inventory_file = (r2_inventory / "r2-verified-builds.json"
                              if (site / "market-prices/v2/history.json").is_file()
                              else r2_inventory / "r2-legacy-inventory.json")
            run(["python3", "scripts/market_price_rollback.py", "sync-r2", "--site-root", SITE_ROOT,
                 "--r2-inventory", inventory_file], cwd=checkout)
            run(["firebase", "deploy", "--only", "hosting:production", "--project", PROJECT, "--non-interactive"],
                cwd=checkout)
            run(["python3", "scripts/catalog_hosting_cache.py", "verify-firebase-catalogs",
                 "--site", SITE_ROOT, "--namespace", "one-piece/v1", "--revision", revision], cwd=checkout)
            run(["python3", "scripts/market_price_rollback.py", "verify", "--site-root", SITE_ROOT], cwd=checkout)
            run(["python3", "scripts/market_price_rollback.py", "confirm-primary", "--site-root", SITE_ROOT],
                cwd=checkout)
            print(f"Firebase backup for One Piece revision {revision} verified on {ORIGINS[0]}.")
        except Exception as error:
            print(f"Warning: Firebase backup failed ({error}). The verified R2 catalog publication remains active.",
                  file=sys.stderr)
    finally:
        run(["git", "worktree", "remove", "--force", checkout], cwd=repo)


if __name__ == "__main__":
    main()
