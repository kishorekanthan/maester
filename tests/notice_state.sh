#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Maester"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "ok: $1"
}

if [ ! -x "$BIN" ]; then
  fail "binary not found at $BIN — run 'zsh build.sh' first"
fi

field_json() {
  python3 -c '
import json, sys
data = json.loads(sys.argv[1])
v = data.get(sys.argv[2])
print("null" if v is None else v)
' "$1" "$2"
}

check() {
  local label="$1" hasReport="$2" hasMessage="$3" msgFail="$4" stateOff="$5" reportEmpty="$6" want="$7"
  local out kind
  out="$("$BIN" --notice-check \
    --has-report "$hasReport" --has-message "$hasMessage" \
    --message-is-failure "$msgFail" --report-state-off "$stateOff" \
    --report-is-empty "$reportEmpty")"
  kind="$(field_json "$out" kind)"
  [ "$kind" = "$want" ] || fail "$label: kind = $kind, expected $want"
  pass "$label"
}

check "never reported, no message: loading"       false false false false false loading
check "no report, failed message: error"          false true  true  false false error
check "no report, non-fatal notice: none"         false true  false false false null
check "stopped with nothing else to show: timedOut" true false false true  true  timedOut
check "stopped but still has content: none"       true false false true  false null
check "healthy report: none"                      true false false false false null
check "stopped, empty, but has a message: none"   true true  false true  true  null
