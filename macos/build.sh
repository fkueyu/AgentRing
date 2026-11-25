#!/bin/sh
# Build dist/AgentRing.app from macos/Sources/AgentRing.
#
#   ./macos/build.sh
#
# Requires Xcode command line tools (swift, iconutil, sips) and Python 3 for the
# icon (override with PY=...).

set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/dist/AgentRing.app"
VERSION=$(cat "$ROOT/VERSION")

if [ -z "${PY:-}" ]; then
  for candidate in "$HOME/.dsh/dsh-runtimes/dsh-primary-runtime/dependencies/python/bin/python3" "$(command -v python3 || true)"; do
    if [ -x "$candidate" ]; then PY="$candidate"; break; fi
  done
fi
if [ -z "${PY:-}" ]; then
  echo "python3 not found; pass PY=/path/to/python3" >&2
  exit 1
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> compiling"
swift build -c release --package-path "$ROOT/macos"
cp "$ROOT/macos/.build/release/AgentRing" "$APP/Contents/MacOS/AgentRing"

echo "==> Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>AgentRing</string>
  <key>CFBundleDisplayName</key><string>AgentRing</string>
  <key>CFBundleIdentifier</key><string>com.agentring.app</string>
  <key>CFBundleExecutable</key><string>AgentRing</string>
  <key>CFBundleIconFile</key><string>AgentRing</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>__VERSION__</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key><true/>
  </dict>
</dict>
</plist>
PLIST
sed -i '' "s/__VERSION__/$VERSION/" "$APP/Contents/Info.plist"

echo "==> icon"
"$PY" "$ROOT/macos/make-icon.py" \
  "$ROOT/macos/Resources/Logo.png" \
  "$ROOT/dist/icon-1024.png" \
  "$APP/Contents/Resources/MenuBarIcon.png" \
  "$APP/Contents/Resources/MenuBarIcon@2x.png" >/dev/null
ICONSET="$ROOT/dist/AgentRing.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512; do
  sips -z $size $size "$ROOT/dist/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double "$ROOT/dist/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AgentRing.icns"
rm -rf "$ICONSET" "$ROOT/dist/icon-1024.png"

echo "==> signing (ad-hoc)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || echo "   (codesign skipped)"

echo "==> built $APP"
