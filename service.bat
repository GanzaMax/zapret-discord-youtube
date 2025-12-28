@echo off
set "LOCAL_VERSION=1.9.2"
reg add "HKCU\Console" /v "FontSize" /t REG_DWORD /d 0x000e0000 /f
cls
reg add "HKCU\Console" /v "FaceName" /t REG_SZ /d "Consolas" /f
cls
reg add "HKCU\Console" /v "FaceName" /t REG_SZ /d "Lucida Console" /f
cls
chcp 65001 > nul
:: External commands
if "%~1"=="status_zapret" (
    call :test_service zapret soft
    call :tcp_enable
    exit /b
)

if "%~1"=="check_updates" (
    if exist "%~dp0utils\check_updates.enabled" (
        if not "%~2"=="soft" (
            start /b service check_updates soft
        ) else (
            call :service_check_updates soft
        )
    )

    exit /b
)

if "%~1"=="load_game_filter" (
    call :game_switch_status
    exit /b
)

if "%1"=="admin" (
    call :check_command chcp
    call :check_command find
    call :check_command findstr
    call :check_command netsh
    color 02
    echo Запущено с правами администратора
) else (
    call :check_extracted
    call :check_command powershell
    color 06
    echo Запрос прав администратора...
    powershell -Command "Start-Process 'cmd.exe' -ArgumentList '/c \"\"%~f0\" admin\"' -Verb RunAs"
    exit
)


:: MENU ================================
setlocal EnableDelayedExpansion
:menu
cls
call :ipset_switch_status
call :game_switch_status
call :check_updates_switch_status
chcp 65001 > nul
color 07
set "menu_choice=null"
echo =========  v!LOCAL_VERSION!  =========
echo 1. Установить службу
echo 2. Отключить службу
echo 3. Проверить статус
echo 4. Запустить диагностику
echo 5. Проверить обновления
echo 6. Автоматическая проверка обновлений (%CheckUpdatesStatus%)
echo 7. Игровой фильтр (%GameFilterStatus%)
echo 8. Фильтр IP-адресов (%IPsetStatus%)
echo 9. Обновить список IP-адресов
echo 10. Обновить файл hosts (для голоса в discord)
echo 11. Провести тестирование
echo 0. Выход
set /p menu_choice=Введите цифру (0-11): 

if "%menu_choice%"=="1" goto service_install
if "%menu_choice%"=="2" goto service_remove
if "%menu_choice%"=="3" goto service_status
if "%menu_choice%"=="4" goto service_diagnostics
if "%menu_choice%"=="5" goto service_check_updates
if "%menu_choice%"=="6" goto check_updates_switch
if "%menu_choice%"=="7" goto game_switch
if "%menu_choice%"=="8" goto ipset_switch
if "%menu_choice%"=="9" goto ipset_update
if "%menu_choice%"=="10" goto hosts_update
if "%menu_choice%"=="11" goto run_tests
if "%menu_choice%"=="0" exit /b
goto menu


:: TCP ENABLE ==========================
:tcp_enable
netsh interface tcp show global | findstr /i "timestamps" | findstr /i "enabled" > nul || netsh interface tcp set global timestamps=enabled > nul 2>&1
exit /b


:: STATUS ==============================
:service_status
cls
chcp 65001 > nul

sc query "zapret" >nul 2>&1
if !errorlevel!==0 (
    for /f "tokens=2*" %%A in ('reg query "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube 2^>nul') do echo Установлена стратегия "%%B"
)

call :test_service zapret
call :test_service WinDivert

set "BIN_PATH=%~dp0bin\"
if not exist "%BIN_PATH%\*.sys" (
    call :PrintRed "WinDivert64.sys файл НЕ НАЙДЕН."
)
echo:

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if !errorlevel!==0 (
    call :PrintGreen "Обход (winws.exe) ЗАПУЩЕН."
) else (
    call :PrintRed "Обход (winws.exe) НЕ ЗАПУЩЕН."
)

