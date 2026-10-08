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
echo DISM online health probe > dism_check.log
date /t >> dism_check.log
time /t >> dism_check.log
echo === CheckHealth === >> dism_check.log
dism /Online /Cleanup-Image /CheckHealth >> dism_check.log 2>&1
echo === ScanHealth === >> dism_check.log
dism /Online /Cleanup-Image /ScanHealth >> dism_check.log 2>&1
echo === version === >> dism_check.log
dism /Online /English /Get-CurrentEdition >> dism_check.log 2>&1
echo === DONE === >> dism_check.log
