#!/bin/sh
# Installs the LucidMic microphone driver. Runs as root (the app asks for the password).
# Usage: install-driver.sh <path-to-LucidMic.driver>
set -eu
DST=/Library/Audio/Plug-Ins/HAL
mkdir -p "$DST"
rm -rf "$DST/LucidMic.driver"
cp -R "$1" "$DST/LucidMic.driver"
xattr -dr com.apple.quarantine "$DST/LucidMic.driver" 2>/dev/null || true
chown -R root:wheel "$DST/LucidMic.driver"
killall -9 coreaudiod 2>/dev/null || true  # launchd restarts it and it loads the driver
