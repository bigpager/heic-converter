#!/bin/zsh
# install.sh — install straight from a repo checkout, for the dev loop.
#
# This is the fast path for iterating: it points the launchd agent at the
# heic-watch.sh *in this checkout*, so edits take effect on the next dropped
# file with no reinstall step.
#
# For distribution, build the signed .pkg instead:
#   make pkg && make notarize
#
# Usage:
#   ./install.sh                 # interactive prompt for format
#   ./install.sh --format png    # non-interactive
#   ./install.sh --format jpg
#   ./install.sh --format both

set -e

SCRIPT_DIR="${0:A:h}"
LABEL="is.bfc.heic-converter"
APP_SUPPORT="$HOME/Library/Application Support/heic-converter"
CONFIG_FILE="$APP_SUPPORT/config.conf"
LOG_DIR="$HOME/Library/Logs"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
WATCH_DIR="$HOME/Downloads"
WATCHER="$SCRIPT_DIR/heic-watch.sh"

FORMAT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format) FORMAT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$FORMAT" ]]; then
  echo "Convert HEIC files to which format?"
  echo "  1) PNG"
  echo "  2) JPG"
  echo "  3) Both"
  read "choice?Enter 1, 2, or 3: "
  case "$choice" in
    1) FORMAT="png" ;;
    2) FORMAT="jpg" ;;
    3) FORMAT="both" ;;
    *) echo "Invalid choice, defaulting to png"; FORMAT="png" ;;
  esac
fi

if [[ "$FORMAT" != "png" && "$FORMAT" != "jpg" && "$FORMAT" != "both" ]]; then
  echo "Invalid --format: $FORMAT (expected png, jpg, or both)"
  exit 1
fi

echo "==> Installing HEIC converter (dev mode) for $(whoami)"
echo "    Format:   $FORMAT"
echo "    Watching: $WATCH_DIR"
echo "    Watcher:  $WATCHER"
echo

mkdir -p "$APP_SUPPORT" "$LOG_DIR" "$HOME/Library/LaunchAgents"
chmod +x "$WATCHER"

# --- Config ---
cat > "$CONFIG_FILE" << CONF_EOF
# heic-converter config — the watcher re-reads this on every run, so changes
# take effect on the next converted file. No reinstall needed.
FORMAT="$FORMAT"
JPG_QUALITY="90"
CONF_EOF

# --- Retire the pre-1.0 per-user agent, if this machine has one ---
LEGACY_LABEL="com.$(whoami).heicconverter"
LEGACY_PLIST="$HOME/Library/LaunchAgents/${LEGACY_LABEL}.plist"
if [[ -f "$LEGACY_PLIST" ]]; then
  echo "==> Removing legacy agent $LEGACY_LABEL"
  launchctl bootout "gui/$(id -u)/${LEGACY_LABEL}" 2>/dev/null || true
  rm -f "$LEGACY_PLIST" "$HOME/bin/heic-watch.sh"
fi

# --- launchd plist ---
cat > "$PLIST_PATH" << PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>${WATCHER}</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>${WATCH_DIR}</string>
    </array>
    <key>StandardOutPath</key>
    <string>${LOG_DIR}/heic-converter.out.log</string>
    <key>StandardErrorPath</key>
    <string>${LOG_DIR}/heic-converter.err.log</string>
    <key>ThrottleInterval</key>
    <integer>2</integer>
</dict>
</plist>
PLIST_EOF

plutil -lint "$PLIST_PATH" > /dev/null

launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo "==> Installed. Agent status:"
launchctl print "gui/$(id -u)/${LABEL}" > /dev/null 2>&1 \
  && echo "    loaded" \
  || echo "    (not loaded yet — may need a moment)"
echo
echo "==> Config file (edit anytime, no reinstall needed):"
echo "    $CONFIG_FILE"
