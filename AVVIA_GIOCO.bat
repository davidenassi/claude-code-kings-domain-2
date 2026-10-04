@echo off
rem King's Domain - avvio del gioco (Windows). Doppio clic per giocare.
rem
rem   AVVIA_GIOCO.bat              avvia la Valle
rem   AVVIA_GIOCO.bat galleria     avvia la galleria degli asset
rem   AVVIA_GIOCO.bat benchmark    misura gli FPS sulle viste della Fase 1B
rem
rem Cerca Godot 4.7.2 da solo (variabile GODOT, file godot_path.txt, PATH, cartelle comuni). Se non lo trova,
rem o trova una versione sbagliata, chiede il percorso (basta trascinare il file .exe nella finestra) e lo
rem ricorda in godot_path.txt. Per cambiare Godot: cancellare godot_path.txt.
setlocal EnableExtensions
title King's Domain
cd /d "%~dp0"
set "GAME=%~dp0game"
set "GODOT_EXE="
set "ASKED="

if not exist "%GAME%\project.godot" (
    echo.
    echo   Non trovo la cartella "game" accanto a questo file.
    echo   AVVIA_GIOCO.bat deve stare nella cartella principale del gioco, insieme alla cartella "game".
    echo   Se hai scaricato lo zip, estrailo tutto prima di avviare.
    echo.
    pause
    exit /b 1
)

rem 1) variabile d'ambiente GODOT
if defined GODOT if exist "%GODOT%" set "GODOT_EXE=%GODOT%"

rem 2) percorso ricordato in godot_path.txt
if not defined GODOT_EXE if exist "%~dp0godot_path.txt" set /p GODOT_EXE=<"%~dp0godot_path.txt"
if defined GODOT_EXE if not exist "%GODOT_EXE%" set "GODOT_EXE="

rem 3) zip di Godot 4.7.x scaricato ed estratto (cartella del gioco, Download, Desktop, Documenti, Programmi, C:\Godot):
rem    prima la 4.7.2 esatta, poi qualsiasi 4.7
rem    (due righe separate: un "*" dentro la lista di un for verrebbe espanso sui file della cartella corrente)
set "DIRS="%~dp0." "%USERPROFILE%\Downloads" "%USERPROFILE%\Desktop" "%USERPROFILE%\Documents" "%LOCALAPPDATA%\Programs" "%ProgramFiles%\Godot" "C:\Godot""
if not defined GODOT_EXE for %%d in (%DIRS%) do if not defined GODOT_EXE if exist "%%~d" for /f "delims=" %%p in ('dir /b /s /o-n "%%~d\Godot_v4.7.2-stable_win64.exe" 2^>nul') do if not defined GODOT_EXE set "GODOT_EXE=%%p"
if not defined GODOT_EXE for %%d in (%DIRS%) do if not defined GODOT_EXE if exist "%%~d" for /f "delims=" %%p in ('dir /b /s /o-n "%%~d\Godot_v4.7*_win64.exe" 2^>nul ^| findstr /v /i "_console"') do if not defined GODOT_EXE set "GODOT_EXE=%%p"

rem 4) nel PATH e Steam (la versione si controlla dopo)
if not defined GODOT_EXE for %%c in (godot.exe godot4.exe) do if not defined GODOT_EXE for /f "delims=" %%p in ('where %%c 2^>nul') do if not defined GODOT_EXE set "GODOT_EXE=%%p"
if not defined GODOT_EXE if exist "%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" set "GODOT_EXE=%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

if not defined GODOT_EXE goto :ask
goto :check

