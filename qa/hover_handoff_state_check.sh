#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

checker=$(mktemp -t quotarail-hover-handoff)
trap 'rm -f "$checker"' EXIT
swiftc \
  Sources/QuotaRail/RailState.swift \
  qa/hover_handoff_state_check.swift \
  -o "$checker"
"$checker"
