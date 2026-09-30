#!/bin/sh
# Removes the LucidMic microphone driver. Runs as root (the app asks for the password).
set -eu
rm -rf /Library/Audio/Plug-Ins/HAL/LucidMic.driver
killall -9 coreaudiod 2>/dev/null || true
