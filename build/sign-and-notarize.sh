#!/bin/zsh
# sign-and-notarize.sh
# Signs Install.command and the bundled scripts with your Developer ID, then
# submits for notarization so Gatekeeper won't show the "unidentified developer"
# warning at all. Run this LOCALLY on your Mac — it uses certs from your own
# keychain and your own notarytool credentials, neither of which exist in this
# sandbox, so this script has NOT been run yet. Treat this as a starting point
# to iterate on in Claude Code.
#
# One-time setup before this will work:
#   1. Have a "Developer ID Application" certificate in Keychain Access
#      (Xcode → Settings → Accounts → Manage Certificates → +  → Developer ID Application)
#   2. Create an app-specific password at appleid.apple.com, then store notarization
#      credentials in your keychain once:
#        xcrun notarytool store-credentials "heic-converter-notary" \
#          --apple-id "you@example.com" \
#          --team-id "YOURTEAMID" \
#          --password "your-app-specific-password"
#
# Usage:
#   ./build/sign-and-notarize.sh "Developer ID Application: Your Name (TEAMID)"

set -e

IDENTITY="$1"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
ZIP_PATH="$DIST_DIR/HEIC-Converter-Installer.zip"
NOTARY_PROFILE="heic-converter-notary"   # matches store-credentials name above

if [[ -z "$IDENTITY" ]]; then
  echo "Usage: $0 \"Developer ID Application: Your Name (TEAMID)\""
  echo
  echo "Find your identity with:"
  echo "  security find-identity -v -p codesigning"
  exit 1
fi

echo "==> Signing with identity: $IDENTITY"

# Sign the .command entry point and the scripts it calls.
codesign --force --options runtime --sign "$IDENTITY" "$PROJECT_DIR/Install.command"
codesign --force --options runtime --sign "$IDENTITY" "$PROJECT_DIR/scripts/install.sh"
codesign --force --options runtime --sign "$IDENTITY" "$PROJECT_DIR/scripts/heic-watch.sh"
codesign --force --options runtime --sign "$IDENTITY" "$PROJECT_DIR/scripts/uninstall.sh"

echo "==> Verifying signatures"
codesign --verify --verbose "$PROJECT_DIR/Install.command"

echo "==> Zipping for notarization"
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH"
cd "$PROJECT_DIR"
zip -rX "$ZIP_PATH" Install.command scripts config README.md -x "build/*" "dist/*"

echo "==> Submitting for notarization (this can take a few minutes)"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling notarization ticket"
# Note: .command / plain scripts can't be stapled directly the way .app/.pkg can.
# Gatekeeper will still check online at first launch (fast, automatic) rather than
# showing the "unidentified developer" block — this is expected and fine for a
# script-based distribution. If you want a fully stapled, offline-verifiable
# artifact, package this as a .pkg installer instead (see README "Going further").

echo "==> Done. Re-zip $ZIP_PATH is ready to distribute from $DIST_DIR"
