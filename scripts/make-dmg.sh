#!/bin/bash
# Builds a drag-to-install DMG for Meshy with macOS's built-in hdiutil.
# Usage: scripts/make-dmg.sh path/to/Meshy.app [output.dmg]
set -euo pipefail

APP="${1:?path to Meshy.app}"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="${2:-Meshy-$VERSION.dmg}"
VOLUME="Meshy"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ART="$ROOT/Design/DMG"   # background.tiff (560×360 @1x+@2x) and VolumeIcon.icns
WORK=$(mktemp -d)
trap 'hdiutil detach "/Volumes/$VOLUME" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

# 1. Staging folder: the app and a shortcut to /Applications.
mkdir "$WORK/stage"
ditto "$APP" "$WORK/stage/Meshy.app"
ln -s /Applications "$WORK/stage/Applications"
mkdir "$WORK/stage/.background"
cp "$ART/background.tiff" "$WORK/stage/.background/background.tiff"

# 2. Writable image, then lay out the Finder window.
# Room for the volume icon and Finder metadata added after mounting.
SIZE_MB=$(( $(du -sm "$WORK/stage" | cut -f1) + $(du -sm "$ART/VolumeIcon.icns" | cut -f1) + 20 ))
hdiutil create -quiet -srcfolder "$WORK/stage" -volname "$VOLUME" -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$WORK/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$WORK/rw.dmg"
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 200, 760, 588}
        set opts to icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 128
        set text size of opts to 13
        set background picture of opts to file ".background:background.tiff"
        set position of item "Meshy.app" of container window to {140, 170}
        set position of item "Applications" of container window to {420, 170}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT
# Disk icon. Added after the Finder step, which removes it (and hdiutil -srcfolder drops it).
cp "$ART/VolumeIcon.icns" "/Volumes/$VOLUME/.VolumeIcon.icns"
xcrun SetFile -a C "/Volumes/$VOLUME"
sync
hdiutil detach -quiet "/Volumes/$VOLUME"

# 3. Compressed, read-only final image.
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUT" -ov
shasum -a 256 "$OUT"
