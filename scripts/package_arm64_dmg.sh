#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/build/Arm64DerivedData"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="FocusTime"
VERSION="1.0.0"
APP_PATH="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
STAGE_DIR="$DIST_DIR/dmg-arm64"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-macOS26-arm64.dmg"

cd "$ROOT_DIR"

rm -rf "$DERIVED_DATA" "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$DIST_DIR" "$STAGE_DIR"

xcodebuild \
  -project FocusTime.xcodeproj \
  -scheme FocusTime \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination 'platform=macOS,arch=arm64' \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  -quiet \
  build

ditto "$APP_PATH" "$STAGE_DIR/$APP_NAME.app"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign --verify --deep --strict --verbose=2 "$STAGE_DIR/$APP_NAME.app"
lipo -archs "$STAGE_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"

echo "$DMG_PATH"
