#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETUP="$ROOT/setup.sh"
WORK="$(mktemp -d)"
cleanup() { trash "$WORK" 2>/dev/null || command rm -rf "$WORK"; }
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

FIXHOME="$WORK/home"
CONFIG="$FIXHOME/.config/maester/config.json"
mkdir -p "$FIXHOME/.config/maester"

snapshot_tree() { (cd "$FIXHOME" && find . | /usr/bin/sort); }
config_hash() { /usr/bin/shasum -a 256 "$CONFIG" | /usr/bin/awk '{print $1}'; }

set +e
out="$(HOME="$FIXHOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin "$SETUP" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "a report should always exit 0, got $rc"
[ -e "$CONFIG" ] && fail "setup.sh must not create config.json"
printf '%s\n' "$out" | grep -q 'changes nothing' || fail "output did not state that it changes nothing"
pass "setup.sh reports without creating config.json and exits 0"

printf '%s' '{"disabled":["mac"],"density":"compact"}' > "$CONFIG"
BEFORE="$(config_hash)"
BEFORE_TREE="$(snapshot_tree)"
set +e
HOME="$FIXHOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin "$SETUP" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "a report over an existing config should exit 0, got $rc"
[ "$BEFORE" = "$(config_hash)" ] || fail "setup.sh rewrote config.json"
[ "$BEFORE_TREE" = "$(snapshot_tree)" ] || fail "setup.sh added or removed files under the config directory"
pass "setup.sh leaves an existing config.json byte-identical and the config directory untouched"

set +e
out="$(HOME="$FIXHOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin "$SETUP" --apply 2>&1)"
rc=$?
set -e
[ "$rc" -eq 2 ] || fail "--apply must be refused with exit 2, got $rc"
printf '%s\n' "$out" | grep -q -- '--apply was removed' || fail "--apply was refused without saying why"
[ "$BEFORE" = "$(config_hash)" ] || fail "a refused --apply still rewrote config.json"
pass "--apply is refused with a reason and writes nothing"

for key in disabled density; do
  /usr/bin/grep -q "\"$key\"" "$ROOT/Sources/Config.swift" \
    || fail "README tells a user to set config key $key, but Sources/Config.swift never names it"
done
pass "every config.json key the docs tell a user to set is named in Sources/Config.swift"

echo "setup checks passed"
