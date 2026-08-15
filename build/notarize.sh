#!/bin/zsh
# notarize.sh — submit the signed .pkg to Apple, then staple the ticket to it.
#
#   ./build/notarize.sh                       # newest .pkg in dist/
#   ./build/notarize.sh dist/HEIC-Converter-1.0.0.pkg
#   ./build/notarize.sh --profile my-profile
#
# One-time credential setup — either form works, this script only ever names the
# profile. Full walkthrough in docs/SIGNING.md.
#
#   # App Store Connect API key (recommended):
#   xcrun notarytool store-credentials "heic-converter-notary" \
#     --key AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer-uuid>
#
#   # or Apple ID + app-specific password (not a 2FA code):
#   xcrun notarytool store-credentials "heic-converter-notary" \
#     --apple-id "you@example.com" --team-id "YOURTEAMID"
#
# Stapling is the reason this project moved from a signed .zip to a .pkg. A
# loose .command file can be notarized but not stapled, so Gatekeeper has to
# check with Apple online the first time it runs. Stapling embeds the ticket in
# the .pkg itself, so it verifies offline and on a machine that has never
# spoken to Apple's notary service.

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
DIST_DIR="$PROJECT_DIR/dist"
PROFILE="heic-converter-notary"
PKG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="${2:-}"; shift 2 ;;
    -h|--help) /usr/bin/sed -n '2,18p' "$0"; exit 0 ;;
    *) PKG="$1"; shift ;;
  esac
done

die() { print -r -- "error: $*" >&2; exit 1; }
step() { print -r -- "==> $*"; }

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "this must run on macOS"

if [[ -z "$PKG" ]]; then
  PKG="$(/bin/ls -t "$DIST_DIR"/*.pkg 2>/dev/null | /usr/bin/head -n 1 || true)"
  [[ -n "$PKG" ]] || die "no .pkg found in $DIST_DIR — run ./build/build-pkg.sh first"
fi
[[ -f "$PKG" ]] || die "no such file: $PKG"

# Notarization rejects unsigned packages, and the resulting error is much less
# obvious than this one.
step "Checking the package is signed"
if ! /usr/sbin/pkgutil --check-signature "$PKG" >/dev/null 2>&1; then
  die "$PKG is not signed. Rebuild with ./build/build-pkg.sh (without --unsigned)."
fi

step "Submitting to Apple (this usually takes a few minutes)"
SUBMIT_LOG="$(/usr/bin/mktemp)"
set +e
/usr/bin/xcrun notarytool submit "$PKG" --keychain-profile "$PROFILE" --wait 2>&1 | /usr/bin/tee "$SUBMIT_LOG"
SUBMIT_STATUS=${pipestatus[1]}
set -e

SUBMISSION_ID="$(/usr/bin/grep -Eo '\bid: [0-9a-f-]{36}' "$SUBMIT_LOG" | /usr/bin/head -n 1 | /usr/bin/awk '{print $2}')"

if (( SUBMIT_STATUS != 0 )) || ! /usr/bin/grep -q "status: Accepted" "$SUBMIT_LOG"; then
  print -r -- ""
  print -r -- "Notarization did not succeed."
  if [[ -n "$SUBMISSION_ID" ]]; then
    print -r -- "Fetching the detailed log for submission $SUBMISSION_ID:"
    print -r -- ""
    /usr/bin/xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" || true
  fi
  /bin/rm -f "$SUBMIT_LOG"
  exit 1
fi
/bin/rm -f "$SUBMIT_LOG"

step "Stapling the ticket to the package"
/usr/bin/xcrun stapler staple "$PKG"

step "Validating"
/usr/bin/xcrun stapler validate "$PKG"

# The authoritative check: exactly what Gatekeeper will do on the target Mac.
# --type install is required for installer packages; the default (execute) is
# for applications and reports a misleading failure here.
/usr/sbin/spctl --assess --type install -vv "$PKG"

print -r -- ""
print -r -- "Notarized and stapled: $PKG"
print -r -- "This now installs cleanly on a Mac that has never seen it, with no"
print -r -- "Gatekeeper warning and no network round-trip."
