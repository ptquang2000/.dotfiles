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

`setup.sh` now enables reflector, sets the timezone, configures systemd-resolved
with a stub symlink, sets per-interface DNS (if an active interface is found),
enables libvirt sockets, adds `$USER` to the `libvirt` group, starts the default
libvirt network and connects Cloudflare WARP (`mode warp`). To verify after
boot:

```bash
resolvectl status   # Global must stay empty; active interface shows your resolvers
warp-cli status
warp-cli dns stats
warp-cli dns default-fallbacks
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
