#!/bin/bash
# Generate all app icon sizes from appicon.png in project root

set -e
cd "$(dirname "$0")"

SOURCE="appicon.png"
DEST="Todo/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SOURCE" ]; then
    echo "Error: $SOURCE not found in project root"
    exit 1
fi

echo "Generating icons from $SOURCE..."

# iOS (1024x1024)
cp "$SOURCE" "$DEST/icon_1024x1024.png"

# macOS sizes
sips -z 16 16 "$SOURCE" --out "$DEST/icon_16x16.png"
sips -z 32 32 "$SOURCE" --out "$DEST/icon_16x16@2x.png"
sips -z 32 32 "$SOURCE" --out "$DEST/icon_32x32.png"
sips -z 64 64 "$SOURCE" --out "$DEST/icon_32x32@2x.png"
sips -z 128 128 "$SOURCE" --out "$DEST/icon_128x128.png"
sips -z 256 256 "$SOURCE" --out "$DEST/icon_128x128@2x.png"
sips -z 256 256 "$SOURCE" --out "$DEST/icon_256x256.png"
sips -z 512 512 "$SOURCE" --out "$DEST/icon_256x256@2x.png"
sips -z 512 512 "$SOURCE" --out "$DEST/icon_512x512.png"
cp "$SOURCE" "$DEST/icon_512x512@2x.png"

echo "Done. Icons generated in $DEST"
