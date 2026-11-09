@echo off
setlocal
cd /d "%~dp0"
echo Classes: tank bmp apc truck sam heli shahed infantry
set /p K=Class: 
if "%K%"=="" set K=tank
set DESTR_CLASS=%K%
start "" "%~dp0Godot_v4.6.1-stable_win64.exe" --path . res://test/destruction_gallery.tscn
endlocal
