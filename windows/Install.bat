@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fisch-hub.ps1" %*
echo.
if "%~1"=="" pause
