@echo off
rem King's Domain - avvio del gioco (Windows). Doppio clic per giocare.
rem
rem   AVVIA_GIOCO.bat              avvia la Valle
rem   AVVIA_GIOCO.bat galleria     avvia la galleria degli asset
rem   AVVIA_GIOCO.bat benchmark    misura gli FPS sulle viste della Fase 1B
rem
rem Cerca Godot 4.7.2 da solo (variabile GODOT, file godot_path.txt, PATH, cartelle comuni). Se non lo trova,
rem chiede il percorso (basta trascinare il file .exe nella finestra) e lo ricorda in godot_path.txt.
setlocal EnableExtensions
title King's Domain
cd /d "%~dp0"
set "GAME=%~dp0game"
set "GODOT_EXE="

rem 1) variabile d'ambiente GODOT
if defined GODOT if exist "%GODOT%" set "GODOT_EXE=%GODOT%"

rem 2) percorso ricordato in godot_path.txt
if not defined GODOT_EXE if exist "%~dp0godot_path.txt" set /p GODOT_EXE=<"%~dp0godot_path.txt"
if defined GODOT_EXE if not exist "%GODOT_EXE%" set "GODOT_EXE="

rem 3) nel PATH
if not defined GODOT_EXE for %%c in (godot.exe godot4.exe) do if not defined GODOT_EXE for /f "delims=" %%p in ('where %%c 2^>nul') do if not defined GODOT_EXE set "GODOT_EXE=%%p"

rem 4) Steam
if not defined GODOT_EXE if exist "%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" set "GODOT_EXE=%ProgramFiles(x86)%\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

rem 5) zip scaricato ed estratto: cartella del gioco, Download, Desktop, Documenti, Programmi, C:\Godot
if not defined GODOT_EXE for %%d in ("%~dp0." "%USERPROFILE%\Downloads" "%USERPROFILE%\Desktop" "%USERPROFILE%\Documents" "%LOCALAPPDATA%\Programs" "%ProgramFiles%\Godot" "C:\Godot") do if not defined GODOT_EXE if exist "%%~d" for /f "delims=" %%p in ('dir /b /s /o-n "%%~d\Godot_v4*_win64.exe" 2^>nul ^| findstr /v /i "_console"') do if not defined GODOT_EXE set "GODOT_EXE=%%p"

rem 6) chiedo all'utente
if defined GODOT_EXE goto :found
echo.
echo   Non trovo Godot 4.7.2 su questo computer.
echo   1. Scaricalo da https://godotengine.org/download/archive/   (versione 4.7.2, Windows, standard - non .NET)
echo   2. Estrai lo zip in una cartella qualsiasi
echo   3. Trascina in questa finestra il file Godot_v4.7.2-stable_win64.exe e premi Invio
echo.
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
echo   Percorso salvato in godot_path.txt

:found
rem la versione "_console" (nello stesso zip) mostra i messaggi nella finestra: la uso per versione e importazione
set "GODOT_CLI=%GODOT_EXE%"
if exist "%GODOT_EXE:~0,-4%_console.exe" set "GODOT_CLI=%GODOT_EXE:~0,-4%_console.exe"

set "VER="
"%GODOT_CLI%" --version >"%TEMP%\kd_godot_version.txt" 2>nul
if exist "%TEMP%\kd_godot_version.txt" set /p VER=<"%TEMP%\kd_godot_version.txt"
if not defined VER (
    echo Attenzione: non riesco a leggere la versione di Godot ^(serve 4.7.2^).
) else (
    echo %VER% | findstr /b "4.7" >nul || echo Attenzione: Godot %VER% - il progetto e' fatto per Godot 4.7.2. Potrebbe non funzionare.
)

rem risorse: Godot le importa alla prima apertura e dopo ogni aggiornamento dei file (poi bastano pochi secondi)
if exist "%GAME%\.godot\imported" (
    echo Controllo delle risorse...
) else (
    echo Prima apertura: preparazione delle risorse ^(texture, sprite, terreno^). Puo' richiedere alcuni minuti...
)
"%GODOT_CLI%" --headless --path "%GAME%" --import >"%~dp0.import_log.txt" 2>&1
if errorlevel 1 (
    echo Errore durante l'importazione. Dettagli in .import_log.txt
    pause
    exit /b 1
)

set "ARGS="
if /i "%~1"=="galleria" set "ARGS=res://gallery/gallery.tscn"
if /i "%~1"=="benchmark" set "ARGS=-- --benchmark --views=res://data/capture/slice_views.json"

echo Avvio di King's Domain...
echo Comandi: rotellina = zoom, WASD / frecce = spostamento, tasto destro trascinato = spostamento, F3 = prestazioni
start "King's Domain" "%GODOT_EXE%" --path "%GAME%" %ARGS%
endlocal
