#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

view="Sources/QuotaRail/UI/RailRootView.swift"

if rg -q '\.scaleEffect\(CGFloat\(motion\.scale\)\)' "$view"; then
  echo "FAIL Dock magnification still scales the percentage label"
  exit 1
fi

for required_pattern in 'magnificationScale' 'showsInlinePercent' '\.monospacedDigit\(\)'; do
  if ! rg -q "$required_pattern" "$view"; then
    echo "FAIL percentage label architecture missing: $required_pattern"
    exit 1
  fi
done

echo "PASS icon magnifies independently; percentage typography stays fixed"
