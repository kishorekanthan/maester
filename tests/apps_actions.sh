#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROVIDER="$ROOT/providers/apps"
JQ=/usr/bin/jq
REPORT_JQ="$ROOT/providers/lib/apps_report.jq"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

build_for() {
  "$JQ" -n --argjson apps "$1" --argjson before '{}' --argjson after '{}' \
    --argjson elapsed 0 --argjson hangs '{}' --argjson ncpu 1 --argjson max_apps 12 \
    -f "$REPORT_JQ"
}

expected='["open","quit","force-quit"]'

apps_with_bundle='[{"name":"Mail","asn":null,"bundle":"com.apple.mail","pid":111,"pids":[111]}]'
ids="$(build_for "$apps_with_bundle" | "$JQ" -c '.items[0].actions | map(.id)')"
[ "$ids" = "$expected" ] || fail "actions with a bundle id were $ids, expected $expected"
pass "open/quit/force-quit are declared in that order, with a bundle id"

apps_no_bundle='[{"name":"Terminal","asn":null,"bundle":null,"pid":222,"pids":[222]}]'
ids2="$(build_for "$apps_no_bundle" | "$JQ" -c '.items[0].actions | map(.id)')"
[ "$ids2" = "$expected" ] || fail "actions without a bundle id were $ids2, expected $expected"
pass "open/quit/force-quit are declared in that order, without a bundle id"

if ! "$PROVIDER" do open 2>/dev/null; then
  pass "open with no item argument is refused"
else
  fail "open with no item argument should be refused"
fi

if ! "$PROVIDER" do bogus-action nonexistent 2>/dev/null; then
  pass "an unknown action id is still refused"
else
  fail "an unknown action id should be refused"
fi

echo "apps action checks passed"
