#!/bin/sh
# Builds dist/LucidMic-<version>.dmg (drag-to-Applications window). Usage: scripts/build.sh [version]
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:-1.0.1}"
case "$VERSION" in
    *[!0-9.]*|'') echo "Version must use numeric major.minor.patch format" >&2; exit 1 ;;
esac
printf '%s\n' "$VERSION" | /usr/bin/grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "Invalid version" >&2; exit 1; }
[ "$(uname -m)" = arm64 ] || { echo "Build on an Apple silicon Mac (arm64)" >&2; exit 1; }
APP=build/LucidMic.app
DMG=dist/LucidMic-$VERSION.dmg

scripts/fetch-deps.sh
scripts/build-driver.sh

swift build -c release --product LucidMic
BIN="$(swift build -c release --show-bin-path)/LucidMic"

rm -rf "$APP"
rm -f "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" dist
cp "$BIN" "$APP/Contents/MacOS/LucidMic"
install_name_tool -delete_rpath "$PWD/build/deps/sherpa/lib" "$APP/Contents/MacOS/LucidMic"  # dev-only path
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/THIRD_PARTY_NOTICES.txt LICENSE "$APP/Contents/Resources/"
cp -R Resources/Licenses "$APP/Contents/Resources/"
cp scripts/runtime-sources.json "$APP/Contents/Resources/Runtime-Sources.json"
cp build/deps/dpdfnet2_48khz_hr.onnx "$APP/Contents/Resources/"
cp build/deps/sherpa/lib/libsherpa-onnx-c-api.dylib build/deps/sherpa/lib/libonnxruntime.dylib "$APP/Contents/Frameworks/"
cp -R build/LucidMic.driver "$APP/Contents/Resources/"
cp scripts/install-driver.sh scripts/uninstall-driver.sh "$APP/Contents/Resources/"
for lib in "$APP"/Contents/Frameworks/*.dylib; do codesign --force --sign - "$lib"; done
codesign --force --sign - "$APP"

uv run --no-project --with-requirements requirements-dev.txt python scripts/verify_release.py "$APP" "$VERSION"
uv run --no-project --with-requirements requirements-dev.txt dmgbuild -s scripts/dmg_settings.py \
    -D app="$APP" -D background=Resources/dmg-background.tiff -D volume_icon=Resources/AppIcon.icns \
    "LucidMic" "$DMG"
hdiutil verify "$DMG"
# Exact corresponding source for the bundled GPL driver; customization lives in scripts/build-driver.sh.
git -C build/blackhole-src archive --format=tar --prefix=BlackHole-0.7.1/ HEAD | gzip -n > "dist/BlackHole-0.7.1-source.tar.gz"
uv run --no-project --with-requirements requirements-dev.txt python scripts/package-runtime-sources.py "$VERSION"
(cd dist && shasum -a 256 "LucidMic-$VERSION.dmg" BlackHole-0.7.1-source.tar.gz "LucidMic-$VERSION-runtime-source.tar.gz" > SHA256SUMS.txt)
echo "Built $DMG"
