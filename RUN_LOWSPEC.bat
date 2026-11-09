@echo off
chcp 65001 >nul
cd /d "%~dp0"
set DRONE_QUALITY=lowspec
echo Starting Nebesnyi Horyzont - LOWSPEC test...
"%~dp0Godot_v4.6.1-stable_win64.exe" --path "%~dp0."
