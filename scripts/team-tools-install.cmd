@echo off
setlocal
title Company Team Tools - One-click Install
echo ==================================================
echo   Company Team Tools - One-click Install (Gitee)
echo ==================================================
echo.
echo Requirements: Git (required) ; Node.js+npm (>=18) and Claude CLI (recommended).
echo The installer below lists any missing item with its install link.
echo.
where git >nul 2>nul
if errorlevel 1 echo [WARN] Git not found -- install first: https://git-scm.com/download/win
echo.
echo Downloading and running the installer from Gitee...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { irm 'https://gitee.com/wyoooni/yoooni-daily-plugin/raw/master/scripts/bootstrap-install.ps1' -OutFile '%TEMP%\yoooni-boot.ps1'; & '%TEMP%\yoooni-boot.ps1' } catch { Write-Host ('Download/run failed: ' + $_.Exception.Message) -ForegroundColor Red }"
echo.
echo ==================================================
echo Done. Restart Claude Code session to activate plugins.
echo ==================================================
pause
