@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" %*
set "lbn_update_exit=%errorlevel%"
if "%~1"=="" pause
exit /b %lbn_update_exit%
