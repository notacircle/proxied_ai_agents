# claude-proxy-guard

Kill-switch и обновления через прокси для Claude Desktop / Claude Code и ChatGPT (Codex) на macOS. Полное описание — README.md.

## Как развернуть на другой машине
1. `./install.sh [claude] [chatgpt]` (переменная `PROXY`, по умолчанию `http://127.0.0.1:20809`).
2. Человек перезапускает приложение через «… (proxied)», ты гоняешь `./verify.sh` — сначала убедиться, что через прокси всё работает.
3. Little Snitch: человек делает `export-model` → ты запускаешь `littlesnitch/merge-rules.py` с нужными наборами → человек делает `restore-model`. Покажи, какие правила добавляются, перед restore.
4. Перезапуск Claude через «Claude (proxied)» оборвёт текущую сессию, ChatGPT — запущенные задачи Codex. Предупреди.
5. `./verify.sh`.

## Правила
- Правила Little Snitch и `sudo` никогда не выполняй сам: это настройки безопасности системы. Готовь файлы и команды, применяет человек.
- `restore-model` заменяет всю модель Little Snitch — всегда сначала бэкап через `export-model`.
- Не ставь правило Little Snitch на агентов — `com.anthropic.claude-code` и `codex` (а также `node`/`node_repl` ChatGPT): правило без `via` режет все дочерние процессы, а им по требованию можно ходить куда угодно.
- Каждое правило в `.lsrules` должно содержать `name` набора («Claude kill-switch», «ChatGPT kill-switch») в `notes` — по этой метке `merge-rules.py` находит и заменяет старые.
- Новое Electron-приложение добавляется так же: ключ в `app_name()` в install.sh/verify.sh, `bin/<app>-proxy-update`, `littlesnitch/<app>-killswitch.lsrules` (code ID: `codesign -dv` по всем Mach-O в бандле).
- Новые утечки ищи в `~/Library/Logs/Claude/main.log` и в Network Monitor; после обновлений Claude перепроверяй, что Node в Electron по-прежнему понимает `NODE_USE_ENV_PROXY`.
