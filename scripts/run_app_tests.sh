#!/bin/zsh
# Runs the app test suite on a simulator, in parallel, while sampling memory
# pressure and swap so the worker count can be tuned to this machine.
#
# Kind: Simulator / Xcode. Builds the app and test bundle; clones the target
# simulator once per parallel worker (Xcode deletes the clones afterwards).
# Writes only under RESULTS_DIR. Never uninstalls apps or touches catalogs.
#
# Usage: scripts/run_app_tests.sh [fast|centering|full] [extra xcodebuild args...]
#   fast       every test class except centering research (default)
#   centering  only the centering classes
#   full       everything
#
# Environment:
#   DERIVED_DATA   build products; required, and must be on an external volume
#   RESULTS_DIR    result bundles, logs and memory samples (default: $DERIVED_DATA/../test-results)
#   DEVICE_ID      simulator UDID to clone for workers (required)
#   WORKERS        parallel worker count (default 4)
#   SKIP_BUILD=1   reuse the last build-for-testing products
set -euo pipefail

mode=${1:-fast}
shift $(( $# > 0 ? 1 : 0 ))
: "${DERIVED_DATA:?Set DERIVED_DATA to a folder on the external SSD}"
: "${DEVICE_ID:?Set DEVICE_ID to the simulator UDID to test on}"
[[ "$DERIVED_DATA" == /Volumes/* ]] || { echo "DERIVED_DATA must be on an external volume" >&2; exit 2; }
workers=${WORKERS:-4}
results=${RESULTS_DIR:-"$DERIVED_DATA/../test-results"}
root=${0:A:h:h}
mkdir -p "$results"
stamp=$(date +%Y%m%d-%H%M%S)
bundle="$results/$mode-w$workers-$stamp.xcresult"
log="$results/$mode-w$workers-$stamp.log"
samples="$results/$mode-w$workers-$stamp-memory.csv"

# Any class whose name mentions centering, however it is declared.
centering=(${(f)"$(grep -Eho 'class [A-Za-z0-9_]*Center[A-Za-z0-9_]*Tests\b' "$root"/TradingCardScannerTests/*.swift \
    | awk '{print $2}' | sort -u)"})
selection=()
case $mode in
  fast)      for c in $centering; do selection+=("-skip-testing:TradingCardScannerTests/$c"); done ;;
  centering) for c in $centering; do selection+=("-only-testing:TradingCardScannerTests/$c"); done ;;
  full)      ;;
  *) echo "Unknown mode: $mode" >&2; exit 2 ;;
esac

common=(-project "$root/TradingCardScanner.xcodeproj" -scheme TradingCardScanner-ProfileLocal
        -destination "id=$DEVICE_ID" -derivedDataPath "$DERIVED_DATA")

if [[ ${SKIP_BUILD:-0} != 1 ]]; then
  echo "Building for testing…"
  xcodebuild build-for-testing "${common[@]}" > "$results/build-$stamp.log" 2>&1 \
    || { tail -30 "$results/build-$stamp.log"; exit 1; }
fi

swap_mb() { sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+)M.*/\1/'; }
free_pct() { memory_pressure -Q 2>/dev/null | sed -nE 's/.*percentage: ([0-9]+)%.*/\1/p'; }
echo "seconds,free_percent,swap_used_mb" > "$samples"
start_swap=$(swap_mb)
started=$SECONDS
( while true; do echo "$((SECONDS - started)),$(free_pct),$(swap_mb)" >> "$samples"; sleep 5; done ) &
sampler=$!
trap 'kill $sampler 2>/dev/null || true' EXIT

echo "Running $mode with $workers workers (${#centering} centering classes known)…"
set +e
xcodebuild test-without-building "${common[@]}" -resultBundlePath "$bundle" \
  -parallel-testing-enabled YES -parallel-testing-worker-count "$workers" \
  "${selection[@]}" "$@" > "$log" 2>&1
rc=$?
set -e
elapsed=$((SECONDS - started))
kill $sampler 2>/dev/null || true

min_free=$(tail -n +2 "$samples" | cut -d, -f2 | grep -v '^$' | sort -n | head -1)
peak_swap=$(tail -n +2 "$samples" | cut -d, -f3 | sort -n | tail -1)
printf 'Wall time: %dm%02ds   lowest free memory: %s%%   swap: %s MB at start, %s MB peak\n' \
  $((elapsed / 60)) $((elapsed % 60)) "${min_free:-?}" "$start_swap" "${peak_swap:-?}"

# xcresulttool writes a cache under $HOME; keep it beside the results.
mkdir -p "$results/.xcresulttool-home/Library/Caches"
HOME="$results/.xcresulttool-home" CFFIXED_USER_HOME="$results/.xcresulttool-home" xcrun xcresulttool get test-results summary --path "$bundle" 2>/dev/null \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
print("passed", d["passedTests"], "failed", d["failedTests"], "skipped", d["skippedTests"])
for f in d["testFailures"]: print("  FAIL", f["testIdentifierString"], "::", f["failureText"][:160].replace("\n", " "))' \
  || echo "Could not summarize $bundle; see $log"
echo "Result bundle: $bundle"
echo "Memory samples: $samples"
exit $rc
