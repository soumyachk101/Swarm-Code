#!/bin/bash
# Build script for BridgeMind One
set -e

echo "🔨 Building BridgeMind One..."

# Clean
rm -rf .build

# Build release
swift build -c release

# Run tests
echo "🧪 Running tests..."
swift test

# Create app bundle structure
echo "📦 Packaging app bundle..."
APP_NAME="BridgeMindOne.app"
BUILD_DIR=".build/release"
rm -rf "$APP_NAME"

mkdir -p "$APP_NAME/Contents/MacOS"
mkdir -p "$APP_NAME/Contents/Frameworks"
mkdir -p "$APP_NAME/Contents/Resources"
mkdir -p "$APP_NAME/Contents/Resources/Skills"
mkdir -p "$APP_NAME/Contents/Resources/Sounds"

# Copy binary
cp "$BUILD_DIR/App" "$APP_NAME/Contents/MacOS/BridgeMindOne"
chmod +x "$APP_NAME/Contents/MacOS/BridgeMindOne"

# Copy Info.plist
cp Sources/Resources/Info.plist "$APP_NAME/Contents/Info.plist"

# Copy resources
cp -r Sources/Resources/Skills/*.md "$APP_NAME/Contents/Resources/Skills/"
cp -r Sources/Resources/Sounds/*.wav "$APP_NAME/Contents/Resources/Sounds/" 2>/dev/null || true

echo "✅ Build complete: $APP_NAME"
echo "💡 Open $APP_NAME to run"
