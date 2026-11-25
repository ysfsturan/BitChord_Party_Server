@echo off
title BitChord Parti Sunucusu
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0baslat.ps1"
echo.
echo Pencere kapaniyor...
%SystemRoot%\System32\timeout.exe /t 3 >nul 2>&1
if errorlevel 1 ping -n 4 127.0.0.1 >nul
