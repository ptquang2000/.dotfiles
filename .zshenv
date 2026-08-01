export EDITOR="nvim"

# WSL applies no pam_env, so /etc/locale.conf never reaches the shell and
# LANG stays empty. tmux then runs in ASCII mode and prints "_" in place of
# every non-ASCII glyph. C.UTF-8 is always available; en_US.UTF-8 is not.
export LANG="${LANG:-C.UTF-8}"

export PATH="$PATH:${HOME}/.cargo/bin"
export PATH="$PATH:${HOME}/.local/bin"

# cleaning up home folder
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export ZDOTDIR="$HOME/.config/zsh"
