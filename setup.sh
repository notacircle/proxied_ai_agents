#!/bin/sh
# proxied_ai_agents — Claude и ChatGPT на macOS строго через прокси.
#
#   ./setup.sh                                  пошаговая установка с вопросами
#   ./setup.sh install --proxy URL [опции]      установка без вопросов (нужно --yes для правил)
#   ./setup.sh little-snitch [опции]            поставить или обновить kill-switch
#   ./setup.sh verify [опции]                   проверить, что всё работает
#   ./setup.sh uninstall [опции]                удалить всё
#
# Опции:
#   --proxy URL            HTTP-прокси, например http://127.0.0.1:20809
#   --apps claude,chatgpt  какие приложения (по умолчанию все найденные)
#   --little-snitch        ставить kill-switch в Little Snitch (нужен sudo)
#   --no-little-snitch     не трогать Little Snitch
#   --yes                  не спрашивать подтверждений

set -eu

REPO="$(cd "$(dirname "$0")" && pwd)"
APPS_DIR="${APPS_DIR:-/Applications}"
LITTLESNITCH="${LITTLESNITCH:-/Applications/Little Snitch.app/Contents/Components/littlesnitch}"
SUDO="${SUDO:-sudo}"
LAUNCHCTL="${LAUNCHCTL:-launchctl}"
BIN="$HOME/.local/bin"
STATE="$HOME/Library/Application Support/proxied_ai_agents"
SETTINGS="$HOME/.claude/settings.json"
DEFAULT_PROXY="http://127.0.0.1:20809"

CMD=install INTERACTIVE=0
PROXY="${PROXY:-}" APPS="" WITH_LS="" YES=0

step() { printf '\n==> %s\n' "$*"; }
warn() { printf 'ВНИМАНИЕ: %s\n' "$*"; }
die() { printf 'ОШИБКА: %s\n' "$*" >&2; exit 1; }

app_name() { case "$1" in claude) echo Claude;; chatgpt) echo ChatGPT;; *) return 1;; esac; }
app_host() { case "$1" in claude) echo api.anthropic.com;; chatgpt) echo chatgpt.com;; esac; }
updater() { echo "$1-proxy-update"; }

confirm() {
	[ "$YES" = 1 ] && return 0
	[ -t 0 ] || die "нужно подтверждение: запустите в терминале или добавьте --yes"
	printf '%s [y/N] ' "$1"
	read -r answer || answer=""
	case "$answer" in y|Y|yes|д|Д|да) return 0;; *) return 1;; esac
}

need_python() {
	xcode-select -p >/dev/null 2>&1 || die "нужны Command Line Tools: выполните xcode-select --install и запустите снова"
}

check_proxy() {
	case "$1" in http://*|https://*) ;; *) die "прокси должен начинаться с http:// или https:// (SOCKS не поддерживается)";; esac
	# Значение попадает в sed и AppleScript. Логин в адресе флаг --proxy-server всё равно не понимает
	case "$1" in *[!]A-Za-z0-9.:/_[-]*) die "недопустимые символы в адресе прокси (логин и пароль в адресе не поддерживаются): $1";; esac
}

# Заполняет APPS: заданные через --apps или все найденные в /Applications
resolve_apps() {
	if [ -n "$APPS" ]; then
		APPS=$(printf '%s' "$APPS" | tr ',' ' ')
	else
		for a in claude chatgpt; do
			[ -d "$APPS_DIR/$(app_name "$a").app" ] && APPS="$APPS $a"
		done
	fi
	[ -n "$APPS" ] || die "нет ни Claude.app, ни ChatGPT.app в $APPS_DIR"
	for a in $APPS; do
		n=$(app_name "$a") || die "неизвестное приложение: $a (есть claude, chatgpt)"
		[ -d "$APPS_DIR/$n.app" ] || [ "$CMD" = uninstall ] || die "нет $APPS_DIR/$n.app — сначала установите его"
	done
}

