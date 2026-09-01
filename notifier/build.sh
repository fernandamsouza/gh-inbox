#!/usr/bin/env bash
# Compila o notificador e monta o app bundle com nome e icone proprios.
#
#   ./build.sh                        icone de ../assets/icon.svg, nome gh-inbox
#   ./build.sh caminho/logo.png       usa a sua imagem
#   ./build.sh logo.png OutroNome     nome customizado
#
# Sem dependencia externa: swiftc vem no Command Line Tools, e o bundle e
# montado com sips/iconutil/PlistBuddy/codesign, todos nativos do macOS.
# qlmanage rasteriza SVG.
#
# Universal (arm64 + x86_64) quando os dois targets estao disponiveis, para o
# mesmo build servir Apple Silicon e Intel.
set -euo pipefail

SRC=$(cd "$(dirname "$0")" && pwd)
IMG="${1:-$SRC/../assets/icon.svg}"
NAME="${2:-gh-inbox}"
BASE_ID="${GH_INBOX_BUNDLE_BASE:-io.github.fernandamsouza.gh-inbox}"

die() { printf 'build: %s\n' "$*" >&2; exit 1; }

# NAME entra num `rm -rf`: valida antes.
case "$NAME" in
  *[!A-Za-z0-9._-]*|""|.*) die "nome invalido: use so letras, numeros, ponto, hifen e underscore" ;;
esac
DEST="$HOME/Applications/$NAME.app"
[ -f "$IMG" ] || die "imagem nao encontrada: $IMG"
command -v swiftc >/dev/null || die "swiftc nao encontrado. Instale o Command Line Tools: xcode-select --install"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

echo "==> compilando"
BIN="$WORK/notifier"
ARM="$WORK/notifier-arm64"; INTEL="$WORK/notifier-x86_64"
ok_arm=0; ok_intel=0
swiftc -O -target arm64-apple-macosx10.14  -o "$ARM"   "$SRC/notifier.swift" 2>/dev/null && ok_arm=1
swiftc -O -target x86_64-apple-macosx10.14 -o "$INTEL" "$SRC/notifier.swift" 2>/dev/null && ok_intel=1
if [ "$ok_arm" = 1 ] && [ "$ok_intel" = 1 ]; then
  lipo -create -output "$BIN" "$ARM" "$INTEL"
  echo "    universal (arm64 + x86_64)"
elif [ "$ok_arm" = 1 ]; then cp "$ARM" "$BIN"; echo "    arm64 apenas"
elif [ "$ok_intel" = 1 ]; then cp "$INTEL" "$BIN"; echo "    x86_64 apenas"
else
  swiftc -O -o "$BIN" "$SRC/notifier.swift" || die "compilacao falhou"
  echo "    nativo do host"
fi

echo "==> montando $DEST"
rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"
install -m 755 "$BIN" "$DEST/Contents/MacOS/notifier"

case "$IMG" in
  *.svg|*.SVG)
    qlmanage -t -s 1024 -o "$WORK" "$IMG" >/dev/null 2>&1 || die "nao consegui rasterizar o SVG"
    IMG="$WORK/$(basename "$IMG").png"
    [ -f "$IMG" ] || die "rasterizacao do SVG falhou" ;;
esac
case "$IMG" in
  *.icns) cp "$IMG" "$DEST/Contents/Resources/icon.icns" ;;
  *)
    SET="$WORK/icon.iconset"; mkdir -p "$SET"
    for s in 16 32 128 256 512; do
      sips -z "$s" "$s" "$IMG" --out "$SET/icon_${s}x${s}.png" >/dev/null
      sips -z "$((s*2))" "$((s*2))" "$IMG" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil --convert icns "$SET" --output "$DEST/Contents/Resources/icon.icns" ;;
esac

if [ "$NAME" = "gh-inbox" ]; then BUNDLE_ID="$BASE_ID"; else BUNDLE_ID="$BASE_ID.$NAME"; fi
cat > "$DEST/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>notifier</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>10.14</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$DEST" 2>/dev/null || die "codesign falhou"

# Sem registrar no Launch Services, o macOS nao deixa o app pedir autorizacao
# de notificacao — e o pedido falha para sempre, sem nunca perguntar.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREG" ] && "$LSREG" -f "$DEST" 2>/dev/null || true

echo "==> $DEST"
echo "    bundle id: $BUNDLE_ID"
echo "    arquitetura: $(lipo -archs "$DEST/Contents/MacOS/notifier" 2>/dev/null || echo '?')"
