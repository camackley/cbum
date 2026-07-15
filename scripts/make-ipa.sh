#!/usr/bin/env bash
# make-ipa.sh — compila CBUM (Release, iOS device) y produce build/CBUM.ipa para AltStore.
# Uso:  ./scripts/make-ipa.sh            (firmado con tu Personal Team, sesión de Xcode)
#       ./scripts/make-ipa.sh --unsigned (sin firma; AltStore re-firma al instalar)
set -euo pipefail
cd "$(dirname "$0")/.."

PROJ="ios/CBUM.xcodeproj"
SCHEME="CBUM"
DERIVED="build/derived"
OUT="build/CBUM.ipa"

SIGN_ARGS=(-allowProvisioningUpdates)
if [[ "${1:-}" == "--unsigned" ]]; then
  SIGN_ARGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
fi

echo "▸ Compilando ${SCHEME} (Release, iphoneos)…"
xcodebuild -project "$PROJ" -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED" \
  "${SIGN_ARGS[@]}" \
  build

APP="$DERIVED/Build/Products/Release-iphoneos/CBUM.app"
[[ -d "$APP" ]] || { echo "✗ No se encontró $APP"; exit 1; }

echo "▸ Empaquetando .ipa…"
rm -rf build/Payload "$OUT"
mkdir -p build/Payload
cp -R "$APP" build/Payload/
(cd build && zip -qry CBUM.ipa Payload)
rm -rf build/Payload

echo "✓ $OUT listo — AirDrop al iPhone y ábrelo con AltStore (My Apps → +)"
