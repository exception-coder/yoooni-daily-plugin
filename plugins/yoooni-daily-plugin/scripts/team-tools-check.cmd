@echo off
setlocal
title Company Team Tools - One-click Check
echo ==================================================
echo   Company Team Tools - One-click Check
echo ==================================================
echo.
if not exist "%~dp0check-team-tools.ps1" (
  echo [ERROR] check-team-tools.ps1 NOT found next to this .cmd.
  echo Keep team-tools-check.cmd and check-team-tools.ps1 in the SAME folder.
  echo.
  pause
  exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0check-team-tools.ps1"
set "CHECK_EXIT=%ERRORLEVEL%"
echo.
if "%CHECK_EXIT%"=="0" (
  echo ==================================================
  echo Check finished. Review the Final Summary table above.
  echo In Claude Code, run /reload-plugins or restart the session.
  echo ==================================================
) else (
  echo ==================================================
  echo Check found blocking issues. Review the Final Summary table above.
  echo ==================================================
)
pause
exit /b %CHECK_EXIT%
