#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Maester"
JQ=/usr/bin/jq

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }
accepted() {
  "$BIN" --report-check "$1" | "$JQ" -r .accepted
}

[ -x "$BIN" ] || fail "binary not found at $BIN — run 'zsh build.sh' first"

[ "$(accepted '{"schema":1,"title":"fixture","state":"ok"}')" = true ] \
  || fail "a schema 1 report was refused"
[ "$(accepted '{"schema":2,"title":"fixture","state":"ok"}')" = false ] \
  || fail "a schema 2 report was accepted"

pass "only schema 1 reports are accepted"
