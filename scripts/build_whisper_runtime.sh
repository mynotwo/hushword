#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE_ROOT="$ROOT/.build/whisper-runtime-cache"
SOURCE_ARCHIVE="$CACHE_ROOT/whisper.cpp-1.9.1.tar.gz"
SOURCE_DIR="$CACHE_ROOT/whisper.cpp-1.9.1"
OUTPUT_DIR="${1:-$ROOT/.build/whisper-runtime}"
SOURCE_URL="https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.9.1.tar.gz"
SOURCE_SHA256="147267177eef7b22ec3d2476dd514d1b12e160e176230b740e3d1bd600118447"

for command in cmake curl shasum tar; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "Missing build dependency: $command" >&2
    exit 1
  fi
done

mkdir -p "$CACHE_ROOT"
if [[ ! -f "$SOURCE_ARCHIVE" ]] || \
   [[ "$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{print $1}')" != "$SOURCE_SHA256" ]]; then
  rm -f "$SOURCE_ARCHIVE"
  curl \
    --fail \
    --location \
    --retry 3 \
    --connect-timeout 15 \
    --output "$SOURCE_ARCHIVE" \
    "$SOURCE_URL"
fi

ACTUAL_SHA256="$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$SOURCE_SHA256" ]]; then
  echo "whisper.cpp source checksum mismatch" >&2
  exit 1
fi

if [[ ! -f "$SOURCE_DIR/CMakeLists.txt" ]]; then
  rm -rf "$SOURCE_DIR"
  tar -xzf "$SOURCE_ARCHIVE" -C "$CACHE_ROOT"
fi

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

build_variant() {
  local name="$1"
  local arm_arch="$2"
  local deployment_target="$3"
  local build_dir="$CACHE_ROOT/build-$name"

  cmake \
    -S "$SOURCE_DIR" \
    -B "$build_dir" \
    -Wno-deprecated \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="-ffile-prefix-map=$SOURCE_DIR=whisper.cpp" \
    -DCMAKE_CXX_FLAGS="-ffile-prefix-map=$SOURCE_DIR=whisper.cpp" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
    -DBUILD_SHARED_LIBS=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DWHISPER_BUILD_EXAMPLES=ON \
    -DWHISPER_BUILD_SERVER=ON \
    -DWHISPER_USE_SYSTEM_GGML=OFF \
    -DGGML_BACKEND_DL=OFF \
    -DGGML_NATIVE=OFF \
    -DGGML_CPU_ARM_ARCH="$arm_arch" \
    -DGGML_OPENMP=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DGGML_ACCELERATE=ON \
    -DGGML_CCACHE=OFF

  cmake \
    --build "$build_dir" \
    --config Release \
    --target whisper-server whisper-cli \
    -j "$(sysctl -n hw.logicalcpu)"

  cp "$build_dir/bin/whisper-server" "$OUTPUT_DIR/whisper-server-$name"
  cp "$build_dir/bin/whisper-cli" "$OUTPUT_DIR/whisper-cli-$name"
}

build_variant "apple_m1" "armv8.2-a+dotprod" "13.3"
build_variant "apple_m2_m3" "armv8.6-a+dotprod+i8mm+nosve" "13.3"
build_variant "apple_m4" "armv9.2-a+dotprod+i8mm+nosve+sme" "15.0"

for binary in "$OUTPUT_DIR"/whisper-*; do
  chmod 755 "$binary"
  if ! file "$binary" | grep -q "Mach-O 64-bit executable arm64"; then
    echo "Unexpected Whisper runtime architecture: $binary" >&2
    exit 1
  fi
  if otool -L "$binary" | tail -n +2 | grep -Eq \
    '/opt/homebrew|/usr/local|@rpath|@loader_path|@executable_path'; then
    echo "Whisper runtime has a non-system dependency: $binary" >&2
    otool -L "$binary" >&2
    exit 1
  fi
  if strings -a "$binary" | grep -F "$ROOT/" >/dev/null; then
    echo "Whisper runtime contains a private build path: $binary" >&2
    exit 1
  fi
  codesign --force --sign - "$binary"
done

cp "$SOURCE_DIR/LICENSE" "$OUTPUT_DIR/whisper.cpp-LICENSE.txt"
cat > "$OUTPUT_DIR/cpp-httplib-LICENSE.txt" <<'EOF'
MIT License

Copyright (c) 2025 Yuji Hirose

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF

echo "Built self-contained Whisper runtime at $OUTPUT_DIR"
