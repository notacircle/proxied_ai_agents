-- launch-proxied.applescript
-- Запуск Electron-приложения (Claude, ChatGPT) на macOS через прокси.
--
-- Приложение не наследует системный прокси, поэтому бинарник
-- запускается напрямую с флагом --proxy-server и env-переменными.
-- install.sh собирает из этого файла «Claude (proxied)» и «ChatGPT (proxied)»,
-- подставляя appName и updaterName.
--
-- Как пользоваться:
--   1. Откройте файл в Script Editor (Скрипт-редактор).
--   2. Отредактируйте свойства ниже (хост, порт, тип прокси).
--   3. Нажмите Run. Либо из терминала: osascript launch-proxied.applescript
--
-- Можно сохранить как Программу (File -> Export -> File Format: Application),
-- тогда получится кликабельный лаунчер в Dock.

-- ============================================================
-- НАСТРОЙКИ
-- ============================================================

-- HTTP/HTTPS прокси для самого приложения и его встроенного CLI.
-- Схема всегда http:// или https://.
property httpProxyURL : "http://127.0.0.1:20809"

-- Адреса в обход прокси
property noProxyList : "localhost,127.0.0.1,::1"

-- Имя приложения как в /Applications
property appName : "Claude"

-- Обновлятор через прокси в ~/.local/bin (claude-proxy-update, chatgpt-proxy-update)
property updaterName : "claude-proxy-update"

-- Один раз подтянуть иконку приложения на этот скрипт-лаунчер.
-- Работает только если скрипт сохранён как Программа (.app).
property setOwnIcon : true

-- ============================================================
-- Дальше менять не нужно
-- ============================================================

-- true, если процессы из бандла ещё живы
on bundleAlive(bundlePath)
	try
		do shell script "pgrep -f " & quoted form of bundlePath
		return true
	end try
	return false
end bundleAlive

-- Ждёт исчезновения процессов до (n * 0.5) сек; true — если все завершились
on waitGone(bundlePath, n)
	repeat n times
		if not my bundleAlive(bundlePath) then return true
		delay 0.5
	end repeat
	return not my bundleAlive(bundlePath)
end waitGone

on quitAppIfRunning(theApp)
	-- 1. Пробуем закрыть штатно
	try
		if application theApp is running then
			tell application theApp to quit
			delay 1.5
		end if
	end try

	-- 2. Принудительно добиваем все процессы из бандла приложения
	--    (главный процесс, Electron-хелперы, встроенный CLI).
	set bundlePath to "/Applications/" & theApp & ".app/"
	try
		do shell script "pkill -f " & quoted form of bundlePath
	end try
	if my waitGone(bundlePath, 10) then return true

	-- 3. Кто не ушёл по SIGTERM — SIGKILL
	try
		do shell script "pkill -9 -f " & quoted form of bundlePath
	end try
	return my waitGone(bundlePath, 10)
end quitAppIfRunning

-- Копирует .icns из приложения на бандл этого лаунчера.
-- Тихо выходит, если скрипт запущен не как .app или иконка уже совпадает.
on applyOwnIcon()
	try
		set mePath to POSIX path of (path to me)
		if mePath does not end with ".app/" and mePath does not end with ".app" then return

		set meBundle to mePath
		if meBundle ends with "/" then set meBundle to text 1 thru -2 of meBundle

		set sh to "src=$(ls -S /Applications/" & appName & ".app/Contents/Resources/*.icns 2>/dev/null | head -1); " & ¬
			"dst=" & quoted form of meBundle & "/Contents/Resources/applet.icns; " & ¬
			"if [ -n \"$src\" ] && [ -f \"$dst\" ] && ! cmp -s \"$src\" \"$dst\"; then " & ¬
			"cp \"$src\" \"$dst\" && touch " & quoted form of meBundle & " && killall Finder; fi"
		do shell script sh
	on error
		-- иконка не критична, молча игнорируем
	end try
end applyOwnIcon

on run
	if setOwnIcon then my applyOwnIcon()

	-- Полностью закрываем старый экземпляр: при работающем процессе
	-- single-instance lock отдаёт запуск ему, и новый флаг теряется.
	-- Если старый не умер — не запускаем, иначе приложение останется без прокси.
	if not my quitAppIfRunning(appName) then
		display dialog "Старый процесс " & appName & " не завершился — запуск отменён, чтобы не остаться без прокси." & return & return & ¬
			"Закройте " & appName & " вручную и запустите лаунчер снова." buttons {"OK"} default button "OK" with icon stop
		return
	end if

	-- Ставим обновление, скачанное через прокси (<updaterName> check).
	-- Встроенный обновлятор (Squirrel, Sparkle) ходит мимо прокси и заблокирован.
	try
		do shell script "\"$HOME/.local/bin/" & updaterName & "\" install >> \"$HOME/Library/Logs/" & updaterName & ".log\" 2>&1"
	on error
		display notification "Обновление не установлено, запускаю текущую версию" with title appName & " proxy launcher"
	end try

	-- КЛЮЧЕВОЕ: сетевой стек Electron/Chromium НЕ читает HTTPS_PROXY,
	-- ему нужен флаг --proxy-server. Запускаем бинарник напрямую с флагом.
	-- env-переменные — для Node-части главного процесса (NODE_USE_ENV_PROXY=1,
	-- без него Node игнорирует HTTPS_PROXY) и для встроенного CLI.
	set hq to quoted form of httpProxyURL
	set nq to quoted form of noProxyList
	set pv to quoted form of httpProxyURL
	set macosDir to quoted form of ("/Applications/" & appName & ".app/Contents/MacOS")

	set sh to "DIR=" & macosDir & "; BIN=\"$DIR/$(ls \"$DIR\" | head -1)\"; " & ¬
		"HTTPS_PROXY=" & hq & " HTTP_PROXY=" & hq & " NO_PROXY=" & nq & " NODE_USE_ENV_PROXY=1 " & ¬
		"nohup \"$BIN\" --proxy-server=" & pv & " >/dev/null 2>&1 &"

	try
		do shell script sh
		display notification "--proxy-server=" & httpProxyURL with title appName & " proxy launcher"
	on error errMsg number errNum
		display dialog "Запуск не удался:" & return & return & errMsg & ¬
			" (" & errNum & ")" & return & return & "Команда:" & return & sh ¬
			buttons {"OK"} default button "OK" with icon stop
	end try
end run
