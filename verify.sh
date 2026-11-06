#!/bin/sh
# Проверка, что Claude и ChatGPT работают строго через прокси. Ничего не меняет.
#   ./verify.sh               # все установленные
#   ./verify.sh chatgpt       # только выбранные: claude, chatgpt

PATH="$HOME/.local/bin:$PATH"
# Адрес прокси — тот, с которым поставлен обновлятор
for u in claude-proxy-update chatgpt-proxy-update; do
	[ -n "${PROXY:-}" ] || PROXY=$(sed -n 's/^PROXY="\${[A-Z_]*:-\(.*\)}"$/\1/p' "$HOME/.local/bin/$u" 2>/dev/null)
done
PROXY="${PROXY:-http://127.0.0.1:20809}"
PORT="${PROXY##*:}"; PORT="${PORT%%/*}"
ok() { printf '  OK    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; FAILED=1; }
FAILED=0

app_name() { case "$1" in claude) echo Claude;; chatgpt) echo ChatGPT;; esac; }
APPS="$*"
[ -n "$APPS" ] || for a in claude chatgpt; do [ -d "/Applications/$(app_name $a).app" ] && APPS="$APPS $a"; done

echo "Прокси"
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then ok "кто-то слушает порт $PORT"; else bad "порт $PORT никто не слушает"; fi

for a in $APPS; do
	n=$(app_name "$a"); u="$a-proxy-update"
	echo; echo "=== $n"

	echo "Главный процесс"
	M=$(ps -axo pid=,command= | awk -v p="/Applications/$n.app/Contents/MacOS/$n" '{c=$0; sub(/^ *[0-9]+ /,"",c)} c==p || index(c,p" ")==1 {print $1; exit}')
	if [ -z "$M" ]; then
		bad "$n не запущен"
	else
		cmd=$(ps -o command= -p "$M"); envs=$(ps -E -ww -o command= -p "$M" | tr ' ' '\n')
		echo "$cmd" | grep -q -- "--proxy-server=" && ok "флаг --proxy-server" || bad "нет --proxy-server — запущен не через лаунчер"
		echo "$envs" | grep -q '^NODE_USE_ENV_PROXY=1$' && ok "NODE_USE_ENV_PROXY=1" || bad "нет NODE_USE_ENV_PROXY=1 (Node-часть ходит напрямую)"
		echo "$envs" | grep -q '^HTTPS_PROXY=' && ok "HTTPS_PROXY в окружении" || bad "нет HTTPS_PROXY в окружении"
	fi

	echo "Прямые соединения процессов из бандла (10 секунд; UDP без адреса назначения не видно — их ловит Little Snitch)"
	direct=$(for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
		for pid in $(pgrep -f "/Applications/$n.app/"); do
			lsof -nP -a -p "$pid" -i 2>/dev/null | awk 'NR>1 && $9 ~ /->/ && $9 !~ /->(127\.0\.0\.1|\[::1\]):/ {print $1, $9}'
		done; sleep 0.5; done | sort -u)
	[ -z "$direct" ] && ok "ни одного соединения мимо loopback" || { bad "соединения мимо прокси:"; echo "$direct" | sed 's/^/        /'; }

	if [ "$a" = claude ]; then
		echo "Claude Code CLI"
		if grep -q '"HTTPS_PROXY"' "$HOME/.claude/settings.json" 2>/dev/null; then ok "HTTPS_PROXY в ~/.claude/settings.json"; else bad "нет env.HTTPS_PROXY в ~/.claude/settings.json"; fi
	fi

	echo "Обновления"
	if launchctl print "gui/$(id -u)/local.$u" >/dev/null 2>&1; then ok "LaunchAgent local.$u загружен"; else bad "LaunchAgent local.$u не загружен"; fi
	command -v "$u" >/dev/null && "$u" status | sed 's/^/        /' || bad "$u не найден в PATH"
done

echo; echo "Little Snitch (проверить вручную)"
echo "        Network Monitor → фильтр по приложению: заблокированные соединения на внешние адреса = пойманные утечки"

exit "$FAILED"
