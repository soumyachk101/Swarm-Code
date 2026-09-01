#!/bin/bash
# Build script for BridgeMind One (App Bundle & DMG)
set -e

echo "🔨 Building BridgeMind One release binary..."

# Build release
swift build -c release

# Create app bundle structure
echo "📦 Packaging BridgeMindOne.app bundle..."
APP_NAME="BridgeMindOne.app"
BUILD_DIR=".build/release"
rm -rf "$APP_NAME"

mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Frameworks"
mkdir -p "$APP_NAME/Contents/Resources"
mkdir -p "$APP_NAME/Contents/Resources/Skills"
mkdir -p "$APP_NAME/Contents/Resources/Sounds"

# Copy binary
if [ -f "$BUILD_DIR/BridgeMindOne" ]; then
    cp "$BUILD_DIR/BridgeMindOne" "$APP_NAME/Contents/MacOS/BridgeMindOne"
elif [ -f "$BUILD_DIR/App" ]; then
    cp "$BUILD_DIR/App" "$APP_NAME/Contents/MacOS/BridgeMindOne"
fi
chmod +x "$APP_NAME/Contents/MacOS/BridgeMindOne"

# Copy Info.plist
cp Sources/Resources/Info.plist "$APP_NAME/Contents/Info.plist"

# Copy AppIcon and all resource icons
cp Sources/Resources/AppIcon.icns "$APP_NAME/Contents/Resources/" 2>/dev/null || true
cp Sources/Resources/*.png "$APP_NAME/Contents/Resources/" 2>/dev/null || true

# Copy skills & sounds
cp -r Sources/Resources/Skills/*.md "$APP_NAME/Contents/Resources/Skills/" 2>/dev/null || true
cp -r Sources/Resources/Sounds/*.wav "$APP_NAME/Contents/Resources/Sounds/" 2>/dev/null || true

echo "✅ App bundle created: $APP_NAME"

# Package DMG if hdiutil is available
echo "💿 Creating BridgeMindOne-universal.dmg..."
DMG_NAME="BridgeMindOne-universal.dmg"
DMG_TEMP="dmg_temp"
rm -rf "$DMG_TEMP" "$DMG_NAME"
mkdir -p "$DMG_TEMP"

cp -R "$APP_NAME" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create -volname "BridgeMind" -srcfolder "$DMG_TEMP" -ov -format UDZO "$DMG_NAME"
rm -rf "$DMG_TEMP"

echo "🎉 Build & Packaging complete!"
echo "📍 Application: $(pwd)/$APP_NAME"
echo "📍 DMG: $(pwd)/$DMG_NAME"
