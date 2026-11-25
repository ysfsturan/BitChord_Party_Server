@echo off
title BitChord - Durdur
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0durdur.ps1"
%SystemRoot%\System32\timeout.exe /t 2 >nul 2>&1
if errorlevel 1 ping -n 3 127.0.0.1 >nul
