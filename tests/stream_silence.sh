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
    printf '%s\n' '{"schema":1,"title":"fixture","state":"ok","capabilities":{"stream":true,"refresh":1}}'
    sleep 600
    ;;
  *)
    exit 2
    ;;
esac
PROVIDER
chmod 700 "$CONFIG_DIR/providers/fixture"

spawn_count() {
  [ -f "$STATE_DIR/spawns.log" ] || { echo 0; return; }
  wc -l < "$STATE_DIR/spawns.log" | tr -d ' '
}

TRACE="$STATE_DIR/trace.log"
MAESTER_DEBUG=1 MAESTER_CONFIG_DIR="$CONFIG_DIR" FIXTURE_STATE_DIR="$STATE_DIR" "$BIN" 2> "$TRACE" &
APP_PID=$!

tries=120
while [ "$(spawn_count)" -lt 2 ] && [ "$tries" -gt 0 ]; do
  sleep 1
  tries=$((tries - 1))
done
SPAWNS="$(spawn_count)"
sleep 3

kill -TERM "$APP_PID" 2>/dev/null || true
tries=80
while kill -0 "$APP_PID" 2>/dev/null && [ "$tries" -gt 0 ]; do
  sleep 0.1
  tries=$((tries - 1))
done
kill -9 "$APP_PID" 2>/dev/null || true

if [ "$SPAWNS" -lt 2 ]; then
  fail "a stream that went silent was never restarted — saw $SPAWNS spawn(s) in 120s, so the provider stayed dead behind a permanent 'stream went silent' notice"
fi

T0="$(sed -n '1p' "$STATE_DIR/spawns.log" | awk '{print $1}')"
T1="$(sed -n '2p' "$STATE_DIR/spawns.log" | awk '{print $1}')"
GAP=$((T1 - T0))
if [ "$GAP" -lt 20 ]; then
  fail "the silent stream was restarted after ${GAP}s — sooner than the silence limit, so something other than the watchdog killed it"
fi

grep -q 'provider fixture .*note=stream went silent' "$TRACE" \
  || fail "the watchdog never reported the silence — a stream that stops emitting must still raise the notice"

LAST_NOTE="$(grep 'provider fixture ' "$TRACE" | sed -n '$p' | sed 's/.*note=\(.*\) overall=.*/\1/')"
if [ "$LAST_NOTE" != "-" ]; then
  fail "the silence notice latched — the provider is streaming again but its last published note was '$LAST_NOTE'"
fi

pass "a stream that goes silent while its process stays alive is restarted (${GAP}s after it last spoke)"
pass "the silence notice is raised while it is true and cleared once the restarted stream reports again"
