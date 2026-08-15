#!/bin/zsh
# Install.command — double-click entry point.
# Shows a native macOS dialog to pick the output format, then runs install.sh.

cd "$(dirname "$0")"

clear
echo "═══════════════════════════════════════════════════"
echo "  HEIC Converter — Installer"
echo "═══════════════════════════════════════════════════"
echo

CHOICE=$(osascript -e 'tell application "System Events"
  activate
  set theChoice to button returned of (display dialog "Convert HEIC files in Downloads to:" buttons {"PNG", "JPG", "Both"} default button "Both" with title "HEIC Converter")
end tell
return theChoice')

case "$CHOICE" in
  "PNG")  FORMAT="png" ;;
  "JPG")  FORMAT="jpg" ;;
  "Both") FORMAT="both" ;;
  *) echo "Cancelled."; exit 0 ;;
esac

echo "Selected format: $FORMAT"
echo

./scripts/install.sh --format "$FORMAT"

echo
echo "═══════════════════════════════════════════════════"
echo "  ONE MORE STEP (required — can't be automated):"
echo "═══════════════════════════════════════════════════"
echo
echo "  1. Open System Settings"
echo "  2. Go to Privacy & Security → Full Disk Access"
echo "  3. Click the '+' button"
echo "  4. Press Cmd+Shift+G, type: /bin/zsh"
echo "  5. Add it, then turn the toggle ON"
echo "  6. Come back here and press Return to finish"
echo
read "?Press Return once you've done that... "

LABEL="com.$(whoami).heicconverter"
launchctl unload "$HOME/Library/LaunchAgents/${LABEL}.plist" 2>/dev/null || true
launchctl load "$HOME/Library/LaunchAgents/${LABEL}.plist"

echo
echo "✅ All set. Drop a .heic file into Downloads to test it."
echo "   (You can change the format later by editing:"
echo "    ~/Library/Application Support/heic-converter/config.conf)"
echo
read "?Press Return to close this window... "
