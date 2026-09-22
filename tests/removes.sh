#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JQ=/usr/bin/jq
PROVIDER="$ROOT/providers/apps"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

EXPECTED='open=false
quit=true
force-quit=true'

out="$(mktemp)"
"$PROVIDER" stream > "$out" 2>/dev/null &
pid=$!
tries=40
while [ ! -s "$out" ] && [ "$tries" -gt 0 ]; do
  sleep 0.25
  tries=$((tries - 1))
done
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
line="$(head -1 "$out")"
command rm -f "$out"

[ -n "$line" ] || fail "apps stream produced no line within timeout"

actual="$(printf '%s\n' "$line" | $JQ -r '
  [.items[]?.actions[]?] | unique_by(.id) | sort_by(.id) | .[]
  | "\(.id)=\(.removes // false)"' | sort)"

[ -n "$actual" ] || fail "apps stream declared no item actions"

if [ "$actual" != "$(printf '%s\n' "$EXPECTED" | sort)" ]; then
  echo "expected:" >&2; printf '%s\n' "$EXPECTED" | sort >&2
  echo "actual:" >&2; printf '%s\n' "$actual" >&2
  fail "item actions do not declare removal as expected"
fi

pass "quit and force-quit declare removes, open does not"
