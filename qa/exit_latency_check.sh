#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

binary="dist/QuotaRail.app/Contents/MacOS/QuotaRail"
if [[ ! -x "$binary" ]]; then
  echo "QuotaRail production app is missing. Run ./build-app.sh first."
  exit 1
fi

sampler_binary=$(mktemp -t quotarail-two-window-sampler)
trap 'rm -f "$sampler_binary"' EXIT
swiftc qa/two_window_sampler.swift -o "$sampler_binary"

measure_exit() {
  local label="$1"
  local always_visible="$2"
  local marker_file samples_file signal_directory signal_path
  marker_file=$(mktemp -t quotarail-exit-marker)
  samples_file=$(mktemp -t quotarail-exit-samples)
  signal_directory=$(mktemp -d -t quotarail-exit-signal)
  signal_path="$signal_directory/go"

  env \
    QUOTARAIL_PREVIEW=1 \
    QUOTARAIL_PREVIEW_EXIT=1 \
    QUOTARAIL_PREVIEW_STATE=rail \
    QUOTARAIL_PREVIEW_ALWAYS_VISIBLE="$always_visible" \
    QUOTARAIL_PREVIEW_TRACK_SCALE=0.75 \
    QUOTARAIL_PREVIEW_PROVIDERS=Codex,Claude,Grok \
    QUOTARAIL_PREVIEW_WINDOW_NAMES=1 \
    QUOTARAIL_PREVIEW_EXIT_SIGNAL_PATH="$signal_path" \
    "$binary" >"$marker_file" 2>/dev/null &
  local app_process_id=$!

  local armed=false
  for _ in {1..200}; do
    if grep -q '^QR_EXIT_ARMED ' "$marker_file"; then
      armed=true
      break
    fi
    sleep 0.05
  done
  if [[ "$armed" != true ]]; then
    echo "FAIL $label preview never reached a stable hover frame"
    kill "$app_process_id" 2>/dev/null || true
    wait "$app_process_id" 2>/dev/null || true
    rm -f "$marker_file" "$samples_file"
    rmdir "$signal_directory"
    return 1
  fi

  "$sampler_binary" "$app_process_id" 1.5 >"$samples_file" &
  local sampler_process_id=$!
  samples_ready=false
  for _ in {1..100}; do
    if awk '
      $2 == 72 && $3 == 200 { rail++ }
      $4 == 104 && $5 == 28 { overlay++ }
      END { exit !(rail >= 2 && overlay >= 2) }
    ' "$samples_file"; then
      samples_ready=true
      break
    fi
    sleep 0.02
  done
  if [[ "$samples_ready" != true ]]; then
    echo "FAIL $label two-window sampler did not capture two stable rail and overlay frames"
    kill "$sampler_process_id" "$app_process_id" 2>/dev/null || true
    wait "$sampler_process_id" 2>/dev/null || true
    wait "$app_process_id" 2>/dev/null || true
    rm -f "$marker_file" "$samples_file"
    rmdir "$signal_directory"
    return 1
  fi

  touch "$signal_path"
  wait "$sampler_process_id"
  kill "$app_process_id" 2>/dev/null || true
  wait "$app_process_id" 2>/dev/null || true

  local trigger_time
  trigger_time=$(awk '/^QR_EXIT_BEGIN / { print $2; exit }' "$marker_file")
  if [[ -z "$trigger_time" ]]; then
    echo "FAIL $label missing exit trigger marker"
    rm -f "$marker_file" "$samples_file" "$signal_path"
    rmdir "$signal_directory"
    return 1
  fi

  local measurements
  measurements=$(awk -v trigger="$trigger_time" -v persistent="$always_visible" '
    $1 < trigger {
      if ($2 == 72 && $3 == 200) stable_rail++
      else if ($2 != 0 || $3 != 0) invalid_before++
      if ($4 == 104 && $5 == 28) overlay_seen++
    }
    $1 >= trigger {
      if (overlay_hidden == "" && $4 == 0 && $5 == 0) {
        overlay_hidden = ($1 - trigger) * 1000
      }
      if (persistent == 1 && ($2 != 72 || $3 != 200)) invalid_after++
      if (persistent == 0 && final_rail == "" && $2 == 8 && $3 == 28) {
        final_rail = ($1 - trigger) * 1000
      }
    }
    END {
      if (overlay_hidden == "") overlay_hidden = -1
      if (final_rail == "") final_rail = persistent == 1 ? 0 : -1
      printf "%d %d %d %d %.1f %.1f", stable_rail + 0, overlay_seen + 0,
        invalid_before + 0, invalid_after + 0, overlay_hidden, final_rail
    }
  ' "$samples_file")

  rm -f "$marker_file" "$samples_file" "$signal_path"
  rmdir "$signal_directory"

  local stable_rail overlay_seen invalid_before invalid_after overlay_hidden_ms final_rail_ms
  read -r stable_rail overlay_seen invalid_before invalid_after overlay_hidden_ms final_rail_ms <<< "$measurements"
  if (( stable_rail < 2 || overlay_seen < 2 || invalid_before != 0 || invalid_after != 0 )); then
    echo "FAIL $label rail=$stable_rail overlay=$overlay_seen invalid-before=$invalid_before invalid-after=$invalid_after"
    return 1
  fi
  if ! awk -v value="$overlay_hidden_ms" 'BEGIN { exit !(value >= 0 && value <= 500) }'; then
    echo "FAIL $label overlay-hidden=${overlay_hidden_ms}ms limit=500ms"
    return 1
  fi
  if [[ "$always_visible" == "0" ]] && ! awk -v value="$final_rail_ms" \
      'BEGIN { exit !(value >= 0 && value <= 750) }'; then
    echo "FAIL $label collapsed=${final_rail_ms}ms limit=750ms"
    return 1
  fi

  echo "PASS $label rail-fixed=72x200 overlay-hidden=${overlay_hidden_ms}ms final=${final_rail_ms}ms (no system pointer events)"
}

passed=true
measure_exit persistent-exit 1 || passed=false
measure_exit collapse-exit 0 || passed=false
[[ "$passed" == true ]]