# PID главного процесса приложения, если запущено
main_pid() {
	ps -axo pid=,command= | awk -v p="$APPS_DIR/$1.app/Contents/MacOS/$1" \
		'{c=$0; sub(/^ *[0-9]+ /,"",c)} c==p || index(c,p" ")==1 {print $1; exit}'
}

install_app() {
	a=$1; n=$(app_name "$a"); u=$(updater "$a")
	launcher="$APPS_DIR/$n (proxied).app"
	agent="$HOME/Library/LaunchAgents/local.$u.plist"

	step "$n: обновлятор $BIN/$u"
	install -m 755 "$REPO/bin/$u" "$BIN/"
	sed -i '' "s#^PROXY=\"\${\([A-Z_]*\):-.*}\"#PROXY=\"\${\1:-$PROXY}\"#" "$BIN/$u"

	step "$n: лаунчер $launcher"
	sed -e "s#^property httpProxyURL : .*#property httpProxyURL : \"$PROXY\"#" \
		-e "s#^property appName : .*#property appName : \"$n\"#" \
		-e "s#^property updaterName : .*#property updaterName : \"$u\"#" \
		"$REPO/launcher/launch-proxied.applescript" > "$TMP/$a.applescript"
	osacompile -o "$TMP/$n (proxied).app" "$TMP/$a.applescript"
	# иконка — та, на которую указывает CFBundleIconFile оригинала (у ChatGPT рядом лежит ещё иконка Codex)
	icon=$(defaults read "$APPS_DIR/$n.app/Contents/Info" CFBundleIconFile 2>/dev/null || true)
	if [ -n "$icon" ] && [ -f "$APPS_DIR/$n.app/Contents/Resources/${icon%.icns}.icns" ]; then
		cp "$APPS_DIR/$n.app/Contents/Resources/${icon%.icns}.icns" "$TMP/$n (proxied).app/Contents/Resources/applet.icns"
	else
		warn "иконку $n не нашёл, останется стандартная"
	fi
	codesign --force --sign - "$TMP/$n (proxied).app" 2>/dev/null
	if [ -d "$launcher" ]; then mv "$launcher" "$TMP/old-$a.app"; fi
	mv "$TMP/$n (proxied).app" "$launcher"
	echo "собран, иконка взята из $n.app"

	step "$n: LaunchAgent обновлений через прокси"
	sed -e "s#__HOME__#$HOME#g" -e "s#__UPDATER__#$u#g" "$REPO/launchd/proxy-update.plist.template" > "$agent"
	plutil -lint "$agent" >/dev/null
	$LAUNCHCTL bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
	$LAUNCHCTL bootstrap "gui/$(id -u)" "$agent"
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
}

