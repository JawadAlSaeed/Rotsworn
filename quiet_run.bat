@echo off
rem Starts the game in QUIET mode: the window opens on the second screen (else the only screen,
rem behind your other windows), never takes keyboard or mouse focus, and makes no sound.
rem For picture and bot runs while someone plays or works on the same PC. Everything you type
rem after the name goes to the game, for example:
rem   quiet_run.bat --shots=2 --screen=menu
rem   quiet_run.bat --autoplay --quit-on-end
rem The real project is never changed; see DESIGN.md 10 (quiet runs) and tools\quiet_run.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\quiet_run.ps1" %*
exit /b %ERRORLEVEL%
