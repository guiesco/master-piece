#!/bin/sh
# =============================================================================
# backend-watch.sh — polling hot-reload for the Nakama Go plugin
#
# Watches backend/ for changes (polling — works on Docker Desktop / Windows),
# rebuilds plugin.so via backend-builder, then restarts nakama on success.
# =============================================================================

set -eu

POLL_INTERVAL="${POLL_INTERVAL:-2}"
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-1}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.yml}"

log() {
  printf '[backend-watch] %s\n' "$*"
}

# Fingerprint: path + mtime + size for relevant backend sources.
# Uses ls (BusyBox-safe) — polling works on Docker Desktop / Windows bind mounts.
fingerprint() {
  find backend \
    \( -name '*.go' -o -name '*.json' -o -name 'go.mod' -o -name 'go.sum' \) \
    -type f \
    -exec ls -ln {} \; 2>/dev/null \
    | sort \
    | cksum \
    | awk '{print $1}'
}

rebuild_and_restart() {
  log "change detected — rebuilding plugin..."
  if docker compose -f "$COMPOSE_FILE" run --rm --no-deps backend-builder; then
    log "rebuild ok — restarting nakama..."
    if docker compose -f "$COMPOSE_FILE" restart nakama; then
      log "nakama restarted"
    else
      log "ERROR: nakama restart failed"
    fi
  else
    log "rebuild failed — nakama left running with previous plugin"
  fi
}

log "watching backend/ (poll=${POLL_INTERVAL}s, debounce=${DEBOUNCE_SECONDS}s)"
last="$(fingerprint || echo none)"

while true; do
  sleep "$POLL_INTERVAL"
  current="$(fingerprint || echo none)"
  if [ "$current" != "$last" ]; then
    # Debounce: wait for editors to finish writing, then re-check
    sleep "$DEBOUNCE_SECONDS"
    current="$(fingerprint || echo none)"
    if [ "$current" != "$last" ]; then
      last="$current"
      rebuild_and_restart
    fi
  fi
done
