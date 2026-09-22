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
report() {
  items=""
  i=0
  while [ "$i" -lt 30 ]; do
    [ -n "$items" ] && items="$items,"
    items="$items{\"id\":\"row$i\",\"label\":\"a steady row padded so every line is larger than one pipe read $i\",\"state\":\"ok\"}"
    i=$((i + 1))
  done
  printf '{"schema":1,"title":"fixture","state":"ok","capabilities":{"stream":true,"refresh":2},"items":[%s]}\n' "$items"
}
case "${1:-}" in
  status) report ;;
  stream)
    printf '%s %s\n' "$(date +%s)" "$$" >> "$STATE/spawns.log"
    while :; do report; date +%s >> "$STATE/emits.log"; sleep 3; done
    ;;
  *) exit 2 ;;
esac
PROVIDER
chmod 700 "$CONFIG_DIR/providers/fixture"

TRACE="$STATE_DIR/trace.log"
MAESTER_DEBUG=1 MAESTER_CONFIG_DIR="$CONFIG_DIR" FIXTURE_STATE_DIR="$STATE_DIR" "$BIN" 2> "$TRACE" &
APP_PID=$!

sleep 50

kill -TERM "$APP_PID" 2>/dev/null || true
tries=80
while kill -0 "$APP_PID" 2>/dev/null && [ "$tries" -gt 0 ]; do
  sleep 0.1
  tries=$((tries - 1))
done
kill -9 "$APP_PID" 2>/dev/null || true
pkill -f "$CONFIG_DIR/providers/fixture" 2>/dev/null || true

LINE_BYTES="$(FIXTURE_STATE_DIR="$STATE_DIR" sh "$CONFIG_DIR/providers/fixture" status | wc -c | tr -d ' ')"
[ "$LINE_BYTES" -gt 2048 ] || fail "the fixture line is only ${LINE_BYTES} bytes, too small to span more than one pipe read"

SPAWNS="$(wc -l < "$STATE_DIR/spawns.log" | tr -d ' ')"
[ "$SPAWNS" -eq 1 ] || fail "a stream that never stopped emitting was started $SPAWNS times in 50s"

if grep -q 'provider fixture .*note=stream went silent' "$TRACE"; then
  fail "the silence notice was published against a stream emitting every 3s"
fi

EMITS="$(wc -l < "$STATE_DIR/emits.log" | tr -d ' ')"
[ "$EMITS" -ge 10 ] || fail "the fixture wrote only $EMITS lines in 50s, so the stream was not steady"

pass "a stream emitting ${LINE_BYTES}-byte lines every 3s ran 50s without a restart or a silence notice ($EMITS lines)"
