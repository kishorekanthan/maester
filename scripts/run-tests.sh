#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TEST_PATH="/usr/bin:/bin:/usr/sbin:/sbin"

for f in tests/*.sh; do
  echo "-- $f --"
  if [ "$(basename "$f")" = "provider_live.sh" ]; then
    PATH="$TEST_PATH" "$f" ./providers/apps
    PATH="$TEST_PATH" "$f" ./providers/mac
  else
    PATH="$TEST_PATH" "$f"
  fi
done
