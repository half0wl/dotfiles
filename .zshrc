# -----------------------------------------------------------------------------
# Environment
# -----------------------------------------------------------------------------
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export TERM=xterm-256color
export CLICOLOR=1
export EDITOR='nvim'

# PATH
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/usr/sbin/:/sbin/:/bin
export PATH=$PATH:/Applications/Sublime\ Text.app/Contents/SharedSupport/bin
export PATH=$PATH:$(yarn global bin)
export PATH=/opt/homebrew/opt/openjdk/bin:$PATH
export PATH=/opt/homebrew/opt/openjdk@11/bin:$PATH
export PATH=/usr/local/go/bin:$PATH

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
alias cw='cd ~/Code'
alias opf='open .'
alias reload='source ~/.zshrc'
alias flushdns='sudo dscacheutil -flushcache;sudo killall -HUP mDNSResponder'
alias httpserv='python3 -m http.server 8000 --bind 127.0.0.1'

# Docker
alias dcl='docker container logs -f --tail 500'
alias dce='docker container exec'
alias dcps='docker container ps -a'

# kubectl
alias kubectx=__kube_ps1
alias kc='kubectl -n'

# pyenv
alias av='pyenv activate'
alias dv='pyenv deactivate'

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

# Enable fzf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Enable gcloud completions
if [ -f '/Users/ray/Tools/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/ray/Tools/google-cloud-sdk/path.zsh.inc'; fi
if [ -f '/Users/ray/Tools/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/ray/Tools/google-cloud-sdk/completion.zsh.inc'; fi
