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
  mkdir -p "$dir/providers"
  printf '%s' "$dir"
}

add_real_provider() {
  local dir="$1" name="$2"
  cat > "$dir/providers/$name" <<'PROVIDER'
#!/bin/sh
echo '{"schema":1,"title":"t","state":"ok"}'
PROVIDER
  chmod 700 "$dir/providers/$name"
}

add_refused_provider() {
  local dir="$1" name="$2"
  mkdir -p "$dir/providers/$name"
}

write_config() {
  local dir="$1" content="$2"
  printf '%s' "$content" > "$dir/config.json"
}

run_diagnostic() {
  local dir="$1"
  MAESTER_CONFIG_DIR="$dir" "$BIN" --providers
}

run_disable() {
  local dir="$1" name="$2"
  MAESTER_CONFIG_DIR="$dir" "$BIN" --disable "$name"
}

run_enable() {
  local dir="$1" name="$2"
  MAESTER_CONFIG_DIR="$dir" "$BIN" --enable "$name"
}

count_tmp_files() {
  local dir="$1"
  find "$dir" -maxdepth 1 -name '*.tmp.*' | wc -l | tr -d ' '
}

assert_no_tmp_files() {
  local dir="$1" case_name="$2"
  [ "$(count_tmp_files "$dir")" = "0" ] || fail "$case_name: .tmp files left behind in config dir"
}

config_json_value() {
  local dir="$1" key="$2"
  python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
print(json.dumps(data.get(sys.argv[2])))
' "$dir/config.json" "$key"
}

checksum() {
  local dir="$1"
  shasum -a 256 "$dir/config.json" | awk '{print $1}'
}

assert_unparsable() {
  local dir="$1" case_name="$2" rc
  set +e
  python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    json.load(f)
' "$dir/config.json" >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "$case_name: fixture unexpectedly parses as JSON"
}

config_is_valid_json() {
  local dir="$1" case_name="$2"
  python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    json.load(f)
' "$dir/config.json" || fail "$case_name: config.json is not valid JSON"
}

field_json() {
  python3 -c '
import json, sys
data = json.loads(sys.argv[1])
name, field = sys.argv[2], sys.argv[3]
for e in data:
    if e["name"] == name:
        print(json.dumps(e.get(field)))
        sys.exit(0)
sys.exit(1)
' "$1" "$2" "$3"
}

has_entry() {
  local out="$1" name="$2"
  python3 -c '
import json, sys
data = json.loads(sys.argv[1])
sys.exit(0 if any(e["name"] == sys.argv[2] for e in data) else 1)
' "$out" "$name"
}

assert_field() {
  local out="$1" name="$2" field="$3" expected="$4" case_name="$5"
  local actual
  actual="$(field_json "$out" "$name" "$field")" || fail "$case_name: no entry named '$name' in output"
  [ "$actual" = "$expected" ] || fail "$case_name: $name.$field = $actual, expected $expected"
}

case_absent_config() {
  local d out
  d="$(fixture_dir case_absent_config)"
  add_real_provider "$d" mac
  out="$(run_diagnostic "$d")"
  assert_field "$out" mac enabled true "absent config"
  pass "absent config leaves mac enabled"
}

case_empty_config() {
  local d out
  d="$(fixture_dir case_empty_config)"
  add_real_provider "$d" mac
  write_config "$d" '{}'
  out="$(run_diagnostic "$d")"
  assert_field "$out" mac enabled true "empty config"
  pass "empty config {} leaves mac enabled"
}

case_empty_disabled_array() {
  local d out
  d="$(fixture_dir case_empty_disabled_array)"
  add_real_provider "$d" mac
  write_config "$d" '{"disabled": []}'
  out="$(run_diagnostic "$d")"
  assert_field "$out" mac enabled true "empty disabled array"
  pass "empty disabled array leaves mac enabled"
}

