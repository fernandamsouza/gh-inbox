#!/usr/bin/env bash
# Remove o gh-inbox.
#   ./uninstall.sh            remove tudo, PRESERVA o estado (fila e historico de vistos)
#   ./uninstall.sh --purge    remove tambem o estado em ~/.claude/gh-inbox
#
# O notificador e compilado localmente e vive em ~/Applications: e removido
# aqui. Se voce tinha o terminal-notifier do brew como fallback:
# brew uninstall terminal-notifier
set -euo pipefail
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

PLIST="$HOME/Library/LaunchAgents/com.gh-inbox.poll.plist"
launchctl unload "$PLIST" 2>/dev/null || true
rm -f "$PLIST"
rm -f "$HOME/.claude/bin/gh-inbox" "$HOME/.claude/bin/gh-inbox-poll"
rm -rf "$HOME/.claude/skills/inbox"
rm -rf "$HOME/Applications/gh-inbox.app"                   # notificador proprio
rm -rf "$HOME/Applications/terminal-notifier.app"          # fallback, se existir
rm -rf "$HOME/.claude/gh-inbox/.lock"                       # lock orfao
echo "gh-inbox removido."

if [ "$PURGE" = "1" ]; then
  rm -rf "$HOME/.claude/gh-inbox"
  rm -f "$HOME/Library/Logs/gh-inbox-poll.log" "$HOME/Library/Logs/gh-inbox-poll.err.log"
  echo "estado e logs apagados."
else
  echo "estado preservado em ~/.claude/gh-inbox (reinstalar nao traz o backlog de volta)."
  echo "para apagar tambem: ./uninstall.sh --purge"
fi
