#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_DOMAIN="gui/$(id -u)"
LABEL="${SOUNDA_LAUNCHD_LABEL:-sounda-dev}"
LEGACY_LABEL="sounda-test"
TMP_BASE="${TMPDIR:?TMPDIR must be set on macOS}"
PLIST="$TMP_BASE/$LABEL.plist"
STDOUT_LOG="$TMP_BASE/$LABEL.out.log"
STDERR_LOG="$TMP_BASE/$LABEL.err.log"
APP_PATH="$ROOT_DIR/.build/debug/SoundaApp"

swift build --package-path "$ROOT_DIR" --product SoundaApp

launchctl bootout "$USER_DOMAIN/$LEGACY_LABEL" 2>/dev/null || true
launchctl bootout "$USER_DOMAIN/$LABEL" 2>/dev/null || true

rm -f "$PLIST"
/usr/libexec/PlistBuddy -c "Add :Label string $LABEL" "$PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Add :ProgramArguments array" "$PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Add :ProgramArguments:0 string $APP_PATH" "$PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Add :RunAtLoad bool true" "$PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Add :KeepAlive bool false" "$PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Add :StandardOutPath string $STDOUT_LOG" "$PLIST" >/dev/null
/usr/libexec/PlistBuddy -c "Add :StandardErrorPath string $STDERR_LOG" "$PLIST" >/dev/null
plutil -convert xml1 "$PLIST"

launchctl bootstrap "$USER_DOMAIN" "$PLIST"

echo "Sounda launched as $LABEL without KeepAlive."
echo "Quit from the menu bar or Control-Option-Command-Q; launchd will not relaunch it."