:ask
echo.
if defined ASKED echo   Il file indicato non e' Godot 4.7.2.
echo   Serve Godot 4.7.2 ^(Windows, versione standard - non .NET^).
echo   1. Scaricalo da https://godotengine.org/download/archive/  -  cerca "4.7.2", scarica "Windows 64 bit"
echo   2. Estrai lo zip in una cartella qualsiasi
echo   3. Trascina in questa finestra il file Godot_v4.7.2-stable_win64.exe e premi Invio
echo.
set "GODOT_EXE="
set /p "GODOT_EXE=  Percorso di Godot: "
if not defined GODOT_EXE goto :nopath
set GODOT_EXE=%GODOT_EXE:"=%
rem (niente blocchi tra parentesi con il percorso dentro: "Program Files (x86)" li spezzerebbe)
if exist "%GODOT_EXE%" goto :save
:nopath
echo   File non trovato: "%GODOT_EXE%"
pause
exit /b 1
:save
>"%~dp0godot_path.txt" echo %GODOT_EXE%
set "ASKED=1"

:check
rem la versione "_console" (nello stesso zip) scrive i messaggi nella finestra: la uso per versione e importazione
set "GODOT_CLI=%GODOT_EXE%"
if exist "%GODOT_EXE:~0,-4%_console.exe" set "GODOT_CLI=%GODOT_EXE:~0,-4%_console.exe"
echo Godot: "%GODOT_EXE%"

rem versione: da --version, altrimenti dal nome del file (Godot_v4.7.2-stable_win64.exe)
set "VER="
"%GODOT_CLI%" --version >"%TEMP%\kd_godot_version.txt" 2>nul
if exist "%TEMP%\kd_godot_version.txt" set /p VER=<"%TEMP%\kd_godot_version.txt"
for %%f in ("%GODOT_EXE%") do set "GNAME=%%~nf"
if not defined VER echo %GNAME%| findstr /i /c:"_v4.7" >nul && set "VER=4.7 - dal nome del file"
if not defined VER for /f "tokens=2 delims=_v-" %%v in ("%GNAME%") do set "VER=%%v"
if not defined VER goto :unknown_version
echo Versione: %VER%
echo %VER%| findstr /b /c:"4.7" >nul && goto :import
echo.
echo   Questo Godot e' la versione %VER%: il gioco richiede la 4.7.2.
if exist "%~dp0godot_path.txt" del "%~dp0godot_path.txt"
set "ASKED=1"
goto :ask

:unknown_version
echo Attenzione: non riesco a leggere la versione di questo Godot ^(serve 4.7.2^). Provo comunque.

:import
rem risorse: Godot le importa alla prima apertura e dopo ogni aggiornamento dei file (poi bastano pochi secondi)
if exist "%GAME%\.godot\imported" (
    echo Controllo delle risorse...
) else (
    echo Prima apertura: preparazione delle risorse ^(texture, sprite, terreno^). Puo' richiedere alcuni minuti...
)
"%GODOT_CLI%" --headless --path "%GAME%" --import >"%~dp0import_log.txt" 2>&1
set "IMPORT_CODE=%ERRORLEVEL%"
rem conta le risorse preparate: se ci sono, il gioco puo' partire anche se Godot ha segnalato avvisi
set "NIMP=0"
if exist "%GAME%\.godot\imported" for /f %%c in ('dir /b /a-d "%GAME%\.godot\imported" 2^>nul ^| find /c /v ""') do set "NIMP=%%c"
if %NIMP% GEQ 900 goto :run
echo.
echo   Preparazione delle risorse non riuscita ^(codice %IMPORT_CODE%, risorse pronte: %NIMP% su circa 1100^).
echo   Ultime righe di import_log.txt:
echo   ----------------------------------------------------------------
powershell -NoProfile -Command "Get-Content -LiteralPath '%~dp0import_log.txt' -Tail 25" 2>nul || type "%~dp0import_log.txt"
echo   ----------------------------------------------------------------
echo   Fai uno screenshot di questa finestra e mandalo a Claude.
echo.
pause
exit /b 1

:run
set "ARGS="
if /i "%~1"=="galleria" set "ARGS=res://gallery/gallery.tscn"
if /i "%~1"=="benchmark" set "ARGS=-- --benchmark --views=res://data/capture/slice_views.json"

echo Avvio di King's Domain...
echo Comandi: rotellina = zoom, WASD / frecce = spostamento, tasto destro trascinato = spostamento, F3 = prestazioni
start "King's Domain" "%GODOT_EXE%" --path "%GAME%" %ARGS%
endlocal
