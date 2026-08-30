#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
swift build --product QuotaRail
swift run QuotaRailCoreChecks
