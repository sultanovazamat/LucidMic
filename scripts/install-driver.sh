#!/bin/sh
# Installs the LucidMic microphone driver. Runs as root (the app asks for the password).
# Usage: install-driver.sh <path-to-LucidMic.driver>
set -eu
DST=/Library/Audio/Plug-Ins/HAL

fail() { echo "$*" >&2; exit 1; }
[ "$#" -eq 1 ] || fail "Usage: install-driver.sh <path-to-LucidMic.driver>"
[ -d "$1" ] && [ ! -L "$1" ] || fail "Driver source must be a directory, not a symbolic link."
[ "$(/usr/bin/id -u)" -eq 0 ] || fail "Driver installation requires administrator privileges."
SRC=$(cd "$1" && pwd -P)

validate() {
    [ -z "$(/usr/bin/find "$1" -type l -print -quit)" ] || fail "Driver contains a symbolic link."
    [ -f "$1/Contents/Info.plist" ] && [ -x "$1/Contents/MacOS/BlackHole" ] || fail "Driver bundle is incomplete."
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist")" = \
        com.sultanovazamat.lucidmic.driver ] || fail "Unexpected driver bundle identifier."
    [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$1/Contents/Info.plist")" = BlackHole ] || \
        fail "Unexpected driver executable."
    /usr/bin/codesign --verify --deep --strict "$1"
}

# Validate before touching an installed driver, then validate the independent copy.
validate "$SRC"
umask 022
/bin/mkdir -p "$DST"
umask 077
STAGE=$(/usr/bin/mktemp -d "$DST/.LucidMic-install.XXXXXX")
INSTALLED="$DST/LucidMic.driver"
COMMITTED=0

cleanup() {
    result=$?
    trap - EXIT HUP INT TERM
    if [ "$COMMITTED" -eq 0 ] && [ -e "$STAGE/previous.driver" ]; then
        /bin/rm -rf "$INSTALLED"
        if ! /bin/mv "$STAGE/previous.driver" "$INSTALLED"; then
            echo "Could not restore the previous driver; it remains at $STAGE/previous.driver" >&2
            exit 1
        fi
    fi
    /bin/rm -rf "$STAGE"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

/bin/cp -R "$SRC" "$STAGE/LucidMic.driver"
validate "$STAGE/LucidMic.driver"
/usr/bin/xattr -dr com.apple.quarantine "$STAGE/LucidMic.driver" 2>/dev/null || true
/usr/sbin/chown -R root:wheel "$STAGE/LucidMic.driver"
/bin/chmod -R a-s,u+rwX,go+rX,go-w "$STAGE/LucidMic.driver"
/usr/bin/codesign --verify --deep --strict "$STAGE/LucidMic.driver"

# Both moves stay on the HAL filesystem. Keep the old bundle until promotion succeeds.
if [ -e "$INSTALLED" ] || [ -L "$INSTALLED" ]; then
    /bin/mv "$INSTALLED" "$STAGE/previous.driver"
fi
/bin/mv "$STAGE/LucidMic.driver" "$INSTALLED"
COMMITTED=1
/usr/bin/killall -9 coreaudiod 2>/dev/null || true  # launchd reloads the complete driver
