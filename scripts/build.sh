#!/bin/sh
# Builds dist/LucidMic-<version>.dmg (drag-to-Applications window). Usage: scripts/build.sh [version]
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
APP=build/LucidMic.app
DMG=dist/LucidMic-$VERSION.dmg

scripts/fetch-deps.sh
[ -d build/LucidMic.driver ] || scripts/build-driver.sh

swift build -c release --product LucidMic
BIN="$(swift build -c release --show-bin-path)/LucidMic"

rm -rf "$APP" dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" dist
cp "$BIN" "$APP/Contents/MacOS/LucidMic"
install_name_tool -delete_rpath "$PWD/build/deps/sherpa/lib" "$APP/Contents/MacOS/LucidMic"  # dev-only path
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/THIRD_PARTY_NOTICES.txt "$APP/Contents/Resources/"
cp build/deps/dpdfnet2_48khz_hr.onnx "$APP/Contents/Resources/"
cp build/deps/sherpa/lib/libsherpa-onnx-c-api.dylib build/deps/sherpa/lib/libonnxruntime.dylib "$APP/Contents/Frameworks/"
cp -R build/LucidMic.driver "$APP/Contents/Resources/"
cp scripts/install-driver.sh scripts/uninstall-driver.sh "$APP/Contents/Resources/"
cp build/blackhole-src/LICENSE "$APP/Contents/Resources/BlackHole-LICENSE.txt"
for lib in "$APP"/Contents/Frameworks/*.dylib; do codesign --force --sign - "$lib"; done
codesign --force --sign - "$APP"

uv run --no-project --with dmgbuild dmgbuild -s scripts/dmg_settings.py \
    -D app="$APP" -D background=Resources/dmg-background.tiff -D volume_icon=Resources/AppIcon.icns \
    "LucidMic" "$DMG"
echo "Built $DMG"
