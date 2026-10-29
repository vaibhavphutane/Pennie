#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="${PENNIE_APP_DIR:-${WRITEDOCK_APP_DIR:-dist/Pennie.app}}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Pennie "$APP/Contents/MacOS/Pennie"
cp Sources/Pennie/Resources/Pennie.png "$APP/Contents/Resources/Pennie.png"
swift scripts/make-app-icon.swift Sources/Pennie/Resources/Pennie.png .build/Pennie.iconset
iconutil -c icns .build/Pennie.iconset -o "$APP/Contents/Resources/Pennie.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<!-- Preserve the existing preferences domain and application identity across the rename. -->
<key>CFBundleIdentifier</key><string>local.WriteDock</string>
<key>CFBundleName</key><string>Pennie</string>
<key>CFBundleDisplayName</key><string>Pennie</string>
<key>CFBundleExecutable</key><string>Pennie</string>
<key>CFBundleIconFile</key><string>Pennie.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>CFBundleVersion</key><string>6</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAccessibilityUsageDescription</key><string>Pennie sits beside supported editors to help with your writing. It reads text only when you click the companion or invoke capture, and updates the original draft or selection only when you choose Accept.</string>
<key>NSHumanReadableCopyright</key><string>Pennie — Say it like you.</string>
</dict></plist>
PLIST
# Keep the old environment variables working for existing build setups.
# For stable permissions across updates set PENNIE_SIGNING_IDENTITY to your signing identity.
codesign --force --sign "${PENNIE_SIGNING_IDENTITY:-${WRITEDOCK_SIGNING_IDENTITY:--}}" "$APP"
codesign --verify --strict "$APP"
echo "Built $PWD/$APP"
