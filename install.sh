#!/usr/bin/env bash
# Instalador do gh-inbox. Idempotente: rodar de novo nao destroi estado.
#
#   ./install.sh                    poller + banners clicaveis com historico
#   ./install.sh --no-notifier      so banner de aviso, sem instalar nada
#   ./install.sh --no-icon          nao personaliza o icone do banner
#   ./install.sh --org minhaorg     triagem restrita a outra org do GitHub
set -euo pipefail

ORG=""          # sem default: detectado ou exigido, ver abaixo
WANT_TN=1        # banners clicaveis + historico na Central: default
WANT_ICON=1      # banner com nome e icone proprios: default
while [ $# -gt 0 ]; do
  case "$1" in
    --with-notifier) WANT_TN=1 ;;
    --no-notifier)   WANT_TN=0 ;;
    --no-icon)       WANT_ICON=0 ;;
    --org) shift; ORG="${1:?--org precisa de um valor}" ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "opcao desconhecida: $1" >&2; exit 2 ;;
  esac
  shift
done

SRC=$(cd "$(dirname "$0")" && pwd)
BIN_DIR="$HOME/.claude/bin"
SKILL_DIR="$HOME/.claude/skills/inbox"
STATE_DIR="$HOME/.claude/gh-inbox"
PLIST="$HOME/Library/LaunchAgents/com.gh-inbox.poll.plist"
LABEL="com.gh-inbox.poll"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

ok()   { printf '  \033[32mok\033[0m   %s\n' "$*"; }
info() { printf '  ..   %s\n' "$*"; }
die()  { printf '\n  \033[31merro\033[0m %s\n' "$*" >&2; exit 1; }

echo
echo "gh-inbox — triagem de PR do GitHub com notificacao em tempo real"
echo

# ---- pre-requisitos -------------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "isto depende de launchd e osascript: macOS only"
command -v gh >/dev/null || die "gh nao encontrado. brew install gh"
command -v jq >/dev/null || die "jq nao encontrado. brew install jq"
gh auth status >/dev/null 2>&1 || die "gh nao esta autenticado. rode: gh auth login"
LOGIN=$(gh api user -q .login) || die "nao consegui ler seu login do GitHub"
ok "gh autenticado como $LOGIN"

# A org nao tem default: cravar uma faria a ferramenta parecer quebrada para
# quem nao e dela (as buscas voltariam vazias sem erro). Detecta quando e
# inequivoco; exige --org quando nao e.
if [ -z "$ORG" ]; then
  ORGS=$(gh api user/orgs -q '.[].login' 2>/dev/null || true)
  N=$(printf '%s\n' "$ORGS" | grep -c . || true)
  if [ "$N" = "1" ]; then
    ORG=$(printf '%s' "$ORGS")
    ok "org detectada: $ORG"
  else
    printf '\n  \033[31merro\033[0m preciso saber a org do GitHub a triar.\n\n' >&2
    if [ "$N" = "0" ]; then
      printf '    Sua conta nao aparece em nenhuma org. Use: ./install.sh --org NOME\n\n' >&2
    else
      printf '    Voce esta em %s orgs, entao nao da para adivinhar:\n' "$N" >&2
      printf '%s\n' "$ORGS" | sed 's/^/      /' >&2
      printf '\n    Rode: ./install.sh --org NOME\n\n' >&2
    fi
    exit 1
  fi
fi
mkdir -p "$STATE_DIR"
printf '%s' "$LOGIN" > "$STATE_DIR/login"   # primeiro run ja com a identidade certa
gh api "/notifications?per_page=1" >/dev/null 2>&1 \
  || die "seu token nao le /notifications. rode: gh auth refresh -s notifications"
ok "acesso a /notifications confirmado"

# ---- banner clicavel ------------------------------------------------------
# Exige UMA concessao de permissao por pessoa: o macOS pede consentimento do
# usuario para qualquer app postar notificacao, e isso nao e pre-concedivel.
# Sem a permissao o poller cai no osascript, que notifica mas nao clica.
if [ "$WANT_TN" = "1" ]; then
  if command -v brew >/dev/null && ! [ -d /opt/homebrew/opt/terminal-notifier ] \
     && ! [ -d /usr/local/opt/terminal-notifier ]; then
    info "instalando terminal-notifier"
    brew install terminal-notifier >/dev/null 2>&1 || info "falhou; o osascript cobre"
  fi
  # O Launch Services NAO indexa /opt/homebrew/Cellar, e o macOS nao deixa um
  # app desconhecido pedir autorizacao de notificacao. Sem copiar para
  # ~/Applications e registrar, o terminal-notifier retorna exit 3 para sempre
  # e o `tccutil reset` que a mensagem de erro sugere falha por nao achar
  # registro nenhum.
  for TNAPP in /opt/homebrew/opt/terminal-notifier/terminal-notifier.app \
               /usr/local/opt/terminal-notifier/terminal-notifier.app; do
    if [ -d "$TNAPP" ]; then
      mkdir -p "$HOME/Applications"
      rm -rf "$HOME/Applications/terminal-notifier.app"
      cp -R "$TNAPP" "$HOME/Applications/" 2>/dev/null || true
      [ -x "$LSREG" ] && "$LSREG" -f "$HOME/Applications/terminal-notifier.app" 2>/dev/null || true
      ok "terminal-notifier registrado em ~/Applications"
      break
    fi
  done

  # Copia com nome e icone proprios: o banner aparece como "gh-inbox" em vez de
  # "terminal-notifier". A 3.0.0 removeu a flag -appIcon porque o icone sempre
  # vem do bundle que envia, entao a unica via e um bundle proprio.
  if [ "$WANT_ICON" = "1" ] && [ -f "$SRC/assets/icon.svg" ] && [ -x "$SRC/make-icon.sh" ]; then
    if "$SRC/make-icon.sh" >/dev/null 2>&1; then
      ok "banner personalizado (~/Applications/gh-inbox.app)"
      NOTIFIER_BUNDLE="io.github.fernandamsouza.gh-inbox"
    else
      info "nao consegui personalizar o icone; segue com o padrao"
    fi
  fi
