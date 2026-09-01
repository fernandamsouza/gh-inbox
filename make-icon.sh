#!/usr/bin/env bash
# Cria uma copia do terminal-notifier com nome e icone proprios, para o banner
# aparecer como "gh-inbox" em vez de "terminal-notifier".
#
#   ./make-icon.sh                       usa assets/icon.svg, nome gh-inbox
#   ./make-icon.sh caminho/logo.png      usa a sua imagem
#   ./make-icon.sh logo.png MeuNome      nome customizado
#
# Nao precisa de Xcode: replica o target `make icon` do upstream, que so copia
# um app ja compilado e mexe no plist. Usa sips/iconutil/PlistBuddy/codesign,
# todos nativos do macOS, e qlmanage para rasterizar SVG.
#
# ATENCAO: trocar o CFBundleIdentifier cria um app NOVO para o macOS, entao a
# permissao de notificacao precisa ser concedida de novo (um clique).
set -euo pipefail

SRC=$(cd "$(dirname "$0")" && pwd)
IMG="${1:-$SRC/assets/icon.svg}"
NAME="${2:-gh-inbox}"
# Namespace proprio. O app e uma copia derivada do terminal-notifier, mas o
# bundle id nao deve viver no reverse-DNS do autor dele: identidade e dele, nao
# nossa. Configuravel para quem fizer fork.
BASE_ID="${GH_INBOX_BUNDLE_BASE:-io.github.fernandamsouza.gh-inbox}"

die() { printf 'make-icon: %s\n' "$*" >&2; exit 1; }

# NAME entra num `rm -rf`. Sem validar, `make-icon.sh logo.png ../../algo`
# apagaria fora de ~/Applications. Aceita so o que pode ser nome de app.
case "$NAME" in
  *[!A-Za-z0-9._-]*|""|.*) die "nome invalido: use so letras, numeros, ponto, hifen e underscore" ;;
esac
DEST="$HOME/Applications/$NAME.app"

[ -f "$IMG" ] || die "imagem nao encontrada: $IMG"

BASE=""
for p in "$HOME/Applications/terminal-notifier.app" \
         /opt/homebrew/opt/terminal-notifier/terminal-notifier.app \
         /usr/local/opt/terminal-notifier/terminal-notifier.app; do
  [ -d "$p" ] && { BASE="$p"; break; }
done
[ -n "$BASE" ] || die "terminal-notifier nao encontrado. brew install terminal-notifier"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# SVG e vetor: rasteriza pelo QuickLook antes de redimensionar
case "$IMG" in
  *.svg|*.SVG)
    qlmanage -t -s 1024 -o "$WORK" "$IMG" >/dev/null 2>&1 || die "nao consegui rasterizar o SVG"
    IMG="$WORK/$(basename "$IMG").png"
    [ -f "$IMG" ] || die "rasterizacao do SVG falhou"
    ;;
esac

echo "==> montando $DEST"
rm -rf "$DEST"
mkdir -p "$HOME/Applications"
cp -R "$BASE" "$DEST"

case "$IMG" in
  *.icns) cp "$IMG" "$DEST/Contents/Resources/icon.icns" ;;
  *)
    SET="$WORK/icon.iconset"; mkdir -p "$SET"
    for size in 16 32 128 256 512; do
      sips -z "$size" "$size" "$IMG" --out "$SET/icon_${size}x${size}.png" >/dev/null
      sips -z "$((size*2))" "$((size*2))" "$IMG" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil --convert icns "$SET" --output "$DEST/Contents/Resources/icon.icns"
    ;;
esac

rm -f "$DEST/Contents/Resources/Terminal.icns"
PB=/usr/libexec/PlistBuddy
"$PB" -c "Set :CFBundleIconFile icon"              "$DEST/Contents/Info.plist"
"$PB" -c "Set :CFBundleName $NAME"                 "$DEST/Contents/Info.plist"
# NAME ja e o sufixo natural quando bate com o default; evita gh-inbox.gh-inbox
if [ "$NAME" = "gh-inbox" ]; then BUNDLE_ID="$BASE_ID"; else BUNDLE_ID="$BASE_ID.$NAME"; fi
"$PB" -c "Set :CFBundleIdentifier $BUNDLE_ID"     "$DEST/Contents/Info.plist"
codesign --force --sign - "$DEST" 2>/dev/null || die "codesign falhou"

LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREG" ] && "$LSREG" -f "$DEST" 2>/dev/null || true

echo "==> $DEST"
echo "    bundle id: $BUNDLE_ID"
echo "    o banner vai aparecer como \"$NAME\", com o seu icone"
echo "    a permissao de notificacao e pedida de novo (bundle id novo): um clique"
