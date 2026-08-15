#!/bin/zsh
# uninstall.sh — removes the agent, config, and any installed files. Leaves
# already-converted images alone.
#
# Handles all three install shapes: the current .pkg, a dev-mode install from a
# repo checkout, and the pre-1.0 per-user agent.

LABEL="is.bfc.heic-converter"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
APP_SUPPORT="$HOME/Library/Application Support/heic-converter"

LEGACY_LABEL="com.$(whoami).heicconverter"
LEGACY_PLIST="$HOME/Library/LaunchAgents/${LEGACY_LABEL}.plist"
LEGACY_BIN="$HOME/bin/heic-watch.sh"

echo "==> Removing HEIC converter"

launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
rm -f "$PLIST_PATH"

launchctl bootout "gui/$(id -u)/${LEGACY_LABEL}" 2>/dev/null || true
rm -f "$LEGACY_PLIST" "$LEGACY_BIN"

rm -rf "$APP_SUPPORT"

# Installed by the .pkg, so removing it needs root — only ask if it's there.
if [[ -e /usr/local/lib/heic-converter || -e /usr/local/bin/heic-converter \
      || -e "/Applications/HEIC Converter.app" ]]; then
  echo "==> Removing system files (requires your password)"
  sudo rm -rf /usr/local/lib/heic-converter /usr/local/bin/heic-converter \
              "/Applications/HEIC Converter.app"
  sudo pkgutil --forget is.bfc.heic-converter > /dev/null 2>&1 || true
fi

echo "==> Done. (Full Disk Access grant for /bin/zsh was left in place —"
echo "    remove it manually in System Settings if you no longer want it.)"
