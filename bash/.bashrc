# ble.sh: suggestions as you type + syntax highlighting (must stay at the top)
[[ $- == *i* && -f /usr/share/blesh/ble.sh ]] && source -- /usr/share/blesh/ble.sh --attach=none

# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
HISTSIZE=50000
HISTFILESIZE=100000

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
    xterm-color|*-256color) color_prompt=yes;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
	# We have color support; assume it's compliant with Ecma-48
	# (ISO/IEC-6429). (Lack of such support is extremely rare, and such
	# a case would tend to support setf rather than setaf.)
	color_prompt=yes
    else
	color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm*|rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*)
    ;;
esac

# enable color support of ls and also add handy aliases
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    #alias dir='dir --color=auto'
    #alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
    . ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# --- My aliases ---
alias update='sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y'   # update everything
alias c='clear'

# --- My functions ---
# dot: one command for the dotfiles (dot help). `dot cd` needs to be a function,
# because only the shell itself can change its folder.
# The dotfiles folder: where this file links to (it may not be ~/dotfiles, see
# DOTFILES_DIR in bootstrap.sh), else ~/dotfiles. $DOTFILES, if set, wins.
__dotfiles_dir="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
[ -x "$__dotfiles_dir/dot" ] || __dotfiles_dir="$HOME/dotfiles"
dot() {
  if [ "${1:-}" = cd ]; then cd "${DOTFILES:-$__dotfiles_dir}" || return
  else "${DOTFILES:-$__dotfiles_dir}/dot" "$@"; fi
}
# Tab completes the commands in dot's own list (dot help), read when you press Tab.
_dot() {
  [ "$COMP_CWORD" = 1 ] || return 0
  local cmds; cmds="$(sed -n 's/^dot \([a-z]\{1,\}\).*|.*/\1/p' "${DOTFILES:-$__dotfiles_dir}/dot")"
  mapfile -t COMPREPLY < <(compgen -W "$cmds" -- "${COMP_WORDS[1]}")
}
complete -F _dot dot

# --- Terminal customization ---
# Everything in Catppuccin Mocha, like Ghostty: fzf's colours and layout are in
# ~/.config/fzf/fzfrc, bat's theme in ~/.config/bat, eza's in ~/.config/eza/theme.yml.
export FZF_DEFAULT_OPTS_FILE="$HOME/.config/fzf/fzfrc"
# man pages in colour, through bat
if command -v batcat >/dev/null; then
  export MANPAGER="sh -c 'col -bx | batcat --language=man --style=plain'" MANROFFOPT="-c"
fi
# ble.sh's colours as you type: quiet grey suggestions (its default is a light grey
# block), and Catppuccin for commands, strings, options and mistakes.
if [[ ${BLE_VERSION-} ]]; then
  ble-face auto_complete=fg=#6c7086 syntax_comment=fg=#6c7086 \
    syntax_error=fg=#f38ba8,underline syntax_quoted=fg=#a6e3a1 syntax_varname=fg=#fab387 \
    syntax_param_expansion=fg=#f5c2e7 syntax_expr=fg=#89dceb syntax_glob=fg=#eba0ac,bold \
    syntax_tilde=fg=#b4befe,bold syntax_command=fg=#f9e2af syntax_history_expansion=fg=#11111b,bg=#f9e2af \
    command_builtin=fg=#fab387 command_builtin_dot=fg=#fab387,bold command_keyword=fg=#cba6f7 \
    command_function=fg=#89b4fa command_alias=fg=#94e2d5 command_file=fg=#a6e3a1 \
    command_directory=fg=#89b4fa,underline argument_option=fg=#94e2d5 \
    filename_directory=fg=#89b4fa,underline filename_executable=fg=#a6e3a1,underline \
    filename_link=fg=#94e2d5,underline
fi

# Prompt (Starship), smarter cd (zoxide: `z <name>`), fuzzy search (fzf: Ctrl+R, Ctrl+T, Alt+C)
command -v starship >/dev/null && eval "$(starship init bash)"
command -v zoxide   >/dev/null && eval "$(zoxide init bash)"
if command -v fzf >/dev/null; then
  if [[ ${BLE_VERSION-} ]]; then
    ble-import -d integration/fzf-completion
    ble-import -d integration/fzf-key-bindings
  else
    eval "$(fzf --bash)"
  fi
fi

# Nicer ls and cat
if command -v eza >/dev/null; then
  alias ls='eza --icons --group-directories-first'
  alias ll='eza -la --icons --git --group-directories-first'
  alias l='eza --icons --group-directories-first'   # Ubuntu's default `ls -CF` doesn't work with eza
  alias tree='eza --tree --icons'
fi
command -v batcat >/dev/null && alias bat='batcat'

# ble.sh: turn it on (must stay at the very end)
[[ ! ${BLE_VERSION-} ]] || ble-attach
