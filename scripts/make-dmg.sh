#!/usr/bin/env bash
# Build a Release app and package it as a DMG.
# Usage: scripts/make-dmg.sh <version> [build-number]
# Output: dist/ClaudeUsage-<version>.dmg (+ .sha256)
# The app is ad-hoc signed (no Developer ID). Widgets and the App Group need a
# Team-signed build; see README.
set -euo pipefail

VERSION="${1:?usage: make-dmg.sh <version> [build-number]}"
BUILD="${2:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="$ROOT/build"
DIST="$ROOT/dist"
APP_NAME="ClaudeUsageWidget"
DMG="$DIST/ClaudeUsage-$VERSION.dmg"

rm -rf "$DERIVED" "$DIST"
mkdir -p "$DIST"

xcodegen generate
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP" ] || { echo "app not found at $APP" >&2; exit 1; }

# Ad-hoc sign so Gatekeeper treats it as a coherent bundle (right-click > Open on first launch).
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Claude Usage.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Claude Usage $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Built $DMG"
