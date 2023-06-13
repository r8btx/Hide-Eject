@echo off

::Attain necessary permission
call :elevate || exit /b 1

::Start main-----------------------------------------------------------------------------------------------------::
::PowerShell command chaining used "command1 | &{command2}" because semicolon is used as a Windows Terminal syntax

set "filePath='%~dp0\InteractiveLayer.ps1'"
set "command=Set-ExecutionPolicy Bypass -Scope Process^| ^&{^&%filePath%}"

if "%WT_SESSION%"=="" (
  wt.exe -p "Windows PowerShell" powershell.exe -Command %command% 2>nul && exit /b 0
  wtd.exe -p "Windows PowerShell" powershell.exe -Command %command% 2>nul && exit /b 0
  pause
)
powershell.exe -Command %command% 2>nul && exit /b 0

exit /b 1

::End main-------------------------------------------------------------------------------------------------------::

:elevate
whoami /groups |find " S-1-16-12288 " >nul 2>&1 && exit /b 0
echo/Admin privilege is required.
echo/Requesting administrative privilege...
powershell Start-Process '%~s0' -Verb runAs
if %ErrorLevel% neq 0 echo/User denied the request. && pause && exit /b 1
exit /b 2
