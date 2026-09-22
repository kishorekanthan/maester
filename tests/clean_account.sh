#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
cleanup() { trash "$WORK" 2>/dev/null || command rm -rf "$WORK"; }
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

STOCK_PATH="/usr/bin:/bin:/usr/sbin:/sbin"
FIXHOME="$WORK/home"
TRIP="$WORK/tripwire"
TRIPLOG="$WORK/tripped"
mkdir -p "$FIXHOME" "$TRIP"
: > "$TRIPLOG"

shim_count=0
for f in /usr/bin/*(N.x); do
  /usr/bin/otool -L "$f" 2>/dev/null | /usr/bin/grep -q libxcselect || continue
  name="${f:t}"
  printf '#!/bin/sh\nprintf "%%s\\n" "%s" >> "%s"\nexit 1\n' "$name" "$TRIPLOG" > "$TRIP/$name"
  chmod 755 "$TRIP/$name"
  shim_count=$((shim_count + 1))
done
[ "$shim_count" -ge 20 ] || fail "found only $shim_count developer-tools stubs in /usr/bin; the guard is not armed"
pass "armed $shim_count tripwires over the /usr/bin developer-tools stubs"

clean_run() {
  /usr/bin/env -i \
    HOME="$FIXHOME" \
    PATH="$TRIP:$STOCK_PATH" \
    TMPDIR="$WORK/tmp" \
    "$@"
}
mkdir -p "$WORK/tmp"

set +e
out="$(clean_run "$ROOT/install.sh" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "install.sh exited $rc on a clean account:\n$out"
for name in apps mac; do
  [ -L "$FIXHOME/.config/maester/providers/$name" ] \
    || fail "install.sh did not symlink the $name provider into a clean account"
done
pass "install.sh completes on a clean account and links both bundled providers"

set +e
clean_run "$ROOT/setup.sh" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 0 ] || fail "setup.sh exited $rc on a clean account"
pass "setup.sh runs on a clean account"

for name in apps mac; do
  set +e
  report="$(clean_run "$ROOT/providers/$name" status 2>/dev/null)"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || fail "provider $name exited $rc on a clean account"
  printf '%s' "$report" | /usr/bin/jq -e '.schema == 1 and (.title | length > 0) and (.state | test("^(ok|warn|error|off)$"))' >/dev/null \
    || fail "provider $name did not print a valid report on a clean account: $report"
done
pass "both bundled providers print a valid report on a clean account"

set +e
doctor_out="$(clean_run "$ROOT/maester-doctor" 2>&1)"
set -e
printf '%s\n' "$doctor_out" | /usr/bin/grep -qE '0 failing' \
  || fail "maester-doctor did not report 0 failing on a clean account:\n$doctor_out"
pass "maester-doctor reports 0 failing on a clean account"

if [ -s "$TRIPLOG" ]; then
  fail "the install path invoked developer-tools stubs, which prompt for Xcode on a Mac without them: $(/usr/bin/sort -u "$TRIPLOG" | /usr/bin/tr '\n' ' ')"
fi
pass "no step of the install path invokes a developer-tools stub"

echo "clean-account checks passed"
