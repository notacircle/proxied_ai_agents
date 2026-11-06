# proxied_ai_agents

Kill-switch и обновления через прокси для Claude Desktop / Claude Code и ChatGPT (Codex) на macOS. Полное описание — README.md.

## Как развернуть на другой машине
Точка входа — `setup.sh`, описание команд в README.
1. `./setup.sh install --proxy URL --no-little-snitch` можешь запускать сам (без root).
2. Человек перезапускает приложение через «… (proxied)», ты запускаешь `./setup.sh verify`. Перезапуск Claude оборвёт текущую сессию, ChatGPT — задачи Codex. Предупреди.
3. `./setup.sh little-snitch` запускает только человек в своём терминале: скрипт вызывает `sudo` и меняет правила.
4. После изменений `setup.sh` гоняй `tests/smoke.sh`.

## Правила
- Правила Little Snitch и `sudo` никогда не выполняй сам: это настройки безопасности системы. Готовь файлы и команды, применяет человек.
- `restore-model` заменяет всю модель Little Snitch — всегда сначала бэкап через `export-model`.
- Не ставь правило Little Snitch на `com.anthropic.claude-code`: правило без `via` режет все дочерние процессы, а им по требованию можно ходить куда угодно.
- У ChatGPT агент `codex` лежит в бандле, и правило главного процесса действует на все его команды. Это выбрано сознательно (строгий режим): не добавляй исключения для них без просьбы человека.
- Каждое правило в `.lsrules` должно содержать `name` набора («Claude kill-switch», «ChatGPT kill-switch») в `notes` — по этой метке `merge-rules.py` находит и заменяет старые.
- Новое Electron-приложение добавляется так же: ключ в `app_name()` в setup.sh и verify.sh, `bin/<app>-proxy-update`, `littlesnitch/<app>-killswitch.lsrules` (code ID: `codesign -dv` по всем Mach-O в бандле).
- Новые утечки ищи в `~/Library/Logs/Claude/main.log` и в Network Monitor; после обновлений Claude перепроверяй, что Node в Electron по-прежнему понимает `NODE_USE_ENV_PROXY`.
