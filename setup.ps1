#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot -and $MyInvocation.MyCommand.Path) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }

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

function Install-Scoop {
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-Host "Scoop already installed at: $((Get-Command scoop).Source)"
        return
    }
    Write-Host "Installing Scoop (non-admin)..."
    $current = Get-ExecutionPolicy -Scope CurrentUser
    if ($current -notin 'RemoteSigned', 'Unrestricted', 'Bypass') {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    }
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    Refresh-Path
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        throw "Scoop is still not available on PATH after installation. Open a new shell and re-run."
    }
}

function Install-Git {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Write-Host "Git already available at: $((Get-Command git).Source)"
        return
    }
    Write-Host "Installing git via scoop..."
    scoop install git
    Refresh-Path
}

function Test-IsJunction {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $item = Get-Item -LiteralPath $Path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Get-JunctionTarget {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    return ($item.Target | Select-Object -First 1)
}

function New-DotfilesJunction {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Target
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        Write-Warning "Source directory does not exist, skipping: $Source"
        return
    }
    $sourceFull = (Resolve-Path -LiteralPath $Source).ProviderPath.TrimEnd('\')

    if (Test-Path -LiteralPath $Target) {
        if (Test-IsJunction -Path $Target) {
            $existing = (Get-JunctionTarget -Path $Target)
            if ($existing) { $existing = $existing.TrimEnd('\') }
            if ($existing -and ($existing -ieq $sourceFull)) {
                Write-Host "Junction already correct: $Target -> $sourceFull"
                return
            }
            Write-Host "Removing existing junction/symlink: $Target"
            & cmd /c rmdir """$Target""" | Out-Null
        } else {
            Write-Host "Removing existing directory: $Target"
            Remove-Item -LiteralPath $Target -Recurse -Force
        }
    }

    $parent = Split-Path -Parent $Target
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Write-Host "Creating junction: $Target -> $sourceFull"
    New-Item -ItemType Junction -Path $Target -Value $sourceFull | Out-Null
}

function Test-InDotfilesRepo {
    param([string]$Path)
    if (-not $Path) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $markers = @('setup.ps1', 'packages\scoop.json')
    foreach ($m in $markers) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $m))) { return $false }
    }
    return $true
}

function Sync-Submodules {
    param([Parameter(Mandatory)][string]$RepoRoot)
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot '.gitmodules'))) { return }
    Write-Host "Updating git submodules (recursive)..."
    Push-Location $RepoRoot
    try {
        & git submodule update --init --recursive
        if ($LASTEXITCODE -ne 0) { throw "git submodule update failed with exit code $LASTEXITCODE." }
    } finally {
        Pop-Location
    }
}

Write-Section "Install Scoop"
Install-Scoop

Write-Section "Install Git"
Install-Git

Write-Section "Ensure dotfiles repository"
$RepoUrl = 'https://github.com/ptquang2000/.dotfiles.git'
$DotfilesTarget = Join-Path $env:USERPROFILE '.dotfiles'

if (Test-InDotfilesRepo -Path $ScriptRoot) {
    Write-Host "Running from inside the dotfiles repo: $ScriptRoot"
    Sync-Submodules -RepoRoot $ScriptRoot
} else {
    if ((Test-Path -LiteralPath (Join-Path $DotfilesTarget '.git')) -or (Test-InDotfilesRepo -Path $DotfilesTarget)) {
        Write-Host "Existing dotfiles clone found at: $DotfilesTarget (skipping clone)"
        Sync-Submodules -RepoRoot $DotfilesTarget
    } else {
        if (Test-Path -LiteralPath $DotfilesTarget) {
            throw "Target path exists but is not a dotfiles clone: $DotfilesTarget"
        }
        Write-Host "Cloning $RepoUrl -> $DotfilesTarget"
        & git clone --recurse-submodules $RepoUrl $DotfilesTarget
        if ($LASTEXITCODE -ne 0) { throw "git clone failed with exit code $LASTEXITCODE." }
    }

    $clonedSetup = Join-Path $DotfilesTarget 'setup.ps1'
    if (-not (Test-Path -LiteralPath $clonedSetup)) {
        throw "Cloned setup.ps1 not found at: $clonedSetup"
    }
    Write-Host "Re-invoking cloned setup.ps1 at: $clonedSetup"
    & $clonedSetup
    return
}

Write-Section "Link dotfiles"
$documents = [Environment]::GetFolderPath('MyDocuments')
$junctions = @(
    @{ Source = Join-Path $ScriptRoot 'powershell'; Target = Join-Path $documents       'PowerShell' }
    @{ Source = Join-Path $ScriptRoot 'nvim-init';  Target = Join-Path $env:LOCALAPPDATA 'nvim'	}
    @{ Source = Join-Path $ScriptRoot 'psmux';      Target = Join-Path $env:USERPROFILE  '.config\psmux'	}
)
foreach ($j in $junctions) {
    New-DotfilesJunction -Source $j.Source -Target $j.Target
}

Write-Section "Import scoop packages"
$ScoopJson = Join-Path $ScriptRoot 'packages\scoop.json'
if (-not (Test-Path -LiteralPath $ScoopJson)) {
    throw "scoop.json not found next to this script at: $ScoopJson"
}
Refresh-Path
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    throw "scoop is not available on PATH. Re-run this script in a fresh shell."
}
Write-Host "Importing packages from: $ScoopJson"
scoop import $ScoopJson
if ($LASTEXITCODE -ne 0) {
    throw "scoop import failed with exit code $LASTEXITCODE."
}

Write-Section "Import winget packages"
$WingetJson = Join-Path $ScriptRoot 'packages\winget.json'
if (-not (Test-Path -LiteralPath $WingetJson)) {
    throw "winget.json not found next to this script at: $WingetJson"
}
Refresh-Path
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw "winget is not available on PATH. Re-run this script in a fresh shell."
}
Write-Host "Importing packages from: $WingetJson"
winget import -i $WingetJson --accept-package-agreements --accept-source-agreements --disable-interactivity
if ($LASTEXITCODE -ne 0) {
    throw "winget import failed with exit code $LASTEXITCODE."
}

'prefs_user.config', 'keys_user.config' | ForEach-Object { New-Item -ItemType HardLink -Force -Path (Join-Path (scoop prefix sioyek) $_) -Value (Join-Path $ScriptRoot "sioyek\$_") | Out-Null }

Write-Host ""
Write-Host "Setup complete." -ForegroundColor Green
