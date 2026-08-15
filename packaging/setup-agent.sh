#!/bin/zsh
# setup-agent.sh [username]
#
# Wires up the per-user half of the install: the config file and the launchd
# WatchPaths agent. The .pkg payload is system-wide (/usr/local/...), but the
# watcher has to run *as the logged-in user* — it reads that user's ~/Downloads
# and writes converted images next to the originals. So the agent can't live in
# the payload; it has to be materialised per user, which is what this does.
#
# Called two ways:
#   - from the .pkg postinstall, as root, with the console user as $1
#   - by hand via `heic-converter install-agent`, as the user, with no argument
#
# Also migrates anyone off the older per-user install (the com.$USER.heicconverter
# agent that scripts/install.sh used to create), so a machine that had the old
# .command installer doesn't end up running two watchers over the same folder.

set -u

LABEL="is.bfc.heic-converter"
LIB_DIR="/usr/local/lib/heic-converter"
WATCHER="$LIB_DIR/heic-watch.sh"

log() { print -r -- "[heic-converter] $*"; }
die() { print -r -- "[heic-converter] error: $*" >&2; exit 1; }

CURRENT_USER="$(/usr/bin/id -un)"
TARGET_USER="${1:-$CURRENT_USER}"

if [[ "$TARGET_USER" != "$CURRENT_USER" && "$(/usr/bin/id -u)" != "0" ]]; then
  die "setting up for another user ($TARGET_USER) requires root; re-run with sudo."
fi

TARGET_UID="$(/usr/bin/id -u "$TARGET_USER" 2>/dev/null)" \
  || die "no such user: $TARGET_USER"
# Parse with sed rather than `awk '{print $2}'`: a home directory containing a
# space would otherwise be silently truncated at the first one.
TARGET_HOME="$(/usr/bin/dscl . -read "/Users/$TARGET_USER" NFSHomeDirectory 2>/dev/null | /usr/bin/sed -n 's/^NFSHomeDirectory: //p')"
[[ -n "$TARGET_HOME" && -d "$TARGET_HOME" ]] \
  || die "could not resolve a home directory for $TARGET_USER"

[[ -x "$WATCHER" ]] || die "watcher not found at $WATCHER (is the package installed?)"

APP_SUPPORT="$TARGET_HOME/Library/Application Support/heic-converter"
CONFIG_FILE="$APP_SUPPORT/config.conf"
LOG_DIR="$TARGET_HOME/Library/Logs"
LAUNCH_AGENTS="$TARGET_HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENTS/${LABEL}.plist"
WATCH_DIR="$TARGET_HOME/Downloads"

# Escape the handful of characters that would otherwise break the plist. Home
# directory paths are usually boring, but "Ben & Jerry" is a legal macOS
# username and would produce invalid XML.
xml_escape() {
  print -r -- "$1" | /usr/bin/sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

/bin/mkdir -p "$APP_SUPPORT" "$LOG_DIR" "$LAUNCH_AGENTS" "$WATCH_DIR"

# --- Config -----------------------------------------------------------------
# Never clobber an existing config: on upgrade, or on a reinstall over the old
# .command-based install, the user's chosen format has to survive.
if [[ -f "$CONFIG_FILE" ]]; then
  log "keeping existing config at $CONFIG_FILE"
else
  /bin/cat > "$CONFIG_FILE" <<'CONF'
# heic-converter config
#
# heic-watch.sh re-reads this file on every run, so changes take effect on the
# next file dropped into the watched folder — no reinstall, no logout.
# Easiest way to change it:  heic-converter format both

FORMAT="both"        # png | jpg | both
JPG_QUALITY="90"     # 0-100 (passed to sips formatOptions)

# Folder to watch. Changing this needs the agent rebuilt so launchd picks up the
# new WatchPaths entry:  heic-converter install-agent
# WATCH_DIR="$HOME/Downloads"
CONF
  log "wrote default config to $CONFIG_FILE"
fi

# --- Retire the legacy per-user agent ---------------------------------------
LEGACY_LABEL="com.${TARGET_USER}.heicconverter"
LEGACY_PLIST="$LAUNCH_AGENTS/${LEGACY_LABEL}.plist"
LEGACY_BIN="$TARGET_HOME/bin/heic-watch.sh"

if [[ -f "$LEGACY_PLIST" ]]; then
  log "removing legacy agent $LEGACY_LABEL"
  /bin/launchctl bootout "gui/${TARGET_UID}/${LEGACY_LABEL}" 2>/dev/null
  /bin/rm -f "$LEGACY_PLIST"
fi
[[ -f "$LEGACY_BIN" ]] && /bin/rm -f "$LEGACY_BIN"

# --- LaunchAgent -------------------------------------------------------------
/bin/cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>$(xml_escape "$WATCHER")</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>$(xml_escape "$WATCH_DIR")</string>
    </array>
    <key>StandardOutPath</key>
    <string>$(xml_escape "$LOG_DIR/heic-converter.out.log")</string>
    <key>StandardErrorPath</key>
    <string>$(xml_escape "$LOG_DIR/heic-converter.err.log")</string>
    <key>ThrottleInterval</key>
    <integer>2</integer>
</dict>
</plist>
PLIST_EOF

/usr/bin/plutil -lint "$PLIST" >/dev/null || die "generated an invalid plist at $PLIST"

# Anything created above while running as root has to end up owned by the user,
# or launchd will refuse to load the agent ("Path had bad ownership/permissions").
if [[ "$(/usr/bin/id -u)" == "0" ]]; then
  /usr/sbin/chown "$TARGET_USER" "$PLIST" "$CONFIG_FILE"
  /usr/sbin/chown -R "$TARGET_USER" "$APP_SUPPORT"
fi
/bin/chmod 644 "$PLIST"

# --- Load it -----------------------------------------------------------------
# bootout first so a reinstall picks up the regenerated plist rather than
# silently keeping the old definition loaded.
/bin/launchctl bootout "gui/${TARGET_UID}/${LABEL}" 2>/dev/null
if /bin/launchctl bootstrap "gui/${TARGET_UID}" "$PLIST" 2>/dev/null; then
  log "agent loaded for $TARGET_USER (watching $WATCH_DIR)"
else
  # A bootstrap failure here is not fatal: the agent will load at next login.
  log "agent installed but could not be loaded now — it will start at next login"
fi

exit 0
