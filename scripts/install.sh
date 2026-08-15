#!/bin/zsh
# install.sh — install straight from a repo checkout, for the dev loop.
#
# This is the fast path for iterating: the agent points at the heic-watch.sh
# *in this checkout*, so edits take effect on the next dropped file with no
# reinstall step.
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
PROJECT_DIR="${SCRIPT_DIR:h}"
SETUP_AGENT="$PROJECT_DIR/packaging/setup-agent.sh"
CLI="$SCRIPT_DIR/heic-converter"

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
echo

chmod +x "$SCRIPT_DIR/heic-watch.sh" "$CLI" "$SETUP_AGENT"

# setup-agent.sh owns config creation, the plist, the legacy migration, and
# loading the agent — the same code the .pkg runs. Duplicating it here is how
# the two paths would drift.
"$SETUP_AGENT"

# Set the format afterwards, so an existing config (and any custom watch folder)
# survives rather than being overwritten.
"$CLI" format "$FORMAT"

echo
"$CLI" status
