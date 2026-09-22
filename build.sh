#!/usr/bin/env bash
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/Maester.app"
BUNDLE_ID="com.kishore.maester"
VERSION="0.1.0"

echo "compiling..."
mkdir -p "$SRC/build"
swiftc -O \
  -target arm64-apple-macos15.0 \
  -framework SwiftUI -framework AppKit \
  -o "$SRC/build/Maester" \
  "$SRC/Sources/"*.swift

echo "assembling bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$SRC/build/Maester" "$APP/Contents/MacOS/Maester"
cp "$SRC/Resources/Maester.icns" "$APP/Contents/Resources/Maester.icns"
mkdir -p "$APP/Contents/Resources/menubar"
cp "$SRC/Resources/menubar/"*.png "$APP/Contents/Resources/menubar/"
mkdir -p "$APP/Contents/Resources/glyphs"
cp "$SRC/Resources/glyphs/"*.png "$APP/Contents/Resources/glyphs/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>Maester</string>
  <key>CFBundleDisplayName</key>       <string>Maester</string>
  <key>CFBundleExecutable</key>        <string>Maester</string>
  <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleIconFile</key>          <string>Maester</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key>           <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>    <string>15.0</string>
  <key>NSHighResolutionCapable</key>   <true/>
  <key>LSUIElement</key>               <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Maester asks an application to quit when you choose Quit.</string>
</dict>
</plist>
PLIST

echo "signing (ad-hoc)..."
codesign --force --sign - --identifier "$BUNDLE_ID" \
  --options runtime --timestamp=none "$APP" 2>&1 | sed 's/^/  /'

echo
echo "built: $APP"
echo "run:   open -a $APP"
