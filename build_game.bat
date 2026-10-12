@echo off
rem Builds the game file to share: build\windows\RottenLands.exe and build\RottenLands.zip.
rem Needs Godot's Windows export templates (Editor > Manage Export Templates).
rem Online, everyone must play the same build: send the new zip after every change.
setlocal
if "%GODOT%"=="" set "GODOT=C:\Users\Drago\Godot\Godot_v4.7.2-stable_win64_console.exe"
cd /d "%~dp0"
if not exist build\windows mkdir build\windows
"%GODOT%" --headless --path . --import >nul 2>&1
"%GODOT%" --headless --path . --export-release "Windows" build\windows\RottenLands.exe >nul 2>&1
if not exist build\windows\RottenLands.exe (
	echo Build failed. Are the export templates installed?
	if not "%1"=="--no-pause" pause
	exit /b 1
)
powershell -NoProfile -Command "Compress-Archive -Path build\windows\RottenLands.exe -DestinationPath build\RottenLands.zip -Force"
echo Done: build\RottenLands.zip
if not "%1"=="--no-pause" pause
