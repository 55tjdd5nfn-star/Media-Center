#!/bin/bash
# Make MediaCenter-1.1.dmg from a built MediaCenter.app
# Step 1 - in Xcode: Product > Archive, then Distribute App >
# Direct Distribution, and save the .app somewhere (e.g. Desktop).
# Step 2 - run this in Terminal, with the path to that .app:
#   bash make-dmg.sh ~/Desktop/MediaCenter.app
# It makes MediaCenter-1.1.dmg next to this script.
set -e
APP="${1:?Usage: bash make-dmg.sh /path/to/MediaCenter.app}"
DMG="MediaCenter-1.1.dmg"
VOL="MediaCenter"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/MediaCenter.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOL" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
echo "Made $DMG - test it by opening it and dragging Media Center to Applications."
