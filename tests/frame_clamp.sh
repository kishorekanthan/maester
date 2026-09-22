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
  local label="$1" cx="$2" cy="$3" cw="$4" ch="$5" tw="$6"
  local vx="$7" vy="$8" vw="$9" vh="${10}"
  local want_x="${11}" want_y="${12}" want_w="${13}" want_h="${14}"
  local out x y w h
  out="$("$BIN" --frame-check \
    --cur-x "$cx" --cur-y "$cy" --cur-width "$cw" --cur-height "$ch" \
    --target-width "$tw" \
    --visible-x "$vx" --visible-y "$vy" --visible-width "$vw" --visible-height "$vh")"
  x="$(field_json "$out" x)"
  y="$(field_json "$out" y)"
  w="$(field_json "$out" width)"
  h="$(field_json "$out" height)"
  [ "$x" = "$want_x" ] || fail "$label: x = $x, expected $want_x"
  [ "$y" = "$want_y" ] || fail "$label: y = $y, expected $want_y"
  [ "$w" = "$want_w" ] || fail "$label: width = $w, expected $want_w"
  [ "$h" = "$want_h" ] || fail "$label: height = $h, expected $want_h"
  pass "$label"
}

check "regrow, centered, no edge clamp" \
  982 35 298 806 736 \
  0 0 1512 945 \
  763 35 736 806

check "regrow, right-edge clamp" \
  1400 10 300 500 736 \
  0 0 1512 945 \
  764 10 736 500

check "height cap, width unchanged" \
  100 100 736 1200 736 \
  0 0 1512 945 \
  100 0 736 945

echo "all frame clamp cases passed"
