@echo off
chcp 65001 >nul
title FPV Stream Overlay
cd /d "%~dp0"

echo ============================================
echo  FPV Stream Overlay - Nebesnyi Horizont
echo ============================================
echo.
echo  Local URL for LIVE Studio (Link Source):
echo.
echo      http://127.0.0.1:8765/overlay.html
echo.
echo  Copy this URL into:
echo  LIVE Studio - Add source - Link
echo.
echo  Keep this window OPEN during the stream.
echo  Press Ctrl+C in this window to stop.
echo.

where python >nul 2>nul
if %errorlevel%==0 (
  python -m http.server 8765 --bind 127.0.0.1
) else (
  py -3 -m http.server 8765 --bind 127.0.0.1
)
pause
