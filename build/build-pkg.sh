#!/bin/zsh
# build-pkg.sh — assemble, then sign, a distributable .pkg installer.
#
#   ./build/build-pkg.sh                       # auto-detect both certificates
#   ./build/build-pkg.sh --identity "Developer ID Installer: Name (TEAMID)" \
#                        --app-identity "Developer ID Application: Name (TEAMID)"
#   ./build/build-pkg.sh --unsigned            # local testing only
#
# This needs BOTH Developer ID certificates, which are not interchangeable:
#   Application — signs HEIC Converter.app (the settings window's launcher)
#   Installer   — signs the .pkg itself
# See docs/SIGNING.md.

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
WORK="$PROJECT_DIR/build/_work"
DIST_DIR="$PROJECT_DIR/dist"
PKG_ID="is.bfc.heic-converter"

VERSION="$(< "$PROJECT_DIR/VERSION")"
IDENTITY=""
APP_IDENTITY=""
UNSIGNED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity)     IDENTITY="${2:-}"; shift 2 ;;
    --app-identity) APP_IDENTITY="${2:-}"; shift 2 ;;
    --version)  VERSION="${2:-}";  shift 2 ;;
    --unsigned) UNSIGNED=1; shift ;;
    -h|--help)  /usr/bin/sed -n '2,12p' "$0"; exit 0 ;;
    *) print -r -- "unknown argument: $1" >&2; exit 2 ;;
  esac
done

die() { print -r -- "error: $*" >&2; exit 1; }
step() { print -r -- "==> $*"; }

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "this must run on macOS (needs pkgbuild/productbuild)"

# --- Resolve the signing identities ------------------------------------------
# Two different certificates are involved:
#   Developer ID Application — signs HEIC Converter.app
#   Developer ID Installer   — signs the .pkg itself
# They are not interchangeable, and the errors you get from using the wrong one
# are unhelpful, so resolve both up front.
find_identity() {
  local kind="$1" flag="$2"
  local matches=()
  while IFS= read -r line; do
    matches+=("$line")
  done < <(/usr/bin/security find-identity -v 2>/dev/null \
             | /usr/bin/grep "Developer ID $kind" \
             | /usr/bin/sed -E 's/.*"(.*)".*/\1/')

  case ${#matches[@]} in
    0) die "no 'Developer ID $kind' certificate found in your keychain.
       Create one at https://developer.apple.com/account/resources/certificates
       (see docs/SIGNING.md), or pass --unsigned to build a test package." ;;
    1) print -r -- "${matches[1]}" ;;
    *) print -r -- "Multiple Developer ID $kind certificates found:" >&2
       printf '  %s\n' "${matches[@]}" >&2
       die "pass one explicitly with $flag" ;;
  esac
}

if (( ! UNSIGNED )); then
  if [[ -z "$APP_IDENTITY" ]]; then
    step "Looking for a Developer ID Application certificate"
    APP_IDENTITY="$(find_identity Application --app-identity)" || exit 1
    print -r -- "    using: $APP_IDENTITY"
  fi
  if [[ -z "$IDENTITY" ]]; then
    step "Looking for a Developer ID Installer certificate"
    IDENTITY="$(find_identity Installer --identity)" || exit 1
    print -r -- "    using: $IDENTITY"
  fi
fi

# --- Stage the payload -------------------------------------------------------
step "Staging payload (version $VERSION)"
/bin/rm -rf "$WORK"
/bin/mkdir -p "$WORK/payload/usr/local/lib/heic-converter" \
              "$WORK/payload/usr/local/bin" \
              "$WORK/scripts" \
              "$WORK/resources"

/bin/cp "$PROJECT_DIR/scripts/heic-watch.sh"      "$WORK/payload/usr/local/lib/heic-converter/"
/bin/cp "$PROJECT_DIR/packaging/setup-agent.sh"   "$WORK/payload/usr/local/lib/heic-converter/"
/bin/cp "$PROJECT_DIR/packaging/settings-ui.js"   "$WORK/payload/usr/local/lib/heic-converter/"
/bin/cp "$PROJECT_DIR/VERSION"                    "$WORK/payload/usr/local/lib/heic-converter/"
/bin/cp "$PROJECT_DIR/scripts/heic-converter"     "$WORK/payload/usr/local/bin/"

/bin/chmod 755 "$WORK/payload/usr/local/lib/heic-converter/heic-watch.sh" \
               "$WORK/payload/usr/local/lib/heic-converter/setup-agent.sh" \
               "$WORK/payload/usr/local/bin/heic-converter"
