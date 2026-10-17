@echo off
rem Builds the game file to share: build\windows\Rotsworn.exe and build\Rotsworn.zip.
rem Needs Godot's Windows export templates (Editor > Manage Export Templates).
rem Online, everyone must play the same build: send the new zip after every change.
rem This is a release export: the dev command-line switches (--autoplay, --tuning ...) are off in it.
setlocal
if "%GODOT%"=="" set "GODOT=C:\Users\Drago\Godot\Godot_v4.7.2-stable_win64_console.exe"
cd /d "%~dp0"
if not exist build\windows mkdir build\windows
rem Remove the old results first, so a failed export can never hand out a stale file.
if exist build\windows\Rotsworn.exe del /f /q build\windows\Rotsworn.exe
if exist build\Rotsworn.zip del /f /q build\Rotsworn.zip
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --headless --path . --export-release "Windows" build\windows\Rotsworn.exe > build\export.log 2>&1
if errorlevel 1 goto failed
if not exist build\windows\Rotsworn.exe goto failed
findstr /C:"SCRIPT ERROR" /C:"Parse Error" /C:"ERROR:" build\export.log >nul && goto failed
powershell -NoProfile -Command "Compress-Archive -Path build\windows\Rotsworn.exe -DestinationPath build\Rotsworn.zip -Force"
if errorlevel 1 goto failed
if not exist build\Rotsworn.zip goto failed
echo Done: build\Rotsworn.zip
dir build\windows\Rotsworn.exe | findstr /C:"Rotsworn.exe"
if not "%1"=="--no-pause" pause
exit /b 0

:failed
echo BUILD FAILED. See build\export.log. Are the export templates installed?
if exist build\windows\Rotsworn.exe del /f /q build\windows\Rotsworn.exe
if exist build\Rotsworn.zip del /f /q build\Rotsworn.zip
if not "%1"=="--no-pause" pause
exit /b 1
