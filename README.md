# Dotfiles

Personal dotfiles and initial-setup recipes for my Arch Linux (primary) and
Windows workstations. The same repository drives both platforms — only the
bootstrap scripts differ.

# Prerequisites

## Github SSH key
```bash
ssh-keygen -t ed25519 -C "ptquang2000@gmail.com"
eval "$(ssh-agent -s)"
ssh-add ${HOME}/.ssh/id_ed25519
cat ${HOME}/.ssh/id_ed25519.pub
```

## Git global config
```bash
git config --global user.email "ptquang2000@gmail.com"
git config --global user.name "quang.phan"
```

## Clone and update submodules
```bash
git submodule update --init --recursive
```

# Usage

Both platforms are driven from this same repository; only the bootstrap
scripts differ. On Windows, run **setup** first (prerequisites + symlinks),
then **install** (packages). On Linux, run **install** first (system
packages), then **setup** (symlinks into user-config locations).

## Windows

Requires PowerShell 5.1+. **No administrator privileges needed** for either
script — Scoop is installed per-user and `setup.ps1` uses directory
junctions (no symlink privilege required).

**Fresh machine (one-liner):**

Downloads and runs `setup.ps1` directly from GitHub, which installs Scoop +
git and then recursively clones this repository into `%USERPROFILE%\.dotfiles`
before linking configs. **No administrator privileges needed.**

```powershell
irm https://raw.githubusercontent.com/ptquang2000/.dotfiles/master/setup.ps1 | iex
```

If script execution is blocked by policy, use a one-shot bypass (still no
admin required):

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/ptquang2000/.dotfiles/master/setup.ps1 | iex"
```

After `setup.ps1` finishes, `cd` into the cloned repo and run `install.ps1`
to install packages:

```powershell
cd $env:USERPROFILE\.dotfiles
.\install.ps1
```

**If the repo is already cloned:**

```powershell
# 1. Install Scoop + git, and link powershell\, nvim-init\, and psmux\ into
#    their expected Windows locations (Documents\PowerShell,
#    %LOCALAPPDATA%\nvim, %USERPROFILE%\.config\psmux).
.\setup.ps1

# 2. Install every package declared in packages\scoop.json (via `scoop import`).
.\install.ps1
```

If script execution is blocked by policy, either allow it once per user:

```powershell
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

or invoke each script with a one-shot bypass (no admin, no persistent change):

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

## Linux

Arch Linux only. This repo is for personal use, so there is no distro
detection, no AUR-helper selection, and no fallback for other
distributions — `install.sh` assumes pacman + yay.

```bash
# Make the scripts executable (first time only)
chmod +x install.sh setup.sh

# 1. Install system packages (pacman + AUR via yay + cargo crates),
#    install the SDDM theme, configure default apps (zsh shell, zathura
#    for PDFs), and run waydroid post-install (init GAPPS, enable
#    container, install libndk + libhoudini). Requires sudo.
./install.sh

# 2. Preview what setup.sh would link (no filesystem changes)
./setup.sh --dry-run

# 3. Link configs into ~/.config, $HOME, and /etc (sudo prompted for
#    /etc/sddm.conf.d and /etc/systemd/resolved.conf.d). Idempotent: safe
#    to re-run. Any pre-existing non-symlink targets are backed up to
#    <path>.bak.<timestamp> before being replaced.
./setup.sh
```

# Post-install (Linux)

## Enable services
```bash
# slow boot
systemctl enable --now reflector.service
# use this instead
sudo systemctl enable --now reflector.timer

sudo timedatectl set-timezone Asia/Bangkok

# require graphical-session???
systemctl --user enable --now waybar.service

systemctl enable --now systemd-resolved
sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

## systemd-boot — dual boot with Windows

If Windows is installed on a **separate EFI System Partition** from Linux,
systemd-boot's auto-detected "Windows Boot Manager" entry often fails to boot
because it does not pass the BCD (Boot Configuration Database) path to the
Windows bootloader.

A helper script is included in this repo:

```bash
# Copy bootmgfw.efi + BCD to the systemd-boot ESP and create a loader entry
sudo ./bin/add-windows-entry
```

Reboot — a **Windows** entry will appear in the systemd-boot menu.

## Manual steps

The only step `install.sh` cannot automate is the waydroid certification,
which requires a Google Services Framework ID retrieved through a browser
running inside the waydroid session. After launching waydroid and
signing in via a browser, run:

```bash
sudo waydroid-extras certified
```

# TODO
- If there is no sound from videos on x or fb, installing vlc-plugin-ffmpeg might help (https://bbs.archlinux.org/viewtopic.php?id=306853)
