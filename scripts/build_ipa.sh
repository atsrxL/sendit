#!/usr/bin/env bash
# Builds an unsigned SendIt.ipa (ad-hoc signed with entitlements so that
# AltStore / SideStore / Sideloadly can pick up the App Group when re-signing).
# Usage: scripts/build_ipa.sh [extra xcodebuild args...]
set -euo pipefail
cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || { echo "xcodegen not found (brew install xcodegen)"; exit 1; }
xcodegen generate --quiet

rm -rf build/dd/Build/Products dist
mkdir -p build
xcodebuild -project SendIt.xcodeproj -scheme SendIt -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/dd \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  "$@" build 2>&1 | tee build/xcodebuild.log | grep -E "error:|\*\* BUILD"

APP=build/dd/Build/Products/Release-iphoneos/SendIt.app
[ -d "$APP" ] || { echo "Build failed: $APP missing"; exit 1; }

# Ad-hoc sign inside-out with entitlements.
for fw in "$APP"/Frameworks/*.framework; do
  [ -e "$fw" ] && codesign -f -s - "$fw"
done
codesign -f -s - --entitlements ShareExtension/SendItShare.entitlements "$APP/PlugIns/SendItShare.appex"
codesign -f -s - --entitlements App/SendIt.entitlements "$APP"

mkdir -p dist/Payload
cp -R "$APP" dist/Payload/
(cd dist && zip -qry SendIt.ipa Payload && rm -rf Payload)
echo "Built dist/SendIt.ipa ($(stat -f%z dist/SendIt.ipa 2>/dev/null || stat -c%s dist/SendIt.ipa) bytes)"
