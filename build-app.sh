#!/bin/bash
# Builds a universal (Apple Silicon + Intel) Throttle.app and drops it in
# the project root, ready to drag into /Applications.
set -euo pipefail
cd "$(dirname "$0")"

echo "Building universal binary (arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64

BUILD_OUT=".build/apple/Products/Release"
APP="Throttle.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_OUT/Throttle" "$APP/Contents/MacOS/Throttle"
# SPM's resource bundle (brand mark PNGs) — Bundle.module needs this next to
# the executable, or icons silently fall back to a placeholder glyph.
cp -R "$BUILD_OUT/Throttle_Throttle.bundle" "$APP/Contents/Resources/"
cp "AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>Throttle</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>CFBundleIdentifier</key>
  <string>com.throttle.app</string>
  <key>CFBundleName</key>
  <string>Throttle</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSUIElement</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>11.0</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.developer-tools</string>
  <key>NSHumanReadableCopyright</key>
  <string>Personal utility. Not affiliated with Anthropic, OpenAI, or Google.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper, Keychain ACLs, login-item registration, and
# notification permissions all see a stable, consistent app identity across
# rebuilds instead of treating every build as a brand-new unknown binary.
codesign --force --deep --sign - "$APP" 2>&1 | grep -v "^Throttle.app: replacing existing signature$" || true

echo "Verifying architectures…"
lipo -info "$APP/Contents/MacOS/Throttle"

echo ""
echo "Built $APP (universal: Apple Silicon + Intel)."
echo "Move it to /Applications, then open it — or run: open $APP"
