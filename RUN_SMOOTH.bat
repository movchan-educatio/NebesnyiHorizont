@echo off
chcp 65001 >nul
cd /d "%~dp0"
set DRONE_QUALITY=smooth
echo Starting Nebesnyi Horyzont - SMOOTH 60 comparison...
"%~dp0Godot_v4.6.1-stable_win64.exe" --path "%~dp0."
