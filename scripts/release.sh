#!/bin/bash
set -euo pipefail

# DockToggle Release Script
# Usage: ./scripts/release.sh [version]
# Example: ./scripts/release.sh 1.1.0

REPO="KirillCustom/DockToggle"
SCHEME="DockToggle"
APP_NAME="DockToggle"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
APPCAST_PATH="$PROJECT_DIR/appcast.xml"

# Find Sparkle sign_update in DerivedData
SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData/DockToggle-*/SourcePackages/artifacts -name "sign_update" -not -path "*/old_dsa_scripts/*" -type f 2>/dev/null | head -1)

if [ -z "$SIGN_UPDATE" ]; then
    echo "Error: sign_update not found. Build the project in Xcode first to fetch Sparkle."
    exit 1
fi

# Get version from argument or from project
if [ $# -ge 1 ]; then
    VERSION="$1"
else
    VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/DockToggle.xcodeproj/project.pbxproj" | head -1 | sed 's/.*= //;s/;.*//')
    echo "No version specified, using current: $VERSION"
fi

echo "==> Building $APP_NAME v$VERSION"
echo ""

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Archive
echo "==> Archiving..."
xcodebuild archive \
    -scheme "$SCHEME" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    MARKETING_VERSION="$VERSION" \
    -quiet

# Export .app from archive
echo "==> Exporting .app..."
cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app" "$APP_PATH"

# Create zip
echo "==> Creating zip..."
cd "$BUILD_DIR"
ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip"
cd "$PROJECT_DIR"

ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
echo "    ZIP size: $ZIP_SIZE bytes"

# Create DMG
echo "==> Creating DMG..."
create-dmg \
    --volname "$APP_NAME" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 150 185 \
    --app-drop-link 450 185 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_PATH" \
    2>/dev/null || true

if [ -f "$DMG_PATH" ]; then
    DMG_SIZE=$(stat -f%z "$DMG_PATH")
    echo "    DMG size: $DMG_SIZE bytes"
else
    echo "    Warning: DMG creation failed, continuing with ZIP only"
fi

# Sign with Sparkle EdDSA
echo "==> Signing with EdDSA..."
SIGNATURE=$("$SIGN_UPDATE" "$ZIP_PATH" 2>&1)
ED_SIGNATURE=$(echo "$SIGNATURE" | grep 'sparkle:edSignature=' | sed 's/.*sparkle:edSignature="//;s/".*//')

if [ -z "$ED_SIGNATURE" ]; then
    echo "Error: Failed to get EdDSA signature."
    echo "sign_update output: $SIGNATURE"
    exit 1
fi

echo "    Signature: ${ED_SIGNATURE:0:20}..."

# Update appcast.xml
DOWNLOAD_URL="https://github.com/$REPO/releases/download/v$VERSION/$APP_NAME.zip"
PUB_DATE=$(date -R)
BUILD_NUMBER=$(grep 'CURRENT_PROJECT_VERSION' "$PROJECT_DIR/DockToggle.xcodeproj/project.pbxproj" | head -1 | sed 's/.*= //;s/;.*//')

echo "==> Updating appcast.xml..."

cat > "$APPCAST_PATH" << EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
  <channel>
    <title>DockToggle</title>
    <link>https://github.com/$REPO</link>
    <description>DockToggle update feed</description>
    <language>en</language>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure
        url="$DOWNLOAD_URL"
        length="$ZIP_SIZE"
        type="application/octet-stream"
        sparkle:edSignature="$ED_SIGNATURE"
      />
    </item>
  </channel>
</rss>
EOF

echo ""
echo "==> Done!"
echo ""
echo "Next steps:"
echo "  1. Commit updated appcast.xml and push to main"
echo "  2. Create GitHub release v$VERSION and upload artifacts:"
echo "     $ZIP_PATH"
if [ -f "$DMG_PATH" ]; then
echo "     $DMG_PATH"
fi
echo ""
echo "Quick commands:"
echo "  git add appcast.xml && git commit -m \"Update appcast for v$VERSION\""
echo "  git push"
if [ -f "$DMG_PATH" ]; then
echo "  gh release create v$VERSION \"$ZIP_PATH\" \"$DMG_PATH\" --title \"v$VERSION\" --notes \"Release v$VERSION\""
else
echo "  gh release create v$VERSION \"$ZIP_PATH\" --title \"v$VERSION\" --notes \"Release v$VERSION\""
fi