pause
goto menu

:test_service
set "ServiceName=%~1"
set "ServiceStatus="

for /f "tokens=3 delims=: " %%A in ('sc query "%ServiceName%" ^| findstr /i "STATE"') do set "ServiceStatus=%%A"
set "ServiceStatus=%ServiceStatus: =%"

if "%ServiceStatus%"=="RUNNING" (
    if "%~2"=="soft" (
        echo "%ServiceName%" уже ЗАПУЩЕНО как служба, используйте файл "service.bat" и сначала выберите "Отключить службу", если хотите запустить автономный bat-файл.
        pause
        exit /b
    ) else (
        color 0A
        echo Служба "%ServiceName%" ЗАПУЩЕНА.
    )
) else if "%ServiceStatus%"=="STOP_PENDING" (
    call :PrintYellow "Служба !ServiceName! ЗАМОРОЖЕНА, это может быть вызвано конфликтом с другим каналом обхода. Запустите диагностику, чтобы попытаться устранить конфликты"
) else if not "%~2"=="soft" (
    color 04
    echo Служба "%ServiceName%" НЕ ЗАПУЩЕНА.
)

exit /b


:: REMOVE ==============================
:service_remove
cls
chcp 65001 > nul
color 04
set SRVCNAME=zapret
sc query "!SRVCNAME!" >nul 2>&1
if !errorlevel!==0 (
    net stop %SRVCNAME%
    sc delete %SRVCNAME%
) else (
     color 06
     echo Служба "%SRVCNAME%" не установлена.
)

tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
if !errorlevel!==0 (
    taskkill /IM winws.exe /F > nul
)

sc query "WinDivert" >nul 2>&1
if !errorlevel!==0 (
    net stop "WinDivert"

    sc query "WinDivert" >nul 2>&1
    if !errorlevel!==0 (
        sc delete "WinDivert"
    )
)
net stop "WinDivert14" >nul 2>&1
sc delete "WinDivert14" >nul 2>&1

pause
goto menu


:: INSTALL =============================
:service_install
cls
chcp 65001 > nul
color 02
:: Main
cd /d "%~dp0"
set "BIN_PATH=%~dp0bin\"
set "LISTS_PATH=%~dp0lists\"

:: Searching for .bat files in current folder, except files that start with "service"
echo Выберите один из вариантов:
set "count=0"
for %%f in (*.bat) do (
    set "filename=%%~nxf"
    if /i not "!filename:~0,7!"=="service" (
        set /a count+=1
        echo !count!. %%f
        set "file!count!=%%f"
    )
)

:: Choosing file
set "choice="
set /p "choice=Введите номер файла для установки: "
if "!choice!"=="" (
    echo Неверный выбор, выход...
    pause
    goto menu
)

set "selectedFile=!file%choice%!"
if not defined selectedFile (
    echo Invalid choice, exiting...
    pause
    goto menu
)

:: Args that should be followed by value
set "args_with_value=sni host altorder"

:: Parsing args (mergeargs: 2=start param|3=arg with value|1=params args|0=default)
set "args="
set "capture=0"
set "mergeargs=0"
set QUOTE="

