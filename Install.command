#!/bin/zsh
# Install.command — double-click entry point for running from a source checkout.
#
# For distribution, prefer the signed .pkg (`make pkg && make notarize`): it is
# notarized *and stapled*, so it installs with no Gatekeeper warning and no
# online check. This file is kept for the local dev loop, where it points the
# agent at the scripts in this checkout so edits take effect immediately.

cd "$(dirname "$0")"

clear
echo "═══════════════════════════════════════════════════"
echo "  HEIC Converter — Installer (source checkout)"
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
echo
echo "  Opening that pane for you now..."
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null
echo
read "?Press Return once you've done that... "

echo
echo "✅ All set. Drop a .heic file into Downloads to test it."
echo
echo "   Change format later:  ./scripts/heic-converter format png"
echo "   Troubleshoot:         ./scripts/heic-converter doctor"
echo
read "?Press Return to close this window... "
