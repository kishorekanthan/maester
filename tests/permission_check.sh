#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Maester"
JQ=/usr/bin/jq
WORK="$(mktemp -d)"
cleanup() { chmod -R u+w "$WORK" 2>/dev/null || true; trash "$WORK" 2>/dev/null || true; }
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

if [ ! -x "$BIN" ]; then
  fail "binary not found at $BIN — run 'zsh build.sh' first"
fi

touch "$WORK/ok_file"
chmod 700 "$WORK"

out="$("$BIN" --permission-check --path "$WORK/ok_file")"
[ "$($JQ -r .refused <<<"$out")" = "false" ] || fail "an owned, non-writable-by-others file should not be refused: $out"

chmod 777 "$WORK"
out="$("$BIN" --permission-check --path "$WORK/ok_file")"
[ "$($JQ -r .refused <<<"$out")" = "true" ] || fail "a world-writable directory should be refused: $out"
$JQ -r .reason <<<"$out" | grep -q "group/world-writable" || fail "refusal reason should name group/world-writable: $out"
chmod 700 "$WORK"

chmod 666 "$WORK/ok_file"
out="$("$BIN" --permission-check --path "$WORK/ok_file")"
[ "$($JQ -r .refused <<<"$out")" = "true" ] || fail "a world-writable file should be refused: $out"
chmod 600 "$WORK/ok_file"

refuses() {
  local target="$1" mode="$2" label="$3"
  chmod "$mode" "$target"
  local out
  out="$("$BIN" --permission-check --path "$WORK/ok_file")"
  chmod 700 "$WORK"
  chmod 600 "$WORK/ok_file"
  [ "$($JQ -r .refused <<<"$out")" = "true" ] || fail "$label should be refused: $out"
  $JQ -r .reason <<<"$out" | grep -q "group/world-writable" || fail "$label should name group/world-writable: $out"
}

refuses "$WORK" 720 "a group-writable directory"
refuses "$WORK" 702 "a world-writable directory"
refuses "$WORK/ok_file" 620 "a group-writable file"
refuses "$WORK/ok_file" 602 "a world-writable file"

out="$("$BIN" --permission-check --path "$WORK/does-not-exist")"
[ "$($JQ -r .refused <<<"$out")" = "true" ] || fail "a path whose parent cannot be stat'd should be refused: $out"

out="$("$BIN" --permission-check 2>&1)" && rc=0 || rc=$?
[ "$rc" -ne 0 ] || fail "missing --path should exit non-zero"
printf '%s\n' "$out" | grep -q -- "--permission-check requires --path" || fail "missing --path should say what is required: $out"

pass "ownership and writability match the provider ownership check, with the group-write and world-write bits exercised one at a time"
echo "permission-check tests passed"