fi
NOTIFIER_BUNDLE="${NOTIFIER_BUNDLE:-fr.julienxx.oss.terminal-notifier}"

# ---- arquivos -------------------------------------------------------------
mkdir -p "$BIN_DIR" "$SKILL_DIR" "$STATE_DIR" "$HOME/Library/LaunchAgents"
# Estado guarda titulos de PR internos e o login: nao deve ser legivel por
# outros usuarios da maquina.
chmod 700 "$STATE_DIR" 2>/dev/null || true
printf '%s' "$ORG" > "$STATE_DIR/org"   # para uso manual sem exportar variavel
chmod 600 "$STATE_DIR"/* 2>/dev/null || true
install -m 755 "$SRC/bin/gh-inbox" "$BIN_DIR/gh-inbox"
install -m 755 "$SRC/bin/gh-inbox-poll" "$BIN_DIR/gh-inbox-poll"
install -m 644 "$SRC/skills/inbox/SKILL.md" "$SKILL_DIR/SKILL.md"
ok "scripts em $BIN_DIR, skill /inbox em $SKILL_DIR"

# ---- LaunchAgent ----------------------------------------------------------
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key>
    <array><string>$BIN_DIR/gh-inbox-poll</string></array>
    <key>StartInterval</key><integer>60</integer>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>$HOME/Library/Logs/gh-inbox-poll.err.log</string>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/gh-inbox-poll.err.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>GH_INBOX_ORG</key><string>$ORG</string>
    </dict>
</dict>
</plist>
PLIST_EOF
plutil -lint "$PLIST" >/dev/null || die "plist gerado invalido"
launchctl unload "$PLIST" >/dev/null 2>&1 || true
launchctl load "$PLIST"
ok "LaunchAgent carregado (poll de 60s, org: $ORG)"

# ---- baseline -------------------------------------------------------------
if [ -s "$STATE_DIR/seen.json" ] && [ "$(jq 'length' "$STATE_DIR/seen.json")" -gt 0 ]; then
  ok "estado preservado ($(jq 'length' "$STATE_DIR/seen.json") itens ja vistos)"
else
  info "marcando o backlog atual como visto (so o que for novo te avisa)"
  GH_INBOX_ORG="$ORG" "$BIN_DIR/gh-inbox" seed >/dev/null
  GH_INBOX_ORG="$ORG" GH_INBOX_SEED=1 "$BIN_DIR/gh-inbox-poll" >/dev/null 2>&1 || true
  ok "baseline pronto"
fi

N=$(jq '[.items[]] | length' "$STATE_DIR/queue.json" 2>/dev/null || echo "?")
echo
echo "  pronto. $N PRs na sua fila."
echo
echo "  no Claude Code:   /inbox      ve a fila e dispara o review"
echo "  no terminal:      gh-inbox list"
echo
if [ "$WANT_TN" = "1" ]; then
  # Dispara uma notificacao agora, de proposito: numa maquina nova isto faz o
  # macOS abrir o prompt de permissao NA HORA, com a pessoa ainda no terminal.
  # Sem isto o prompt so apareceria no primeiro evento real do GitHub, horas
  # depois e fora de contexto — ou, se o estado ja estiver negado, nunca.
  TNBIN="$HOME/Applications/gh-inbox.app/Contents/MacOS/terminal-notifier"
  [ -x "$TNBIN" ] || TNBIN="$HOME/Applications/terminal-notifier.app/Contents/MacOS/terminal-notifier"
  if [ -x "$TNBIN" ]; then
    echo "  Vai aparecer um pedido de permissao de notificacao. Clique em Permitir."
    echo
    if "$TNBIN" -title "gh-inbox" -subtitle "instalacao concluida" \
         -message "clique aqui para ver sua fila de PRs" \
         -open "https://github.com/pulls/review-requested" \
         -group "ghinbox-instalacao" >/dev/null 2>&1; then
      ok "notificacao de teste entregue — o banner clicavel esta funcionando"
    else
      echo "  A notificacao nao passou. Se voce nao viu prompt nenhum, o macOS ja"
      echo "  tem um \"nao\" gravado para este app. Para ele poder perguntar de novo:"
      echo
      echo "    tccutil reset UserNotification $NOTIFIER_BUNDLE"
      echo
      echo "  ou libere em Ajustes do Sistema > Notificacoes > gh-inbox."
      echo "  Sem isso o banner ainda aparece (via osascript), mas nao e clicavel."
      echo
    fi
  fi
  echo "  Opcional: em Ajustes do Sistema > Notificacoes > gh-inbox,"
  echo "  troque o estilo para \"Alertas\" — o aviso passa a ficar na tela ate"
  echo "  voce dispensar, em vez de sumir sozinho."
  echo
  echo "  O historico fica na Central de Notificacoes (clique no relogio),"
  echo "  uma entrada por PR. Pelo terminal: terminal-notifier -list ALL"
  echo
fi
