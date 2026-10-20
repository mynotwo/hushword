#!/bin/bash
set -euo pipefail

APP_PATH="${1:-}"
EXPECTED_BUNDLE_ID="${2:-}"

if [[ -z "$APP_PATH" || -z "$EXPECTED_BUNDLE_ID" ]]; then
  echo "Usage: $0 /path/to/FlowType.app com.example.flowtype" >&2
  exit 64
fi

PLIST="$APP_PATH/Contents/Info.plist"
EXECUTABLE="$APP_PATH/Contents/MacOS/FlowType"
SPARKLE="$APP_PATH/Contents/Frameworks/Sparkle.framework"

[[ -d "$APP_PATH" ]] || {
  echo "Missing app: $APP_PATH" >&2
  exit 1
}
[[ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]] || {
  echo "Missing app icon." >&2
  exit 1
}
[[ -d "$SPARKLE" ]] || {
  echo "Missing Sparkle.framework." >&2
  exit 1
}

ACTUAL_BUNDLE_ID="$(
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST"
)"
[[ "$ACTUAL_BUNDLE_ID" == "$EXPECTED_BUNDLE_ID" ]] || {
  echo "Bundle ID mismatch: $ACTUAL_BUNDLE_ID" >&2
  exit 1
}

for key in \
  FlowTypeWhisperModelURL \
  SUFeedURL \
  SUPublicEDKey \
  FlowTypeSupportURL \
  FlowTypePrivacyURL; do
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST")"
  [[ "$value" == https://* ]] || {
    if [[ "$key" == "SUPublicEDKey" && -n "$value" ]]; then
      continue
    fi
    echo "Invalid release metadata for $key: $value" >&2
    exit 1
  }
done

file "$EXECUTABLE" | grep -q 'arm64' || {
  echo "FlowType is not an Apple Silicon build." >&2
  exit 1
}
otool -l "$EXECUTABLE" \
  | grep -q '@executable_path/../Frameworks' || {
  echo "FlowType cannot locate embedded frameworks." >&2
  exit 1
}

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

SIGNATURE="$(
  codesign -dv --verbose=4 "$APP_PATH" 2>&1
)"
grep -q 'flags=.*runtime' <<<"$SIGNATURE" || {
  echo "Hardened Runtime is not enabled." >&2
  exit 1
}
grep -q 'TeamIdentifier=' <<<"$SIGNATURE" || {
  echo "Developer ID team identifier is missing." >&2
  exit 1
}
grep -qv 'TeamIdentifier=not set' <<<"$SIGNATURE" || {
  echo "App is still ad-hoc signed." >&2
  exit 1
}

while IFS= read -r binary; do
  if otool -L "$binary" 2>/dev/null | tail -n +2 | grep -Eq \
    '/opt/homebrew|/usr/local'; then
    echo "Non-system runtime dependency: $binary" >&2
    exit 1
  fi
done < <(find "$APP_PATH" -type f -perm -111 -print)

echo "Distribution verification passed: $APP_PATH"
