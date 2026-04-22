@echo off
REM =====================================================================
REM  install.bat
REM
REM  SYNOPSIS
REM    Bootstraps Scoop and installs all packages declared in the sibling
REM    packages\scoop.json.
REM
REM  DESCRIPTION
REM    - Installs Scoop (non-admin) if it is not already available on PATH.
REM    - Refreshes the current session's PATH so scoop becomes callable
REM      without restarting the shell.
REM    - Ensures git is installed (required by scoop buckets).
REM    - Invokes `scoop import` against the scoop.json that lives next to
REM      this script, letting scoop handle bucket registration and app
REM      installation.
REM
REM  USAGE
REM    install.bat
REM
REM  NOTES
REM    Requires PowerShell 5.1+. Does NOT require administrator privileges.
REM =====================================================================

setlocal EnableDelayedExpansion

set "SCOOP_JSON=%~dp0packages\scoop.json"

REM Detect double-click launch (transient cmd host) so we can pause at end.
set "DOUBLE_CLICKED=0"
echo %cmdcmdline% | findstr /i /c:"/c \"\"" >nul 2>&1
if not errorlevel 1 set "DOUBLE_CLICKED=1"

if not exist "%SCOOP_JSON%" (
    echo ERROR: scoop.json not found next to this script at: %SCOOP_JSON%
    set "EXITCODE=1"
    goto :end
)

REM --- Install Scoop if missing ---------------------------------------------
where scoop >nul 2>&1
if errorlevel 1 (
    echo Scoop not found. Installing Scoop ^(non-admin^)...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "try { if ((Get-ExecutionPolicy -Scope CurrentUser) -notin 'RemoteSigned','Unrestricted','Bypass') { Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force } } catch { Write-Warning $_.Exception.Message }; & ([scriptblock]::Create((Invoke-RestMethod get.scoop.sh))) -RunAsAdmin:$false"
    if errorlevel 1 (
        echo ERROR: Scoop installation failed with exit code !ERRORLEVEL!.
        set "EXITCODE=!ERRORLEVEL!"
        goto :end
    )
) else (
    for /f "delims=" %%S in ('where scoop') do echo Scoop already installed at: %%S
)

REM --- Refresh PATH from registry (Machine + User) --------------------------
for /f "usebackq tokens=* delims=" %%P in (`powershell -NoProfile -Command "$m=[Environment]::GetEnvironmentVariable('Path','Machine'); $u=[Environment]::GetEnvironmentVariable('Path','User'); @($m,$u) -join ';'"`) do set "PATH=%%P"

where scoop >nul 2>&1
if errorlevel 1 (
    echo ERROR: Scoop is still not available on PATH after installation.
    echo Open a new shell and re-run.
    set "EXITCODE=1"
    goto :end
)

REM --- Ensure git is installed (buckets require it) -------------------------
where git >nul 2>&1
if errorlevel 1 (
    echo Git not found. Installing git via scoop...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "scoop install git"
    if errorlevel 1 (
        echo ERROR: scoop install git failed with exit code !ERRORLEVEL!.
        set "EXITCODE=!ERRORLEVEL!"
        goto :end
    )
    for /f "usebackq tokens=* delims=" %%P in (`powershell -NoProfile -Command "$m=[Environment]::GetEnvironmentVariable('Path','Machine'); $u=[Environment]::GetEnvironmentVariable('Path','User'); @($m,$u) -join ';'"`) do set "PATH=%%P"
) else (
    for /f "delims=" %%G in ('where git') do echo Git already available at: %%G
)

REM --- Run scoop import -----------------------------------------------------
echo Importing packages from: %SCOOP_JSON%
powershell -NoProfile -ExecutionPolicy Bypass -Command "scoop import '%SCOOP_JSON%'"
if errorlevel 1 (
    echo ERROR: scoop import failed with exit code !ERRORLEVEL!.
    set "EXITCODE=!ERRORLEVEL!"
    goto :end
)

echo.
echo All packages imported successfully from scoop.json.
set "EXITCODE=0"

:end
if "%DOUBLE_CLICKED%"=="1" (
    echo.
    pause
)
endlocal & exit /b %EXITCODE%
