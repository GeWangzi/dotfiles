# ~/.zshrc -- read by zsh on interactive shells.
#
# Ported from ~/.bashrc. The graphical session and the GPU pinning live in
# ~/.zprofile, which is the login-shell file; do not move them here.

eval "$(starship init zsh)"
[ -f ~/.config/user-dirs.dirs ] && source ~/.config/user-dirs.dirs

# -w makes `code` block until the file is closed again, which is what git,
# crontab and anything else that shells out to $EDITOR needs; without it they
# see the editor exit immediately and treat the file as unchanged.
export EDITOR="code -w"

# Deliberately NOT "$EDITOR". sudoedit runs this as root, VS Code refuses to
# start as root, and a GUI editor with a root-owned config directory is not a
# thing to want anyway. vim is in the base install and always works.
export SUDO_EDITOR="vim"
export PGHOST="/var/run/postgresql"

# Keep $path (and the $PATH it mirrors) free of duplicates. A login shell
# runs .zprofile and then this file, and both add ~/.local/bin, so without
# this every nested shell grows the variable further. zsh-only; bash has no
# equivalent, which is why ~/.bash_profile guards with a case statement.
typeset -U path PATH

export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/bin:$PATH"
export PATH="$PATH:/usr/local/go/bin"

# GDK_SCALE only accepts integers; fractional scaling is GDK_DPI_SCALE. The
# Hyprland monitor scale of 1.5 already handles GTK apps through the Wayland
# fractional-scale protocol, so this is probably doing nothing useful. Carried
# over unchanged so switching shells does not also change how GTK apps render;
# remove it on its own once you can watch for the difference.
export GDK_SCALE=1.5

# Work credentials and service config, at mode 600 outside version control.
# Also sourced from ~/.zprofile, so a login shell picks it up before this runs.
[ -f ~/.config/secrets.env ] && source ~/.config/secrets.env

export AWS_REGION=us-west-2
export OLLAMA_HOST=127.0.0.1:11434

export NVM_DIR="$HOME/.nvm"
# No bash_completion line here -- that script is bash-specific. zsh gets nvm
# completion through its own completion system once nvm.sh is loaded.
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# ---- history ----
# inc_append_history writes each command as it runs rather than at exit, so a
# crashed or killed shell does not lose the session's history.
HISTFILE=~/.history
HISTSIZE=10000
SAVEHIST=50000
setopt inc_append_history
setopt hist_ignore_dups
# Without this, two terminals open at once overwrite each other's history.
setopt share_history

# ---- completion ----
# compinit builds the completion cache. -u skips the "insecure directories"
# prompt that otherwise blocks startup when a completion dir is group-writable.
autoload -Uz compinit && compinit -u
# Case-insensitive matching, then partial-word: `cd dow` finds Downloads,
# `cd u/l/b` finds usr/local/bin.
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
# Tab cycles through a highlighted menu instead of printing a plain column.
zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# ---- keys ----
# Make Home/End/Delete behave, which zsh does not do out of the box.
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
# Up/Down search history for what has already been typed rather than walking
# every past command blindly.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search

alias ls='ls --color=auto'
alias grep='grep --color=auto'

# ---- plugins ----
# From the zsh-autosuggestions and zsh-syntax-highlighting packages. Guarded
# so a missing package degrades to a plain shell instead of an error on every
# prompt. Syntax highlighting must be sourced last -- it wraps the line editor
# and anything loaded after it will not be highlighted.
[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && \
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# fzf is not installed yet; this stays guarded so it simply does nothing until
# it is. Install with `pacman -S fzf`, which ships its own zsh key bindings.
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