case_disabled_matches_real() {
  local d out
  d="$(fixture_dir case_disabled_matches_real)"
  add_real_provider "$d" mac
  write_config "$d" '{"disabled": ["mac"]}'
  out="$(run_diagnostic "$d")"
  assert_field "$out" mac enabled false "disabled matches real"
  assert_field "$out" mac reason '"disabled"' "disabled matches real"
  pass "disabled name matching a real provider takes effect"
}

case_disabled_matches_nothing() {
  local d out
  d="$(fixture_dir case_disabled_matches_nothing)"
  add_real_provider "$d" mac
  write_config "$d" '{"disabled": ["ghost"]}'
  out="$(run_diagnostic "$d")"
  assert_field "$out" mac enabled true "disabled matches nothing"
  if has_entry "$out" ghost; then
    fail "disabled matches nothing: a nonexistent provider must not appear in output"
  fi
  pass "disabled name matching nothing is silently ignored"
}

case_disabled_and_refused() {
  local d out
  d="$(fixture_dir case_disabled_and_refused)"
  add_refused_provider "$d" refd
  write_config "$d" '{"disabled": ["refd"]}'
  out="$(run_diagnostic "$d")"
  assert_field "$out" refd enabled false "disabled and refused"
  assert_field "$out" refd reason '"refused"' "disabled and refused"
  pass "a disabled name that is also refused reports as refused"
}

case_malformed_json() {
  local d out rc
  d="$(fixture_dir case_malformed_json)"
  add_real_provider "$d" mac
  write_config "$d" '{"disabled": ['
  set +e
  out="$(run_diagnostic "$d")"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || fail "malformed json: --providers exited $rc, expected 0"
  assert_field "$out" mac enabled true "malformed json"
  pass "malformed config.json disables nothing and does not crash"
}

case_unknown_keys_preserved() {
  local d out before after
  d="$(fixture_dir case_unknown_keys_preserved)"
  add_real_provider "$d" mac
  write_config "$d" '{"disabled": ["mac"], "theme": "dark"}'
  before="$(cat "$d/config.json")"
  out="$(run_diagnostic "$d")"
  assert_field "$out" mac enabled false "unknown keys preserved"
  after="$(cat "$d/config.json")"
  [ "$before" = "$after" ] || fail "unknown keys preserved: reading via --providers must not rewrite config.json"
  echo "$after" | grep -q '"theme"' || fail "unknown keys preserved: theme key vanished"
  echo "$after" | grep -q '"dark"' || fail "unknown keys preserved: theme value vanished"
  pass "unknown keys in config.json survive being read"
}

case_disable_preserves_unknown_keys() {
  local d theme note
  d="$(fixture_dir case_disable_preserves_unknown_keys)"
  add_real_provider "$d" mac
  write_config "$d" '{"theme": "dark", "note": 42}'
  run_disable "$d" mac
  config_is_valid_json "$d" "disable preserves unknown keys"
  theme="$(config_json_value "$d" theme)"
  [ "$theme" = '"dark"' ] || fail "disable preserves unknown keys: theme = $theme, expected \"dark\""
  note="$(config_json_value "$d" note)"
  [ "$note" = "42" ] || fail "disable preserves unknown keys: note = $note, expected 42"
  assert_no_tmp_files "$d" "disable preserves unknown keys"
  pass "--disable preserves unknown keys and their values"
}

case_disable_then_providers_reports_disabled() {
  local d out
  d="$(fixture_dir case_disable_then_providers_reports_disabled)"
  add_real_provider "$d" mac
  run_disable "$d" mac
  out="$(run_diagnostic "$d")"
  assert_field "$out" mac enabled false "disable then providers"
  assert_field "$out" mac reason '"disabled"' "disable then providers"
  assert_no_tmp_files "$d" "disable then providers"
  pass "--disable then --providers reports the provider disabled"
}

case_enable_reverses_it() {
  local d out
  d="$(fixture_dir case_enable_reverses_it)"
  add_real_provider "$d" mac
  write_config "$d" '{"disabled": ["mac"]}'
  run_enable "$d" mac
  out="$(run_diagnostic "$d")"
  assert_field "$out" mac enabled true "enable reverses it"
  assert_no_tmp_files "$d" "enable reverses it"
  pass "--enable reverses a --disable"
}

