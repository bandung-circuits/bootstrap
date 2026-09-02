@echo off
rem Start DeepSeek Harness (dsh) Web UI in this workspace.
cd /d "%~dp0"
set "DSH_HOME=%CD%\.dsh"

rem Load machine-local secrets (dsh refuses launch-control names in its own .env
rem files, so they live in secrets.env and we export them here).
if exist "%DSH_HOME%\secrets.env" (
  for /f "usebackq tokens=1,* delims==" %%a in ("%DSH_HOME%\secrets.env") do (
    if not "%%a"=="" set "%%a=%%b"
  )
)
where dsh >nul 2>&1
if errorlevel 1 (
  echo dsh is not installed. Re-run the installer, then try again.
  exit /b 1
)
echo Starting DeepSeek Harness ... (browser opens at http://127.0.0.1:3080)
echo Press Ctrl+C to stop.
dsh web %*