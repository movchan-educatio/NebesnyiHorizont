@echo off
setlocal
cd /d "%~dp0"
start "" "%~dp0Godot_v4.6.1-stable_win64.exe" --path . res://test/destruction_gallery.tscn
endlocal
