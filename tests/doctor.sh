#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCTOR="$ROOT/maester-doctor"
WORK="$(mktemp -d)"
cleanup() { trash "$WORK" 2>/dev/null || command rm -rf "$WORK"; }
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

FIXHOME="$WORK/home"
mkdir -p "$FIXHOME/.config/maester/providers"

cat > "$FIXHOME/.config/maester/providers/good" <<'PROVIDER'
#!/bin/sh
case "${1:-}" in
  status) printf '%s\n' '{"schema":1,"title":"Good","state":"ok","capabilities":{"stream":false},"metrics":[{"id":"cpu","label":"CPU","value":1,"unit":"%","pct":1}]}' ;;
  *) exit 2 ;;
esac
PROVIDER
chmod 700 "$FIXHOME/.config/maester/providers/good"

cat > "$FIXHOME/.config/maester/providers/bad" <<'PROVIDER'
#!/bin/sh
case "${1:-}" in
  status) printf '%s\n' '{"schema":1,"state":"bogus","metrics":[{"id":"m","value":1},{"id":"m","value":2}]}' ;;
  *) exit 2 ;;
esac
PROVIDER
chmod 700 "$FIXHOME/.config/maester/providers/bad"

out="$(HOME="$FIXHOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin "$DOCTOR" good 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || fail "a well-formed provider should exit 0, got $rc"
printf '%s\n' "$out" | grep -q '^good ' || fail "output did not name the provider"
printf '%s\n' "$out" | grep -q 'FAIL\|✗' && fail "a well-formed provider should not report errors"
pass "a contract-clean provider passes with exit 0"

out="$(HOME="$FIXHOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin "$DOCTOR" bad 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || fail "a broken provider should exit 1, got $rc"
printf '%s\n' "$out" | grep -q 'title missing' || fail "missing title was not flagged"
printf '%s\n' "$out" | grep -q 'state bogus' || fail "invalid state was not flagged"
printf '%s\n' "$out" | grep -q 'duplicate id' || fail "duplicate metric id was not flagged"
pass "a provider with a missing title, bad state and duplicate metric id is flagged and fails"

out="$(HOME="$FIXHOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin "$DOCTOR" nonexistent-provider 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || fail "an unknown provider name should exit 1, got $rc"
printf '%s\n' "$out" | grep -q 'no provider named nonexistent-provider' || fail "unknown provider name was not reported"
pass "an unknown provider name is refused"

writable_dir="$WORK/homeperm"
mkdir -p "$writable_dir/.config/maester/providers"
cp "$FIXHOME/.config/maester/providers/good" "$writable_dir/.config/maester/providers/good"
chmod 777 "$writable_dir/.config/maester/providers/good"
out="$(HOME="$writable_dir" PATH=/usr/bin:/bin:/usr/sbin:/sbin "$DOCTOR" good 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] || fail "a world-writable provider should be refused, got exit $rc"
printf '%s\n' "$out" | grep -q 'writable' || fail "world-writable file was not flagged"
pass "a group/world-writable provider file is refused"

override_dir="$WORK/elsewhere"
mkdir -p "$override_dir/providers"
cp "$FIXHOME/.config/maester/providers/good" "$override_dir/providers/good"
chmod 700 "$override_dir/providers/good"
decoy="$WORK/decoyhome"
mkdir -p "$decoy/.config/maester/providers"
out="$(HOME="$decoy" MAESTER_CONFIG_DIR="$override_dir" PATH=/usr/bin:/bin:/usr/sbin:/sbin "$DOCTOR" 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 0 ] || fail "MAESTER_CONFIG_DIR run should exit 0, got $rc"
printf '%s\n' "$out" | grep -q 'good' || fail "maester-doctor ignored MAESTER_CONFIG_DIR and looked under HOME instead: $out"
pass "maester-doctor reads providers from MAESTER_CONFIG_DIR, as install.sh and the app do"

echo "doctor checks passed"
