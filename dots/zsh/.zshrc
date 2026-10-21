# ========================
# >> Environment Setup
# ========================

export EDITOR="nvim"
export MANPAGER="$EDITOR +Man!"

export PATH="$HOME/bin:$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

# Cargo env
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# ========================
# >> Plugins
# ========================
# Provided by the zsh-autosuggestions / zsh-syntax-highlighting /
# zsh-completions packages (all in the official Arch repos).
for plugin_file in \
    /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh \
    /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
    /usr/share/zsh/plugins/zsh-completions/zsh-completions.plugin.zsh
do
    [ -f "$plugin_file" ] && source "$plugin_file"
done
unset plugin_file

# ========================
# >> Tools Init
# ========================
[ -x "$(command -v starship)" ] && eval "$(starship init zsh)"
[ -x "$(command -v zoxide)" ] && eval "$(zoxide init zsh)"
[ -x "$(command -v fzf)" ] && eval "$(fzf --zsh)"

# Run fastfetch on terminal open.
# Pick the logo by terminal width so split/tiled terminals don't wrap it.
ff() {
    local dir="$HOME/.config/fastfetch"
    if (( COLUMNS >= 150 )); then fastfetch --logo "$dir/logo-line.txt" "$@"
    elif (( COLUMNS >= 100 )); then fastfetch --logo "$dir/logo-line-small.txt" "$@"
    else fastfetch --logo none "$@"; fi
}
[ -x "$(command -v fastfetch)" ] && ff

# ========================
# >> Keybindings
# ========================
bindkey -e
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

# ========================
# >> History / Shell Options
# ========================
HISTSIZE=10000
SAVEHIST=10000
HISTFILE="$HOME/.zsh_history"
HISTDUPE=erase

setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_find_no_dups
setopt correct
setopt interactive_comments
setopt nomatch
setopt notify

export FREETYPE_PROPERTIES="truetype:interpreter-version=35 autofitter:no-stem-darkening=0 cff:no-stem-darkining=0"

zstyle ':completion:*' file-sort date
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}' 'r:|=*' 'l:|=* r:|=*'
zstyle ':completion:*:paths' path-completion yes
zstyle ':completion:*:processes' command 'ps -afu $USER'

# ========================
# >> Aliases
# ========================
# eza: the maintained fork of exa (packages/arch.txt installs `eza`).
alias ls='eza --icons --color=always --group-directories-first'
alias ll='eza -alF --icons --color=always --group-directories-first'
alias la='eza -a --icons --color=always --group-directories-first'
alias l='eza -F --icons --color=always --group-directories-first'
alias lt='eza -T --icons --color=always --group-directories-first --level=2'
alias lf='yazi'
alias v="nvim"
alias vim="nvim"
alias cat='bat --style=auto'
alias top='btop'
alias grep='grep --color=auto'

# ========================
# >> Directory Shortcuts
# ========================
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias dev='cd ~/dev 2>/dev/null || cd ~'
alias docs='cd ~/Documents 2>/dev/null || cd ~'
alias dl='cd ~/Downloads 2>/dev/null || cd ~'
alias conf='cd ~/.config'
alias dots='cd ~'

# ========================
# >> Quick Actions
# ========================
alias reload='source ~/.zshrc'
alias path='echo $PATH | tr ":" "\n" | nl'
alias ports='ss -tulanp'
alias myip='curl -s ifconfig.me'

# fzf -- colors are ANSI numbers (0-15) so they track the terminal theme
# (and matugen, if you enable the matugen module).
export FZF_DEFAULT_OPTS="
--height=60%
--layout=reverse
--border=rounded
--border-label=' 󰈲 fzf '
--border-label-pos=3
--padding=0,1
--info=inline-right
--separator='─'
--scrollbar='│'
--prompt='  '
--pointer='❯'
--marker='❯'
--highlight-line
--color=fg:7,fg+:15,bg:-1,bg+:8
--color=hl:4,hl+:4:bold,gutter:-1
--color=border:8,label:4,separator:8
--color=prompt:5,pointer:5,marker:2,spinner:6
--color=info:8,header:4,query:7
"
