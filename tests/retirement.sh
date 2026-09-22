#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Maester"
JQ=/usr/bin/jq

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

[ -x "$BIN" ] || fail "binary not found at $BIN — run 'zsh build.sh' first"

out="$("$BIN" --retirement-check)"
hidden_after_action="$(print -r -- "$out" | "$JQ" -r .hiddenAfterAction)"
hidden_after_live_report="$(print -r -- "$out" | "$JQ" -r .hiddenAfterLiveReport)"
hidden_after_deadline="$(print -r -- "$out" | "$JQ" -r .hiddenAfterDeadline)"

[ "$hidden_after_action" = true ] || fail "an item was not hidden after its successful removing action"
[ "$hidden_after_live_report" = false ] || fail "a live item did not return on the next report"
[ "$hidden_after_deadline" = false ] || fail "an expired retirement still hid the item"

pass "retirement hides immediately, restores on a live report, and expires"
