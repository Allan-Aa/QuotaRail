#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

./build-app.sh

binary="dist/QuotaRail.app/Contents/MacOS/QuotaRail"
if [[ ! -x "$binary" ]]; then
  echo "QuotaRail production app is missing. Run ./build-app.sh first."
  exit 1
fi

two_window_sampler=$(mktemp -t quotarail-visual-sampler)
trap 'rm -f "$two_window_sampler"' EXIT
swiftc qa/two_window_sampler.swift -o "$two_window_sampler"

check_state() {
  local label="$1"
  local state="$2"
  local expected_rail_width="$3"
  local expected_rail_height="$4"
  local expected_overlay_width="$5"
  local expected_overlay_height="$6"
  local track_scale="${7:-1}"
  local providers="${8:-Codex,Claude,Grok,Cursor}"

  env \
    QUOTARAIL_PREVIEW=1 \
    QUOTARAIL_PREVIEW_STATE="$state" \
    QUOTARAIL_PREVIEW_WINDOW_NAMES=1 \
    QUOTARAIL_PREVIEW_TRACK_SCALE="$track_scale" \
    QUOTARAIL_PREVIEW_PROVIDERS="$providers" \
    "$binary" >/dev/null 2>&1 &
  local app_process_id=$!
  local samples_file
  samples_file=$(mktemp -t quotarail-static-samples)
  "$two_window_sampler" "$app_process_id" 1.2 >"$samples_file"
  local geometry
  geometry=$(awk '$2 > 0 { value=$2" "$3" "$4" "$5 } END { print value }' "$samples_file")
  rm -f "$samples_file"
  local actual_rail_width actual_rail_height actual_overlay_width actual_overlay_height
  read -r actual_rail_width actual_rail_height actual_overlay_width actual_overlay_height <<< "$geometry"

  kill "$app_process_id" 2>/dev/null || true
  wait "$app_process_id" 2>/dev/null || true

  if [[ "$actual_rail_width $actual_rail_height $actual_overlay_width $actual_overlay_height" != \
        "$expected_rail_width $expected_rail_height $expected_overlay_width $expected_overlay_height" ]]; then
    echo "FAIL $label rail=${actual_rail_width:-missing}x${actual_rail_height:-missing} overlay=${actual_overlay_width:-missing}x${actual_overlay_height:-missing}"
    return 1
  fi
  echo "PASS $label rail=${actual_rail_width}x${actual_rail_height} overlay=${actual_overlay_width}x${actual_overlay_height}"
}

