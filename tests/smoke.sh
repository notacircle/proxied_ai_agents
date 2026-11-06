#!/bin/sh
# Прогон setup.sh в песочнице: свой HOME и /Applications, заглушки вместо sudo,
# launchctl и Little Snitch. Настоящие правила и настройки не трогает.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SB=$(mktemp -d)
trap 'rm -rf "$SB"' EXIT
FAILED=0
ok() { printf '  OK    %s\n' "$*"; }
bad() { printf '  FAIL  %s\n' "$*"; FAILED=1; }
check() { desc=$1; shift; if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi; }

mkdir -p "$SB/home/.claude" "$SB/apps" "$SB/stub"
echo '{"theme":"dark"}' > "$SB/home/.claude/settings.json"
for n in Claude ChatGPT; do
	mkdir -p "$SB/apps/$n.app/Contents/Resources"
	printf 'icon-%s' "$n" > "$SB/apps/$n.app/Contents/Resources/electron.icns"
	plutil -create xml1 "$SB/apps/$n.app/Contents/Info.plist"
	plutil -insert CFBundleIconFile -string electron.icns "$SB/apps/$n.app/Contents/Info.plist"
done

# Заглушка Little Snitch: export-model отдаёт модель, restore-model кладёт её обратно
cat > "$SB/stub/littlesnitch" <<STUB
#!/bin/sh
case "\$1" in
	export-model) cat "$SB/model.json";;
	restore-model) cp "\$2" "$SB/model.json";;
esac
STUB
chmod +x "$SB/stub/littlesnitch"
echo '{"version":1,"rules":[{"action":"allow","process":"any","remote":"any","notes":"чужое правило"}]}' > "$SB/model.json"

count() { /usr/bin/python3 -I -c "
import json,sys
print(sum(sys.argv[1] in r.get('notes','') for r in json.load(open('$SB/model.json'))['rules']))" "$1"; }

run() { env HOME="$SB/home" APPS_DIR="$SB/apps" LITTLESNITCH="$SB/stub/littlesnitch" SUDO=env LAUNCHCTL=true \
	PATH="$PATH" "$REPO/setup.sh" "$@" </dev/null; }
P=http://127.0.0.1:9

echo "Неверные аргументы"
for bad_proxy in socks5://127.0.0.1:1080 'http://u:p@127.0.0.1:1' 'http://a"b:1' 'http://a#b:1'; do
	if run install --proxy "$bad_proxy" --no-little-snitch --yes >/dev/null 2>&1; then bad "принят прокси $bad_proxy"; else ok "отклонён прокси $bad_proxy"; fi
done
if run install --no-little-snitch --yes >/dev/null 2>&1; then bad "установка без --proxy"; else ok "без --proxy не ставит"; fi
if run install --proxy $P --apps foo --no-little-snitch >/dev/null 2>&1; then bad "неизвестное приложение"; else ok "неизвестное приложение отклонено"; fi

echo "Установка без Little Snitch"
out=$(run install --proxy $P --no-little-snitch 2>&1) && ok "install завершился" || { bad "install упал"; echo "$out"; }
echo "$out" | grep -q 'kill-switch не установлен' && ok "предупреждает об отсутствии kill-switch" || bad "нет предупреждения"
[ "$(count kill-switch)" = 0 ] && ok "правила не тронуты" || bad "правила изменились"
for n in Claude ChatGPT; do
	cmp -s "$SB/apps/$n.app/Contents/Resources/electron.icns" "$SB/apps/$n (proxied).app/Contents/Resources/applet.icns" && ok "$n: иконка" || bad "$n: иконка"
	check "$n: подпись лаунчера" codesign --verify "$SB/apps/$n (proxied).app"
done
for u in claude chatgpt; do
	grep -q "^PROXY=.*:-$P}\"" "$SB/home/.local/bin/$u-proxy-update" && ok "$u: прокси в обновляторе" || bad "$u: прокси в обновляторе"
	check "$u: LaunchAgent валиден" plutil -lint "$SB/home/Library/LaunchAgents/local.$u-proxy-update.plist"
	grep -q __ "$SB/home/Library/LaunchAgents/local.$u-proxy-update.plist" && bad "$u: плейсхолдеры в LaunchAgent" || ok "$u: нет плейсхолдеров"
done
check "nopx установлен" test -x "$SB/home/.local/bin/nopx"
/usr/bin/python3 -I -c "
import json;d=json.load(open('$SB/home/.claude/settings.json'))
assert d['theme']=='dark' and d['env']['HTTPS_PROXY']=='$P'" && ok "settings.json: env добавлен, остальное на месте" || bad "settings.json"

echo "Little Snitch"
if run little-snitch >/dev/null 2>&1; then bad "применил без подтверждения"; else ok "без подтверждения не применяет"; fi
[ "$(count kill-switch)" = 0 ] && ok "модель не изменилась" || bad "модель изменилась"
out=$(run little-snitch --apps chatgpt --yes 2>&1) && ok "little-snitch --apps chatgpt" || { bad "little-snitch упал"; echo "$out"; }
[ "$(count 'ChatGPT kill-switch')" = 14 ] && [ "$(count 'Claude kill-switch')" = 0 ] && ok "только правила ChatGPT" || bad "наборы правил"
out=$(run little-snitch --yes 2>&1) && ok "little-snitch для всех, повторно" || { bad "повторный запуск упал"; echo "$out"; }
[ "$(count 'ChatGPT kill-switch')" = 14 ] && [ "$(count 'Claude kill-switch')" = 7 ] && ok "оба набора без дублей" || bad "дубли правил"
[ "$(count 'чужое правило')" = 1 ] && ok "чужое правило на месте" || bad "чужое правило пропало"
echo "$out" | grep -q 'allow com.openai.codex via com.apple.ssh -> any' && ok "показывает правила" || bad "список правил"
check "выгрузка сохранена" test -n "$(ls "$SB/home/Library/Application Support/proxied_ai_agents/"ls-backup-*.json)"

echo "Установка с --little-snitch и удаление"
out=$(run install --proxy $P --apps claude --little-snitch --yes 2>&1) && ok "install --little-snitch" || { bad "install --little-snitch упал"; echo "$out"; }
[ "$(count 'Claude kill-switch')" = 7 ] && ok "правила Claude без дублей" || bad "правила Claude"
out=$(run uninstall --yes 2>&1) && ok "uninstall" || { bad "uninstall упал"; echo "$out"; }
[ "$(count kill-switch)" = 0 ] && ok "правила убраны" || bad "правила остались"
[ "$(count 'чужое правило')" = 1 ] && ok "чужое правило на месте" || bad "чужое правило пропало"
for n in Claude ChatGPT; do [ -e "$SB/apps/$n (proxied).app" ] && bad "$n: лаунчер остался" || ok "$n: лаунчер удалён"; check "$n: приложение на месте" test -d "$SB/apps/$n.app"; done
[ -e "$SB/home/.local/bin/nopx" ] && bad "nopx остался" || ok "nopx удалён"
/usr/bin/python3 -I -c "
import json;d=json.load(open('$SB/home/.claude/settings.json'))
assert d=={'theme':'dark'}" && ok "settings.json вернулся к исходному" || bad "settings.json после удаления"

exit "$FAILED"
