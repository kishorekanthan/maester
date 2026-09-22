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

add_provider_with_icon() {
  local dir="$1" name="$2" icon="$3"
  cat > "$dir/providers/$name" <<PROVIDER
#!/bin/sh
echo '{"schema":1,"title":"t","state":"ok","icon":"$icon"}'
PROVIDER
  chmod 700 "$dir/providers/$name"
}

icon_check() {
  local dir="$1" name="$2"
  MAESTER_CONFIG_DIR="$dir" "$BIN" --icon-check "$name"
}

symbol_check() {
  "$BIN" --symbol-check "$1"
}

field_json() {
  python3 -c '
import json, sys
data = json.loads(sys.argv[1])
print(json.dumps(data.get(sys.argv[2])))
' "$1" "$2"
}

case_bogus_sf_symbol_is_unresolved() {
  local d out resolved
  d="$(fixture_dir case_bogus_sf_symbol_is_unresolved)"
  add_provider_with_icon "$d" bogus "sf:definitely.not.a.real.symbol"
  out="$(icon_check "$d" bogus)"
  resolved="$(field_json "$out" resolved)"
  [ "$resolved" = "false" ] || fail "bogus sf: symbol: resolved = $resolved, expected false"
  pass "a bogus sf: symbol name is treated as unresolved"
}

case_real_sf_symbol_is_resolved() {
  local d out resolved
  d="$(fixture_dir case_real_sf_symbol_is_resolved)"
  add_provider_with_icon "$d" real "sf:gearshape"
  out="$(icon_check "$d" real)"
  resolved="$(field_json "$out" resolved)"
  [ "$resolved" = "true" ] || fail "real sf: symbol: resolved = $resolved, expected true"
  pass "a real sf: symbol name resolves"
}

case_app_own_symbols_resolve() {
  local names name out resolved
  names="$(python3 - "$ROOT" <<'PYEOF'
import re, sys
root = sys.argv[1]
names = set()
panel = open(f"{root}/Sources/PanelView.swift").read()
tokens = open(f"{root}/Sources/Tokens.swift").read()
props = {"symbol": tokens, "badgeSymbol": panel, "menuBarSymbol": panel}
for prop, source in props.items():
    m = re.search(r'var %s: String \{(.*?)\n    \}' % prop, source, re.S)
    names.update(re.findall(r'"([^"]+)"', m.group(1)))
for path in ["Sources/PanelView.swift", "Sources/main.swift", "Sources/Icons.swift", "Sources/Tokens.swift"]:
    s = open(f"{root}/{path}").read()
    names.update(re.findall(r'Icon\.systemName\("([^"]+)"\)', s))
icons_src = open(f"{root}/Sources/Icons.swift").read()
m = re.search(r'fallbackSymbol = "([^"]+)"', icons_src)
names.add(m.group(1))
for n in sorted(names):
    print(n)
PYEOF
)"
  [ -n "$names" ] || fail "app symbol enumeration found nothing — extraction is broken"
  while IFS= read -r name; do
    out="$(symbol_check "$name")"
    resolved="$(field_json "$out" resolved)"
    [ "$resolved" = "true" ] || fail "app symbol '$name' does not resolve on this machine"
  done <<< "$names"
  pass "every SF Symbol name the app itself uses resolves on the build machine"
}

case_bogus_sf_symbol_is_unresolved
case_real_sf_symbol_is_resolved
case_app_own_symbols_resolve

echo "all icon cases passed"
