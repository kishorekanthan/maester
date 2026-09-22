#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Maester"
WORK="$(mktemp -d)"
cleanup() { trash "$WORK" 2>/dev/null || command rm -r "$WORK"; }
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

if [ ! -x "$BIN" ]; then
  fail "binary not found at $BIN — run 'zsh build.sh' first"
fi

CONFIG_DIR="$WORK/config"
mkdir -p "$CONFIG_DIR/providers"
STATE_DIR="$WORK/state"
mkdir -p "$STATE_DIR"

cat > "$CONFIG_DIR/providers/fixture" <<'PROVIDER'
#!/bin/sh
STATE="${FIXTURE_STATE_DIR:?}"
case "${1:-}" in
  status)
    printf '%s\n' '{"schema":1,"title":"fixture","state":"ok","capabilities":{"stream":true,"refresh":1}}'
    ;;
  stream)
    printf '%s %s\n' "$(date +%s)" "$$" >> "$STATE/spawns.log"
    i=0
    while [ $i -lt 2 ]; do
      printf '%s\n' '{"schema":1,"title":"fixture","state":"ok"}'
      i=$((i + 1))
      sleep 0.2
    done
    exit 7
    ;;
  *)
    exit 2
    ;;
esac
PROVIDER
chmod 700 "$CONFIG_DIR/providers/fixture"

spawn_count() {
  [ -f "$STATE_DIR/spawns.log" ] || { echo 0; return; }
  wc -l < "$STATE_DIR/spawns.log"
}

wait_for_spawns() {
  local n="$1" tries=100
  while [ "$(spawn_count)" -lt "$n" ] && [ "$tries" -gt 0 ]; do
    sleep 0.2
    tries=$((tries - 1))
  done
  [ "$(spawn_count)" -ge "$n" ]
}

MAESTER_CONFIG_DIR="$CONFIG_DIR" FIXTURE_STATE_DIR="$STATE_DIR" "$BIN" &
APP_PID=$!

if ! wait_for_spawns 2; then
  kill -9 "$APP_PID" 2>/dev/null || true
  fail "the fixture stream never got respawned after it exited unexpectedly"
fi

kill -TERM "$APP_PID"
tries=80
while kill -0 "$APP_PID" 2>/dev/null && [ "$tries" -gt 0 ]; do
  sleep 0.1
  tries=$((tries - 1))
done
if kill -0 "$APP_PID" 2>/dev/null; then
  kill -9 "$APP_PID" 2>/dev/null || true
  fail "app did not exit after SIGTERM"
fi

PIDS="$(awk '{print $2}' "$STATE_DIR/spawns.log" | sort -u | wc -l | tr -d ' ')"
if [ "$PIDS" -lt 2 ]; then
  fail "expected at least 2 distinct fixture pids, saw $PIDS"
fi

T0="$(sed -n '1p' "$STATE_DIR/spawns.log" | awk '{print $1}')"
T1="$(sed -n '2p' "$STATE_DIR/spawns.log" | awk '{print $1}')"
GAP=$((T1 - T0))
if [ "$GAP" -lt 1 ]; then
  fail "the second spawn followed the first by ${GAP}s — that looks like a tight crash loop, not a backed-off restart"
fi

pass "a stream that exits unexpectedly gets respawned with backoff ($PIDS distinct pids, first gap ${GAP}s)"
