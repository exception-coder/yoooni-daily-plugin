@echo off
setlocal
:: --- PATH self-heal (key) ---
:: After freshly installing Git/Node/Claude WITHOUT a restart, this double-clicked
:: process inherits the OLD PATH and reports already-installed tools as "missing"
:: (claude is an npm-global command at %APPDATA%\npm; lands on PATH only after a new
:: terminal / re-login). Append the 3 tools' default install dirs to THIS process PATH
:: (only ones that actually exist) so the check does not raise false failures.
if exist "%ProgramFiles%\nodejs" set "PATH=%PATH%;%ProgramFiles%\nodejs"
if exist "%APPDATA%\npm" set "PATH=%PATH%;%APPDATA%\npm"
if exist "%ProgramFiles%\Git\cmd" set "PATH=%PATH%;%ProgramFiles%\Git\cmd"
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
