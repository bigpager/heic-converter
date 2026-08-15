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

chmod +x scripts/heic-converter scripts/*.sh packaging/setup-agent.sh 2>/dev/null

# Create the agent first so a config exists, then let setup drive the dialogs
# for format, JPEG quality, and which folder to watch.
./scripts/heic-converter install-agent || exit 1
./scripts/heic-converter setup || exit 1

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
echo "✅ All set. Drop a .heic file into the watched folder to test it."
echo
echo "   Change settings later:  ./scripts/heic-converter setup"
echo "   Troubleshoot:           ./scripts/heic-converter doctor"
echo
read "?Press Return to close this window... "
