# claude-proxy-guard

Kill-switch и обновления через прокси для Claude Desktop / Claude Code на macOS. Полное описание — README.md.

## Как развернуть на другой машине
1. `./install.sh` (переменная `PROXY`, по умолчанию `http://127.0.0.1:20809`).
2. Little Snitch: человек делает `export-model` → ты запускаешь `littlesnitch/merge-rules.py` → человек делает `restore-model`. Покажи, какие правила добавляются, перед restore.
3. Перезапуск Claude через «Claude (proxied)» оборвёт текущую сессию — предупреди.
4. `./verify.sh`.

## Правила
- Правила Little Snitch и `sudo` никогда не выполняй сам: это настройки безопасности системы. Готовь файлы и команды, применяет человек.
- `restore-model` заменяет всю модель Little Snitch — всегда сначала бэкап через `export-model`.
- Не ставь правило Little Snitch на `com.anthropic.claude-code`: правило без `via` режет все дочерние процессы, а им по требованию можно ходить куда угодно.
- Каждое правило в `.lsrules` должно содержать «Claude kill-switch» в `notes` — по этой метке `merge-rules.py` находит и заменяет старые.
- Новые утечки ищи в `~/Library/Logs/Claude/main.log` и в Network Monitor; после обновлений Claude перепроверяй, что Node в Electron по-прежнему понимает `NODE_USE_ENV_PROXY`.