for /f "tokens=*" %%a in ('type "!selectedFile!"') do (
    set "line=%%a"
    call set "line=%%line:^!=EXCL_MARK%%"

    echo !line! | findstr /i "%BIN%winws.exe" >nul
    if not errorlevel 1 (
        set "capture=1"
    )

    if !capture!==1 (
        if not defined args (
            set "line=!line:*%BIN%winws.exe"=!"
        )

        set "temp_args="
        for %%i in (!line!) do (
            set "arg=%%i"

            if not "!arg!"=="^" (
                if "!arg:~0,2!" EQU "--" if not !mergeargs!==0 (
                    set "mergeargs=0"
                )

                if "!arg:~0,1!" EQU "!QUOTE!" (
                    set "arg=!arg:~1,-1!"

                    echo !arg! | findstr ":" >nul
                    if !errorlevel!==0 (
                        set "arg=\!QUOTE!!arg!\!QUOTE!"
                    ) else if "!arg:~0,1!"=="@" (
                        set "arg=\!QUOTE!@%~dp0!arg:~1!\!QUOTE!"
                    ) else if "!arg:~0,5!"=="%%BIN%%" (
                        set "arg=\!QUOTE!!BIN_PATH!!arg:~5!\!QUOTE!"
                    ) else if "!arg:~0,7!"=="%%LISTS%%" (
                        set "arg=\!QUOTE!!LISTS_PATH!!arg:~7!\!QUOTE!"
                    ) else (
                        set "arg=\!QUOTE!%~dp0!arg!\!QUOTE!"
                    )
                ) else if "!arg:~0,12!" EQU "%%GameFilter%%" (
                    set "arg=%GameFilter%"
                )

                if !mergeargs!==1 (
                    set "temp_args=!temp_args!,!arg!"
                ) else if !mergeargs!==3 (
                    set "temp_args=!temp_args!=!arg!"
                    set "mergeargs=1"
                ) else (
                    set "temp_args=!temp_args! !arg!"
                )

                if "!arg:~0,2!" EQU "--" (
                    set "mergeargs=2"
                ) else if !mergeargs! GEQ 1 (
                    if !mergeargs!==2 set "mergeargs=1"

                    for %%x in (!args_with_value!) do (
                        if /i "%%x"=="!arg!" (
                            set "mergeargs=3"
                        )
                    )
                )
            )
        )

        if not "!temp_args!"=="" (
            set "args=!args! !temp_args!"
        )
    )
)

:: Creating service with parsed args
call :tcp_enable

set ARGS=%args%
call set "ARGS=%%ARGS:EXCL_MARK=^!%%"
echo Установлены аргументы: !ARGS!
set SRVCNAME=zapret

net stop %SRVCNAME% >nul 2>&1
sc delete %SRVCNAME% >nul 2>&1
sc create %SRVCNAME% binPath= "\"%BIN_PATH%winws.exe\" !ARGS!" DisplayName= "zapret" start= auto
sc description %SRVCNAME% "Служба обхода цензуры DPI"
sc start %SRVCNAME%
for %%F in ("!file%choice%!") do (
    set "filename=%%~nF"
)
reg add "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube /t REG_SZ /d "!filename!" /f

pause
goto menu


:: CHECK UPDATES =======================
:service_check_updates
chcp 65001 > nul
color 01
cls

:: Set current version and URLs
set "GITHUB_VERSION_URL=https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/version.txt"
set "GITHUB_RELEASE_URL=https://github.com/Flowseal/zapret-discord-youtube/releases/tag/"
set "GITHUB_DOWNLOAD_URL=https://github.com/Flowseal/zapret-discord-youtube/releases/latest/download/zapret-discord-youtube-"

:: Get the latest version from GitHub
for /f "delims=" %%A in ('powershell -command "(Invoke-WebRequest -Uri \"%GITHUB_VERSION_URL%\" -Headers @{\"Cache-Control\"=\"no-cache\"} -UseBasicParsing -TimeoutSec 5).Content.Trim()" 2^>nul') do set "GITHUB_VERSION=%%A"

:: Error handling
if not defined GITHUB_VERSION (
    echo Предупреждение: не удалось загрузить последнюю версию. Это предупреждение не влияет на работу zapret
    timeout /T 9
    if "%1"=="soft" exit 
    goto menu
)

:: Version comparison
if "%LOCAL_VERSION%"=="%GITHUB_VERSION%" (
    echo Установлена последняя версия: %LOCAL_VERSION%
    
    if "%1"=="soft" exit 
    pause
    goto menu
) 

echo Доступна новая версия: %GITHUB_VERSION%
echo Страница релиза: %GITHUB_RELEASE_URL%%GITHUB_VERSION%

