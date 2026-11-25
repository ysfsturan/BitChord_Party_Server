@echo off
cd /d "%~dp0"
if not exist "run" mkdir "run"
start "" /b cmd /c "cloudflared.exe tunnel --url http://localhost:8000 --no-autoupdate 2>run\tunnel.log"
