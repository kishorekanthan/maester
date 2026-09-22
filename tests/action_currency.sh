#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Maester"
JQ=/usr/bin/jq
WORK="$(mktemp -d)"
cleanup() { trash "$WORK" 2>/dev/null || command rm -r "$WORK"; }
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

[ -x "$BIN" ] || fail "binary not found at $BIN — run 'zsh build.sh' first"

make_provider() {
  local file="$1" stream_actions="$2"
  cat > "$file" <<PROVIDER
#!/bin/sh
LOG="\${FIXTURE_LOG:?}"
case "\${1:-}" in
  status)
    printf '%s\n' '{"schema":1,"title":"fixture","state":"ok","capabilities":{"stream":true,"refresh":600},"actions":[{"id":"doit","label":"Do it"}]}'
    ;;
  stream)
    printf '%s\n' '{"schema":1,"title":"fixture","state":"ok"$stream_actions}'
    sleep 600
    ;;
  do)
    printf '%s\n' "\$2" >> "\$LOG"
    ;;
  *)
    exit 2
    ;;
esac
PROVIDER
  chmod 700 "$file"
}

make_provider "$WORK/withdrawn" ''
make_provider "$WORK/still-declared" ',"actions":[{"id":"doit","label":"Do it"}]'

run_case() {
  local label="$1" prov="$2"
  local log="$WORK/$(basename "$prov").log"
  local out
  : > "$log"
  out="$(FIXTURE_LOG="$log" "$BIN" --action-check "$prov")" || fail "--action-check exited non-zero ($label)"
  printf '%s\n' "$out" | $JQ -r '.problem // ""' > "$log.problem"
  wc -l < "$log" | tr -d ' ' > "$log.ran"
}

run_case "withdrawn" "$WORK/withdrawn"
WITHDRAWN_PROBLEM="$(cat "$WORK/withdrawn.log.problem")"
WITHDRAWN_RAN="$(cat "$WORK/withdrawn.log.ran")"

run_case "still declared" "$WORK/still-declared"
LIVE_PROBLEM="$(cat "$WORK/still-declared.log.problem")"
LIVE_RAN="$(cat "$WORK/still-declared.log.ran")"

[ "$WITHDRAWN_RAN" -eq 0 ] || fail "an action withdrawn by the newest report was still spawned ($WITHDRAWN_RAN time(s))"
[ -n "$WITHDRAWN_PROBLEM" ] || fail "a withdrawn action was refused silently, with no problem reported"
pass "an action the newest report no longer declares is refused: $WITHDRAWN_PROBLEM"

[ "$LIVE_RAN" -eq 1 ] || fail "a still-declared action did not run (ran $LIVE_RAN time(s))"
[ -z "$LIVE_PROBLEM" ] || fail "a still-declared action reported a problem: $LIVE_PROBLEM"
pass "an action the newest report still declares runs"
