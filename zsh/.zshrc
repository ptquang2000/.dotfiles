HISTSIZE=10000
SAVEHIST=10000

unsetopt menu_complete
unsetopt flowcontrol

setopt prompt_subst
setopt always_to_end
setopt append_history
setopt auto_menu
setopt complete_in_word
setopt extended_history
setopt hist_expire_dups_first
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_verify
setopt inc_append_history
setopt share_history
setopt no_list_ambiguous

source ~/.config/zsh/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh
source ~/.config/zsh/zsh-autocomplete/zsh-autocomplete.plugin.zsh
source ~/.config/zsh/zsh-history-substring-search/zsh-history-substring-search.plugin.zsh
source ~/.config/zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh
source ~/.config/zsh/agkozak-zsh-prompt/agkozak-zsh-prompt.plugin.zsh

bindkey -s '\C-_' 'zsh ~/.local/bin/tmux-sessionizer^M'
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
bindkey "^[[1;5D" backward-word 
bindkey "^[[1;5C" forward-word
bindkey "^[[3~" delete-char
bindkey "^[[3;5~" delete-word
bindkey "^H" backward-delete-word
bindkey "^[[1~" beginning-of-line
bindkey "^[[4~" end-of-line
bindkey -r "^["

ZSH_AUTOSUGGEST_STRATEGY=(history completion)

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

alias clear='clear && history -p && printf "\e[3J"'
