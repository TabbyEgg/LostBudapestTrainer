@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1" %*
set "lbn_uninstall_exit=%errorlevel%"
if "%~1"=="" pause
exit /b %lbn_uninstall_exit%