set "CHOICE="
set /p "CHOICE=Начать автоматическую загрузку новой версии? (Y/N) (стандарт: Y) "
if "%CHOICE%"=="" set "CHOICE=Y"
if /i "%CHOICE%"=="y" set "CHOICE=Y"

if /i "%CHOICE%"=="Y" (
    echo Открытие страницы загрузки...
    start "" "%GITHUB_DOWNLOAD_URL%%GITHUB_VERSION%.rar"
)


if "%1"=="soft" exit 
pause
goto menu



:: DIAGNOSTICS =========================
:service_diagnostics
chcp 65001 > nul
cls

:: Base Filtering Engine
sc query BFE | findstr /I "RUNNING" > nul
if !errorlevel!==0 (
    call :PrintGreen "Проверка механизма базовой фильтрации завершена"
) else (
    call :PrintRed "[X] Механизм базовой фильтрации не запущен. Эта служба необходима для работы zapret"
)
echo:

:: Proxy check
set "proxyEnabled=0"
set "proxyServer="

for /f "tokens=2*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable 2^>nul ^| findstr /i "ProxyEnable"') do (
    if "%%B"=="0x1" set "proxyEnabled=1"
)

if !proxyEnabled!==1 (
    for /f "tokens=2*" %%A in ('reg query "HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer 2^>nul ^| findstr /i "ProxyServer"') do (
        set "proxyServer=%%B"
    )
    
    call :PrintYellow "[?] Включен системный прокси: !proxyServer!"
    call :PrintYellow "Убедитесь, что он работает, или отключите его, если вы не используете прокси"
) else (
    call :PrintGreen "Проверка прокси завершена"
)
echo:

:: Check netsh
where netsh >nul 2>nul
if !errorlevel! neq 0  (
    call :PrintRed "[X] Команда netsh не найдена, проверьте переменную PATH"
	echo PATH = "%PATH%"
	echo:
	pause
	goto menu
)

:: TCP timestamps check
netsh interface tcp show global | findstr /i "timestamps" | findstr /i "enabled" > nul
if !errorlevel!==0 (
    call :PrintGreen "Проверка временных меток TCP завершена"
) else (
    call :PrintYellow "[?] Метки времени TCP отключены. Включение меток времени..."
    netsh interface tcp set global timestamps=enabled > nul 2>&1
    if !errorlevel!==0 (
        call :PrintGreen "Временные метки TCP успешно включены"
    ) else (
        call :PrintRed "[X] Не удалось включить метки времени TCP"
    )
)
echo:

:: AdguardSvc.exe
tasklist /FI "IMAGENAME eq AdguardSvc.exe" | find /I "AdguardSvc.exe" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Обнаружен процесс Adguard. Adguard может вызывать проблемы с Discord"
    call :PrintRed "https://github.com/Flowseal/zapret-discord-youtube/issues/417"
) else (
    call :PrintGreen "Проверка наличия Adguard завершена"
)
echo:

:: Killer
sc query | findstr /I "Killer" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Обнаружена служба Killer. Killer конфликтует с zapret"
    call :PrintRed "https://github.com/Flowseal/zapret-discord-youtube/issues/2512#issuecomment-2821119513"
) else (
    call :PrintGreen "Проверка наличия Killer завершена"
)
echo:

:: Intel Connectivity Network Service
sc query | findstr /I "Intel" | findstr /I "Connectivity" | findstr /I "Network" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Обнаружена служба Intel Connectivity Network Service. Она конфликтует с zapret"
    call :PrintRed "https://github.com/ValdikSS/GoodbyeDPI/issues/541#issuecomment-2661670982"
) else (
    call :PrintGreen "Проверка наличия Intel Connectivity завершена"
)
echo:

:: Check Point
set "checkpointFound=0"
sc query | findstr /I "TracSrvWrapper" > nul
if !errorlevel!==0 (
    set "checkpointFound=1"
)

sc query | findstr /I "EPWD" > nul
if !errorlevel!==0 (
    set "checkpointFound=1"
)

