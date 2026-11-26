#!/bin/bash
# SilverNotes v0.1.1 — build a release binary and wrap it in a SilverNotes.app bundle.
# Run on a Mac from inside the silvernotes-app folder:  ./build-app.sh
# Result: dist/SilverNotes.app  (drag it into /Applications)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SilverNotes"
BUNDLE_ID="io.starterdev.silvernotes"
VERSION="0.1.1"
MIN_MACOS="13.0"
DIST="dist"
APP="$DIST/$APP_NAME.app"

echo "==> Building release binary (swift build -c release)…"
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)/$APP_NAME"
if [ ! -f "$BIN_PATH" ]; then
  echo "ERROR: built binary not found at $BIN_PATH" >&2
  exit 1
fi

echo "==> Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"
if [ -f "AppIcon.icns" ]; then
  cp "AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>        <string>AppIcon</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>$VERSION</string>
  <key>CFBundleVersion</key>         <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>  <string>$MIN_MACOS</string>
  <key>LSUIElement</key>             <true/>
  <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

echo "==> Ad-hoc signing (so macOS will run your own build)…"
codesign --force --deep --sign - "$APP"

echo ""
echo "Done: $APP"
echo "Install:  drag $APP_NAME.app from the dist/ folder into /Applications, then double-click it."
echo "First launch: if macOS blocks it, right-click the app > Open, or System Settings > Privacy & Security > Open Anyway."
echo "You should see a thin sliver at the right edge of your screen and a note icon in the menu bar."
