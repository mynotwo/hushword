#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/site"
OUTPUT="$ROOT/dist/site"

required_variables=(
  HUSHWORD_VERSION
  HUSHWORD_DOWNLOAD_URL
  HUSHWORD_SUPPORT_EMAIL
  HUSHWORD_SUPPORT_URL
  HUSHWORD_PRIVACY_URL
)
for variable in "${required_variables[@]}"; do
  if [[ -z "${!variable:-}" ]]; then
    echo "Missing site variable: $variable" >&2
    exit 64
  fi
done

rm -rf "$OUTPUT"
mkdir -p "$OUTPUT"
cp "$SOURCE/styles.css" "$OUTPUT/styles.css"
cp "$ROOT/Resources/AppIcon.svg" "$OUTPUT/app-icon.svg"

render() {
  local source="$1"
  local destination="$2"
  local content
  content="$(<"$source")"
  content="${content//\{\{VERSION\}\}/$HUSHWORD_VERSION}"
  content="${content//\{\{DOWNLOAD_URL\}\}/$HUSHWORD_DOWNLOAD_URL}"
  content="${content//\{\{SUPPORT_EMAIL\}\}/$HUSHWORD_SUPPORT_EMAIL}"
  content="${content//\{\{SUPPORT_URL\}\}/$HUSHWORD_SUPPORT_URL}"
  content="${content//\{\{PRIVACY_URL\}\}/$HUSHWORD_PRIVACY_URL}"
  printf '%s\n' "$content" > "$destination"
  if grep -Eq '\{\{[A-Z_]+\}\}' "$destination"; then
    echo "Unresolved site placeholder in $destination" >&2
    exit 1
  fi
}

render "$SOURCE/index.html" "$OUTPUT/index.html"
render "$SOURCE/privacy.html" "$OUTPUT/privacy.html"
render "$SOURCE/support.html" "$OUTPUT/support.html"

echo "Built $OUTPUT"
