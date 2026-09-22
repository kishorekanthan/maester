#!/usr/bin/env bash
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/providers"
CONFIG_DIR="${MAESTER_CONFIG_DIR:-$HOME/.config/maester}"
DEST="$CONFIG_DIR/providers"

mkdir -p "$DEST"
chmod 755 "$DEST" "$SRC"

for provider in "$SRC"/*; do
  [ -f "$provider" ] || continue
  name="$(basename "$provider")"
  chmod 755 "$provider"
  ln -sfn "$provider" "$DEST/$name"
  echo "  $name -> $provider"
done

echo
echo "installed into $DEST"
echo "validate with: maester-doctor"
