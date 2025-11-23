Archlinux initial setup

# Update repo
```bash
git submodule update --init --recursive
```

# Install packages
```bash
pacman -S --noconfirm - < packages/pacman

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
yay -S --noconfirm - < packages/yay

cargo install - < packages/cargo
```

# Custom config
```bash
# Shell
rm -rf ${HOME}/.zshenv
ln -sf $(pwd)/.zshenv ${HOME}
rm -rf ${HOME}/zsh
ln -sf $(pwd)/zsh ${HOME}/.config
rm -rf ${HOME}/ghostty
ln -sf $(pwd)/ghostty ${HOME}/.config
rm -rf ${local_path}/bin
ln -sf $(pwd)/.local/bin ${HOME}/.local
rm -rf ${HOME}/tmux
ln -sf $(pwd)/tmux ${HOME}/.config
rm -rf ${HOME}/nvim-init
ln -sf $(pwd)/nvim-init ${HOME}/.config

# Hyprland
rm -rf ${HOME}/hypr
ln -sf $(pwd)/hypr ${HOME}/.config

# Applications
rm -rf ${HOME}/waybar
ln -sf $(pwd)/waybar ${HOME}/.config
rm -rf ${HOME}/zathura
ln -sf $(pwd)/zathura ${HOME}/.config
rm -rf ${HOME}/fcitx5
ln -sf $(pwd)/fcitx5 ${HOME}/.config
rm -rf ${HOME}/mpv
ln -sf $(pwd)/mpv ${HOME}/.config
```

# Default apps
```bash
chsh -s /usr/bin/zsh
xdg-mime default org.pwmt.zathura.desktop application/pdf
```

# sddm themes
```bash
git clone https://github.com/ptquang2000/where-is-my-sddm-theme.git
cd where-is-my-sddm-theme
sudo sh install.sh
sudo cp $(pwd)/assets/wallpaper.jpg /usr/share/sddm/themes/where_is_my_sddm_theme
sudo ln -sf $(pwd)/sddm.conf.d /etc/
#sudo sed -i 's|^background=.*|background=wallpaper.jpg|' /usr/share/sddm/themes/where_is_my_sddm_theme/theme.conf
```


# Cleaning up
```bash
rm -rf where-is-my-sddm-theme
rm -rf yay
rm -rf ${HOME}/.bash*
yay -R - < packages/uninstall
```

# Create directories
```bash
mkdir -p ${HOME}/Downloads
mkdir -p ${HOME}/Pictures
```

# Github SSH key
```bash
ssh-keygen -t ed25519 -C "ptquang2000@gmail.com"
eval "$(ssh-agent -s)"
ssh-add ${HOME}/.ssh/id_ed25519
cat ${HOME}/.ssh/id_ed25519.pub
```

# Git global config
```bash
git config --global user.email "ptquang2000@gmail.com"
git config --global user.name "quang.phan"
```

# Enable services
```bash
systemctl enable --now reflector.service

timedatectl set-timezone Asia/Bangkok

systemctl --user enable --now waybar.service

systemctl enable --now systemd-resolved
sudo ln -sf ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
```

# TODO:
- If there is no sound from videos on x or fb, installing vlc-plugin-ffmpeg might help (https://bbs.archlinux.org/viewtopic.php?id=306853)
