@echo off
setlocal enabledelayedexpansion

call :NewJunction "%~dp0powershell" "%HOMEPATH%\Documents\PowerShell"
call :NewJunction "%~dp0nvim-init" "%LOCALAPPDATA%\nvim"
call :NewJunction "%~dp0psmux" "%HOMEPATH%\.config\psmux"

pause
endlocal
exit /b 0

:NewJunction
:: %~1 = Source, %~2 = Target
set "SOURCE=%~1"
set "TARGET=%~2"

:: Remove trailing backslash from source if present
if "!SOURCE:~-1!"=="\" set "SOURCE=!SOURCE:~0,-1!"

:: Check source exists
if not exist "!SOURCE!\" (
    echo WARNING: Source directory does not exist, skipping: !SOURCE!
    exit /b 0
)

:: Resolve source to full path
for %%I in ("!SOURCE!") do set "SOURCE_FULL=%%~fI"

:: Check if target exists
if not exist "!TARGET!" goto :CreateJunction

:: Determine if target is a junction/symlink (check parent listing)
set "IS_JUNCTION=0"
for %%T in ("!TARGET!") do (
    set "TARGET_NAME=%%~nxT"
    set "TARGET_PARENT=%%~dpT"
)
if "!TARGET_PARENT:~-1!"=="\" set "TARGET_PARENT=!TARGET_PARENT:~0,-1!"

:: Use /al /b for bare name listing, findstr /x /i for exact case-insensitive match
for /f "usebackq" %%L in (`dir "!TARGET_PARENT!" /al /b 2^>nul ^| findstr /x /i "!TARGET_NAME!"`) do (
    set "IS_JUNCTION=1"
)

if "!IS_JUNCTION!"=="0" (
    echo Removing existing directory: !TARGET!
    rmdir /s /q "!TARGET!"
    goto :CreateJunction
)

:: Junction exists — verify it points to the correct source using a marker file
set "MARKER=.setup_bat_check_%RANDOM%%RANDOM%"
echo.>"!SOURCE_FULL!\!MARKER!"
if exist "!TARGET!\!MARKER!" (
    del "!SOURCE_FULL!\!MARKER!"
    echo Junction already correct: !TARGET! -^> !SOURCE_FULL!
    exit /b 0
)
del "!SOURCE_FULL!\!MARKER!" 2>nul

:: Junction points to wrong target
echo Removing existing junction/symlink: !TARGET!
rmdir "!TARGET!"

:CreateJunction
:: Ensure parent directory exists
for %%T in ("!TARGET!") do set "PARENT_DIR=%%~dpT"
if not exist "!PARENT_DIR!" mkdir "!PARENT_DIR!"

echo Creating junction: !TARGET! -^> !SOURCE_FULL!
mklink /j "!TARGET!" "!SOURCE_FULL!"
exit /b 0
