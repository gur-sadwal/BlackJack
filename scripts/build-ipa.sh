#!/usr/bin/env bash
# Lokale IPA mit optionalen Extras; --public lässt Private/ vollständig weg.
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
case "${1:-}" in
  ""|--public) ;;
  *) echo "Aufruf: $0 [--public]" >&2; exit 2 ;;
esac

mkdir -p build
BUILD_DIR="$(pwd)/build"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/blackjack-build.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

if xcodebuild \
  -project BlackJack.xcodeproj \
  -scheme BlackJack \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$SCRATCH/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build > "$BUILD_DIR/build.log" 2>&1; then
  echo "BUILD SUCCEEDED"
else
  build_status=$?
  cat "$BUILD_DIR/build.log" >&2
  exit "$build_status"
fi

APP="$SCRATCH/DerivedData/Build/Products/Release-iphoneos/BlackJack.app"
[ -x "$APP/BlackJack" ] || { echo "Ausführbare App fehlt." >&2; exit 1; }
mkdir -p "$SCRATCH/Payload"
cp -R "$APP" "$SCRATCH/Payload/"
if [ "${1:-}" != "--public" ] && [ -f Private/AfterDark.json ]; then
  cp Private/AfterDark.json "$SCRATCH/Payload/BlackJack.app/"
  echo "Lokale Extras eingebunden."
fi
(cd "$SCRATCH" && zip -qry "$SCRATCH/BlackJack.ipa" Payload)
mv "$SCRATCH/BlackJack.ipa" "$BUILD_DIR/BlackJack.ipa"
echo "Fertig: build/BlackJack.ipa ($(du -h "$BUILD_DIR/BlackJack.ipa" | cut -f1))"
