# claude-proxy-guard

Claude Desktop и Claude Code на macOS работают **строго через прокси**, с kill-switch
на уровне Little Snitch и обновлениями, которые тоже идут через прокси.

Требование:
- всё, что делает **само приложение Claude** (чат, API, телеметрия, обновления), идёт только через прокси;
- **дочерние процессы** (команды Bash, MCP, `ssh`) свободны и ходят куда хотят;
- Claude может сознательно выйти без прокси командой `nopx <cmd>`.

Проверено на Claude 4.4212.0 (Electron 44, Node 24.22), Claude Code 2.1.309,
Little Snitch 6.3.3, macOS 15. Прокси — xray в Docker, HTTP на `127.0.0.1:20809`.

## Состав

| Файл | Что делает |
|---|---|
| `launcher/launch-claude-proxy.applescript` | Лаунчер «Claude (proxied).app»: закрывает Claude, ставит отложенное обновление, запускает бинарник с `--proxy-server` и env |
| `bin/claude-proxy-update` | Обновлятор через прокси: `check` / `install` / `status` |
| `bin/nopx` | Запустить команду без proxy-переменных |
| `launchd/local.claude-proxy-update.plist.template` | LaunchAgent: `check` при входе и раз в 4 часа |
| `claude/settings.env.json` | Блок `env` для `~/.claude/settings.json` (прокси для CLI) |
| `littlesnitch/claude-killswitch.lsrules` | Правила kill-switch, единственный источник истины |
| `littlesnitch/merge-rules.py` | Вливает `.lsrules` в выгрузку `export-model` |
| `install.sh` | Ставит всё, кроме правил Little Snitch (без root) |
| `verify.sh` | Проверяет, что всё работает; ничего не меняет |

## Установка на новом Mac

1. Поставить Claude Desktop в `/Applications/Claude.app` и поднять прокси.
2. Установить:
   ```bash
   PROXY=http://127.0.0.1:20809 ./install.sh
   ```
3. Little Snitch — см. раздел ниже (нужен root, делает человек).
4. Закрыть Claude и запускать **только** через «Claude (proxied)». Иконку из Dock от обычного Claude убрать.
5. Проверить: `./verify.sh` и Network Monitor в Little Snitch.

## Little Snitch

Little Snitch 6 не импортирует локальный `.lsrules` (только подписка по https), а CLI
`littlesnitch` требует root и разрешения в **Settings → Security → доступ из командной строки**.
`restore-model` **заменяет всю модель целиком**, поэтому сначала обязательно бэкап.

```bash
sudo "/Applications/Little Snitch.app/Contents/Components/littlesnitch" export-model > ~/Desktop/ls-backup.json
```
```bash
./littlesnitch/merge-rules.py ~/Desktop/ls-backup.json littlesnitch/claude-killswitch.lsrules ~/Desktop/ls-merged.json
```
```bash
sudo "/Applications/Little Snitch.app/Contents/Components/littlesnitch" restore-model ~/Desktop/ls-merged.json
```
Откат:
```bash
sudo "/Applications/Little Snitch.app/Contents/Components/littlesnitch" restore-model ~/Desktop/ls-backup.json
```
После этого выключить доступ из командной строки в настройках Little Snitch.
`merge-rules.py` удаляет прежние правила kill-switch по метке в `notes`, так что его можно гонять повторно.

### Правила

| Процесс (code ID, команда Anthropic `Q6L2SF6YDW`) | Правило |
|---|---|
| `com.anthropic.claudefordesktop` (главный) | Deny any + Allow `127.0.0.1, ::1`, оба Priority |
| `com.anthropic.claudefordesktop.helper` (сеть Chromium) | то же |
| `chrome_crashpad_handler` | то же |
| главный **via** `com.apple.ssh` | Allow any, Priority — SSH-сессии десктопа свободны |
| `com.anthropic.claude-code` (CLI) | **правила нет** — см. ниже |

Правила привязаны к code ID, а не к пути, поэтому переживают обновления (путь CLI
меняется с каждой версией: `~/Library/Application Support/Claude/claude-code/<ver>/<hash>/…`).