if !checkpointFound!==1 (
    call :PrintRed "[X] Обнаружена служба Check Point. Check Point конфликтует с zapret"
    call :PrintRed "Попробуйте удалить Check Point"
) else (
    call :PrintGreen "Проверка наличия Check Point завершена"
)
echo:

:: SmartByte
sc query | findstr /I "SmartByte" > nul
if !errorlevel!==0 (
    call :PrintRed "[X] Обнаружена служба SmartByte. SmartByte конфликтует с zapret"
    call :PrintRed "Попробуйте удалить или отключить SmartByte через services.msc"
) else (
    call :PrintGreen "Проверка наличия SmartByte завершена"
)
echo:

:: WinDivert64.sys file
set "BIN_PATH=%~dp0bin\"
if not exist "%BIN_PATH%\*.sys" (
    call :PrintRed "WinDivert64.sys файл НЕ НАЙДЕН."
)
echo:

:: VPN
set "VPN_SERVICES="
sc query | findstr /I "VPN" > nul
if !errorlevel!==0 (
    for /f "tokens=2 delims=:" %%A in ('sc query ^| findstr /I "VPN"') do (
        if not defined VPN_SERVICES (
            set "VPN_SERVICES=!VPN_SERVICES!%%A"
        ) else (
            set "VPN_SERVICES=!VPN_SERVICES!,%%A"
        )
    )
    call :PrintYellow "[?] Обнаружены службы VPN. Некоторые VPN-сервисы, конфликтуют с zapret"
    call :PrintYellow "Убедитесь, что все VPN-сервисы отключены"
) else (
    call :PrintGreen "Проверка наличия VPN-служб завершена"
)
echo:

:: DNS
set "dohfound=0"
for /f "delims=" %%a in ('powershell -Command "Get-ChildItem -Recurse -Path 'HKLM:System\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\' | Get-ItemProperty | Where-Object { $_.DohFlags -gt 0 } | Measure-Object | Select-Object -ExpandProperty Count"') do (
    if %%a gtr 0 (
        set "dohfound=1"
    )
)
if !dohfound!==0 (
    call :PrintYellow "[?] Убедитесь, что в браузере настроен безопасный DNS с использованием нестандартного DNS-провайдера,"
    call :PrintYellow "Если у вас Windows 11, настройте зашифрованный DNS в параметрах, чтобы скрыть это предупреждение"
) else (
    call :PrintGreen "Проверка DNS завершена"
)
echo:

:: WinDivert conflict
tasklist /FI "IMAGENAME eq winws.exe" | find /I "winws.exe" > nul
set "winws_running=!errorlevel!"

sc query "WinDivert" | findstr /I "RUNNING STOP_PENDING" > nul
set "windivert_running=!errorlevel!"

if !winws_running! neq 0 if !windivert_running!==0 (
    call :PrintYellow "[?] Процесс winws.exe не запущен, но служба WinDivert активна. Запущено удаление WinDivert..."
    
    net stop "WinDivert" >nul 2>&1
    sc delete "WinDivert" >nul 2>&1
    sc query "WinDivert" >nul 2>&1
    if !errorlevel!==0 (
        call :PrintRed "[X] Не удалось удалить WinDivert. Проверяется наличие конфликтующих служб..."
        
        set "conflicting_services=GoodbyeDPI"
        set "found_conflict=0"
        
        for %%s in (!conflicting_services!) do (
            sc query "%%s" >nul 2>&1
            if !errorlevel!==0 (
                call :PrintYellow "[?] Обнаружена конфликтующая служба: %%s. Остановка и удаление..."
                net stop "%%s" >nul 2>&1
                sc delete "%%s" >nul 2>&1
                if !errorlevel!==0 (
                    call :PrintGreen "Успешное удаление службы: %%s"
                ) else (
                    call :PrintRed "[X] Ошибка удаления службы: %%s"
                )
                set "found_conflict=1"
            )
        )
        
        if !found_conflict!==0 (
            call :PrintRed "[X] Конфликтующих служб не обнаружено. Проверьте вручную, возможное использование WinDivert."
        ) else (
            call :PrintYellow "[?] Повторная попытка удалить WinDivert..."

            net stop "WinDivert" >nul 2>&1
            sc delete "WinDivert" >nul 2>&1
            sc query "WinDivert" >nul 2>&1
            if !errorlevel! neq 0 (
                call :PrintGreen "WinDivert успешно удален, после удаления конфликтующих служб"
            ) else (
                call :PrintRed "[X] WinDivert по-прежнему не получается удалить. Проверьте вручную, возможное использование WinDivert."
            )
        )
    ) else (
        call :PrintGreen "WinDivert успешно удалён"
    )
    
    echo:
)

