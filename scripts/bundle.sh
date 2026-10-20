#!/bin/bash
# Builds TokenCalendar.app (universal: Apple Silicon + Intel) and a zip of it.
# Usage: bash scripts/bundle.sh   → build/TokenCalendar.app, build/TokenCalendar-mac.zip
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.0.0}"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP="build/TokenCalendar.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TokenCalendar" "$APP/Contents/MacOS/TokenCalendar"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>TokenCalendar</string>
    <key>CFBundleDisplayName</key><string>Claude Token Calendar</string>
    <key>CFBundleIdentifier</key><string>com.fepckl.tokencalendar</string>
    <key>CFBundleExecutable</key><string>TokenCalendar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

# Ad-hoc signature (no Apple developer account needed). Gatekeeper still asks on first launch.
codesign --force --deep --sign - "$APP"

ditto -c -k --keepParent "$APP" build/TokenCalendar-mac.zip
echo "Built $(pwd)/$APP"
