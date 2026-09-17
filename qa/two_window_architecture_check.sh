#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

controller="Sources/QuotaRail/RailWindowController.swift"
view="Sources/QuotaRail/UI/RailRootView.swift"
layout="Sources/QuotaRailCore/RailPreferences.swift"

if ! rg -q 'public var interactiveWidth: Double \{ railWidth \}' "$layout" \
  || ! rg -q 'width: CGFloat\(layout\.interactiveWidth\)' "$view"; then
  echo "FAIL continuous hover must retain the fixed interactive rail strip"
  exit 1
fi

resolver=$(sed -n '/setPointerInsideRailResolver/,/panel\.isOpaque/p' "$controller")
if [[ "$resolver" == *'panel.frame.contains'* ]] \
  || [[ "$resolver" != *'panel.frame.maxX - layout.interactiveWidth'* ]] \
  || [[ "$resolver" != *'width: layout.interactiveWidth'* ]] \
  || [[ "$resolver" != *'height: panel.frame.height'* ]]; then
  echo "FAIL pointer resolver must use the right-aligned interactive rail rect"
  exit 1
fi

hover_handler=$(sed -n '/\.onContinuousHover { phase in/,/handleContinuousHover(phase)/p' "$view")
if [[ "$hover_handler" != *'guard state.mode != .collapsed else { return }'* ]] \
  || [[ "$hover_handler" == *'!state.isCollapsing'* ]]; then
  echo "FAIL rail hover must accept re-entry while the collapse fade is active"
  exit 1
fi

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

card_height=$(sed -n '/private func cardHeight(/,/^    }/p' "$controller")
if [[ "$card_height" == *actionURL* ]] \
  || [[ "$card_height" != *'guard let item, item.available else {'* ]] \
  || [[ "$card_height" != *'return 62'* ]]; then
  echo "FAIL unavailable detail cards must reserve 62pt for recovery instructions"
  exit 1
fi

if ! rg -q '\.help\(unavailableReason\)' "$view"; then
  echo "FAIL unavailable recovery instructions are missing a full tooltip"
  exit 1
fi

echo "PASS fixed sensor panel and independent overlay panel architecture"
