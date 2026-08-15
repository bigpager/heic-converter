#!/bin/zsh
# uninstall.sh — removes the agent, script, and config. Leaves any already-converted
# images alone.

LABEL="com.$(whoami).heicconverter"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
BIN_PATH="$HOME/bin/heic-watch.sh"
APP_SUPPORT="$HOME/Library/Application Support/heic-converter"

echo "==> Removing HEIC converter"

launchctl unload "$PLIST_PATH" 2>/dev/null || true
rm -f "$PLIST_PATH"
rm -f "$BIN_PATH"
rm -rf "$APP_SUPPORT"

echo "==> Done. (Full Disk Access grant for /bin/zsh was left in place —"
echo "    remove it manually in System Settings if you no longer want it.)"
