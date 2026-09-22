#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JQ=/usr/bin/jq
PROVIDER="${1:-$ROOT/providers/apps}"
NAME="$(basename "$PROVIDER")"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

capture_stream_line() {
  local prov="$1" out
  out="$(mktemp)"
  "$prov" stream > "$out" 2>/dev/null &
  local pid=$!
  local tries=40
  while [ ! -s "$out" ] && [ "$tries" -gt 0 ]; do
    sleep 0.25
    tries=$((tries - 1))
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  head -1 "$out"
  rm -f "$out"
}

check_status() {
  local out
  out="$("$PROVIDER" status)"
  printf '%s\n' "$out" | $JQ -c . >/dev/null || fail "$NAME status did not print a single valid JSON document"
  printf '%s\n' "$out" | $JQ -e '.schema == 1 and (.title | type) == "string" and (.state | type) == "string"' >/dev/null \
    || fail "$NAME status is valid JSON but is not a schema 1 report"
  pass "$NAME status prints one schema 1 report on this machine"
}

check_stream() {
  local line
  line="$(capture_stream_line "$PROVIDER")"
  [ -n "$line" ] || fail "$NAME stream produced no line within timeout"
  printf '%s\n' "$line" | $JQ -e '.schema == 1' >/dev/null \
    || fail "$NAME stream first line is not a schema 1 report"
  pass "$NAME stream first line is a schema 1 report"
}

check_do_rejects_bad_action() {
  if "$PROVIDER" do bogus-action-id nonexistent-item >/dev/null 2>&1; then
    fail "$NAME do with an undeclared action id should be refused"
  fi
  pass "$NAME do with an undeclared action id is refused"
}

check_status
check_stream
check_do_rejects_bad_action

echo "live checks passed for $NAME"
