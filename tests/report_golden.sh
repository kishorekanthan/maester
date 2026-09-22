#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/tests/golden/reports"
LIB="$ROOT/providers/lib"
JQ=/usr/bin/jq

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

render() {
  local input="$1" argv=()
  local report="$($JQ -r .report "$input")"
  local key
  for key in $($JQ -r '.argjson | keys_unsorted[]' "$input"); do
    argv+=(--argjson "$key" "$($JQ -c --arg k "$key" '.argjson[$k]' "$input")")
  done
  for key in $($JQ -r '.arg | keys_unsorted[]' "$input"); do
    argv+=(--arg "$key" "$($JQ -r --arg k "$key" '.arg[$k]' "$input")")
  done
  $JQ -n "${argv[@]}" -f "$LIB/$report"
}

for input in "$FIXTURES"/*/*.input.json; do
  case="${input#$FIXTURES/}"
  case="${case%.input.json}"
  golden="${input%.input.json}.expected.json"
  [ -f "$golden" ] || fail "no recorded report for the $case fixture"
  diff -u "$golden" <(render "$input") \
    || fail "the $case fixture no longer renders the report that was recorded for it"
  pass "$case renders its recorded report exactly"
done
