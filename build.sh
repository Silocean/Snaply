#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
app="build.noindex/Snaply.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swiftc -O -parse-as-library -framework AppKit -framework CoreGraphics -o "$app/Contents/MacOS/Snaply" snaply.swift editor.swift
icon_dir=$(mktemp -d)
swiftc -O -framework AppKit -o "$icon_dir/makeicon" makeicon.swift
"$icon_dir/makeicon" "$icon_dir/icon.png"
mkdir -p "$icon_dir/icon.iconset"
make_size() { sips -z "$1" "$1" "$icon_dir/icon.png" --out "$icon_dir/icon.iconset/$2.png" >/dev/null; }
make_size 16 icon_16x16
make_size 32 icon_16x16@2x
make_size 32 icon_32x32
make_size 64 icon_32x32@2x
make_size 128 icon_128x128
make_size 256 icon_128x128@2x
make_size 256 icon_256x256
make_size 512 icon_256x256@2x
make_size 512 icon_512x512
make_size 1024 icon_512x512@2x
iconutil -c icns "$icon_dir/icon.iconset" -o "$app/Contents/Resources/Snaply.icns"
rm -rf "$icon_dir"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Snaply</string>
  <key>CFBundleDisplayName</key>
  <string>Snaply</string>
  <key>CFBundleIdentifier</key>
  <string>local.snaply</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleExecutable</key>
  <string>Snaply</string>
  <key>CFBundleIconFile</key>
  <string>Snaply</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>LSUIElement</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Snaply 需要录制屏幕才能截图。</string>
</dict>
</plist>
EOF
identity=$(security find-identity -p codesigning -v | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)
if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" --timestamp=none "$app"
else
  codesign --force --sign - "$app"
fi
echo "built $app"
