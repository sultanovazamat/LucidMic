#!/bin/sh
# Builds dist/LucidMic.app and dist/LucidMic-<version>.zip. Usage: scripts/build.sh [version]
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
APP=dist/LucidMic.app

swift build -c release --product LucidMic
BIN="$(swift build -c release --show-bin-path)/LucidMic"

rm -rf dist
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/LucidMic"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" "dist/LucidMic-$VERSION.zip"
echo "Built $APP and dist/LucidMic-$VERSION.zip"
