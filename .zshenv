export EDITOR="nvim"

# Adds ~/.local/bin and subfolders to $PATH
export PATH="$PATH:${$(find -L ${HOME}/.local/bin -maxdepth 1 -type d -printf %p:)%%:}"
export PATH="$PATH:${HOME}/.cargo/bin"

# cleaning up home folder
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export ZDOTDIR="$HOME/.config/zsh"
