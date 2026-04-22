#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machine, $user) -join ';'
}

function Assert-Prerequisite {
    param(
        [Parameter(Mandatory)][string]$Name
    )
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "$Name is not available on PATH. Run setup.ps1 first to install prerequisites (scoop, git)."
    }
    Write-Host "$Name found at: $((Get-Command $Name).Source)"
}

Write-Section "Verify prerequisites"
Refresh-Path
Assert-Prerequisite -Name 'scoop'
Assert-Prerequisite -Name 'git'

$ScoopJson = Join-Path $ScriptRoot 'packages\scoop.json'
if (-not (Test-Path -LiteralPath $ScoopJson)) {
    throw "scoop.json not found next to this script at: $ScoopJson"
}

Write-Section "Import scoop packages"
Write-Host "Importing packages from: $ScoopJson"
scoop import $ScoopJson
if ($LASTEXITCODE -ne 0) {
    throw "scoop import failed with exit code $LASTEXITCODE."
}

Write-Host ""
Write-Host "All packages imported successfully from scoop.json." -ForegroundColor Green
