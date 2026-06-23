@echo off
setlocal
title Company Team Tools - One-click Install
echo ==================================================
echo   Company Team Tools - One-click Install
echo ==================================================
echo.
echo Requirements: Git (required); Node.js 18+ with npm; Claude CLI (recommended).
echo The installer below lists any missing item with its install link.
echo.
if not exist "%~dp0bootstrap-install.ps1" (
  echo [ERROR] bootstrap-install.ps1 NOT found next to this .cmd.
  echo Keep team-tools-install.cmd and bootstrap-install.ps1 in the SAME folder.
  echo.
  pause
  exit /b 1
)
where git >nul 2>nul
if errorlevel 1 echo [WARN] Git not found -- install first: https://git-scm.com/download/win
echo.
echo Running installer (clones repos from Gitee via git; may prompt for Gitee login on first run)...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bootstrap-install.ps1"
echo.
echo ==================================================
echo Done. Restart Claude Code session to activate plugins.
echo ==================================================
pause
