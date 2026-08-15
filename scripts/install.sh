#!/bin/zsh
# install.sh
# Installs the HEIC watcher: copies heic-watch.sh to ~/bin, writes a config
# file recording the chosen output format(s), generates + loads a launchd
# agent scoped to this user's real $HOME/Downloads.
#
# Usage:
#   ./install.sh                 # interactive prompt for format
#   ./install.sh --format png    # non-interactive
#   ./install.sh --format jpg
#   ./install.sh --format both

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.$(whoami).heicconverter"
BIN_PATH="$HOME/bin/heic-watch.sh"
APP_SUPPORT="$HOME/Library/Application Support/heic-converter"
CONFIG_FILE="$APP_SUPPORT/config.conf"
PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"
WATCH_DIR="$HOME/Downloads"

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

echo "==> Installing HEIC converter for $(whoami)"
echo "    Format:   $FORMAT"
echo "    Watching: $WATCH_DIR"
echo

mkdir -p "$HOME/bin"
mkdir -p "$APP_SUPPORT"

# --- Script ---
cp "$SCRIPT_DIR/heic-watch.sh" "$BIN_PATH"
chmod +x "$BIN_PATH"

# --- Config ---
cat > "$CONFIG_FILE" << CONF_EOF
# heic-converter config — edit and re-run install.sh, or just edit this
# and the next conversion will pick it up automatically (no reinstall needed).
FORMAT="$FORMAT"
JPG_QUALITY="90"
CONF_EOF

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
        <string>-c</string>
        <string>${BIN_PATH}</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>${WATCH_DIR}</string>
    </array>
    <key>StandardOutPath</key>
    <string>/tmp/heicconverter.out.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/heicconverter.err.log</string>
    <key>ThrottleInterval</key>
    <integer>2</integer>
</dict>
</plist>
PLIST_EOF

launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo "==> Installed. Agent status:"
launchctl list | grep "$LABEL" || echo "    (not showing yet — may need a moment)"
echo
echo "==> Config file (edit anytime, no reinstall needed):"
echo "    $CONFIG_FILE"
