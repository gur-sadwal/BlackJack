#!/usr/bin/env bash
# Baut eine unsignierte BlackJack.ipa für AltStore.
# AltStore signiert die App beim Installieren mit deiner eigenen Apple-ID.
#
# Aufruf (im Projektordner):  ./scripts/build-ipa.sh            → mit lokalen Extras aus Private/ (falls vorhanden)
#                             ./scripts/build-ipa.sh --public   → ohne lokale Extras
# Ergebnis:                   build/BlackJack.ipa
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

BUILD_DIR="build"
rm -rf "$BUILD_DIR"

xcodebuild \
  -project BlackJack.xcodeproj \
  -scheme BlackJack \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build | grep -E "error:|BUILD" || true

APP="$BUILD_DIR/DerivedData/Build/Products/Release-iphoneos/BlackJack.app"
[ -d "$APP" ] || { echo "Build fehlgeschlagen – siehe Ausgabe oben."; exit 1; }

mkdir -p "$BUILD_DIR/Payload"
cp -R "$APP" "$BUILD_DIR/Payload/"

# Lokale Extras (nicht im Repo) nur in die private IPA
if [ "${1:-}" != "--public" ] && [ -f Private/AfterDark.json ]; then
  cp Private/AfterDark.json "$BUILD_DIR/Payload/BlackJack.app/"
  echo "Lokale Extras eingebunden."
fi

(cd "$BUILD_DIR" && zip -qry BlackJack.ipa Payload)

echo "Fertig: $BUILD_DIR/BlackJack.ipa ($(du -h "$BUILD_DIR/BlackJack.ipa" | cut -f1))"
