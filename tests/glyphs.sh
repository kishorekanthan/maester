#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MENUBAR="$ROOT/Resources/menubar"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

pass() {
  echo "ok: $1"
}

pixel_dims() {
  sips -g pixelWidth -g pixelHeight "$1" 2>/dev/null \
    | awk -F': ' '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w"x"h}'
}

case_every_state_has_at_1x_2x_3x_at_correct_canvas() {
  local state scale suffix file dims expected
  for state in ok warn error sleep; do
    for scale in 1 2 3; do
      if [ "$scale" = "1" ]; then suffix=""; else suffix="@${scale}x"; fi
      file="$MENUBAR/${state}${suffix}.png"
      [ -f "$file" ] || fail "missing glyph asset: $file"
      dims="$(pixel_dims "$file")"
      expected="$((26 * scale))x$((18 * scale))"
      [ "$dims" = "$expected" ] || fail "$file is $dims, expected $expected (26x18pt canvas at ${scale}x)"
    done
  done
  pass "ok/warn/error/sleep each ship @1x/@2x/@3x at the 26x18pt canvas"
}

case_hi_res_assets_are_the_same_artwork_as_their_1x() {
  local out
  out="$(PYTHONPATH="$ROOT/tests/lib" python3 -c '
import sys
from png_rgba import read_png_rgba

STATES = ["ok", "warn", "error", "sleep"]
SELF_LIMIT = 20.0
MARGIN = 1.4

def alpha(path):
    pixels, width, height = read_png_rgba(path)
    return [a for _, _, _, a in pixels], width, height

def downsampled(path, scale):
    px, width, height = alpha(path)
    out = []
    for row in range(height // scale):
        for col in range(width // scale):
            total = 0
            for dr in range(scale):
                for dc in range(scale):
                    total += px[(row * scale + dr) * width + col * scale + dc]
            out.append(total / (scale * scale))
    return out

def mean_abs_error(a, b):
    return sum(abs(x - y) for x, y in zip(a, b)) / len(b)

root = sys.argv[1]
base = {s: alpha(root + "/" + s + ".png")[0] for s in STATES}
problems = []
for state in STATES:
    for scale in (2, 3):
        name = "%s@%dx.png" % (state, scale)
        got = downsampled(root + "/" + name, scale)
        scores = sorted((mean_abs_error(got, base[s]), s) for s in STATES)
        own = next(score for score, s in scores if s == state)
        best_score, best_state = scores[0]
        runner_up = scores[1][0]
        if best_state != state:
            problems.append("%s looks like %s, not %s (%.2f vs %.2f)"
                            % (name, best_state, state, best_score, own))
        elif own > SELF_LIMIT:
            problems.append("%s differs from %s.png by %.2f, over the %.1f limit"
                            % (name, state, own, SELF_LIMIT))
        elif runner_up < own * MARGIN:
            problems.append("%s is only %.2f from %s.png but %.2f from %s.png"
                            % (name, own, state, runner_up, scores[1][1]))
print("; ".join(problems))
' "$MENUBAR")"
  [ -z "$out" ] || fail "$out"
  pass "every @2x and @3x glyph is the same artwork as its 1x, not another state's"
}

case_all_glyphs_are_template_safe_ink() {
  local state file colors
  for state in ok warn error sleep; do
    file="$MENUBAR/${state}.png"
    colors="$(PYTHONPATH="$ROOT/tests/lib" python3 -c '
import sys
from png_rgba import read_png_rgba

pixels, _, _ = read_png_rgba(sys.argv[1])
inked = set((r, g, b) for r, g, b, a in pixels if a > 0)
print(",".join("%d-%d-%d" % c for c in inked))
' "$file")"
    if [ -n "$colors" ] && [ "$colors" != "0-0-0" ]; then
      fail "$file has non-black ink colors ($colors) — template images must be pure black on transparent"
    fi
  done
  pass "every glyph's ink is pure black on transparent (template-safe)"
}

case_off_state_is_dimmer_than_all_clear() {
  local out ok_a sleep_a
  out="$(PYTHONPATH="$ROOT/tests/lib" python3 -c '
import sys
from png_rgba import read_png_rgba

def max_alpha_in_left_columns(path, cols):
    pixels, width, height = read_png_rgba(path)
    best = 0
    for row in range(height):
        for col in range(cols):
            a = pixels[row * width + col][3]
            if a > best:
                best = a
    return best

ok_a = max_alpha_in_left_columns(sys.argv[1] + "/ok.png", 17)
sleep_a = max_alpha_in_left_columns(sys.argv[1] + "/sleep.png", 17)
print(ok_a, sleep_a)
' "$MENUBAR")"
  ok_a="$(echo "$out" | cut -d' ' -f1)"
  sleep_a="$(echo "$out" | cut -d' ' -f2)"
  [ "$ok_a" -gt 200 ] || fail "ok.png's mark peak alpha is $ok_a, expected near-opaque"
  [ "$sleep_a" -lt "$((ok_a * 60 / 100))" ] || \
    fail "sleep.png's mark peak alpha ($sleep_a) is not clearly dimmer than ok.png's ($ok_a) — spec calls for 40%"
  pass "the off/stopped mark is visibly dimmer than the all-clear mark (40% alpha)"
}

case_ok_mark_is_left_aligned_with_empty_space_on_right() {
  local out
  out="$(PYTHONPATH="$ROOT/tests/lib" python3 -c '
import sys
from png_rgba import read_png_rgba

pixels, width, height = read_png_rgba(sys.argv[1] + "/ok.png")
rightmost = -1
for row in range(height):
    for col in range(width):
        if pixels[row * width + col][3] > 0:
            rightmost = max(rightmost, col)
print(rightmost, width)
' "$MENUBAR")"
  local rightmost width
  rightmost="$(echo "$out" | cut -d' ' -f1)"
  width="$(echo "$out" | cut -d' ' -f2)"
  [ "$rightmost" -lt "$((width - 1))" ] || \
    fail "ok.png's ink reaches the canvas's right edge (col $rightmost of $width) — expected empty space on the right"
  pass "the all-clear mark leaves empty space on the canvas's trailing edge"
}

case_every_state_has_at_1x_2x_3x_at_correct_canvas
case_hi_res_assets_are_the_same_artwork_as_their_1x
case_all_glyphs_are_template_safe_ink
case_off_state_is_dimmer_than_all_clear
case_ok_mark_is_left_aligned_with_empty_space_on_right

echo "all glyph cases passed"
