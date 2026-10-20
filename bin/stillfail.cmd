@echo off
rem still.fail's command on Windows: stillfail.ps1 beside it (Unix's is bin/stillfail).
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0stillfail.ps1" %*
exit /b %ERRORLEVEL%
