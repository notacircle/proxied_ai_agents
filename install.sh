#!/bin/sh
# Установка claude-proxy-guard на этот Mac (без root).
# Правила Little Snitch ставятся отдельно и вручную — см. README, раздел «Little Snitch».
#
#   PROXY=http://127.0.0.1:20809 ./install.sh

set -eu

PROXY="${PROXY:-http://127.0.0.1:20809}"
REPO="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
LAUNCHER="/Applications/Claude (proxied).app"
AGENT="$HOME/Library/LaunchAgents/local.claude-proxy-update.plist"
SETTINGS="$HOME/.claude/settings.json"

step() { printf '\n==> %s\n' "$*"; }

[ -d /Applications/Claude.app ] || { echo "Нет /Applications/Claude.app — сначала установите Claude"; exit 1; }
case "$PROXY" in http://*|https://*) ;; *) echo "PROXY должен начинаться с http:// или https://"; exit 1;; esac

step "Проверяю прокси $PROXY"
if curl -sS -x "$PROXY" -m 15 -o /dev/null https://api.anthropic.com/; then echo "прокси отвечает"
else echo "ВНИМАНИЕ: прокси не отвечает — установка продолжится, но Claude не будет работать, пока прокси не поднимется"; fi

step "Скрипты в $BIN"
mkdir -p "$BIN"
install -m 755 "$REPO/bin/claude-proxy-update" "$REPO/bin/nopx" "$BIN/"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "ВНИМАНИЕ: $BIN нет в PATH — добавьте его, чтобы работал nopx";; esac
sed -i '' "s#^PROXY=.*#PROXY=\"\${CLAUDE_UPDATE_PROXY:-$PROXY}\"#" "$BIN/claude-proxy-update"

step "Лаунчер $LAUNCHER"
TMP=$(mktemp -d)
sed "s#^property httpProxyURL : .*#property httpProxyURL : \"$PROXY\"#" "$REPO/launcher/launch-claude-proxy.applescript" > "$TMP/launch.applescript"
osacompile -o "$TMP/Claude (proxied).app" "$TMP/launch.applescript"
codesign --force --sign - "$TMP/Claude (proxied).app" 2>/dev/null
if [ -d "$LAUNCHER" ]; then mv "$LAUNCHER" "$TMP/old-launcher.app"; fi
mv "$TMP/Claude (proxied).app" "$LAUNCHER"
echo "собран; иконка Claude подтянется при первом запуске"

step "Прокси для Claude Code CLI в $SETTINGS"
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d%H%M%S)"
/usr/bin/python3 -I - "$SETTINGS" "$PROXY" <<'EOF'
import json, os, sys
path, proxy = sys.argv[1], sys.argv[2]
d = json.load(open(path)) if os.path.exists(path) else {}
d.setdefault("env", {}).update({"HTTPS_PROXY": proxy, "HTTP_PROXY": proxy, "NO_PROXY": "localhost,127.0.0.1,::1"})
json.dump(d, open(path, "w"), ensure_ascii=False, indent=2)
print("env обновлён, остальные настройки не тронуты")
EOF

step "LaunchAgent обновлений через прокси"
mkdir -p "$(dirname "$AGENT")" "$HOME/Library/Logs"
sed "s#__HOME__#$HOME#g" "$REPO/launchd/local.claude-proxy-update.plist.template" > "$AGENT"
plutil -lint "$AGENT" >/dev/null
launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT"
echo "загружен; лог: ~/Library/Logs/claude-proxy-update.log"

rm -rf "$TMP"

cat <<EOF

Готово. Дальше:
  1. Little Snitch — вручную, см. README («Little Snitch»): export-model, merge-rules.py, restore-model.
  2. Закройте Claude и запускайте его ТОЛЬКО через «Claude (proxied)».
  3. Проверка: $REPO/verify.sh
EOF
