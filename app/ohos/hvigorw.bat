@echo off
rem Resolve DevEco from DEVECO_HOME or tool/ohos.local.json.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0..\tool\hvigor.ps1" %*
exit /b %errorlevel%
