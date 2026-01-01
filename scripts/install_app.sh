#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/apps/macos/VoiceOps.xcodeproj"
SCHEME_NAME="VoiceOps"
CONFIGURATION="Release"
BUILD_DIR="$ROOT_DIR/.build_voiceops"
DEST_PATH="${1:-/Applications/VoiceOps.app}"

echo "[install] Building $SCHEME_NAME ($CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD_DIR" \
  build

APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/VoiceOps.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "[install] Build output not found: $APP_PATH"
  exit 1
fi

echo "[install] Ensure the app is not running before replacing."
if [[ -d "$DEST_PATH" ]]; then
  read -r -p "[install] Replace existing app at $DEST_PATH? (y/N) " REPLY
  if [[ "$REPLY" != "y" && "$REPLY" != "Y" ]]; then
    echo "[install] Aborted."
    exit 1
  fi
  rm -rf "$DEST_PATH"
fi

echo "[install] Copying to $DEST_PATH..."
ditto "$APP_PATH" "$DEST_PATH"

echo "[install] Done."
echo "[install] Next: open System Settings → Privacy & Security → Accessibility and add:"
echo "          $DEST_PATH"
