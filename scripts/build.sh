#!/bin/sh
# Builds dist/LucidMic-<version>.dmg (drag-to-Applications). Usage: scripts/build.sh [version]
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
APP=build/LucidMic.app
DMG=dist/LucidMic-$VERSION.dmg

[ -d build/LucidMic.driver ] || scripts/build-driver.sh

swift build -c release --product LucidMic
BIN="$(swift build -c release --show-bin-path)/LucidMic"

rm -rf "$APP" dist build/dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" dist build/dmg
cp "$BIN" "$APP/Contents/MacOS/LucidMic"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp -R build/LucidMic.driver "$APP/Contents/Resources/"
cp scripts/install-driver.sh scripts/uninstall-driver.sh "$APP/Contents/Resources/"
cp build/blackhole-src/LICENSE "$APP/Contents/Resources/BlackHole-LICENSE.txt"
cp Sources/CRNNoise/COPYING "$APP/Contents/Resources/RNNoise-LICENSE.txt"
codesign --force --sign - "$APP"

cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -quiet -volname "LucidMic" -srcfolder build/dmg -ov -format UDZO "$DMG"
echo "Built $DMG"
