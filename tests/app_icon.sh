#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICNS="$ROOT/Resources/Maester.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "ok: $1"
}

if [ ! -f "$ICNS" ]; then
  fail "icon not found at $ICNS"
fi

ICONSET="$WORK/Maester.iconset"
iconutil -c iconset "$ICNS" -o "$ICONSET" 2>/dev/null || fail "iconutil could not unpack $ICNS"

case_all_ten_required_sizes_are_present() {
  local entry name size dims
  local expected=(
    "icon_16x16.png:16" "icon_16x16@2x.png:32"
    "icon_32x32.png:32" "icon_32x32@2x.png:64"
    "icon_128x128.png:128" "icon_128x128@2x.png:256"
    "icon_256x256.png:256" "icon_256x256@2x.png:512"
    "icon_512x512.png:512" "icon_512x512@2x.png:1024"
  )
  for entry in "${expected[@]}"; do
    name="${entry%%:*}"
    size="${entry##*:}"
    [ -f "$ICONSET/$name" ] || fail "icns is missing $name (16/32/128/256/512 @1x/@2x required)"
    dims="$(sips -g pixelWidth -g pixelHeight "$ICONSET/$name" 2>/dev/null \
      | awk -F': ' '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}')"
    [ "$dims" = "${size}x${size}" ] || fail "$name is $dims, expected ${size}x${size}"
  done
  pass "all 10 required icns renditions (16/32/128/256/512 @1x/@2x) are present at the right size"
}

case_small_renditions_are_a_genuine_redraw_not_a_downsample() {
  local size naive_dims shipped_dims diff
  for size in 16 32; do
    sips -z "$size" "$size" "$ICONSET/icon_512x512@2x.png" \
      --out "$WORK/naive_${size}.png" > /dev/null 2>&1
    diff="$(PYTHONPATH="$ROOT/tests/lib" python3 -c '
import sys
from png_rgba import read_png_rgba

a, wa, ha = read_png_rgba(sys.argv[1])
b, wb, hb = read_png_rgba(sys.argv[2])
assert (wa, ha) == (wb, hb), "size mismatch"
total = 0
for (ra, ga, ba, aa), (rb, gb, bb, ab) in zip(a, b):
    total += abs(ra - rb) + abs(ga - gb) + abs(ba - bb) + abs(aa - ab)
print(total / (wa * ha))
' "$WORK/naive_${size}.png" "$ICONSET/icon_${size}x${size}.png")"
    awk -v d="$diff" 'BEGIN { exit !(d > 20) }' || \
      fail "icon_${size}x${size}.png differs from a plain downsample of the full icon by only $diff/px — expected a redrawn, simplified glyph (one arch, thicker bar), not a resize"
  done
  pass "the 16pt and 32pt icon renditions are a redrawn simplification, not a plain downsample of the full icon"
}

case_large_renditions_match_each_other_at_shared_content() {
  local diff
  sips -z 128 128 "$ICONSET/icon_512x512@2x.png" --out "$WORK/naive_128.png" > /dev/null 2>&1
  diff="$(PYTHONPATH="$ROOT/tests/lib" python3 -c '
import sys
from png_rgba import read_png_rgba

a, wa, ha = read_png_rgba(sys.argv[1])
b, wb, hb = read_png_rgba(sys.argv[2])
total = 0
for (ra, ga, ba, aa), (rb, gb, bb, ab) in zip(a, b):
    total += abs(ra - rb) + abs(ga - gb) + abs(ba - bb) + abs(aa - ab)
print(total / (wa * ha))
' "$WORK/naive_128.png" "$ICONSET/icon_128x128.png")"
  awk -v d="$diff" 'BEGIN { exit !(d < 8) }' || \
    fail "icon_128x128.png differs from a plain downsample of the full icon by $diff/px — the 128pt slot and up must stay unchanged, per the handoff"
  pass "the 128pt rendition (and up) still matches the unchanged full icon"
}

case_all_ten_required_sizes_are_present
case_small_renditions_are_a_genuine_redraw_not_a_downsample
case_large_renditions_match_each_other_at_shared_content

echo "all app icon cases passed"