:: Conflicting bypasses
set "conflicting_services=GoodbyeDPI discordfix_zapret winws1 winws2"
set "found_any_conflict=0"
set "found_conflicts="

for %%s in (!conflicting_services!) do (
    sc query "%%s" >nul 2>&1
    if !errorlevel!==0 (
        if "!found_conflicts!"=="" (
            set "found_conflicts=%%s"
        ) else (
            set "found_conflicts=!found_conflicts! %%s"
        )
        set "found_any_conflict=1"
    )
)

if !found_any_conflict!==1 (
    call :PrintRed "[X] Обнаружены конфликтующие службы: !found_conflicts!"
    
    set "CHOICE="
    set /p "CHOICE=Вы хотите удалить конфликтующие службы? (Y/N) (стандарт: N) "
    if "!CHOICE!"=="" set "CHOICE=N"
    if "!CHOICE!"=="y" set "CHOICE=Y"
    
    if /i "!CHOICE!"=="Y" (
        for %%s in (!found_conflicts!) do (
            call :PrintYellow "Остановка и удаление службы: %%s"
            net stop "%%s" >nul 2>&1
            sc delete "%%s" >nul 2>&1
            if !errorlevel!==0 (
                call :PrintGreen "Успешное удаление службы: %%s"
            ) else (
                call :PrintRed "[X] Ошибка удаления службы: %%s"
            )
        )

        net stop "WinDivert" >nul 2>&1
        sc delete "WinDivert" >nul 2>&1
        net stop "WinDivert14" >nul 2>&1
        sc delete "WinDivert14" >nul 2>&1
    )
    
    echo:
)

:: Discord cache clearing
set "CHOICE="
set /p "CHOICE=Вы хотите очистить кэш Discord? (Y/N) (стандарт: Y)  "
if "!CHOICE!"=="" set "CHOICE=Y"
if "!CHOICE!"=="y" set "CHOICE=Y"

if /i "!CHOICE!"=="Y" (
    tasklist /FI "IMAGENAME eq Discord.exe" | findstr /I "Discord.exe" > nul
    if !errorlevel!==0 (
        echo Discord запущен, остановка...
        taskkill /IM Discord.exe /F > nul
        if !errorlevel! == 0 (
            call :PrintGreen "Discord успешно закрыт"
        ) else (
            call :PrintRed "Не удаётся закрыть Discord"
        )
    )

    set "discordCacheDir=%appdata%\discord"

    for %%d in ("Cache" "Code Cache" "GPUCache") do (
        set "dirPath=!discordCacheDir!\%%~d"
        if exist "!dirPath!" (
            rd /s /q "!dirPath!"
            if !errorlevel!==0 (
                call :PrintGreen "Успешно удалено !dirPath!"
            ) else (
                call :PrintRed "Не получилось удалить !dirPath!"
            )
        ) else (
            call :PrintRed "!dirPath! не существует"
        )
    )
)
echo:

pause
goto menu


:: GAME SWITCH ========================
:game_switch_status
chcp 65001 > nul

set "gameFlagFile=%~dp0utils\game_filter.enabled"

