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
if not exist "%~dp0uninstall-team-tools.ps1" (
  echo [ERROR] uninstall-team-tools.ps1 NOT found next to this .cmd.
  echo Keep team-tools-uninstall.cmd and uninstall-team-tools.ps1 in the SAME folder.
  echo.
  pause
  exit /b 1
)
echo Press any key to CONFIRM uninstall, or close this window to cancel.
pause >nul
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall-team-tools.ps1"
echo.
echo ==================================================
echo Done. Restart Claude Code session for full effect.
echo ==================================================
pause
