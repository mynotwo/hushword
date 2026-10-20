#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

required_variables=(
  FLOWTYPE_BUNDLE_ID
  FLOWTYPE_VERSION
  FLOWTYPE_BUILD_NUMBER
  FLOWTYPE_SIGN_IDENTITY
  FLOWTYPE_NOTARY_PROFILE
  FLOWTYPE_MODEL_URL
  FLOWTYPE_UPDATE_FEED_URL
  FLOWTYPE_UPDATE_DOWNLOAD_PREFIX
  FLOWTYPE_SPARKLE_PUBLIC_KEY
  FLOWTYPE_SUPPORT_URL
  FLOWTYPE_PRIVACY_URL
  FLOWTYPE_SUPPORT_EMAIL
  FLOWTYPE_DOWNLOAD_URL
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Missing required release variable: $variable" >&2
    exit 64
  fi
done

if [[ "$FLOWTYPE_BUNDLE_ID" == "com.local.flowtype" ]]; then
  echo "Refusing to release with the development bundle ID." >&2
  exit 64
fi
if [[ "$FLOWTYPE_SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
  echo "FLOWTYPE_SIGN_IDENTITY must be a Developer ID Application identity." >&2
  exit 64
fi
for url_variable in \
  FLOWTYPE_MODEL_URL \
  FLOWTYPE_UPDATE_FEED_URL \
  FLOWTYPE_UPDATE_DOWNLOAD_PREFIX \
  FLOWTYPE_SUPPORT_URL \
  FLOWTYPE_PRIVACY_URL \
  FLOWTYPE_DOWNLOAD_URL; do
  if [[ "${!url_variable}" != https://* ]]; then
    echo "$url_variable must use HTTPS." >&2
    exit 64
  fi
done
if [[ "$FLOWTYPE_SUPPORT_EMAIL" != *@*.* ]]; then
  echo "FLOWTYPE_SUPPORT_EMAIL is not a valid support address." >&2
  exit 64
fi

export "${required_variables[@]}"
export FLOWTYPE_SPARKLE_KEY_ACCOUNT

cd "$ROOT"
./scripts/build_app.sh
./scripts/verify_distribution.sh \
  "$ROOT/dist/FlowType.app" \
  "$FLOWTYPE_BUNDLE_ID"

NOTARY_ZIP="$ROOT/dist/FlowType-$FLOWTYPE_VERSION-notarization.zip"
rm -f "$NOTARY_ZIP"
ditto -c -k --sequesterRsrc --keepParent \
  "$ROOT/dist/FlowType.app" \
  "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$FLOWTYPE_NOTARY_PROFILE" \
  --wait
rm -f "$NOTARY_ZIP"
xcrun stapler staple "$ROOT/dist/FlowType.app"
xcrun stapler validate "$ROOT/dist/FlowType.app"
spctl -a -vv -t exec "$ROOT/dist/FlowType.app"

RELEASE_ROOT="$ROOT/dist/release-$FLOWTYPE_VERSION"
DMG_ROOT="$RELEASE_ROOT/dmg"
UPDATES_ROOT="$RELEASE_ROOT/updates"
DMG_PATH="$ROOT/dist/FlowType-$FLOWTYPE_VERSION.dmg"

rm -rf "$RELEASE_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT" "$UPDATES_ROOT"
ditto "$ROOT/dist/FlowType.app" "$DMG_ROOT/FlowType.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "FlowType $FLOWTYPE_VERSION" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
codesign \
  --force \
  --timestamp \
  --sign "$FLOWTYPE_SIGN_IDENTITY" \
  "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$FLOWTYPE_NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"

UPDATE_ZIP="$UPDATES_ROOT/FlowType-$FLOWTYPE_VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent \
  "$ROOT/dist/FlowType.app" \
  "$UPDATE_ZIP"

GENERATE_APPCAST="$(
  find "$ROOT/.build/artifacts" -type f -name generate_appcast -print -quit
)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  echo "Sparkle generate_appcast tool was not found." >&2
  exit 1
fi

"$GENERATE_APPCAST" \
  --account "${FLOWTYPE_SPARKLE_KEY_ACCOUNT:-flowtype}" \
  --download-url-prefix "$FLOWTYPE_UPDATE_DOWNLOAD_PREFIX" \
  --link "$FLOWTYPE_SUPPORT_URL" \
  --maximum-versions 5 \
  --maximum-deltas 2 \
  "$UPDATES_ROOT"

./scripts/build_site.sh

echo
echo "Release artifacts:"
echo "  $DMG_PATH"
echo "  $UPDATE_ZIP"
echo "  $UPDATES_ROOT/appcast.xml"
echo "  $ROOT/dist/site/"
