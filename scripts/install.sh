#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build_app.sh"

TARGET="/Applications/FlowType.app"
if pgrep -x FlowType >/dev/null; then
  pkill -TERM -x FlowType
  for _ in {1..50}; do
    if ! pgrep -x FlowType >/dev/null; then
      break
    fi
    sleep 0.1
  done
fi
rm -rf "$TARGET"
cp -R "$ROOT/dist/FlowType.app" "$TARGET"
open "$TARGET"
echo "Installed and opened $TARGET"
