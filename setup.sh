#!/usr/bin/env bash

config_path=${HOME}/.config
local_path=${HOME}/.local
sddm_bg=./assets/wallpaper.jpg

echo CONFIG_PATH=${config_path}
echo local_path=${local_path}

echo Updating submodules
git submodule update --init --recursive

echo Installing yay
git clone https://aur.archlinux.org/yay.git
cd ./yay
makepkg -si
cd -

echo Doing pacman install
yay -Sy --noconfirm - < ./pacman_pkgs

echo Doing yay install
yay -Sy --noconfirm - < ./yay_pkgs

echo Creating symbolic links
rm -rf ${HOME}/.zshenv
ln -sf $(pwd)/.zshenv ${HOME}
rm -rf ${HOME}/hypr
ln -sf $(pwd)/hypr ${config_path}
rm -rf ${HOME}/ghostty
ln -sf $(pwd)/ghostty ${config_path}
rm -rf ${HOME}/nvim
ln -sf $(pwd)/nvim ${config_path}
rm -rf ${HOME}/tmux
ln -sf $(pwd)/tmux ${config_path}
rm -rf ${HOME}/waybar
ln -sf $(pwd)/waybar ${config_path}
rm -rf ${HOME}/zathura
ln -sf $(pwd)/zathura ${config_path}
rm -rf ${HOME}/zsh
ln -sf $(pwd)/zsh ${config_path}
mkdir -p ${HOME}/.local
rm -rf ${local_path}/bin
ln -sf $(pwd)/.local/bin ${local_path}

echo Setting default shell to zsh
chsh -s /usr/bin/zsh

echo Setting default apps
xdg-mime default org.pwmt.zathura.desktop application/pdf

echo Setting sddm themes
git clone https://github.com/ptquang2000/where-is-my-sddm-theme.git
cd ./where-is-my-sddm-theme
sudo sh install.sh
cd -
sudo cp ${sddm_bg} /usr/share/sddm/themes/where_is_my_sddm_theme
sudo ln -sf $(pwd)/sddm.conf.d /etc/
sudo sed -i 's|^background=.*|background=wallpaper.jpg|' /usr/share/sddm/themes/where_is_my_sddm_theme/theme.conf

echo Cleaning up
rm -rf ./where-is-my-sddm-theme
rm -rf ./yay
rm -rf ${HOME}/.bash*
yay -R dolphin kitty

timedatectl set-timezone Asia/Bangkok

echo Create directories
mkdir -p ~/Downloads/ ~/Pictures/

echo TODO:
echo - Setup github SSH key
echo - Enable services
echo systemctl enable reflector.service
echo systemctl start reflector.service
echo systemctl --user enable --now waybar.service

