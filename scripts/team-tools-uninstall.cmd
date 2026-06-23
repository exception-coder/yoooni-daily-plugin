@echo off
setlocal
title Company Team Tools - Uninstall
echo ==================================================
echo   Company Team Tools - One-click Uninstall
echo ==================================================
echo.
echo Removes ONLY company items:
echo   plugins: team-standards / project-coding-profiles / yoooni-daily-plugin
echo   MCP    : domain-knowledge / cross-topology
echo   task   : YoooniTeamToolsAutoUpdate
echo Source repos are KEPT. frontend-design / claude.ai are NOT touched.
echo.
echo Press any key to CONFIRM uninstall, or close this window to cancel.
pause >nul
echo.
echo Downloading and running the uninstaller from Gitee...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { irm 'https://gitee.com/wyoooni/yoooni-daily-plugin/raw/master/scripts/uninstall-team-tools.ps1' -OutFile '%TEMP%\yoooni-uninstall.ps1'; & '%TEMP%\yoooni-uninstall.ps1' } catch { Write-Host ('Download/run failed: ' + $_.Exception.Message) -ForegroundColor Red }"
echo.
echo ==================================================
echo Done. Restart Claude Code session for full effect.
echo ==================================================
pause
