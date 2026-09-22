#!/usr/bin/env zsh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JQ=/usr/bin/jq
LIB="$ROOT/providers/lib"
WORK="$(mktemp -d)"
cleanup() { trash "$WORK" 2>/dev/null || command rm -r "$WORK"; }
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

eq() {
  local what="$1" got="$2" want="$3"
  [ "$got" = "$want" ] || fail "$what: got $got, expected $want"
}

GIB=1073741824

APPS='[]'
AFTER='{}'
for i in {1..13}; do
  mem=$(( (14 - i) * GIB ))
  cpu=0
  [ "$i" -eq 1 ] && cpu=10
  [ "$i" -eq 13 ] && cpu=20
  APPS="$(printf '%s\n' "$APPS" | $JQ -c --arg b "com.t.$i" --arg n "App $i" --argjson p "$i" \
    '. + [{name: $n, bundle: $b, pid: $p, pids: [$p]}]')"
  AFTER="$(printf '%s\n' "$AFTER" | $JQ -c --arg p "$i" --argjson c "$cpu" --argjson m "$mem" \
    '. + {($p): {cpu: $c, mem: $m}}')"
done

REPORT="$($JQ -n --argjson apps "$APPS" --argjson before '{}' --argjson after "$AFTER" \
  --argjson elapsed 10 --argjson hangs '{}' --argjson ncpu 10 --argjson max_apps 12 \
  -f "$LIB/apps_report.jq")" || fail "apps_report.jq did not run"
printf '%s\n' "$REPORT" > "$WORK/apps.json"

get() { $JQ -r "$1" < "$WORK/apps.json"; }

eq "displayed rows" "$(get '.items | length')" "12"
eq "the thirteenth app is not displayed" "$(get '[.items[].id] | index("com.t.13") | tostring')" "null"
eq "apps memory (GiB)" "$(get '.metrics[] | select(.id=="apps_mem") | .value')" "91"
eq "summary" "$(get '.summary')" "13 apps · 91 GiB"
eq "apps CPU (cores)" "$(get '.metrics[] | select(.id=="apps_cpu") | .value')" "3"
eq "apps CPU unit" "$(get '.metrics[] | select(.id=="apps_cpu") | .unit')" "/ 10 cores"
eq "apps CPU percent" "$(get '.metrics[] | select(.id=="apps_cpu") | .pct')" "30"
eq "foreground app count" "$(get '.lines[0].value')" "13"
pass "with 13 apps and a 12-row cap, both section totals cover all 13 (91 GiB, 3 cores)"

eq "undisplayed app CPU is counted" \
  "$(get '(.metrics[] | select(.id=="apps_cpu") | .value) - ([.items[].metrics[] | select(.id=="cpu") | .value] | add)')" "2"
pass "the CPU of the app past the cap is in the total but not in the rows"

SLOW='{"mem":{"used":8589934592,"total":17179869184,"pressure":"normal","compressed":1073741824,"wired":2147483648},
        "disk":{"used":107374182400,"avail":53687091200,"pct":66.6666},
        "gpu":12,"battery":{"pct":null,"state":"none"},"thermal":"nominal","uptime":"3 days","procs":[]}'

MAC="$($JQ -n --argjson slow "$SLOW" --arg cpu_s "37.5" --arg load_s "1.0 2.0 3.0" \
  --arg diskio_s "0.50 MB/s" --argjson ncpu 10 --arg core_split "10 (8P + 2E)" \
  -f "$LIB/mac_report.jq")" || fail "mac_report.jq did not run"
printf '%s\n' "$MAC" > "$WORK/mac.json"

macget() { $JQ -r "$1" < "$WORK/mac.json"; }

eq "volume metric label" "$(macget '.metrics[] | select(.id=="disk") | .label')" "Data volume"
eq "volume used (GiB)" "$(macget '.metrics[] | select(.id=="disk") | .value')" "100"
eq "volume percent" "$(macget '.metrics[] | select(.id=="disk") | .pct')" "66.7"
eq "volume free line" "$(macget '[.lines[] | select(.value == "50 GiB")][0].label')" "Data volume free"
eq "summary names the data volume" "$(macget '.summary | test("data vol 67%") | tostring')" "true"
eq "nothing is called plain Disk" "$(macget '[.metrics[] | select(.label == "Disk")] | length')" "0"
pass "the startup Data volume is labelled and measured as such, not as the Mac's disks"
