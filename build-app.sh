#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

swift build -c release
bin_dir="$(swift build -c release --show-bin-path)"
app_path="dist/QuotaRail.app"

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"

cp "$bin_dir/QuotaRail" "$app_path/Contents/MacOS/QuotaRail"
cp -R "$bin_dir/QuotaRail_QuotaRail.bundle" "$app_path/Contents/Resources/"
cp "Packaging/Info.plist" "$app_path/Contents/Info.plist"
cp "AppIcon.icns" "$app_path/Contents/Resources/AppIcon.icns"
cp "LICENSE" "$app_path/Contents/Resources/LICENSE.txt"
cp "THIRD_PARTY_NOTICES.md" "$app_path/Contents/Resources/THIRD_PARTY_NOTICES.md"

plutil -lint "$app_path/Contents/Info.plist"
[[ -x "$app_path/Contents/MacOS/QuotaRail" ]]
[[ -f "$app_path/Contents/Resources/AppIcon.icns" ]]
[[ -d "$app_path/Contents/Resources/QuotaRail_QuotaRail.bundle" ]]
codesign --force --deep --sign - "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
echo "Built $app_path (version $version)"
