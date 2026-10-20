#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

required_variables=(
  HUSHWORD_BUNDLE_ID
  HUSHWORD_VERSION
  HUSHWORD_BUILD_NUMBER
  HUSHWORD_SIGN_IDENTITY
  HUSHWORD_NOTARY_PROFILE
  HUSHWORD_MODEL_URL
  HUSHWORD_UPDATE_FEED_URL
  HUSHWORD_UPDATE_DOWNLOAD_PREFIX
  HUSHWORD_SPARKLE_PUBLIC_KEY
  HUSHWORD_SUPPORT_URL
  HUSHWORD_PRIVACY_URL
  HUSHWORD_SUPPORT_EMAIL
  HUSHWORD_DOWNLOAD_URL
)

for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Missing required release variable: $variable" >&2
    exit 64
  fi
done

if [[ "$HUSHWORD_BUNDLE_ID" == "com.local.hushword" ]]; then
  echo "Refusing to release with the development bundle ID." >&2
  exit 64
fi
if [[ "$HUSHWORD_SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
  echo "HUSHWORD_SIGN_IDENTITY must be a Developer ID Application identity." >&2
  exit 64
fi
for url_variable in \
  HUSHWORD_MODEL_URL \
  HUSHWORD_UPDATE_FEED_URL \
  HUSHWORD_UPDATE_DOWNLOAD_PREFIX \
  HUSHWORD_SUPPORT_URL \
  HUSHWORD_PRIVACY_URL \
  HUSHWORD_DOWNLOAD_URL; do
  if [[ "${!url_variable}" != https://* ]]; then
    echo "$url_variable must use HTTPS." >&2
    exit 64
  fi
done
if [[ "$HUSHWORD_SUPPORT_EMAIL" != *@*.* ]]; then
  echo "HUSHWORD_SUPPORT_EMAIL is not a valid support address." >&2
  exit 64
fi

export "${required_variables[@]}"
export HUSHWORD_SPARKLE_KEY_ACCOUNT

cd "$ROOT"
./scripts/build_app.sh
./scripts/verify_distribution.sh \
  "$ROOT/dist/Hushword.app" \
  "$HUSHWORD_BUNDLE_ID"

NOTARY_ZIP="$ROOT/dist/Hushword-$HUSHWORD_VERSION-notarization.zip"
rm -f "$NOTARY_ZIP"
ditto -c -k --sequesterRsrc --keepParent \
  "$ROOT/dist/Hushword.app" \
  "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$HUSHWORD_NOTARY_PROFILE" \
  --wait
rm -f "$NOTARY_ZIP"
xcrun stapler staple "$ROOT/dist/Hushword.app"
xcrun stapler validate "$ROOT/dist/Hushword.app"
spctl -a -vv -t exec "$ROOT/dist/Hushword.app"

RELEASE_ROOT="$ROOT/dist/release-$HUSHWORD_VERSION"
DMG_ROOT="$RELEASE_ROOT/dmg"
UPDATES_ROOT="$RELEASE_ROOT/updates"
DMG_PATH="$ROOT/dist/Hushword-$HUSHWORD_VERSION.dmg"

rm -rf "$RELEASE_ROOT" "$DMG_PATH"
mkdir -p "$DMG_ROOT" "$UPDATES_ROOT"
ditto "$ROOT/dist/Hushword.app" "$DMG_ROOT/Hushword.app"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "Hushword $HUSHWORD_VERSION" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
codesign \
  --force \
  --timestamp \
  --sign "$HUSHWORD_SIGN_IDENTITY" \
  "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$HUSHWORD_NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"

UPDATE_ZIP="$UPDATES_ROOT/Hushword-$HUSHWORD_VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent \
  "$ROOT/dist/Hushword.app" \
  "$UPDATE_ZIP"

GENERATE_APPCAST="$(
  find "$ROOT/.build/artifacts" -type f -name generate_appcast -print -quit
)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  echo "Sparkle generate_appcast tool was not found." >&2
  exit 1
fi

"$GENERATE_APPCAST" \
  --account "${HUSHWORD_SPARKLE_KEY_ACCOUNT:-hushword}" \
  --download-url-prefix "$HUSHWORD_UPDATE_DOWNLOAD_PREFIX" \
  --link "$HUSHWORD_SUPPORT_URL" \
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