cmd_install() {
	need_python
	if [ -z "$PROXY" ]; then
		[ "$INTERACTIVE" = 1 ] || die "укажите --proxy URL"
		printf 'Адрес HTTP-прокси [%s]: ' "$DEFAULT_PROXY"
		read -r PROXY || PROXY=""
		PROXY="${PROXY:-$DEFAULT_PROXY}"
	fi
	check_proxy "$PROXY"
	resolve_apps

	if [ -z "$WITH_LS" ]; then
		if [ ! -x "$LITTLESNITCH" ]; then
			WITH_LS=0
		elif [ "$INTERACTIVE" = 1 ]; then
			echo "Little Snitch найден. Kill-switch запретит приложениям выходить в сеть мимо прокси (нужен sudo)."
			if confirm "Поставить kill-switch?"; then WITH_LS=1; else WITH_LS=0; fi
		else
			WITH_LS=0
		fi
	fi
	[ "$WITH_LS" = 0 ] || [ -x "$LITTLESNITCH" ] || die "Little Snitch не найден: $LITTLESNITCH (установите его или запустите с --no-little-snitch)"

	step "Проверяю прокси $PROXY"
	set -- $APPS
	if curl -sS -x "$PROXY" -m 15 -o /dev/null "https://$(app_host "$1")/" 2>/dev/null; then echo "прокси отвечает"
	else warn "прокси не отвечает — установка продолжится, но приложения не будут работать, пока он не поднимется"; fi

	step "nopx в $BIN"
	mkdir -p "$BIN" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
	install -m 755 "$REPO/bin/nopx" "$BIN/"
	case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN нет в PATH — добавьте его, чтобы команда nopx запускалась по имени";; esac

	TMP=$(mktemp -d)
	trap 'rm -rf "$TMP"' EXIT
	for a in $APPS; do install_app "$a"; done

	[ "$WITH_LS" = 0 ] || cmd_little_snitch

	printf '\nГотово:%s\n' "$APPS"
	echo "  1. Закройте приложения и запускайте их только через «… (proxied)» в $APPS_DIR."
	echo "     Обычные значки уберите из Dock. Запуск через лаунчер закрывает приложение и обрывает его задачи."
	echo "  2. Проверка: $REPO/setup.sh verify"
	if [ "$WITH_LS" = 0 ]; then
		echo
		warn "kill-switch не установлен. Приложения работают через прокси, но ничто не запрещает им выйти напрямую:"
		echo "  встроенный обновлятор ходит мимо прокси и после обновления перезапускает приложение уже без него."
		echo "  Поставить позже: $REPO/setup.sh little-snitch"
	fi
}

# Выгружает модель в $backup и собирает $merged. Аргумент --remove только убирает правила
ls_export_and_merge() {
	mkdir -p "$STATE"
	ts=$(date +%Y%m%d%H%M%S)
	backup="$STATE/ls-backup-$ts.json" merged="$STATE/ls-merged-$ts.json"
	old_umask=$(umask); umask 077
	if ! $SUDO "$LITTLESNITCH" export-model > "$backup"; then
		rm -f "$backup"
		die "не удалось выгрузить правила. Включите в Little Snitch: Settings → Security → доступ из командной строки"
	fi
	/usr/bin/python3 -I "$REPO/littlesnitch/merge-rules.py" "$@" "$backup" $RULE_FILES "$merged"
	umask "$old_umask"
}

cmd_little_snitch() {
	need_python
	[ -x "$LITTLESNITCH" ] || die "Little Snitch не найден: $LITTLESNITCH"

	RULE_FILES=""
	for a in $APPS; do
		n=$(app_name "$a")
		RULE_FILES="$RULE_FILES $REPO/littlesnitch/$a-killswitch.lsrules"
		pid=$(main_pid "$n")
		if [ -n "$pid" ] && ! ps -ww -o command= -p "$pid" | grep -q -- "--proxy-server="; then
			warn "$n запущен без прокси: с kill-switch он потеряет сеть, пока вы не откроете его через «$n (proxied)»."
		fi
	done

	step "Выгружаю правила Little Snitch (нужен пароль sudo)"
	ls_export_and_merge

	step "Какие правила будут добавлены"
	/usr/bin/python3 -I -c '
import json, sys
for path in sys.argv[1:]:
    for r in json.load(open(path))["rules"]:
        via = " via " + r["via"].split("/")[-1] if "via" in r else ""
        target = r.get("remote-addresses") or r.get("remote", "")
        print("  %-5s %s%s -> %s" % (r["action"], r["process"].split("/", 1)[1], via, target))
' $RULE_FILES

	if ! confirm "restore-model заменит всю модель правил этим файлом. Применить?"; then
		echo "Не применено. Выгрузка: $backup"
		return 0
	fi
	$SUDO "$LITTLESNITCH" restore-model "$merged" || die "restore-model не сработал. Выгрузка: $backup"

	echo "Правила применены. Откат:"
	printf '  sudo "%s" restore-model "%s"\n' "$LITTLESNITCH" "$backup"
	echo "Теперь выключите в Little Snitch: Settings → Security → доступ из командной строки."
}

