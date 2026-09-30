#!/bin/sh
# Render the README menu illustrations from the same menu items used by LucidMic.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build docs/assets
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 \
    Sources/LucidMic/MenuState.swift Sources/LucidMic/NativeMenu.swift scripts/render-menu.swift \
    -o build/render-menu -framework AppKit
build/render-menu light docs/assets/menu-light.png
build/render-menu dark docs/assets/menu-dark.png
