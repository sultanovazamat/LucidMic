#!/bin/sh
# Builds build/LucidMic.driver: BlackHole v0.7.1 (GPL-3.0) renamed to two LucidMic devices that share one buffer:
#   "LucidMic Microphone" (visible, input only)  <- call apps read this
#   "LucidMic Feed"       (hidden, output only)  <- LucidMic.app writes clean audio here
set -eu
cd "$(dirname "$0")/.."
SRC=build/blackhole-src
OUT=build/LucidMic.driver
FACTORY_UUID=3F377EC4-ED4B-4F93-A13A-206FB8B0A1BC  # unique, so it never clashes with a real BlackHole install

[ -d "$SRC" ] || git clone -q --depth 1 --branch v0.7.1 https://github.com/ExistentialAudio/BlackHole.git "$SRC"

xcodebuild -project "$SRC/BlackHole.xcodeproj" -target BlackHole -configuration Release SYMROOT="$PWD/build/blackhole-build" \
    PRODUCT_BUNDLE_IDENTIFIER=com.sultanovazamat.lucidmic.driver CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM= ARCHS=arm64 ONLY_ACTIVE_ARCH=NO MACOSX_DEPLOYMENT_TARGET=14.0 \
    GCC_PREPROCESSOR_DEFINITIONS='$GCC_PREPROCESSOR_DEFINITIONS kDriver_Name=\"LucidMic\" kPlugIn_BundleID=\"com.sultanovazamat.lucidmic.driver\" kHas_Driver_Name_Format=false kDevice_Name=\"LucidMic\ Microphone\" kDevice2_Name=\"LucidMic\ Feed\" kDevice_HasInput=true kDevice_HasOutput=false kDevice2_HasInput=false kDevice2_HasOutput=true kDevice2_IsHidden=true kManufacturer_Name=\"LucidMic\"' \
    build >build/driver-build.log 2>&1 || { tail -20 build/driver-build.log; exit 1; }

rm -rf "$OUT"
cp -R build/blackhole-build/Release/BlackHole.driver "$OUT"
PLIST="$OUT/Contents/Info.plist"
OLD_UUID=$(/usr/libexec/PlistBuddy -c "Print :CFPlugInTypes:443ABAB8-E7B3-491A-B985-BEB9187030DB:0" "$PLIST")
/usr/libexec/PlistBuddy -c "Delete :CFPlugInFactories:$OLD_UUID" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :CFPlugInFactories:$FACTORY_UUID string BlackHole_Create" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFPlugInTypes:443ABAB8-E7B3-491A-B985-BEB9187030DB:0 $FACTORY_UUID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName LucidMic" "$PLIST"
codesign --force --sign - "$OUT"
echo "Built $OUT"