cmd_verify() {
	resolve_apps
	exec "$REPO/verify.sh" $APPS
}

remove_little_snitch_rules() {
	[ -x "$LITTLESNITCH" ] || return 0
	[ "$WITH_LS" != 0 ] || return 0
	if [ "$WITH_LS" != 1 ]; then
		confirm "Убрать правила kill-switch из Little Snitch (нужен sudo)? Если они есть, без этого приложения останутся без сети." || return 0
	fi
	need_python
	RULE_FILES=""
	for a in $APPS; do RULE_FILES="$RULE_FILES $REPO/littlesnitch/$a-killswitch.lsrules"; done
	ls_export_and_merge --remove
	$SUDO "$LITTLESNITCH" restore-model "$merged" || die "restore-model не сработал. Выгрузка: $backup"
	echo "Правила kill-switch убраны. Выгрузка до изменения: $backup"
}

cmd_uninstall() {
	resolve_apps
	echo "Будет удалено для:$APPS — лаунчер, обновлятор, LaunchAgent, кэш загрузок, прокси в настройках Claude Code."
	confirm "Продолжить?" || exit 0

	# Сначала правила: без лаунчера приложения с kill-switch остались бы без сети
	remove_little_snitch_rules

	for a in $APPS; do
		n=$(app_name "$a"); u=$(updater "$a")
		agent="$HOME/Library/LaunchAgents/local.$u.plist"
		step "$n: удаляю"
		$LAUNCHCTL bootout "gui/$(id -u)" "$agent" 2>/dev/null || true
		rm -f "$agent" "$BIN/$u"
		rm -rf "$APPS_DIR/$n (proxied).app" "$HOME/Library/Caches/$u"
		if [ "$a" = claude ] && [ -f "$SETTINGS" ]; then
			cp "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d%H%M%S)"
			/usr/bin/python3 -I - "$SETTINGS" <<'EOF'
import json, sys
path = sys.argv[1]
d = json.load(open(path))
env = d.get("env", {})
for k in ("HTTPS_PROXY", "HTTP_PROXY", "NO_PROXY"):
    env.pop(k, None)
if not env:
    d.pop("env", None)
json.dump(d, open(path, "w"), ensure_ascii=False, indent=2)
EOF
		fi
	done
	if [ ! -e "$BIN/claude-proxy-update" ] && [ ! -e "$BIN/chatgpt-proxy-update" ]; then rm -f "$BIN/nopx"; fi
	printf '\nГотово. Сами приложения не тронуты. Закройте их и откройте обычным способом.\n'
}

# Разбор аргументов
if [ $# -eq 0 ]; then
	[ -t 0 ] || die "без аргументов скрипт задаёт вопросы, нужен терминал. Или: ./setup.sh install --proxy URL"
	INTERACTIVE=1
else
	case "$1" in
		install|little-snitch|verify|uninstall) CMD=$1; shift;;
		-h|--help|help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
		-*) ;;
		*) die "неизвестная команда: $1 (есть install, little-snitch, verify, uninstall)";;
	esac
fi
while [ $# -gt 0 ]; do
	case "$1" in
		--proxy) [ $# -ge 2 ] || die "--proxy: нужен адрес"; PROXY=$2; shift 2;;
		--apps) [ $# -ge 2 ] || die "--apps: нужен список"; APPS=$2; shift 2;;
		--little-snitch) WITH_LS=1; shift;;
		--no-little-snitch) WITH_LS=0; shift;;
		--yes|-y) YES=1; shift;;
		*) die "неизвестный параметр: $1";;
	esac
done

case "$CMD" in
	install) cmd_install;;
	little-snitch) resolve_apps; cmd_little_snitch;;
	verify) cmd_verify;;
	uninstall) cmd_uninstall;;
esac
