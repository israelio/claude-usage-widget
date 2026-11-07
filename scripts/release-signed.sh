#!/usr/bin/env bash
# Build, Developer-ID sign, notarize and package a DMG locally. Keys never leave this Mac.
#
# Usage: scripts/release-signed.sh <version> [--upload]
#   --upload   replace the DMG + checksum on the existing GitHub release v<version> (gh release upload --clobber)
#
# One-time setup:
#   1. Developer ID Application certificate in your login keychain
#      (Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application).
#   2. Notary login:  xcrun notarytool store-credentials notary \
#                       --apple-id <id> --team-id <TEAM_ID> --password <app-specific-password>
#   3. Local.xcconfig with DEVELOPMENT_TEAM and APP_GROUP_ID (see Local.xcconfig.example).
# Overrides: NOTARY_PROFILE (default "notary"), BUILD_NUMBER (default 1).
set -euo pipefail

VERSION="${1:?usage: release-signed.sh <version> [--upload]}"
UPLOAD="${2:-}"
BUILD="${BUILD_NUMBER:-1}"
PROFILE="${NOTARY_PROFILE:-notary}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="ClaudeUsageWidget"
DERIVED="$ROOT/build"
DIST="$ROOT/dist"
DMG="$DIST/ClaudeUsage-$VERSION.dmg"
REPO="israelio/claude-usage-widget"

fail() { echo "error: $*" >&2; exit 1; }

# --- preflight ---------------------------------------------------------------
[ -f Local.xcconfig ] || fail "Local.xcconfig missing (copy Local.xcconfig.example and set DEVELOPMENT_TEAM / APP_GROUP_ID)"
TEAM="$(sed -nE 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*([A-Z0-9]+).*/\1/p' Local.xcconfig | head -1)"
[ -n "$TEAM" ] || fail "DEVELOPMENT_TEAM not set in Local.xcconfig"

IDENTITY="$(security find-identity -v -p codesigning | sed -nE 's/.*"(Developer ID Application:[^"]*\('"$TEAM"'\))".*/\1/p' | head -1)"
[ -n "$IDENTITY" ] || fail "no 'Developer ID Application' certificate for team $TEAM in your keychain (see setup in this script's header)"

xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || fail "notary login '$PROFILE' not found (run: xcrun notarytool store-credentials $PROFILE ...)"

if [ "$UPLOAD" = "--upload" ]; then
  command -v gh >/dev/null || fail "gh CLI required for --upload"
  gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1 \
    || fail "release v$VERSION does not exist on $REPO (tag it first, e.g. git tag v$VERSION && git push origin v$VERSION)"
fi
echo "Signing as: $IDENTITY (team $TEAM)"

# --- build + export (Developer ID) -------------------------------------------
rm -rf "$DERIVED" "$DIST"; mkdir -p "$DIST"
xcodegen generate

ARCHIVE="$DERIVED/$APP_NAME.xcarchive"
xcodebuild -project "$APP_NAME.xcodeproj" -scheme "$APP_NAME" -configuration Release \
  -destination 'platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" archive

cat > "$DERIVED/exportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$DERIVED/export" \
  -exportOptionsPlist "$DERIVED/exportOptions.plist" -allowProvisioningUpdates

APP="$DERIVED/export/$APP_NAME.app"
[ -d "$APP" ] || fail "exported app not found at $APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# --- notarize + staple the app ------------------------------------------------
ZIP="$DERIVED/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

# --- DMG: package, sign, notarize, staple -------------------------------------
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/Claude Usage.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Claude Usage $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

# --- verify -------------------------------------------------------------------
xcrun stapler validate "$DMG"
spctl -a -t open --context context:primary-signature -vv "$DMG"
spctl -a -t exec -vv "$APP"
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
echo "Built and notarized: $DMG"

# --- publish ------------------------------------------------------------------
if [ "$UPLOAD" = "--upload" ]; then
  gh release upload "v$VERSION" "$DMG" "$DMG.sha256" --repo "$REPO" --clobber
  echo "Uploaded to https://github.com/$REPO/releases/tag/v$VERSION"
else
  echo "Not uploaded. To publish: scripts/release-signed.sh $VERSION --upload"
fi