if exist "%gameFlagFile%" (
    set "GameFilterStatus=активен"
    set "GameFilter=1024-65535"
) else (
    set "GameFilterStatus=отключен"
    set "GameFilter=12"
)
exit /b


:game_switch
chcp 65001 > nul
cls

if not exist "%gameFlagFile%" (
    color 02
    echo Включение игрового фильтра...
    echo ENABLED > "%gameFlagFile%"
    call :PrintYellow "Перезапустите zapret, чтобы применить изменения"
) else (
    color 04
    echo Отключение игрового фильтра...
    del /f /q "%gameFlagFile%"
    call :PrintYellow "Перезапустите zapret, чтобы применить изменения"
)

pause
goto menu


:: CHECK UPDATES SWITCH =================
:check_updates_switch_status
chcp 65001 > nul

set "checkUpdatesFlag=%~dp0utils\check_updates.enabled"

if exist "%checkUpdatesFlag%" (
    set "CheckUpdatesStatus=включено"
) else (
    set "CheckUpdatesStatus=отключено"
)
exit /b


:check_updates_switch
chcp 65001 > nul
cls

if not exist "%checkUpdatesFlag%" (
    color 02
    echo Включение автоматической проверки обновлений...
    echo ENABLED > "%checkUpdatesFlag%"
) else (
    color 04
    echo Отключение автоматической проверки обновлений...
    del /f /q "%checkUpdatesFlag%"
)

pause
goto menu


:: IPSET SWITCH =======================
:ipset_switch_status
chcp 65001 > nul

set "listFile=%~dp0lists\ipset-all.txt"
for /f %%i in ('type "%listFile%" 2^>nul ^| find /c /v ""') do set "lineCount=%%i"

if !lineCount!==0 (
    set "IPsetStatus=активен"
) else (
    findstr /R "^203\.0\.113\.113/32$" "%listFile%" >nul
    if !errorlevel!==0 (
        set "IPsetStatus=отключен"
    ) else (
        set "IPsetStatus=список"
    )
)
exit /b


:ipset_switch
chcp 65001 > nul
cls

set "listFile=%~dp0lists\ipset-all.txt"
set "backupFile=%listFile%.backup"

if "%IPsetStatus%"=="список" (
    color 04
    echo Отключение фильтрации...
    
    if not exist "%backupFile%" (
        ren "%listFile%" "ipset-all.txt.backup"
    ) else (
        del /f /q "%backupFile%"
        ren "%listFile%" "ipset-all.txt.backup"
    )
    
    >"%listFile%" (
        echo 203.0.113.113/32
    )
    
) else if "%IPsetStatus%"=="отключен" (
     color 02
     echo Включение фильтрации...
    
    >"%listFile%" (
        rem Creating empty file
    )
    
) else if "%IPsetStatus%"=="активен" (
     color 06
     echo Загрузка резервной копии...
    
    if exist "%backupFile%" (
        del /f /q "%listFile%"
        ren "%backupFile%" "ipset-all.txt"
    ) else (
        color 04
        echo Ошибка: нет резервной копии для восстановления. Сначала обновите список в главном меню
        pause
        goto menu
    )
    
)

pause
goto menu


:: IPSET UPDATE =======================
:ipset_update
chcp 65001 > nul
cls

set "listFile=%~dp0lists\ipset-all.txt"
set "url=https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/ipset-service.txt"
color 02
echo Обновление списка IP-адресов...

if exist "%SystemRoot%\System32\curl.exe" (
    curl -L -o "%listFile%" "%url%"
) else (
    powershell -Command ^
        "$url = '%url%';" ^
        "$out = '%listFile%';" ^
        "$dir = Split-Path -Parent $out;" ^
        "if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null };" ^
        "$res = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing;" ^
        "if ($res.StatusCode -eq 200) { $res.Content | Out-File -FilePath $out -Encoding UTF8 } else { exit 1 }"
)

echo Завершено

pause
goto menu


