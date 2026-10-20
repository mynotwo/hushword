#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build_app.sh"

TARGET="/Applications/Hushword.app"
if pgrep -x Hushword >/dev/null; then
  pkill -TERM -x Hushword
  for _ in {1..50}; do
    if ! pgrep -x Hushword >/dev/null; then
      break
    fi
    sleep 0.1
  done
fi
rm -rf "$TARGET"
cp -R "$ROOT/dist/Hushword.app" "$TARGET"
open "$TARGET"
echo "Installed and opened $TARGET"
