#!/bin/zsh
# build-pkg.sh — assemble, then sign, a distributable .pkg installer.
#
#   ./build/build-pkg.sh                       # auto-detect your Developer ID Installer cert
#   ./build/build-pkg.sh --identity "Developer ID Installer: Name (TEAMID)"
#   ./build/build-pkg.sh --unsigned            # local testing only
#
# Note this needs a "Developer ID **Installer**" certificate, which is a different
# certificate from the "Developer ID **Application**" one used to sign binaries.
# A .pkg whose payload is entirely shell scripts has no Mach-O code in it, so the
# Application certificate is not involved at all. See docs/SIGNING.md.

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
WORK="$PROJECT_DIR/build/_work"
DIST_DIR="$PROJECT_DIR/dist"
PKG_ID="is.bfc.heic-converter"

VERSION="$(< "$PROJECT_DIR/VERSION")"
IDENTITY=""
UNSIGNED=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --identity) IDENTITY="${2:-}"; shift 2 ;;
    --version)  VERSION="${2:-}";  shift 2 ;;
    --unsigned) UNSIGNED=1; shift ;;
    -h|--help)  /usr/bin/sed -n '2,12p' "$0"; exit 0 ;;
    *) print -r -- "unknown argument: $1" >&2; exit 2 ;;
  esac
done

die() { print -r -- "error: $*" >&2; exit 1; }
step() { print -r -- "==> $*"; }

[[ "$(/usr/bin/uname -s)" == "Darwin" ]] || die "this must run on macOS (needs pkgbuild/productbuild)"

# --- Resolve the signing identity -------------------------------------------
if (( ! UNSIGNED )) && [[ -z "$IDENTITY" ]]; then
  step "Looking for a Developer ID Installer certificate"
  local_matches=()
  while IFS= read -r line; do
    local_matches+=("$line")
  done < <(/usr/bin/security find-identity -v 2>/dev/null \
             | /usr/bin/grep "Developer ID Installer" \
             | /usr/bin/sed -E 's/.*"(.*)".*/\1/')

  case ${#local_matches[@]} in
    0) die "no 'Developer ID Installer' certificate found in your keychain.
       Create one at https://developer.apple.com/account/resources/certificates
       (see docs/SIGNING.md), or pass --unsigned to build a test package." ;;
    1) IDENTITY="${local_matches[1]}" ;;
    *) print -r -- "Multiple Developer ID Installer certificates found:" >&2
       printf '  %s\n' "${local_matches[@]}" >&2
       die "pass one explicitly with --identity" ;;
  esac
  print -r -- "    using: $IDENTITY"
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

/bin/cp "$PROJECT_DIR/packaging/resources/welcome.html"    "$WORK/resources/"
/bin/cp "$PROJECT_DIR/packaging/resources/conclusion.html" "$WORK/resources/"
/bin/cp "$PROJECT_DIR/LICENSE"                             "$WORK/resources/LICENSE.txt"

/usr/bin/sed "s/__VERSION__/$VERSION/g" \
  "$PROJECT_DIR/packaging/distribution.xml" > "$WORK/distribution.xml"

# --- Build the component package --------------------------------------------
# --ownership recommended installs everything root:wheel regardless of who built
# it, so the payload isn't owned by the build machine's user.
step "Building component package"
/usr/bin/pkgbuild \
  --root "$WORK/payload" \
  --scripts "$WORK/scripts" \
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
