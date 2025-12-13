# If not running interactively, don't do anything
if [ "$(tty)" = "/dev/tty1" ];then
  exec Hyprland
fi
