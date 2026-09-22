#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Maester"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "ok: $1"
}

if [ ! -x "$BIN" ]; then
  fail "binary not found at $BIN — run 'zsh build.sh' first"
fi

field_json() {
  python3 -c '
import json, sys
data = json.loads(sys.argv[1])
print(json.dumps(data.get(sys.argv[2])))
' "$1" "$2"
}

check() {
  local label="$1" width="$2" visible_height="$3" want_cols="$4" want_height="$5"
  local out cols height
  out="$("$BIN" --layout-check --width "$width" --visible-height "$visible_height" --provider-count 99)"
  cols="$(field_json "$out" columns)"
  height="$(field_json "$out" panelHeight)"
  [ "$cols" = "$want_cols" ] || fail "$label: columns = $cols, expected $want_cols"
  [ "$height" = "$want_height" ] || fail "$label: panelHeight = $height, expected $want_height"
  pass "$label: $want_cols columns, panel height $want_height"
}

check "13.6in Air"          1470 931  3 811
check "14in Pro"            1512 945  3 825
check "16in Pro"            1728 1080 3 880
check "13in More Space"     1680 1025 3 880
check "27in 4K"             1920 1055 3 880
check "27in 5K Studio"      2560 1415 3 880
check "32in XDR"            3008 1667 3 880
check "Ultrawide 34in"      3440 1415 3 880
check "Sidecar iPad 11in"   1180 795  3 675
check "1024x768 VM"         1024 743  2 623

echo "all layout cases passed"