check_motion_preview() {
  local persistent="$1"
  local label="$2"
  local samples_file
  local marker_file
  local signal_directory
  local signal_path
  samples_file=$(mktemp -t quotarail-motion-samples)
  marker_file=$(mktemp -t quotarail-motion-marker)
  signal_directory=$(mktemp -d -t quotarail-motion-signal)
  signal_path="$signal_directory/go"
  env \
    QUOTARAIL_PREVIEW=1 \
    QUOTARAIL_PREVIEW_MOTION=1 \
    QUOTARAIL_PREVIEW_STATE="$([[ "$persistent" == 1 ]] && echo rail || echo collapsed)" \
    QUOTARAIL_PREVIEW_ALWAYS_VISIBLE="$persistent" \
    QUOTARAIL_PREVIEW_WINDOW_NAMES=1 \
    QUOTARAIL_PREVIEW_MOTION_SIGNAL_PATH="$signal_path" \
    "$binary" >"$marker_file" 2>/dev/null &
  local app_process_id=$!
  local armed=false
  for _ in {1..200}; do
    if grep -q '^QR_MOTION_ARMED ' "$marker_file"; then
      armed=true
      break
    fi
    sleep 0.05
  done
  if [[ "$armed" != true ]]; then
    kill "$app_process_id" 2>/dev/null || true
    wait "$app_process_id" 2>/dev/null || true
    rm -f "$samples_file" "$marker_file"
    rmdir "$signal_directory"
    echo "FAIL $label preview never reached a stable rail frame"
    return 1
  fi

  "$two_window_sampler" "$app_process_id" 3.2 >"$samples_file" &
  local sampler_process_id=$!
  samples_ready=false
  for _ in {1..100}; do
    if [[ $(awk 'END { print NR + 0 }' "$samples_file") -ge 2 ]]; then
      samples_ready=true
      break
    fi
    sleep 0.02
  done
  if [[ "$samples_ready" != true ]]; then
    kill "$sampler_process_id" "$app_process_id" 2>/dev/null || true
    wait "$sampler_process_id" 2>/dev/null || true
    wait "$app_process_id" 2>/dev/null || true
    rm -f "$samples_file" "$marker_file"
    rmdir "$signal_directory"
    echo "FAIL $label sampler did not capture two frames before the motion signal"
    return 1
  fi
  touch "$signal_path"
  wait "$sampler_process_id"
  kill "$app_process_id" 2>/dev/null || true
  wait "$app_process_id" 2>/dev/null || true

  local collapse_time
  collapse_time=$(awk '/^QR_MOTION_COLLAPSE_BEGIN / { print $2; exit }' "$marker_file")
  if [[ -z "$collapse_time" ]]; then
    rm -f "$samples_file" "$marker_file" "$signal_path"
    rmdir "$signal_directory"
    echo "FAIL $label missing collapse marker"
    return 1
  fi

  local result
  result=$(awk -v persistent="$persistent" -v collapse_time="$collapse_time" '
    $2 >= 95 && $2 <= 97 && $3 >= 343 && $3 <= 345 { stable_rail++ }
    $2 == 8 && $3 == 28 { collapsed++ }
    $4 == 104 && $5 == 28 {
      hover++
      if ((persistent == 1 || $1 < collapse_time) && ($2 < 95 || $2 > 97 || $3 < 343 || $3 > 345)) {
        invalid_overlay_rail++
      }
    }
    $4 == 196 && $5 == 94 {
      pinned++
      if ((persistent == 1 || $1 < collapse_time) && ($2 < 95 || $2 > 97 || $3 < 343 || $3 > 345)) {
        invalid_overlay_rail++
      }
    }
    END {
      ok = stable_rail > 0 && hover > 0 && pinned > 0 && invalid_overlay_rail == 0
      if (persistent == 1) ok = ok && collapsed == 0
      else ok = ok && collapsed > 0
      printf "%d %d %d %d %d %d", ok, stable_rail + 0, hover + 0,
        pinned + 0, collapsed + 0, invalid_overlay_rail + 0
    }
  ' "$samples_file")
  rm -f "$samples_file" "$marker_file" "$signal_path"
  rmdir "$signal_directory"

  local passed stable_rail hover pinned collapsed invalid_overlay_rail
  read -r passed stable_rail hover pinned collapsed invalid_overlay_rail <<< "$result"
  if [[ "$passed" != 1 ]]; then
    echo "FAIL $label rail=$stable_rail hover=$hover pinned=$pinned collapsed=$collapsed invalid=$invalid_overlay_rail"
    return 1
  fi
  echo "PASS $label fixed-rail hover-overlay pinned-overlay (no system pointer events)"
}

check_state collapsed collapsed 8 28 0 0
check_state rail rail 96 344 0 0
check_state hover-codex hover-codex 96 344 104 28
check_state hover-claude hover-claude 96 344 104 28
check_state hover-grok hover-grok 96 344 104 28
check_state hover-cursor hover-cursor 96 344 104 28
check_state detail-codex detail-codex 96 344 196 94
check_state detail-claude detail-claude 96 344 196 94
check_state detail-grok detail-grok 96 344 196 64
check_state detail-cursor detail-cursor 96 344 196 94

check_state scaled-two-provider-rail rail 116 226 0 0 1.20 Codex,Grok
check_state scaled-two-provider-hover hover-codex 116 226 104 28 1.20 Codex,Grok
check_state scaled-two-provider-detail detail-grok 116 226 196 64 1.20 Codex,Grok

env QUOTARAIL_PREVIEW=1 QUOTARAIL_PREVIEW_ALWAYS_VISIBLE=1 QUOTARAIL_PREVIEW_WINDOW_NAMES=1 \
  "$binary" >/dev/null 2>&1 &
always_process_id=$!
always_samples=$(mktemp -t quotarail-always-samples)
"$two_window_sampler" "$always_process_id" 1.2 >"$always_samples"
always_geometry=$(awk '$2 > 0 { value=$2" "$3 } END { print value }' "$always_samples")
rm -f "$always_samples"
kill "$always_process_id" 2>/dev/null || true
wait "$always_process_id" 2>/dev/null || true
[[ "$always_geometry" == "96 344" ]] || { echo "FAIL preview-always-visible $always_geometry"; exit 1; }
echo "PASS preview-always-visible rail=96x344"

check_motion_preview 0 internal-motion
check_motion_preview 1 persistent-motion
./qa/motion_architecture_check.sh
./qa/percentage_label_architecture_check.sh
./qa/two_window_architecture_check.sh
./qa/hover_lifecycle_check.sh
./qa/exit_latency_check.sh