case_disable_twice_idempotent() {
  local d out disabled
  d="$(fixture_dir case_disable_twice_idempotent)"
  add_real_provider "$d" mac
  run_disable "$d" mac
  run_disable "$d" mac
  out="$(run_diagnostic "$d")"
  assert_field "$out" mac enabled false "disable twice"
  disabled="$(config_json_value "$d" disabled)"
  [ "$disabled" = '["mac"]' ] || fail "disable twice: disabled = $disabled, expected [\"mac\"]"
  assert_no_tmp_files "$d" "disable twice"
  pass "--disable twice is idempotent"
}

case_enable_never_disabled_noop() {
  local d out
  d="$(fixture_dir case_enable_never_disabled_noop)"
  add_real_provider "$d" mac
  run_enable "$d" mac
  config_is_valid_json "$d" "enable never disabled"
  out="$(run_diagnostic "$d")"
  assert_field "$out" mac enabled true "enable never disabled"
  assert_no_tmp_files "$d" "enable never disabled"
  pass "--enable on a name that was never disabled is a no-op"
}

case_disable_no_existing_config() {
  local d keys
  d="$(fixture_dir case_disable_no_existing_config)"
  add_real_provider "$d" mac
  run_disable "$d" mac
  config_is_valid_json "$d" "disable no existing config"
  keys="$(python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
print(sorted(data.keys()))
' "$d/config.json")"
  [ "$keys" = "['disabled']" ] || fail "disable no existing config: keys = $keys, expected only disabled"
  assert_no_tmp_files "$d" "disable no existing config"
  pass "--disable with no pre-existing config creates one containing only disabled"
}

case_disable_refuses_malformed_config() {
  local d before after rc out
  d="$(fixture_dir case_disable_refuses_malformed_config)"
  add_real_provider "$d" mac
  write_config "$d" '{"disabled": ["a"], "importantUserSetting": {"keep": true}'
  assert_unparsable "$d" "disable refuses malformed config"
  before="$(checksum "$d")"
  set +e
  out="$(run_disable "$d" mac 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "disable refuses malformed config: --disable exited 0, expected non-zero"
  after="$(checksum "$d")"
  [ "$before" = "$after" ] || fail "disable refuses malformed config: config.json was modified"
  echo "$out" | grep -qF "$d/config.json" || fail "disable refuses malformed config: stderr does not name the config path"
  assert_no_tmp_files "$d" "disable refuses malformed config"
  pass "--disable against an unparsable config.json refuses and leaves it untouched"
}

case_enable_refuses_malformed_config() {
  local d before after rc out
  d="$(fixture_dir case_enable_refuses_malformed_config)"
  add_real_provider "$d" mac
  write_config "$d" '{"disabled": ["a"], "importantUserSetting": {"keep": true}'
  assert_unparsable "$d" "enable refuses malformed config"
  before="$(checksum "$d")"
  set +e
  out="$(run_enable "$d" mac 2>&1)"
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail "enable refuses malformed config: --enable exited 0, expected non-zero"
  after="$(checksum "$d")"
  [ "$before" = "$after" ] || fail "enable refuses malformed config: config.json was modified"
  echo "$out" | grep -qF "$d/config.json" || fail "enable refuses malformed config: stderr does not name the config path"
  assert_no_tmp_files "$d" "enable refuses malformed config"
  pass "--enable against an unparsable config.json refuses and leaves it untouched"
}

case_absent_config
case_empty_config
case_empty_disabled_array
case_disabled_matches_real
case_disabled_matches_nothing
case_disabled_and_refused
case_malformed_json
case_unknown_keys_preserved
case_disable_preserves_unknown_keys
case_disable_then_providers_reports_disabled
case_enable_reverses_it
case_disable_twice_idempotent
case_enable_never_disabled_noop
case_disable_no_existing_config
case_disable_refuses_malformed_config
case_enable_refuses_malformed_config

echo "all optionality cases passed"
