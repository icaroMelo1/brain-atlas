#!/usr/bin/env bash
# brain-atlas — build script para desenvolvimento local
# Uso:
#   ./build.sh          → build debug
#   ./build.sh release  → build release + cria .app em dist/
#   ./build.sh run      → build debug + executa
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="BrainAtlas"
BUNDLE_ID="com.icaromelo.brain-atlas"
BUILD_CONFIG="${1:-debug}"

# Sincroniza brain-atlas.html do root para o bundle resources
echo "→ Sincronizando brain-atlas.html..."
cp "$SCRIPT_DIR/../brain-atlas.html" \
   "$SCRIPT_DIR/Sources/BrainAtlas/Resources/brain-atlas.html"

# Sincroniza nodes.json
if [ -f "$SCRIPT_DIR/../nodes.json" ]; then
  cp "$SCRIPT_DIR/../nodes.json" \
     "$SCRIPT_DIR/Sources/BrainAtlas/Resources/nodes.json"
fi

if [ "$BUILD_CONFIG" = "run" ]; then
  echo "→ Build + execução (debug)..."
  swift run --package-path "$SCRIPT_DIR"
  exit 0
fi

if [ "$BUILD_CONFIG" = "release" ]; then
  echo "→ Build release..."
  swift build --package-path "$SCRIPT_DIR" -c release

  BUILD_BIN="$SCRIPT_DIR/.build/release/$APP_NAME"
  DIST_DIR="$SCRIPT_DIR/dist"
  APP_DIR="$DIST_DIR/$APP_NAME.app"

  echo "→ Montando .app em $APP_DIR..."
  rm -rf "$APP_DIR"
  mkdir -p "$APP_DIR/Contents/MacOS"
  mkdir -p "$APP_DIR/Contents/Resources"

  cp "$BUILD_BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
  cp "$SCRIPT_DIR/Sources/BrainAtlas/Resources/Info.plist" "$APP_DIR/Contents/"
  cp "$SCRIPT_DIR/Sources/BrainAtlas/Resources/brain-atlas.html" "$APP_DIR/Contents/Resources/"
  [ -f "$SCRIPT_DIR/Sources/BrainAtlas/Resources/nodes.json" ] && \
    cp "$SCRIPT_DIR/Sources/BrainAtlas/Resources/nodes.json" "$APP_DIR/Contents/Resources/"

  echo ""
  echo "✓ App criado em: $APP_DIR"
  echo "  Para rodar: open '$APP_DIR'"
  echo "  Para notarizar: codesign --deep --force --options runtime \\"
  echo "    --entitlements $SCRIPT_DIR/BrainAtlas.entitlements \\"
  echo "    --sign 'Developer ID Application: <NOME>' '$APP_DIR'"
else
  echo "→ Build debug..."
  swift build --package-path "$SCRIPT_DIR"
  echo "✓ Build OK. Para rodar: swift run --package-path $SCRIPT_DIR"
fi
