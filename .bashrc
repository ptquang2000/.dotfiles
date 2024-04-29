#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias clear='clear && history -c && printf "\e[3J"'
PS1='[\u@\h \W]\$ '

bind -x '"\C-_": bash ~/.local/share/bin/tmux-sessionizer'
bind -s 'set completion-ignore-case on'
