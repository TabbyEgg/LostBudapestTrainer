@echo off
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "lbn_install_exit=%errorlevel%"
if "%~1"=="" pause
exit /b %lbn_install_exit%
