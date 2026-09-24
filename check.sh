#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

echo "== build =="
./build.sh

echo
echo "== tests =="
./scripts/run-tests.sh

echo
echo "== complexity gate =="
if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint is not installed." >&2
  echo "install it with: brew install swiftlint" >&2
  exit 1
fi
swiftlint lint --config .swiftlint.yml --baseline scripts/swiftlint-baseline.json --strict

echo
echo "== no-comments check =="
./scripts/no-comments-check.sh

echo
echo "check.sh passed"
