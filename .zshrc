# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export TERM=xterm-256color
export CLICOLOR=1
export EDITOR='nvim'
export HOMEBREW_NO_AUTO_UPDATE=1

ROOTDIR="/Users/rc"
WORKSPACEDIR="$ROOTDIR/Workspace"

# PATH
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/usr/sbin/:/sbin/:/bin:/opt/homebrew/sbin
export PATH=/Applications/Sublime\ Text.app/Contents/SharedSupport/bin:$PATH # sublime text
export PATH=/usr/local/go/bin:$PATH # go
export PATH=$WORKSPACEDIR/.cargo/bin:$PATH # rust
export PATH=$ROOTDIR/.config/composer/vendor/bin:$PATH # php
export PATH="$PATH:/Users/rc/.lmstudio/bin" # LM Studio CLI
export PATH="$PATH:/Users/rc/go/bin" # go

# virtualenv in verbose mode
export PYENV_VIRTUALENV_VERBOSE_ACTIVATE=1

# -----------------------------------------------------------------------------
# Functions
# -----------------------------------------------------------------------------
# Make current kube context PS1
__kube_ps1()
{
    KUBECTL_CONTEXT=$(kubectl config current-context)
    if [ -n "$KUBECTL_CONTEXT" ]; then
        export PS1="(kubectl: ${KUBECTL_CONTEXT}) "
    fi
}

# -----------------------------------------------------------------------------
# Aliases
# -----------------------------------------------------------------------------
alias c='clear'
alias cw="cd $WORKSPACEDIR"
alias opf='open .'
alias reload='source ~/.zshrc'
alias flushdns='sudo dscacheutil -flushcache;sudo killall -HUP mDNSResponder'
alias httpserv='python3 -m http.server 8000 --bind 127.0.0.1'
alias randname='python -c "from haikunator import Haikunator;print(Haikunator().haikunate());"'

# Docker
alias dcl='docker container logs -f --tail 500'
alias dce='docker container exec'
alias dcps='docker container ps -a'
alias dcbr='docker run -it $(docker build -q .)'
alias dcbrm='docker run --rm -it $(docker build -q .)'

# kubectl
alias kubectx=__kube_ps1
alias kc='kubectl -n'

# pyenv
alias av='pyenv activate'
alias dv='pyenv deactivate'

alias killport=__kill_port
__kill_port() {
  kill -9 $(lsof -ti:$1)
}

alias pport=lsof -ti:$1

alias tailscale="/Applications/Tailscale.app/Contents/MacOS/Tailscale"

# -----------------------------------------------------------------------------
# Runtime
# -----------------------------------------------------------------------------

# Load prezto
source "${ZDOTDIR:-$HOME}/.zprezto/init.zsh"

# Disable hostname completion
zstyle ':completion:*' hosts off

# Enable pyenv & pyenv-virtualenv
eval "$(pyenv init --path)"
eval "$(pyenv init -)"
eval "$(pyenv virtualenv-init -)"

# fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# kubectl
[[ $commands[kubectl] ]] && source <(kubectl completion zsh)

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

# rbenv
eval "$(rbenv init - zsh)"

# cargo
source "$HOME/.cargo/env"

# gcloud sdk
if [ -f '/Users/rc/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/rc/google-cloud-sdk/path.zsh.inc'; fi
if [ -f '/Users/rc/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/rc/google-cloud-sdk/completion.zsh.inc'; fi

[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

# Created by `pipx` on 2023-11-20 13:06:31
export PATH="$PATH:/Users/rc/.local/bin"
export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"

# pnpm
export PNPM_HOME="/Users/rc/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
eval "$(direnv hook zsh)"
export PATH=/Users/rc/Workspace/rw/mono/packages/_common/deploy/local/bin:$PATH

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion
# nvm end

# Nix
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
  unset __ETC_PROFILE_NIX_SOURCED
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi
# End Nix
