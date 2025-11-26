#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '

# custom
PATH=$PATH:$(find -L ${HOME}/.local/bin -maxdepth 1 -type d -printf %p: | sed 's/:$//')

bind '"\C-H": backward-kill-word'
bind '"\e[3;5~": kill-word'

alias clear='clear && history -c && printf "\e[3J"'

bind -x '"\C-f": bash tmux-sessionizer'
bind -s 'set completion-ignore-case on'
