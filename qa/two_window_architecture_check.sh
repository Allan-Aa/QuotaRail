#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

controller="Sources/QuotaRail/RailWindowController.swift"
view="Sources/QuotaRail/UI/RailRootView.swift"

if ! rg -q 'overlayPanel' "$controller"; then
  echo "FAIL rail controller has no independent overlay panel"
  exit 1
fi

if sed -n '/private func size(/,/^    }/p' "$controller" | rg -q 'hoverWidth|pinnedWidth'; then
  echo "FAIL sensor panel still changes width for hover or pinned detail"
  exit 1
fi

if ! rg -q 'struct RailOverlayRootView' "$view"; then
  echo "FAIL hover label and detail card have not moved to an overlay view"
  exit 1
fi

echo "PASS fixed sensor panel and independent overlay panel architecture"