/bin/chmod 644 "$WORK/payload/usr/local/lib/heic-converter/VERSION" \
               "$WORK/payload/usr/local/lib/heic-converter/settings-ui.js"

/bin/cp "$PROJECT_DIR/packaging/preinstall"  "$WORK/scripts/"
/bin/cp "$PROJECT_DIR/packaging/postinstall" "$WORK/scripts/"
/bin/chmod 755 "$WORK/scripts/preinstall" "$WORK/scripts/postinstall"

# --- The settings app --------------------------------------------------------
# Built with osacompile rather than Xcode: the applet stub it produces is
# Apple's own, so this stays buildable on a Mac with no developer tooling beyond
# the signing certificates. This stub is the only Mach-O the project ships,
# which is why a Developer ID *Application* certificate is needed in addition to
# the Installer one.
step "Building HEIC Converter.app"
/bin/mkdir -p "$WORK/payload/Applications"
APP="$WORK/payload/Applications/HEIC Converter.app"
/usr/bin/osacompile -o "$APP" "$PROJECT_DIR/packaging/app-launcher.applescript" \
  || die "osacompile failed to build the settings app"

APP_PLIST="$APP/Contents/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "$PKG_ID.settings" "$APP_PLIST"
/usr/bin/plutil -replace CFBundleName -string "HEIC Converter" "$APP_PLIST"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_PLIST"
/usr/bin/plutil -replace CFBundleVersion -string "$VERSION" "$APP_PLIST"
# Nothing here handles opened documents, and showing up in the Open With menu
# for every file would be noise.
/usr/bin/plutil -remove CFBundleDocumentTypes "$APP_PLIST" 2>/dev/null || true

if (( ! UNSIGNED )); then
  step "Signing HEIC Converter.app"
  /usr/bin/codesign --force --options runtime --timestamp \
    --sign "$APP_IDENTITY" "$APP"
  /usr/bin/codesign --verify --strict --verbose=2 "$APP"
fi

/bin/cp "$PROJECT_DIR/packaging/resources/welcome.html"    "$WORK/resources/"
/bin/cp "$PROJECT_DIR/packaging/resources/conclusion.html" "$WORK/resources/"
/bin/cp "$PROJECT_DIR/LICENSE"                             "$WORK/resources/LICENSE.txt"

/usr/bin/sed "s/__VERSION__/$VERSION/g" \
  "$PROJECT_DIR/packaging/distribution.xml" > "$WORK/distribution.xml"

# --- Build the component package --------------------------------------------
# --ownership recommended installs everything root:wheel regardless of who built
# it, so the payload isn't owned by the build machine's user.
step "Building component package"

# pkgbuild treats any .app it finds in the payload as a *relocatable* bundle by
# default. That means the Installer looks up the bundle identifier on the target
# Mac and, if it finds an existing copy anywhere — a stale one in ~/Downloads,
# say — installs over that instead of /Applications. Pin it to the path we
# actually chose.
/usr/bin/pkgbuild --analyze --root "$WORK/payload" "$WORK/component.plist" >/dev/null
/usr/bin/plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/component.plist" \
  || die "expected pkgbuild to detect HEIC Converter.app as a bundle component;
       it did not, so the relocatable flag could not be cleared."

/usr/bin/pkgbuild \
  --root "$WORK/payload" \
  --scripts "$WORK/scripts" \
  --component-plist "$WORK/component.plist" \
  --identifier "$PKG_ID" \
  --version "$VERSION" \
  --install-location / \
  --ownership recommended \
  "$WORK/component.pkg"

# --- Build the distribution package -----------------------------------------
step "Building distribution package"
/usr/bin/productbuild \
  --distribution "$WORK/distribution.xml" \
  --resources "$WORK/resources" \
  --package-path "$WORK" \
  "$WORK/unsigned.pkg"

/bin/mkdir -p "$DIST_DIR"
OUT="$DIST_DIR/HEIC-Converter-${VERSION}.pkg"

if (( UNSIGNED )); then
  /bin/cp "$WORK/unsigned.pkg" "$OUT"
  print -r -- ""
  print -r -- "!!  Built UNSIGNED: $OUT"
  print -r -- "!!  Gatekeeper will refuse this on any Mac but your own, and it"
  print -r -- "!!  cannot be notarized. For distribution, rebuild without --unsigned."
else
  step "Signing installer"
  /usr/bin/productsign --sign "$IDENTITY" "$WORK/unsigned.pkg" "$OUT"

  step "Verifying signature"
  /usr/sbin/pkgutil --check-signature "$OUT"
fi

print -r -- ""
print -r -- "Built: $OUT"
if (( ! UNSIGNED )); then
  print -r -- "Next:  ./build/notarize.sh"
fi
