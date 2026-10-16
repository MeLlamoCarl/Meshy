#!/bin/bash
# Builds a universal (Apple silicon + Intel), ad-hoc signed Meshy.app and packs it into a DMG.
# Output: dist/Meshy-<version>.dmg (+ its SHA-256). Requires Xcode; no Apple Developer account.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DERIVED="$ROOT/build/release"

xcodebuild -scheme Meshy -configuration Release -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -quiet

APP="$DERIVED/Build/Products/Release/Meshy.app"
# Ad-hoc signature: free, keeps the bundle intact and lets Gatekeeper offer "Open Anyway".
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p dist
"$ROOT/scripts/make-dmg.sh" "$APP" "dist/Meshy-$VERSION.dmg" | tee "dist/Meshy-$VERSION.dmg.sha256"
echo "Built dist/Meshy-$VERSION.dmg ($(lipo -archs "$APP/Contents/MacOS/Meshy"))"
