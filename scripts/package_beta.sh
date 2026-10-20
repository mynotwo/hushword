#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${FLOWTYPE_VERSION:-0.1.0}"
DMG_ROOT="$ROOT/dist/beta-dmg"
DMG_PATH="$ROOT/dist/FlowType-$VERSION-beta.dmg"

cd "$ROOT"
./scripts/build_app.sh

rm -rf "$DMG_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT"
ditto "$ROOT/dist/FlowType.app" "$DMG_ROOT/FlowType.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "FlowType Beta $VERSION" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$DMG_ROOT"
echo "Built $DMG_PATH"
echo "This beta is ad-hoc signed and is not suitable for public sale."
