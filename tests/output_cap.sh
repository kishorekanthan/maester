#!/usr/bin/env zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/build/Maester"
JQ=/usr/bin/jq
CAP=1048576
WORK="$(mktemp -d)"
cleanup() { trash "$WORK" 2>/dev/null || command rm -r "$WORK"; }
trap cleanup EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "ok: $1"; }

[ -x "$BIN" ] || fail "binary not found at $BIN — run 'zsh build.sh' first"

make_provider() {
  local file="$1" redirect="$2" kib="$3"
  cat > "$file" <<PROVIDER
#!/bin/sh
i=0
while [ \$i -lt $kib ]; do
  printf '%1024s' '' $redirect
  i=\$((i + 1))
done
exit 0
PROVIDER
  chmod 700 "$file"
}

make_provider "$WORK/flood-stdout" '' 8192
make_provider "$WORK/flood-stderr" '>&2' 8192
make_provider "$WORK/small" '' 4

cat > "$WORK/stream-flood" <<'PROVIDER'
#!/bin/sh
case "${1:-}" in
  status)
    printf '%s\n' '{"schema":1,"title":"fixture","state":"ok","capabilities":{"stream":true,"refresh":600}}'
    ;;
  stream)
    i=0
    while [ "$i" -lt 2048 ]; do
      printf '%1024s' ''
      i=$((i + 1))
    done
    printf '%s\n' survived >> "${FIXTURE_LOG:?}"
    sleep 600
    ;;
  *) exit 2 ;;
esac
PROVIDER
chmod 700 "$WORK/stream-flood"

bytes() {
  "$BIN" --exec-check "$1" | $JQ -r ".$2"
}

SMALL_OUT="$(bytes "$WORK/small" stdoutBytes)"
[ "$SMALL_OUT" -eq 4096 ] || fail "a 4 KiB provider was not reported verbatim (got $SMALL_OUT bytes, expected 4096)"
pass "output below the cap is delivered whole: $SMALL_OUT bytes"

FLOOD_OUT="$(bytes "$WORK/flood-stdout" stdoutBytes)"
[ "$FLOOD_OUT" -ge "$CAP" ] || fail "stdout was cut below the $CAP byte cap (got $FLOOD_OUT)"
[ "$FLOOD_OUT" -le $((CAP + 4096)) ] || fail "a provider writing 8 MiB to stdout was buffered past the cap (got $FLOOD_OUT bytes)"
pass "stdout is held to the cap: $FLOOD_OUT bytes of an 8 MiB flood"

FLOOD_ERR="$(bytes "$WORK/flood-stderr" stderrBytes)"
[ "$FLOOD_ERR" -ge "$CAP" ] || fail "stderr was cut below the $CAP byte cap (got $FLOOD_ERR)"
[ "$FLOOD_ERR" -le $((CAP + 4096)) ] || fail "a provider writing 8 MiB to stderr was buffered past the cap (got $FLOOD_ERR bytes)"
pass "stderr is held to the cap: $FLOOD_ERR bytes of an 8 MiB flood"

STREAM_LOG="$WORK/stream.log"
FIXTURE_LOG="$STREAM_LOG" "$BIN" --refresh-check "$WORK/stream-flood" >/dev/null || fail "stream cap check exited non-zero"
[ ! -s "$STREAM_LOG" ] || fail "a streaming provider wrote 2 MiB without a newline and was not stopped"
pass "stream stdout is stopped before a 2 MiB unterminated line can complete"
