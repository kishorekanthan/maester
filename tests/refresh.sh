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

cat > "$WORK/streamer" <<'PROVIDER'
#!/bin/sh
case "${1:-}" in
  status)
    printf '%s\n' '{"schema":1,"title":"fixture","state":"ok","capabilities":{"stream":true,"refresh":600}}'
    ;;
  stream)
    printf '%s\n' '{"schema":1,"title":"fixture","state":"ok"}'
    sleep 600
    ;;
  *)
    exit 2
    ;;
esac
PROVIDER
chmod 700 "$WORK/streamer"

cat > "$WORK/poller" <<'PROVIDER'
#!/bin/sh
case "${1:-}" in
  status)
    printf '%s\n' '{"schema":1,"title":"fixture","state":"ok","capabilities":{"stream":false,"refresh":600}}'
    ;;
  *)
    exit 2
    ;;
esac
PROVIDER
chmod 700 "$WORK/poller"

check() {
  local label="$1" prov="$2" out before after
  out="$("$BIN" --refresh-check "$prov")" || fail "--refresh-check exited non-zero ($label)"
  before="$(printf '%s\n' "$out" | $JQ -r '.beforeRefresh')"
  after="$(printf '%s\n' "$out" | $JQ -r '.afterRefresh')"
  [ "$before" -ge 1 ] || fail "$label never published a report before the refresh"
  [ "$after" -gt "$before" ] || fail "$label published $before reports and still $after after Refresh All"
  pass "$label produced a fresh report on Refresh All ($before -> $after)"
}

check "a streaming provider" "$WORK/streamer"
check "a polling provider" "$WORK/poller"
