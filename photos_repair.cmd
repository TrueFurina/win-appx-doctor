@echo off
cd /d "%~dp0"
if "[%1]" == "[49127c4b-02dc-482e-ac4f-ec4d659b7547]" goto :START
REG QUERY HKU\S-1-5-19\Environment >NUL 2>&1 && goto :START
set command="""%~f0""" 49127c4b-02dc-482e-ac4f-ec4d659b7547
SETLOCAL ENABLEDELAYEDEXPANSION
set "command=!command:'=''!"
powershell -NoProfile Start-Process -FilePath '%COMSPEC%' -ArgumentList '/c """!command!"""' -Verb RunAs 2>NUL
IF %ERRORLEVEL% GTR 0 ( echo This script needs administrator. & pause )
goto :EOF

:START
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0photos_repair.ps1"
