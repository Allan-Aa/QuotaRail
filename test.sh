#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
bash qa/hover_handoff_legacy_check.sh
bash qa/hover_handoff_state_check.sh
swift build --product QuotaRail
swift run QuotaRailCoreChecks
