#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

checker=$(mktemp -t quotarail-hover-handoff-legacy)
trap 'rm -f "$checker"' EXIT
swiftc "${RAIL_STATE_SOURCE:-Sources/QuotaRail/RailState.swift}" \
  qa/hover_handoff_legacy_check.swift \
  -o "$checker"
"$checker"
