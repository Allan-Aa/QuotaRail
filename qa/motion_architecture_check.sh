#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

view_file="Sources/QuotaRail/UI/RailRootView.swift"
violations=$(rg -n '\.animation\(dockAnimation, value: (motion|focusY)\)' "$view_file" || true)
if [[ -n "$violations" ]]; then
  echo "FAIL continuous pointer targets must not restart implicit springs"
  echo "$violations"
  exit 1
fi

if ! rg -q 'value: focusedTool' "$view_file"; then
  echo "FAIL low-frequency focus transition animation is missing"
  exit 1
fi

echo "PASS pointer motion is direct; focus transitions retain animation"
