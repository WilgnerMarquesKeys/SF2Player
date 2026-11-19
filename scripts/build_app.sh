#!/bin/bash
# Compila o SF2Player com Swift Package Manager e monta SF2Player.app (sem Xcode project).
#
# Variáveis opcionais:
#   ARCHS="x86_64"            só Intel     (padrão: "x86_64 arm64" = Universal)
#   SANDBOX=0                 assina sem App Sandbox (padrão: 1 = com sandbox)
set -euo pipefail

APP_NAME="SF2Player"
ARCHS="${ARCHS:-x86_64 arm64}"
SANDBOX="${SANDBOX:-1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"

cd "$ROOT"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

ARCH_FLAGS=()
for arch in $ARCHS; do
  ARCH_FLAGS+=(--arch "$arch")
done

echo "==> Compilando ($ARCHS) — alvo mínimo macOS 10.15"
swift build -c release "${ARCH_FLAGS[@]}"

BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
if [ ! -f "$BIN" ]; then
  echo "ERRO: executável não encontrado em $BIN" >&2
  exit 1
fi

echo "==> Arquiteturas do binário:"
lipo -info "$BIN"
echo "==> Versão mínima do macOS no binário:"
otool -l "$BIN" | grep -A4 -E "LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX" | head -12 || true

echo "==> Montando $APP_NAME.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/Info.plist" "$APP_DIR/Contents/Info.plist"
printf "APPL????" > "$APP_DIR/Contents/PkgInfo"

echo "==> Assinando (ad-hoc, sem conta de desenvolvedor)"
if [ "$SANDBOX" = "1" ]; then
  codesign --force --deep --sign - --entitlements "$ROOT/SF2Player.entitlements" "$APP_DIR"
else
  codesign --force --deep --sign - "$APP_DIR"
fi
codesign --verify --verbose=2 "$APP_DIR"

echo "==> Pronto: $APP_DIR"
