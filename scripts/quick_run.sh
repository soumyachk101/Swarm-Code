#!/bin/bash
# Dev loop for Droppy Code: build Debug, install it as the single
# /Applications copy, and relaunch it.
#
#   scripts/quick_run.sh
#
# Builds under build.noindex (never ~/Library/Developer/Xcode/DerivedData),
# because the ".noindex" suffix keeps Spotlight and Launchpad from listing
# the build folder as a second copy of the app. There must only ever be one
# Droppy Code: /Applications/Droppy Code.app.
#
# Safe to run from an agent inside Droppy Code itself: quitting the app may
# interrupt the calling session, but this script keeps going and the fresh
# build picks up the new changes on relaunch.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="Droppy Code"
DERIVED="build.noindex/dev"
PRODUCT="$DERIVED/Build/Products/Debug/$APP_NAME.app"
TARGET="/Applications/$APP_NAME.app"

step() { printf '\n==> %s\n' "$1"; }

step "Building $APP_NAME (Debug)"
xcodebuild \
  -project DroppyCode.xcodeproj \
  -scheme DroppyCode \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -skipPackagePluginValidation \
  build 2>&1 | tail -n 5

step "Installing the single copy to $TARGET"
osascript -e "tell application \"$APP_NAME\" to quit" 2>/dev/null || true
for _ in $(seq 1 20); do
  ps aux | grep -F "$APP_NAME.app/Contents/MacOS" | grep -v grep >/dev/null || break
  sleep 1
done
rm -rf "$TARGET"
ditto "$PRODUCT" "$TARGET"
# Ad-hoc sign the installed copy so Gatekeeper never blocks the dev loop,
# regardless of which build the signature came from.
codesign --force --deep --preserve-metadata=entitlements --sign - "$TARGET"

step "Relaunching"
open "$TARGET"
sleep 4
ps aux | grep -F "$APP_NAME.app/Contents/MacOS" | grep -v grep | head -n 3
