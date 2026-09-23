#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SOURCE_APP="$HOME/Applications/Maester.app"
TEST_BUNDLE_ID="com.kishore.maester.uitest"
PROJECT_DIR="$ROOT/build/uitests"
LOG="$PROJECT_DIR/xcodebuild.log"
WORK="$(mktemp -d)"
cleanup() { trash "$WORK" 2>/dev/null || command rm -r "$WORK"; }
trap cleanup EXIT

[ -d "$SOURCE_APP" ] || { echo "run-ui-tests: $SOURCE_APP not found, run ./build.sh first" >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "run-ui-tests: xcodegen not found, brew install xcodegen" >&2; exit 1; }

APP="$WORK/MaesterUITest.app"
CONFIG="$WORK/config"
cp -R "$SOURCE_APP" "$APP"
plutil -replace CFBundleIdentifier -string "$TEST_BUNDLE_ID" "$APP/Contents/Info.plist"
codesign --force --sign - --identifier "$TEST_BUNDLE_ID" --options runtime --timestamp=none "$APP" 2>/dev/null
mkdir -m 700 "$CONFIG" "$CONFIG/providers"
cp tests/ui/rows-provider.sh "$CONFIG/providers/rows"
chmod 700 "$CONFIG/providers/rows"

mkdir -p "$PROJECT_DIR"
xcodegen generate --quiet --spec tests/ui/project.yml --project "$PROJECT_DIR"

export TEST_RUNNER_MAESTER_UI_APP="$APP"
export TEST_RUNNER_MAESTER_UI_CONFIG_DIR="$CONFIG"
if xcodebuild test \
    -project "$PROJECT_DIR/MaesterUITests.xcodeproj" \
    -scheme MaesterUITests \
    -destination 'platform=macOS' \
    -derivedDataPath "$PROJECT_DIR/derived" "$@" >"$LOG" 2>&1; then
  grep -E "^Test Case .*(passed|failed)" "$LOG" | sed 's/^/  /'
  echo "ui tests passed"
else
  grep -E "^Test Case .*(passed|failed)|error:|XCTAssert" "$LOG" | sed 's/^/  /' >&2 || true
  tail -40 "$LOG" >&2
  echo "ui tests failed, full log: $LOG" >&2
  exit 1
fi