## Почему так — найденные причины утечек

1. **Автообновление перезапускает Claude мимо лаунчера.** После установки обновления
   (`[stealth-relaunch]` в `~/Library/Logs/Claude/main.log`) приложение стартует без
   `--proxy-server` и без env. Признак в логе: в таком запуске нет строки
   `[CCD] Resolved system proxy for Code sessions`. Решение — свой обновлятор и kill-switch.
2. **Node-часть главного процесса игнорирует `--proxy-server`.** Флаг читает только сеть
   Chromium. Node (в Electron 44 это Node 24) берёт `HTTPS_PROXY`, только если задано
   `NODE_USE_ENV_PROXY=1`. Без этого были прямые запросы на `api.anthropic.com:443`
   даже при правильном запуске.
3. **Встроенный обновлятор (Squirrel.Mac) — нативная сеть macOS.** Не понимает ни флаг, ни
   env. Под kill-switch падает с `The network connection was lost` — это нормально.
4. **Single-instance lock.** Если старый Claude не умер, новый запуск отдаёт аргументы
   старому процессу без прокси. Лаунчер добивает SIGKILL и иначе отменяет запуск.
5. Мелочи: `curl http://` не читает `HTTP_PROXY` в верхнем регистре; `node`, `nc`, `ssh`
   переменные прокси игнорируют. Для дочерних процессов это допустимо по требованию.

## Little Snitch: грабли

- **Правило без `via` действует и на все дочерние процессы** («claude via curl»). Поэтому на
  CLI правила нет: иначе режутся все команды Bash и `nopx` бесполезен. Задать «via любой» нельзя.
  CLI держится на `env` из `~/.claude/settings.json` (его читают все Code-сессии, включая VS Code).
- **Priority обязателен.** Правило на конкретный сервер (например, созданное по алерту
  «Claude → anthropic.com Allow») сильнее «Any Server» без приоритета.
- **Явный Allow на `127.0.0.1, ::1` обязателен.** Встроенного скрытого правила для loopback
  не хватило: без явного разрешения у Claude отвалились новые соединения с прокси.
- Для **неподписанных** дочерних процессов (например, Python из pyenv) правило по via не
  применяется, Little Snitch показывает алерт. Это свои тестовые процессы — Deny/Allow по ситуации.
- Тестировать «проходит ли прямое соединение» запуском `curl` из Claude бессмысленно: это
  «claude via curl». Плюс TUN-режим Happ (маршрут по умолчанию через `utun`) сам рвёт соединения
  на тестовые адреса. Надёжная проверка — Network Monitor.

## Обновления через прокси

Фид (тот же, что у встроенного обновлятора):
```
https://api.anthropic.com/api/desktop/darwin/<arm64|x64>/squirrel/update?device_id=<id>&version=<v>&os_version=<macOS>
```
- `device_id` обязателен: это UUID в base64 из `~/Library/Application Support/Claude/ant-did`.
- Ответ: `releases[0].updateTo.{version,url,sha256,size}`; `url` на `downloads.claude.ai`.
- `claude.ai/api/desktop/.../latest/redirect` отдаёт 403 для curl — не использовать.

`claude-proxy-update check` качает с докачкой (прокси рвёт длинные загрузки), сверяет
sha256 и подпись (`Q6L2SF6YDW` / `com.anthropic.claudefordesktop`), кладёт копию в
`~/Library/Caches/claude-proxy-update/staged`. Лаунчер вызывает `install`, когда Claude
закрыт; прошлая версия остаётся в `…/previous`.

## Выход без прокси

```bash
nopx ssh user@host
```
Убирает `HTTP(S)_PROXY`, `NO_PROXY`, `ALL_PROXY` (оба регистра) и `NODE_USE_ENV_PROXY`.

## Диагностика

- `./verify.sh` — флаги и env главного процесса, прямые сокеты, LaunchAgent, версии.
- `~/Library/Logs/Claude/main.log` — `[updater]`, `stealth-relaunch`, `Resolved system proxy`.
- `~/Library/Logs/claude-proxy-update.log` — обновлятор.
- `claude-proxy-update status` — установлена / отложена / актуальная.
