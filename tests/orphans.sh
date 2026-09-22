#!/usr/bin/env zsh
set -euo pipefail
zmodload zsh/datetime

QUIT_BUDGET=1.0

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
    trap '' TERM
    echo $$ > "$STATE/provider.pid"
    while true; do
      printf '%s\n' '{"schema":1,"title":"fixture","state":"ok"}'
      sleep 1
    done
    ;;
  *)
    exit 2
    ;;
esac
PROVIDER
chmod 700 "$CONFIG_DIR/providers/fixture"

wait_for_pidfile() {
  local file="$1" tries=100
  while [ ! -s "$file" ] && [ "$tries" -gt 0 ]; do
    sleep 0.1
    tries=$((tries - 1))
  done
  [ -s "$file" ]
}

run_case() {
  local label="$1"
  local pidfile="$STATE_DIR/provider.pid"
  rm -f "$pidfile" 2>/dev/null || true
  MAESTER_CONFIG_DIR="$CONFIG_DIR" FIXTURE_STATE_DIR="$STATE_DIR" "$BIN" &
  local app_pid=$!
  if ! wait_for_pidfile "$pidfile"; then
    kill -9 "$app_pid" 2>/dev/null || true
    fail "fixture provider never started streaming ($label)"
  fi
  local fixture_pid
  fixture_pid="$(cat "$pidfile")"
  local started=$EPOCHREALTIME
  kill -TERM "$app_pid"
  local tries=400
  while kill -0 "$app_pid" 2>/dev/null && [ "$tries" -gt 0 ]; do
    sleep 0.02
    tries=$((tries - 1))
  done
  local elapsed=$((EPOCHREALTIME - started))
  if kill -0 "$app_pid" 2>/dev/null; then
    kill -9 "$app_pid" 2>/dev/null || true
    fail "app did not exit after SIGTERM ($label)"
  fi
  if (( elapsed > QUIT_BUDGET )); then
    fail "app took ${elapsed}s to exit, over the ${QUIT_BUDGET}s budget ($label)"
  fi
  printf 'ok: app exited %.3fs after SIGTERM, under the %ss budget (%s)\n' "$elapsed" "$QUIT_BUDGET" "$label"
  sleep 0.3
  if kill -0 "$fixture_pid" 2>/dev/null; then
    kill -9 "$fixture_pid" 2>/dev/null || true
    fail "fixture provider survived app exit, orphaned pid $fixture_pid ($label)"
  fi
  pass "fixture provider process is gone after app exit ($label)"
}

run_case "SIGTERM to app"
