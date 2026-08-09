# Dotfiles

Personal dotfiles and initial-setup recipes for my Arch Linux (primary) and
Windows workstations. The same repository drives both platforms — only the
bootstrap scripts differ.

# Prerequisites

# Usage

## Windows

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://raw.githubusercontent.com/ptquang2000/.dotfiles/master/setup.ps1 | Invoke-Expression
```

## Linux

```bash
sudo pacman -S curl git
curl -fsSL https://raw.githubusercontent.com/ptquang2000/.dotfiles/master/setup.sh | bash
```

The one-liner clones the repo to `$DOTFILES_DIR` (default `~/.dotfiles`,
override with an env var) and provisions from there.

## WSL

```bash
sudo pacman -S curl git
curl -fsSL https://raw.githubusercontent.com/ptquang2000/.dotfiles/master/wsl.sh | bash
```

# Post-install (Linux)

## Enable services
```bash
sudo systemctl enable --now reflector.timer
sudo timedatectl set-timezone Asia/Bangkok

# require graphical-session???
systemctl --user enable --now waybar.service

systemctl enable --now systemd-resolved
sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

# libvirt, for virutils
sudo systemctl enable --now virtqemud.socket virtqemud-ro.socket \
	virtqemud-admin.socket virtnetworkd.socket virtstoraged.socket \
	virtnodedevd.socket virtsecretd.socket virtinterfaced.socket
sudo usermod -aG libvirt "$USER"
virsh --connect qemu:///system net-autostart default
virsh --connect qemu:///system net-start default
```

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


## systemd-boot — dual boot with Windows

```bash
# Copy bootmgfw.efi + BCD to the systemd-boot ESP and create a loader entry
sudo ./bin/add-windows-entry
```

## Manual steps

```bash
sudo waydroid-extras certified
```

# TODO
- If there is no sound from videos on x or fb, installing vlc-plugin-ffmpeg might help (https://bbs.archlinux.org/viewtopic.php?id=306853)