:: HOSTS UPDATE =======================
:hosts_update
chcp 65001 > nul
cls

set "hostsFile=%SystemRoot%\System32\drivers\etc\hosts"
set "hostsUrl=https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/refs/heads/main/.service/hosts"
set "tempFile=%TEMP%\zapret_hosts.txt"
set "needsUpdate=0"
color 02
echo Проверка файла hosts...

if exist "%SystemRoot%\System32\curl.exe" (
    curl -L -s -o "%tempFile%" "%hostsUrl%"
) else (
    powershell -Command ^
        "$url = '%hostsUrl%';" ^
        "$out = '%tempFile%';" ^
        "$res = Invoke-WebRequest -Uri $url -TimeoutSec 10 -UseBasicParsing;" ^
        "if ($res.StatusCode -eq 200) { $res.Content | Out-File -FilePath $out -Encoding UTF8 } else { exit 1 }"
)

if not exist "%tempFile%" (
    call :PrintRed "Не удалось загрузить файл hosts из репозитория"
    pause
    goto menu
)

set "firstLine="
set "lastLine="
for /f "usebackq delims=" %%a in ("%tempFile%") do (
    if not defined firstLine (
        set "firstLine=%%a"
    )
    set "lastLine=%%a"
)

findstr /C:"!firstLine!" "%hostsFile%" >nul 2>&1
if !errorlevel! neq 0 (
    color 04
    echo Первая строка из репозитория не найдена в файле hosts
    set "needsUpdate=1"
)

findstr /C:"!lastLine!" "%hostsFile%" >nul 2>&1
if !errorlevel! neq 0 (
    color 04
    echo Последняя строка из репозитория не найдена в файле hosts
    set "needsUpdate=1"
)

if "%needsUpdate%"=="1" (
    echo:
    call :PrintYellow "Файл hosts необходимо обновить"
    call :PrintYellow "Пожалуйста, вручную скопируйте содержимое загруженного файла в файл hosts"
    
    start notepad "%tempFile%"
    explorer /select,"%hostsFile%"
) else (
    call :PrintGreen "Файл hosts актуален"
    if exist "%tempFile%" del /f /q "%tempFile%"
)

echo:
pause
goto menu


:: RUN TESTS =============================
:run_tests
chcp 65001 >nul
cls

:: Require PowerShell 3.0+
powershell -NoProfile -Command "if ($PSVersionTable -and $PSVersionTable.PSVersion -and $PSVersionTable.PSVersion.Major -ge 3) { exit 0 } else { exit 1 }" >nul 2>&1
if %errorLevel% neq 0 (
    echo Требуется PowerShell 3.0 или более поздняя версия.
    echo Пожалуйста, обновите PowerShell и повторно запустите этот скрипт.
    echo.
    pause
    goto menu
)

color 06
echo Запущено тестирование вашей конфигурации в окне PowerShell...
echo.
start "" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\test zapret.ps1"
pause
goto menu


:: Utility functions

:PrintGreen
powershell -Command "Write-Host \"%~1\" -ForegroundColor Green"
exit /b

:PrintRed
powershell -Command "Write-Host \"%~1\" -ForegroundColor Red"
exit /b

:PrintYellow
powershell -Command "Write-Host \"%~1\" -ForegroundColor Yellow"
exit /b

:check_command
where %1 >nul 2>&1
if %errorLevel% neq 0 (
    echo [ОШИБКА] %1 не найдено в PATH
    echo Исправьте переменную PATH, следуя инструкциям, указанным здесь https://github.com/Flowseal/zapret-discord-youtube/issues/7490
    pause
    exit /b 1
)
exit /b 0

:check_extracted
set "extracted=1"

if not exist "%~dp0bin\" set "extracted=0"

if "%extracted%"=="0" (
    color 06
    echo Zapret необходимо извлечь из архива, перед началом работы, иначе папка bin не будет обнаружена и возникнет ошибка
    pause
    exit
)
exit /b 0
