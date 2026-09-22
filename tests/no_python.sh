#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

typeset -a shipped
shipped=("$ROOT/build.sh" "$ROOT/install.sh" "$ROOT/maester-doctor" "$ROOT/setup.sh")
for f in "$ROOT"/providers/*(N.); do
  shipped+=("$f")
done
for f in "$ROOT"/providers/lib/*.jq(N) "$ROOT"/lib/*.jq(N); do
  shipped+=("$f")
done

bad=0
interpreter_pattern='(^|[^A-Za-z0-9_./-])python[0-9]?([^A-Za-z0-9_./-]|$)'
for f in "${shipped[@]}"; do
  first_line="$(head -1 "$f")"
  case "$first_line" in
    '#!'*python*)
      echo "FAIL: $f has a python shebang: $first_line" >&2
      bad=1
      ;;
  esac
  if grep -qE "$interpreter_pattern" "$f"; then
    echo "FAIL: $f references python" >&2
    bad=1
  fi
done

[ "$bad" -eq 0 ] || fail "a shipped script references python"
pass "no shipped script has a python shebang or invokes python"
echo "no-python guard passed"
