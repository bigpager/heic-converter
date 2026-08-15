#!/bin/zsh
# heic-watch.sh
# Converts *.heic / *.HEIC files in $WATCH_DIR to PNG, JPG, or both,
# based on the config file. Designed to be run by the launchd WatchPaths
# agent that packaging/setup-agent.sh installs, but works fine run manually
# (`heic-converter run`) or via cron too.

WATCH_DIR="$HOME/Downloads"
APP_SUPPORT="$HOME/Library/Application Support/heic-converter"
CONFIG_FILE="$APP_SUPPORT/config.conf"
LOG="$HOME/Library/Logs/heic-converter.log"

mkdir -p "${LOG:h}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG"; }

# --- Load config (format=png|jpg|both, jpg_quality=0-100) ---
FORMAT="png"
JPG_QUALITY="90"
if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  log "WARN: no config at $CONFIG_FILE, defaulting to format=$FORMAT"
fi

# --- Wait for a file to stop growing (handles AirDrop/downloads in progress) ---
wait_stable() {
  local f="$1"
  local prev=-1
  # Declared out here on purpose: re-running `local size` on each iteration makes
  # zsh echo "size=<n>" to stdout, which ends up as noise in the agent's out.log.
  local size
  for i in $(seq 1 20); do
    size=$(/usr/bin/stat -f%z "$f" 2>/dev/null)
    if [[ "$size" == "$prev" && -n "$size" ]]; then
      return 0
    fi
    prev="$size"
    sleep 0.5
  done
  return 1
}

convert_one() {
  local f="$1"
  local base="${f%.*}"

  if ! wait_stable "$f"; then
    log "SKIP (never stabilized): $f"
    return
  fi

  if [[ "$FORMAT" == "png" || "$FORMAT" == "both" ]]; then
    local out_png="${base}.png"
    if [[ ! -e "$out_png" ]]; then
      if /usr/bin/sips -s format png "$f" --out "$out_png" >> "$LOG" 2>&1; then
        log "OK (png): $f -> $out_png"
      else
        log "FAIL (png): $f"
      fi
    fi
  fi

  if [[ "$FORMAT" == "jpg" || "$FORMAT" == "both" ]]; then
    local out_jpg="${base}.jpg"
    if [[ ! -e "$out_jpg" ]]; then
      if /usr/bin/sips -s format jpeg -s formatOptions "$JPG_QUALITY" "$f" --out "$out_jpg" >> "$LOG" 2>&1; then
        log "OK (jpg): $f -> $out_jpg"
      else
        log "FAIL (jpg): $f"
      fi
    fi
  fi
}

setopt NULL_GLOB
for f in "$WATCH_DIR"/*.heic "$WATCH_DIR"/*.HEIC; do
  [[ -e "$f" ]] || continue
  convert_one "$f"
done
