#!/bin/sh
# Установка proxy-guard на этот Mac (без root).
# Правила Little Snitch ставятся отдельно и вручную — см. README, раздел «Little Snitch».
#
#   PROXY=http://127.0.0.1:20809 ./install.sh            # все поддерживаемые приложения из /Applications
#   PROXY=http://127.0.0.1:20809 ./install.sh chatgpt    # только выбранные: claude, chatgpt

set -eu

PROXY="${PROXY:-http://127.0.0.1:20809}"
REPO="$(cd "$(dirname "$0")" && pwd)"
BIN="$HOME/.local/bin"
SETTINGS="$HOME/.claude/settings.json"

step() { printf '\n==> %s\n' "$*"; }

# ключ -> имя в /Applications, обновлятор
app_name() { case "$1" in claude) echo Claude;; chatgpt) echo ChatGPT;; *) return 1;; esac; }
updater() { echo "$1-proxy-update"; }

APPS="$*"
[ -n "$APPS" ] || for a in claude chatgpt; do [ -d "/Applications/$(app_name $a).app" ] && APPS="$APPS $a"; done
[ -n "$APPS" ] || { echo "Нет ни Claude.app, ни ChatGPT.app в /Applications"; exit 1; }
for a in $APPS; do
	n=$(app_name "$a") || { echo "Неизвестное приложение: $a (есть claude, chatgpt)"; exit 1; }
	[ -d "/Applications/$n.app" ] || { echo "Нет /Applications/$n.app — сначала установите его"; exit 1; }
done
case "$PROXY" in http://*|https://*) ;; *) echo "PROXY должен начинаться с http:// или https://"; exit 1;; esac

step "Проверяю прокси $PROXY"
if curl -sS -x "$PROXY" -m 15 -o /dev/null https://api.anthropic.com/; then echo "прокси отвечает"
else echo "ВНИМАНИЕ: прокси не отвечает — установка продолжится, но приложения не будут работать, пока прокси не поднимется"; fi

step "nopx в $BIN"
mkdir -p "$BIN" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
install -m 755 "$REPO/bin/nopx" "$BIN/"
case ":$PATH:" in *":$BIN:"*) ;; *) echo "ВНИМАНИЕ: $BIN нет в PATH — добавьте его, чтобы работал nopx";; esac

TMP=$(mktemp -d)
for a in $APPS; do
	n=$(app_name "$a"); u=$(updater "$a")
	LAUNCHER="/Applications/$n (proxied).app"
	AGENT="$HOME/Library/LaunchAgents/local.$u.plist"

	step "$n: обновлятор $BIN/$u"
	install -m 755 "$REPO/bin/$u" "$BIN/"
	sed -i '' "s#^PROXY=\"\${\([A-Z_]*\):-.*}\"#PROXY=\"\${\1:-$PROXY}\"#" "$BIN/$u"

	step "$n: лаунчер $LAUNCHER"
	sed -e "s#^property httpProxyURL : .*#property httpProxyURL : \"$PROXY\"#" \
		-e "s#^property appName : .*#property appName : \"$n\"#" \
		-e "s#^property updaterName : .*#property updaterName : \"$u\"#" \
		"$REPO/launcher/launch-proxied.applescript" > "$TMP/$a.applescript"
	osacompile -o "$TMP/$n (proxied).app" "$TMP/$a.applescript"
	# иконка — та, на которую указывает CFBundleIconFile оригинала (у ChatGPT рядом лежит ещё иконка Codex)
	icon=$(defaults read "/Applications/$n.app/Contents/Info" CFBundleIconFile 2>/dev/null || true)
	[ -n "$icon" ] && cp "/Applications/$n.app/Contents/Resources/${icon%.icns}.icns" "$TMP/$n (proxied).app/Contents/Resources/applet.icns" \
		|| echo "ВНИМАНИЕ: иконку $n не нашёл, останется стандартная"
	codesign --force --sign - "$TMP/$n (proxied).app" 2>/dev/null
	if [ -d "$LAUNCHER" ]; then mv "$LAUNCHER" "$TMP/old-$a.app"; fi
	mv "$TMP/$n (proxied).app" "$LAUNCHER"
	echo "собран, иконка взята из $n.app"

	step "$n: LaunchAgent обновлений через прокси"
	sed -e "s#__HOME__#$HOME#g" -e "s#__UPDATER__#$u#g" "$REPO/launchd/proxy-update.plist.template" > "$AGENT"
	plutil -lint "$AGENT" >/dev/null
	launchctl bootout "gui/$(id -u)" "$AGENT" 2>/dev/null || true
	launchctl bootstrap "gui/$(id -u)" "$AGENT"
	echo "загружен; лог: ~/Library/Logs/$u.log"

	if [ "$a" = claude ]; then
		step "Claude: прокси для Claude Code CLI в $SETTINGS"
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
	fi
done
rm -rf "$TMP"

cat <<EOF

Готово ($APPS). Дальше:
  1. Little Snitch — вручную, см. README («Little Snitch»): export-model, merge-rules.py, restore-model.
  2. Закройте приложения и запускайте их ТОЛЬКО через «… (proxied)».
  3. Проверка: $REPO/verify.sh
EOF
