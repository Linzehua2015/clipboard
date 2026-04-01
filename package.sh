#!/usr/bin/env bash
# package.sh — Build ClipHistory.app (distributable, double-click to launch)
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="ClipHistory"
APP_BUNDLE="${APP_NAME}.app"
BUNDLE_ID="com.user.cliphistory"
VERSION="1.0.0"

echo "=== 1/4  Building binary ==="
./build.sh

echo ""
echo "=== 2/4  Creating .app bundle ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp cliphistory "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>       <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>       <string>${BUNDLE_ID}</string>
  <key>CFBundleName</key>             <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>      <string>${APP_NAME}</string>
  <key>CFBundleVersion</key>          <string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundlePackageType</key>      <string>APPL</string>
  <key>CFBundleIconFile</key>         <string>AppIcon</string>
  <key>LSUIElement</key>              <true/>
  <key>NSHighResolutionCapable</key>  <true/>
  <key>LSMinimumSystemVersion</key>   <string>12.0</string>
  <key>NSAccessibilityUsageDescription</key>
  <string>ClipHistory needs Accessibility access to simulate paste (Cmd+V).</string>
</dict>
</plist>
PLIST

echo ""
echo "=== 3/4  Generating icon ==="
ICONSET="/tmp/AppIcon_cliphistory.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Compile and run icon generator
swiftc -O gen_icon.swift -o /tmp/gen_icon_cliphistory -framework AppKit 2>/dev/null
/tmp/gen_icon_cliphistory /tmp/icon_cliphistory_512.png

for size in 16 32 128 256 512; do
    sips -z $size $size /tmp/icon_cliphistory_512.png \
        --out "$ICONSET/icon_${size}x${size}.png"    >/dev/null
    double=$((size * 2))
    if [[ $double -le 1024 ]]; then
        sips -z $double $double /tmp/icon_cliphistory_512.png \
            --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    fi
done
iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" /tmp/icon_cliphistory_512.png /tmp/gen_icon_cliphistory

echo "  Icon done."

echo ""
echo "=== 4/4  Ad-hoc signing ==="
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "✔  Done: $(pwd)/${APP_BUNDLE}"
echo ""
echo "用法:"
echo "  双击 ${APP_BUNDLE} 即可启动"
echo "  首次运行需在「系统设置 → 隐私与安全性 → 辅助功能」中允许 ${APP_NAME}"
echo ""
echo "分享给别人:"
echo "  zip -r ClipHistory.zip ClipHistory.app"
echo "  或直接把 ClipHistory.app 拖给对方"
