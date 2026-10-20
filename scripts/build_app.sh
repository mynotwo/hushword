#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$(cd "$ROOT" && swift build -c release --product FlowType --show-bin-path)"
APP_DIR="$ROOT/dist/FlowType.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
FRAMEWORKS="$CONTENTS/Frameworks"
WHISPER_RUNTIME="$RESOURCES/WhisperRuntime"
PLIST="$CONTENTS/Info.plist"
SIGN_IDENTITY="${FLOWTYPE_SIGN_IDENTITY:--}"

cd "$ROOT"
swift build -c release --product FlowType

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$WHISPER_RUNTIME" "$FRAMEWORKS"
cp "$BUILD_DIR/FlowType" "$MACOS/FlowType"
cp "$ROOT/Resources/Info.plist" "$PLIST"
ditto "$BUILD_DIR/Sparkle.framework" "$FRAMEWORKS/Sparkle.framework"
"$ROOT/scripts/build_icon.sh" "$RESOURCES/AppIcon.icns"
cp "$ROOT/.build/checkouts/Sparkle/LICENSE" "$RESOURCES/LICENSE-Sparkle.txt"
"$ROOT/scripts/build_whisper_runtime.sh" "$WHISPER_RUNTIME"

set_plist_string() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$key string $value" "$PLIST"
}

set_plist_boolean() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$key bool $value" "$PLIST"
}

set_plist_string CFBundleIdentifier \
  "${FLOWTYPE_BUNDLE_ID:-com.local.flowtype}"
set_plist_string CFBundleShortVersionString \
  "${FLOWTYPE_VERSION:-0.1.0}"
set_plist_string CFBundleVersion \
  "${FLOWTYPE_BUILD_NUMBER:-1}"

if [[ -n "${FLOWTYPE_MODEL_URL:-}" ]]; then
  set_plist_string FlowTypeWhisperModelURL "$FLOWTYPE_MODEL_URL"
fi
if [[ -n "${FLOWTYPE_UPDATE_FEED_URL:-}" ]]; then
  set_plist_string SUFeedURL "$FLOWTYPE_UPDATE_FEED_URL"
fi
if [[ -n "${FLOWTYPE_SPARKLE_PUBLIC_KEY:-}" ]]; then
  set_plist_string SUPublicEDKey "$FLOWTYPE_SPARKLE_PUBLIC_KEY"
fi
if [[ -n "${FLOWTYPE_SUPPORT_URL:-}" ]]; then
  set_plist_string FlowTypeSupportURL "$FLOWTYPE_SUPPORT_URL"
fi
if [[ -n "${FLOWTYPE_PRIVACY_URL:-}" ]]; then
  set_plist_string FlowTypePrivacyURL "$FLOWTYPE_PRIVACY_URL"
fi
set_plist_boolean SUEnableAutomaticChecks \
  "${FLOWTYPE_AUTOMATIC_UPDATE_CHECKS:-true}"

for binary in "$WHISPER_RUNTIME"/whisper-*; do
  if [[ -x "$binary" ]] && otool -L "$binary" | tail -n +2 | grep -Eq \
    '/opt/homebrew|/usr/local|@rpath|@loader_path|@executable_path'; then
    echo "Packaged Whisper runtime has a non-system dependency: $binary" >&2
    exit 1
  fi
done

SPARKLE="$FRAMEWORKS/Sparkle.framework"

sign_component() {
  local path="$1"
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$path"
  else
    codesign \
      --force \
      --options runtime \
      --timestamp \
      --sign "$SIGN_IDENTITY" \
      "$path"
  fi
}

sign_bundle_preserving_entitlements() {
  local path="$1"
  if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign \
      --force \
      --sign - \
      --preserve-metadata=entitlements,requirements \
      "$path"
  else
    codesign \
      --force \
      --options runtime \
      --timestamp \
      --sign "$SIGN_IDENTITY" \
      --preserve-metadata=entitlements,requirements \
      "$path"
  fi
}

for bundle in \
  "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
  "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
  "$SPARKLE/Versions/B/Updater.app"; do
  sign_bundle_preserving_entitlements "$bundle"
done
sign_component "$SPARKLE/Versions/B/Autoupdate"
sign_component "$SPARKLE"

for binary in "$WHISPER_RUNTIME"/whisper-*; do
  sign_component "$binary"
done

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign \
    --force \
    --sign - \
    --identifier "${FLOWTYPE_BUNDLE_ID:-com.local.flowtype}" \
    --requirements \
    "=designated => identifier \"${FLOWTYPE_BUNDLE_ID:-com.local.flowtype}\"" \
    "$APP_DIR"
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    --identifier "$FLOWTYPE_BUNDLE_ID" \
    "$APP_DIR"
fi
codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "Built $APP_DIR"
