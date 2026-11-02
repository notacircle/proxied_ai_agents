#!/bin/sh
# Проверка, что Claude работает строго через прокси. Ничего не меняет.

PROXY="${PROXY:-http://127.0.0.1:20809}"
PORT="${PROXY##*:}"; PORT="${PORT%%/*}"
ok() { printf '  OK    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; FAILED=1; }
FAILED=0

echo "Прокси"
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then ok "кто-то слушает порт $PORT"; else bad "порт $PORT никто не слушает"; fi

echo "Главный процесс Claude"
M=$(ps -axo pid=,command= | awk '/\/Applications\/Claude.app\/Contents\/MacOS\/Claude( |$)/ && !/awk/ {print $1; exit}')
if [ -z "$M" ]; then
	bad "Claude не запущен"
else
	cmd=$(ps -o command= -p "$M"); envs=$(ps -E -ww -o command= -p "$M" | tr ' ' '\n')
	echo "$cmd" | grep -q -- "--proxy-server=" && ok "флаг --proxy-server" || bad "нет --proxy-server — запущен не через лаунчер"
	echo "$envs" | grep -q '^NODE_USE_ENV_PROXY=1$' && ok "NODE_USE_ENV_PROXY=1" || bad "нет NODE_USE_ENV_PROXY=1 (Node-часть ходит напрямую)"
	echo "$envs" | grep -q '^HTTPS_PROXY=' && ok "HTTPS_PROXY в окружении" || bad "нет HTTPS_PROXY в окружении"
fi

echo "Прямые соединения процессов Claude (10 секунд)"
direct=$(for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
	for pid in $(pgrep -f '/Applications/Claude.app/'); do
		lsof -nP -a -p "$pid" -i 2>/dev/null | awk 'NR>1 && $9 !~ /^(127\.0\.0\.1|\[::1\]|\*)/ {print $1, $9}'
	done; sleep 0.5; done | sort -u)
[ -z "$direct" ] && ok "ни одного соединения мимо loopback" || { bad "соединения мимо прокси:"; echo "$direct" | sed 's/^/        /'; }

echo "Claude Code CLI"
if grep -q '"HTTPS_PROXY"' "$HOME/.claude/settings.json" 2>/dev/null; then ok "HTTPS_PROXY в ~/.claude/settings.json"; else bad "нет env.HTTPS_PROXY в ~/.claude/settings.json"; fi

echo "Обновления"
if launchctl print "gui/$(id -u)/local.claude-proxy-update" >/dev/null 2>&1; then ok "LaunchAgent local.claude-proxy-update загружен"; else bad "LaunchAgent не загружен"; fi
command -v claude-proxy-update >/dev/null && claude-proxy-update status | sed 's/^/        /' || bad "claude-proxy-update не найден в PATH"

echo "Little Snitch (проверить вручную)"
echo "        Network Monitor → фильтр Claude: заблокированные соединения на внешние адреса = пойманные утечки"

exit "$FAILED"
