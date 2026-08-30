#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

binary="dist/QuotaRail.app/Contents/MacOS/QuotaRail"
if [[ ! -x "$binary" ]]; then
  echo "QuotaRail production app is missing. Run ./build-app.sh first."
  exit 1
fi

trace_file=$(mktemp -t quotarail-hover-lifecycle)
signal_directory=$(mktemp -d -t quotarail-hover-signal)
signal_path="$signal_directory/go"
env \
  QUOTARAIL_PREVIEW=1 \
  QUOTARAIL_PREVIEW_EXIT=1 \
  QUOTARAIL_PREVIEW_TRACE_HOVER=1 \
  QUOTARAIL_PREVIEW_STATE=rail \
  QUOTARAIL_PREVIEW_ALWAYS_VISIBLE=1 \
  QUOTARAIL_PREVIEW_EXIT_SIGNAL_PATH="$signal_path" \
  "$binary" >"$trace_file" 2>/dev/null &
app_process_id=$!
armed=false
for _ in {1..220}; do
  if grep -q '^QR_EXIT_ARMED ' "$trace_file"; then
    armed=true
    break
  fi
  sleep 0.05
done
if [[ "$armed" == true ]]; then touch "$signal_path"; fi
triggered=false
for _ in {1..40}; do
  if grep -q '^QR_EXIT_BEGIN ' "$trace_file"; then
    triggered=true
    break
  fi
  sleep 0.05
done
if [[ "$triggered" == true ]]; then sleep 0.5; fi
kill "$app_process_id" 2>/dev/null || true
wait "$app_process_id" 2>/dev/null || true

appear_count=$(awk '$1 == "QR_HOVER" && $3 == "rail-appear" { count++ } END { print count + 0 }' "$trace_file")
disappear_count=$(awk '$1 == "QR_HOVER" && $3 == "rail-disappear" { count++ } END { print count + 0 }' "$trace_file")
trace_summary=$(awk '$1 == "QR_HOVER" { printf "%s%s", separator, $3; separator=" -> " }' "$trace_file")
rm -f "$trace_file" "$signal_path"
rmdir "$signal_directory"

if [[ "$triggered" != true ]]; then
  echo "FAIL stable-hover-lifecycle preview never reached exit trigger"
  exit 1
fi
if [[ "$appear_count" != "1" || "$disappear_count" != "0" ]]; then
  echo "FAIL stable-hover-lifecycle appear=$appear_count disappear=$disappear_count trace=$trace_summary"
  exit 1
fi

echo "PASS stable-hover-lifecycle one persistent rail view (no system pointer events)"
