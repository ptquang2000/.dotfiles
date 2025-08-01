#!/bin/bash

config_path=${HOME}/.config
local_path=${HOME}/.local
sddm_bg=./assets/wallpaper.jpg

echo CONFIG_PATH=${config_path}
echo local_path=${local_path}

echo Doing pacman install
yay -Sy --noconfirm - < ./pacman_pkgs

echo Installing yay
git clone https://aur.archlinux.org/yay.git
cd ./yay
makepkg -si
cd -

echo Doing yay install
yay -Sy --noconfirm - < ./yay_pkgs

echo Updating submodules
git submodule update --init --recursive

echo Creating symbolic links 
ln -sf $(pwd)/.zshenv ${HOME}
ln -sf $(pwd)/hypr ${config_path}
ln -sf $(pwd)/kitty ${config_path}
ln -sf $(pwd)/nvim ${config_path}
ln -sf $(pwd)/tmux ${config_path}
ln -sf $(pwd)/waybar ${config_path}
ln -sf $(pwd)/zathura ${config_path}
ln -sf $(pwd)/zsh ${config_path}
ln -sf $(pwd)/.local/bin ${local_path}/bin

echo Setting default shell to zsh
chsh -s /usr/bin/zsh

echo Setting default apps
xdg-mime default org.pwmt.zathura.desktop application/pdf

echo Start services
systemctl enable reflector.service
systemctl start reflector.service
systemctl --user enable --now waybar.service

echo Setting sddm themes
git clone https://github.com/ptquang2000/where-is-my-sddm-theme.git
cd ./where-is-my-sddm-theme
sudo sh install.sh
cd -
sudo cp ${sddm_bg} /usr/share/sddm/themes/where_is_my_sddm_theme
sudo ln -sf $(pwd)/sddm.conf.d /etc/

echo Cleaning up
rm -rf ./where-is-my-sddm-theme
rm -rf ./yay

echo Create directories
mkdir -p ~/Downloads/ ~/Pictures/

echo TODO:
echo - Setup github SSH key
