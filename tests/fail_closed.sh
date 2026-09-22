#!/usr/bin/env zsh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JQ=/usr/bin/jq
WORK="$(mktemp -d)"
cleanup() { trash "$WORK" 2>/dev/null || command rm -r "$WORK"; }
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

grep -q '^export LC_ALL=C LANG=C$' "$ROOT/providers/mac" || fail "providers/mac does not pin the locale"
grep -q '^export LC_ALL=C LANG=C$' "$ROOT/providers/apps" || fail "providers/apps does not pin the locale"
pass "both providers pin LC_ALL=C LANG=C before parsing command output"

source "$ROOT/providers/mac"

ENGLISH="$(cat <<'VMSTAT'
Mach Virtual Memory Statistics: (page size of 4096 bytes)
Pages free:                                1.
Anonymous pages:                        1000.
Pages purgeable:                         200.
Pages wired down:                        300.
Pages occupied by compressor:            100.
VMSTAT
)"

TRANSLATED="$(cat <<'VMSTAT'
Statistiques de mémoire virtuelle Mach : (taille de page 4096 octets)
Pages libres :                             1.
Pages anonymes :                        1000.
Pages purgeables :                       200.
Pages résidentes verrouillées :          300.
VMSTAT
)"

GOT="$(memory_from_vmstat "$ENGLISH" 8589934592 1)" || fail "the English vm_stat sample was rejected"
EXPECTED='{"compressed":409600,"pressure":"normal","total":8589934592,"used":4915200,"wired":1228800}'
CANON="$(printf '%s\n' "$GOT" | $JQ -Sc .)"
[ "$CANON" = "$EXPECTED" ] || fail "hand-computed memory did not match: got $CANON, expected $EXPECTED"
pass "a known vm_stat sample yields the hand-computed bytes: $CANON"

GOT="$(memory_from_vmstat "$TRANSLATED" 8589934592 1 2>"$WORK/err")"
RC=$?
[ "$RC" -ne 0 ] || fail "vm_stat output with no recognised page counts was accepted (returned 0)"
[ "$GOT" = "null" ] || fail "a rejected memory reading was not null (got '$GOT')"
[ -s "$WORK/err" ] || fail "a rejected memory reading explained nothing on stderr"
pass "vm_stat text the parser does not recognise fails closed: $(cat "$WORK/err")"

source "$ROOT/providers/apps"

cat > "$WORK/lsappinfo-translated" <<'STUB'
#!/bin/sh
cat <<'OUT'
   1) "Finder" ASN:0x0-0x1001:
       bundleID="com.apple.finder"
       type="Premier plan"
       pid = 501
OUT
STUB
chmod 700 "$WORK/lsappinfo-translated"

cat > "$WORK/lsappinfo-silent" <<'STUB'
#!/bin/sh
exit 0
STUB
chmod 700 "$WORK/lsappinfo-silent"

LSAPPINFO="$WORK/lsappinfo-translated"
GOT="$(foreground_apps_json 2>"$WORK/err2")"
RC=$?
[ "$RC" -ne 0 ] || fail "lsappinfo output with no recognised foreground marker was accepted (returned 0)"
[ -s "$WORK/err2" ] || fail "a rejected app list explained nothing on stderr"
pass "lsappinfo text the parser does not recognise fails closed: $(cat "$WORK/err2")"

LSAPPINFO="$WORK/lsappinfo-silent"
GOT="$(foreground_apps_json 2>"$WORK/err3")"
RC=$?
[ "$RC" -ne 0 ] || fail "an empty lsappinfo list was reported as zero healthy apps (returned 0)"
[ -s "$WORK/err3" ] || fail "an empty app list explained nothing on stderr"
pass "an empty lsappinfo list fails closed: $(cat "$WORK/err3")"
