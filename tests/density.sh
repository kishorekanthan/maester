#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Maester"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

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

fixture_dir() {
  local dir="$WORK/$1"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

field_json() {
  python3 -c '
import json, sys
data = json.loads(sys.argv[1])
print(json.dumps(data.get(sys.argv[2])))
' "$1" "$2"
}

case_default_is_comfortable() {
  local d out density
  d="$(fixture_dir case_default_is_comfortable)"
  out="$(MAESTER_CONFIG_DIR="$d" "$BIN" --density-check)"
  density="$(field_json "$out" density)"
  [ "$density" = '"comfortable"' ] || fail "default density: got $density, expected comfortable"
  pass "with no config.json, density defaults to comfortable"
}

case_set_persists_across_processes() {
  local d out density
  d="$(fixture_dir case_set_persists_across_processes)"
  MAESTER_CONFIG_DIR="$d" "$BIN" --density-check --set compact > /dev/null
  out="$(MAESTER_CONFIG_DIR="$d" "$BIN" --density-check)"
  density="$(field_json "$out" density)"
  [ "$density" = '"compact"' ] || fail "persisted density: got $density, expected compact (separate process, fresh read)"
  pass "a density set by one process is read back by another"
}

case_set_round_trips_back_to_comfortable() {
  local d out density
  d="$(fixture_dir case_set_round_trips_back_to_comfortable)"
  MAESTER_CONFIG_DIR="$d" "$BIN" --density-check --set compact > /dev/null
  MAESTER_CONFIG_DIR="$d" "$BIN" --density-check --set comfortable > /dev/null
  out="$(MAESTER_CONFIG_DIR="$d" "$BIN" --density-check)"
  density="$(field_json "$out" density)"
  [ "$density" = '"comfortable"' ] || fail "round trip: got $density, expected comfortable"
  pass "setting density twice leaves the last value in effect"
}

case_preserves_unrelated_config_keys() {
  local d out density disabled
  d="$(fixture_dir case_preserves_unrelated_config_keys)"
  mkdir -p "$d"
  printf '{"disabled":["apps"]}' > "$d/config.json"
  MAESTER_CONFIG_DIR="$d" "$BIN" --density-check --set compact > /dev/null
  disabled="$(python3 -c 'import json; print(json.load(open("'"$d"'/config.json"))["disabled"])')"
  [ "$disabled" = "['apps']" ] || fail "unrelated key: disabled = $disabled, expected ['apps'] preserved"
  pass "writing density preserves the pre-existing disabled key"
}

case_default_is_comfortable
case_set_persists_across_processes
case_set_round_trips_back_to_comfortable
case_preserves_unrelated_config_keys

echo "all density cases passed"
