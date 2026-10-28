#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="dist/WriteDock.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/WriteDock "$APP/Contents/MacOS/WriteDock"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.WriteDock</string>
<key>CFBundleName</key><string>WriteDock</string>
<key>CFBundleDisplayName</key><string>WriteDock</string>
<key>CFBundleExecutable</key><string>WriteDock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAccessibilityUsageDescription</key><string>WriteDock reads selected text only when you invoke capture and replaces it only after you accept a suggestion.</string>
<key>NSHumanReadableCopyright</key><string>WriteDock — independent local writing assistant</string>
</dict></plist>
PLIST
# For stable permissions across updates set WRITEDOCK_SIGNING_IDENTITY to your own signing identity.
codesign --force --sign "${WRITEDOCK_SIGNING_IDENTITY:--}" "$APP"
codesign --verify --strict "$APP"
echo "Built $PWD/$APP"
